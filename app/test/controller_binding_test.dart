import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/controller/control_target.dart';
import 'package:homedeck/src/controller/controller_binding.dart';
import 'package:homedeck/src/controller/controller_input.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const Duration _window = Duration(milliseconds: 20);

/// Two rooms, three lights, all at different brightness.
const String _home = '''
[
  {"id":"a1","name":"Reading lamp","room":"Living room","isOn":true,"brightness":80,
   "colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-19T10:00:00Z"},
  {"id":"a2","name":"Ceiling","room":"Living room","isOn":true,"brightness":40,
   "colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-19T10:00:00Z"},
  {"id":"b1","name":"Desk","room":"Office","isOn":false,"brightness":0,
   "colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-19T10:00:00Z"}
]
''';

/// A wired-up knob and store, recording which light each command was aimed at.
Future<(MockControllerInput, LightStore, Map<String, List<Map<String, dynamic>>>)>
knobOn([String home = _home]) async {
  final commands = <String, List<Map<String, dynamic>>>{};
  final known = {
    for (final light in (jsonDecode(home) as List).cast<Map<String, dynamic>>())
      light['id'] as String: light,
  };

  final store = LightStore(
    HomeDeckApi(
      baseUrl: Uri.parse('http://backend'),
      client: MockClient((request) async {
        if (request.method == 'GET') return http.Response(home, 200);

        final id = request.url.pathSegments[2];
        (commands[id] ??= []).add(jsonDecode(request.body) as Map<String, dynamic>);

        // Echo the light the command was aimed at. A confirmation that renamed the light
        // would be a fiction the store would then have to live with.
        return http.Response(jsonEncode(known[id]), 200);
      }),
    ),
  );
  await store.load();

  final knob = MockControllerInput();
  ControllerBinding(
    input: knob,
    targets: {0: BrightnessTarget(store)},
    settleWindow: _window,
  ).attach();
  return (knob, store, commands);
}

Future<void> settle() => Future<void>.delayed(_window * 4);

void main() {
  test('with nothing chosen the knob moves the whole home', () async {
    final (knob, store, commands) = await knobOn();
    expect(store.selectionLabel, 'All lights');

    knob.rotate(1);
    await settle();

    expect(commands.keys.toSet(), {'a1', 'a2', 'b1'});
    expect(commands['a1']!.single, {'brightnessDelta': 5});
  });

  test('a group moves by a delta, so the lights keep their differences', () async {
    final (knob, store, commands) = await knobOn();

    knob.rotate(-4);
    await settle();

    // 80 and 40 both fall by 20. An absolute control would have collapsed them onto one value.
    expect(commands['a1']!.single, {'brightnessDelta': -20});
    expect(commands['a2']!.single, {'brightnessDelta': -20});
    expect(store.selectedLights.length, 3);
  });

  test('choosing a room narrows the knob to that room', () async {
    final (knob, store, commands) = await knobOn();

    store.selectRoom('Living room');
    knob.rotate(2);
    await settle();

    expect(commands.keys.toSet(), {'a1', 'a2'});
    expect(store.selectionLabel, 'Living room');
  });

  test('choosing one light narrows it to that light', () async {
    final (knob, store, commands) = await knobOn();

    store.selectLight('b1');
    knob.rotate(1);
    await settle();

    expect(commands.keys.toSet(), {'b1'});
    expect(store.selectionLabel, 'Desk');
  });

  test('widening back to everything is one call', () async {
    final (knob, store, commands) = await knobOn();

    store.selectLight('b1');
    store.selectAll();
    knob.rotate(1);
    await settle();

    expect(commands.keys.toSet(), {'a1', 'a2', 'b1'});
  });

  test('a press turns the whole selection off when any of it is on', () async {
    final (knob, store, commands) = await knobOn();
    store.selectRoom('Living room');

    knob.press();
    await settle();

    // Toggling each light on its own would leave a room half lit, which is not what one
    // button should ever produce.
    expect(commands['a1']!.single, {'isOn': false});
    expect(commands['a2']!.single, {'isOn': false});
  });

  test('a press turns everything on when none of it is', () async {
    final (knob, store, commands) = await knobOn();
    store.selectLight('b1');

    knob.press();
    await settle();

    expect(commands['b1']!.single, {'isOn': true});
  });

  test('a fast spin becomes one request per light, not one per detent', () async {
    final (knob, store, commands) = await knobOn();
    store.selectLight('a1');

    for (var detent = 0; detent < 12; detent++) {
      knob.rotate(1);
    }
    await settle();

    expect(commands['a1']!.single, {'brightnessDelta': 60});
  });

  test('a control with nothing wired to it is ignored', () async {
    final (knob, _, commands) = await knobOn();

    knob.rotate(3, control: 1);
    knob.press(control: 1);
    await settle();

    // Only control 0 has a target here; an unmapped knob must stay silent.
    expect(commands, isEmpty);
  });

  test('a selection that no longer exists falls back to everything', () async {
    final (knob, store, commands) = await knobOn();

    store.selectLight('gone');
    knob.rotate(1);
    await settle();

    expect(commands.keys.toSet(), {'a1', 'a2', 'b1'});
    expect(store.selectionLabel, 'All lights');
  });
}
