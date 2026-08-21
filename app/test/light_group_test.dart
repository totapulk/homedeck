import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/controller/controller_binding.dart';
import 'package:homedeck/src/controller/controller_input.dart';
import 'package:homedeck/src/models/light.dart';
import 'package:homedeck/src/models/light_command.dart';
import 'package:homedeck/src/models/light_group.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Light light({
  required String id,
  required String name,
  String room = 'Living room',
  String? fixture,
  bool isOn = true,
  int brightness = 70,
  int? colorTempK = 2700,
}) => Light(
  id: id,
  name: name,
  room: room,
  fixture: fixture,
  isOn: isOn,
  brightness: brightness,
  colorTempK: colorTempK,
  isReachable: true,
  updatedAt: DateTime.utc(2026, 8, 19),
);

/// One three-bulb ceiling lamp and one lamp of its own.
const String _home = '''
[
  {"id":"c1","name":"Bulb 1","room":"Living room","fixture":"Ceiling lamp","isOn":true,
   "brightness":80,"colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-19T10:00:00Z"},
  {"id":"c2","name":"Bulb 2","room":"Living room","fixture":"Ceiling lamp","isOn":true,
   "brightness":40,"colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-19T10:00:00Z"},
  {"id":"c3","name":"Bulb 3","room":"Living room","fixture":"Ceiling lamp","isOn":false,
   "brightness":0,"colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-19T10:00:00Z"},
  {"id":"r1","name":"Reading lamp","room":"Living room","fixture":null,"isOn":true,
   "brightness":60,"colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-19T10:00:00Z"}
]
''';

Future<(MockControllerInput, LightStore, Map<String, List<Map<String, dynamic>>>)>
knobOnHome() async {
  final commands = <String, List<Map<String, dynamic>>>{};
  final known = {
    for (final entry in (jsonDecode(_home) as List).cast<Map<String, dynamic>>())
      entry['id'] as String: entry,
  };

  final store = LightStore(
    HomeDeckApi(
      baseUrl: Uri.parse('http://backend'),
      client: MockClient((request) async {
        if (request.method == 'GET') return http.Response(_home, 200);

        final id = request.url.pathSegments[2];
        (commands[id] ??= []).add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(known[id]), 200);
      }),
    ),
  );
  await store.load();

  final knob = MockControllerInput();
  ControllerBinding(
    input: knob,
    store: store,
    settleWindow: const Duration(milliseconds: 20),
  ).attach();

  return (knob, store, commands);
}

void main() {
  group('grouping', () {
    test('bulbs sharing a fixture become one lamp', () {
      final groups = groupLights([
        light(id: 'c1', name: 'Bulb 1', fixture: 'Ceiling lamp'),
        light(id: 'c2', name: 'Bulb 2', fixture: 'Ceiling lamp'),
        light(id: 'r1', name: 'Reading lamp'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.name, 'Ceiling lamp');
      expect(groups.first.lights, hasLength(2));
      expect(groups.first.isFixture, isTrue);
    });

    test('a bulb belonging to no fixture is a group of one', () {
      final groups = groupLights([light(id: 'r1', name: 'Reading lamp')]);

      expect(groups.single.name, 'Reading lamp');
      expect(groups.single.isFixture, isFalse);
      expect(groups.single.lights, hasLength(1));
    });

    test('two lamps with the same bulb names do not merge', () {
      final groups = groupLights([
        light(id: 'a', name: 'Bulb'),
        light(id: 'b', name: 'Bulb'),
      ]);

      expect(groups, hasLength(2));
    });

    test('order follows first appearance so cards do not jump between polls', () {
      final groups = groupLights([
        light(id: 'r1', name: 'Reading lamp'),
        light(id: 'c1', name: 'Bulb 1', fixture: 'Ceiling lamp'),
        light(id: 'c2', name: 'Bulb 2', fixture: 'Ceiling lamp'),
      ]);

      expect(groups.map((group) => group.name), ['Reading lamp', 'Ceiling lamp']);
    });
  });

  group('a lamp made of several bulbs', () {
    test('is on when any bulb is', () {
      final group = groupLights([
        light(id: 'c1', name: 'a', fixture: 'Ceiling lamp', isOn: false, brightness: 0),
        light(id: 'c2', name: 'b', fixture: 'Ceiling lamp', isOn: true, brightness: 50),
      ]).single;

      // Reporting "off" while one bulb still glows would be a lie the room can see through.
      expect(group.isOn, isTrue);
    });

    test('reads as the average of its bulbs', () {
      final group = groupLights([
        light(id: 'c1', name: 'a', fixture: 'Ceiling lamp', brightness: 80),
        light(id: 'c2', name: 'b', fixture: 'Ceiling lamp', brightness: 40),
      ]).single;

      expect(group.brightness, 60);
    });

    test('reports a colour temperature only when its bulbs agree', () {
      final same = groupLights([
        light(id: 'c1', name: 'a', fixture: 'F', colorTempK: 2700),
        light(id: 'c2', name: 'b', fixture: 'F', colorTempK: 2700),
      ]).single;
      final mixed = groupLights([
        light(id: 'c1', name: 'a', fixture: 'F', colorTempK: 2700),
        light(id: 'c2', name: 'b', fixture: 'F', colorTempK: 4000),
      ]).single;

      expect(same.colorTempK, 2700);
      expect(mixed.colorTempK, isNull);
    });
  });

  group('controlling a lamp', () {
    test('a command reaches every bulb in it', () async {
      final (_, store, commands) = await knobOnHome();
      final ceiling = groupLights(
        (store.state as LightsReady).lights,
      ).firstWhere((group) => group.isFixture);

      await store.applyToAll(ceiling.lights, const LightCommand(isOn: false));

      expect(commands.keys.toSet(), {'c1', 'c2', 'c3'});
    });

    test('selecting the lamp points the knob at all of its bulbs', () async {
      final (knob, store, commands) = await knobOnHome();

      store.selectFixture('Ceiling lamp');
      expect(store.selectionLabel, 'Ceiling lamp');

      knob.rotate(2);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(commands.keys.toSet(), {'c1', 'c2', 'c3'});
      expect(commands['c1']!.single, {'brightnessDelta': 10});

      // The lamp that is not part of the fixture is left alone.
      expect(commands.containsKey('r1'), isFalse);
    });

    test('a fixture that is no longer there falls back to everything', () async {
      final (knob, store, commands) = await knobOnHome();

      store.selectFixture('Chandelier');
      knob.rotate(1);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(store.selectionLabel, 'All lights');
      expect(commands.keys.toSet(), {'c1', 'c2', 'c3', 'r1'});
    });
  });
}
