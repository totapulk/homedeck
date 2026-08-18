import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/controller/controller_binding.dart';
import 'package:homedeck/src/controller/controller_input.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const Duration _window = Duration(milliseconds: 20);

String lightJson({
  String id = 'a1',
  String name = 'Reading lamp',
  bool isOn = true,
  int brightness = 70,
  bool isReachable = true,
}) =>
    '{"id":"$id","name":"$name","room":"Living room","isOn":$isOn,'
    '"brightness":$brightness,"colorTempK":2700,"isReachable":$isReachable,'
    '"updatedAt":"2026-08-18T10:00:00Z"}';

/// A wired-up knob, store and recording backend.
Future<(MockControllerInput, LightStore, List<Map<String, dynamic>>)> knobOn(
  String lightsJson,
) async {
  final commands = <Map<String, dynamic>>[];

  final store = LightStore(
    HomeDeckApi(
      baseUrl: Uri.parse('http://backend'),
      client: MockClient((request) async {
        if (request.method == 'GET') return http.Response(lightsJson, 200);
        commands.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(lightJson(), 200);
      }),
    ),
  );
  await store.load();

  final knob = MockControllerInput();
  ControllerBinding(input: knob, store: store, settleWindow: _window).attach();
  return (knob, store, commands);
}

Future<void> settle() => Future<void>.delayed(_window * 3);

void main() {
  test('a detent becomes a relative brightness command', () async {
    final (knob, _, commands) = await knobOn('[${lightJson()}]');

    knob.rotate(1);
    await settle();

    // Relative, not absolute: the knob never sends a brightness, only a change to one.
    expect(commands.single, {'brightnessDelta': 5});
  });

  test('turning the other way sends the opposite sign', () async {
    final (knob, _, commands) = await knobOn('[${lightJson()}]');

    knob.rotate(-3);
    await settle();

    expect(commands.single, {'brightnessDelta': -15});
  });

  test('a fast spin becomes one request, not one per detent', () async {
    final (knob, _, commands) = await knobOn('[${lightJson()}]');

    for (var detent = 0; detent < 12; detent++) {
      knob.rotate(1);
    }
    await settle();

    // A bulb answering over UDP cannot keep up with a hand; the deltas are summed instead.
    expect(commands.single, {'brightnessDelta': 60});
  });

  test('a press toggles the light the knob is on', () async {
    final (knob, _, commands) = await knobOn('[${lightJson(isOn: true)}]');

    knob.press();
    await settle();

    expect(commands.single, {'isOn': false});
  });

  test('control 1 moves the selection instead of the brightness', () async {
    final (knob, store, commands) = await knobOn(
      '[${lightJson()},${lightJson(id: 'b2', name: 'Desk')}]',
    );
    expect(store.selected!.id, 'a1');

    knob.rotate(1, control: 1);
    await settle();

    expect(store.selected!.id, 'b2');
    expect(commands, isEmpty, reason: 'picking a light must not change one');
  });

  test('the selection wraps rather than stopping at the ends', () async {
    final (knob, store, _) = await knobOn(
      '[${lightJson()},${lightJson(id: 'b2', name: 'Desk')}]',
    );

    knob.rotate(-1, control: 1);
    await settle();

    // A knob has no end stops, so neither does the list.
    expect(store.selected!.id, 'b2');
  });

  test('two controls turned at once do not pool their detents', () async {
    final (knob, store, commands) = await knobOn(
      '[${lightJson()},${lightJson(id: 'b2', name: 'Desk')}]',
    );

    knob.rotate(2, control: 0);
    knob.rotate(1, control: 1);
    await settle();

    expect(commands.single, {'brightnessDelta': 10});
    expect(store.selected!.id, 'b2');
  });

  test('an unknown control is treated as a dimmer rather than ignored', () async {
    final (knob, _, commands) = await knobOn('[${lightJson()}]');

    knob.rotate(1, control: 7);
    await settle();

    // A knob added to the firmware before the app has an opinion about it should still do
    // something obvious, not nothing.
    expect(commands.single, {'brightnessDelta': 5});
  });

  test('the knob follows the selection rather than the list order', () async {
    final (knob, store, commands) = await knobOn(
      '[${lightJson()},${lightJson(id: 'b2', name: 'Desk')}]',
    );

    store.select('b2');
    knob.rotate(2);
    await settle();

    expect(commands.single, {'brightnessDelta': 10});
    expect(store.selected!.id, 'b2');
  });

  test('with nothing to control the knob is harmless', () async {
    final (knob, store, commands) = await knobOn('[]');

    knob.rotate(4);
    knob.press();
    await settle();

    expect(store.selected, isNull);
    expect(commands, isEmpty);
  });

  test('an unreachable light is not what the knob defaults to', () async {
    final (_, store, _) = await knobOn(
      '[${lightJson(isReachable: false)},${lightJson(id: 'b2', name: 'Desk')}]',
    );

    expect(store.selected!.id, 'b2');
  });
}
