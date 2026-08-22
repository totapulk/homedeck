import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/controller/control_target.dart';
import 'package:homedeck/src/controller/controller_binding.dart';
import 'package:homedeck/src/controller/controller_input.dart';
import 'package:homedeck/src/models/vacuum.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:homedeck/src/state/vacuum_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const Duration _window = Duration(milliseconds: 20);

const String _lights = '''
[
  {"id":"a1","name":"Reading lamp","room":"Living room","isOn":true,"brightness":80,
   "colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-21T10:00:00Z"}
]
''';

String _vacuumJson(String activity, {int battery = 100, bool simulated = true}) => jsonEncode({
  'name': 'Robot vacuum',
  'activity': activity,
  'batteryPercent': battery,
  'isSimulated': simulated,
  'updatedAt': '2026-08-21T10:00:00Z',
});

/// A backend serving both domains, recording every path that was asked for.
({LightStore lights, VacuumStore vacuum, List<String> calls}) backend({
  bool vacuumIsDown = false,
}) {
  final calls = <String>[];

  http.Client client() => MockClient((request) async {
    final path = '${request.method} ${request.url.path}';
    calls.add(path);

    if (request.url.path.startsWith('/api/vacuum')) {
      if (vacuumIsDown) return http.Response('nope', 500);

      return http.Response(
        switch (request.url.path) {
          '/api/vacuum/start' => _vacuumJson('Cleaning', battery: 98),
          '/api/vacuum/dock' => _vacuumJson('Returning', battery: 80),
          _ => _vacuumJson('Docked'),
        },
        200,
      );
    }

    if (request.method == 'GET') return http.Response(_lights, 200);
    return http.Response(
      jsonEncode((jsonDecode(_lights) as List).first),
      200,
    );
  });

  return (
    lights: LightStore(
      HomeDeckApi(baseUrl: Uri.parse('http://backend'), client: client()),
    ),
    vacuum: VacuumStore(
      HomeDeckApi(baseUrl: Uri.parse('http://backend'), client: client()),
    ),
    calls: calls,
  );
}

Future<void> settle() => Future<void>.delayed(_window * 4);

void main() {
  group('the vacuum store', () {
    test('reads the robot from the backend', () async {
      final home = backend();

      await home.vacuum.load();

      expect(home.vacuum.vacuum?.activity, VacuumActivity.docked);
      expect(home.vacuum.vacuum?.batteryPercent, 100);
      expect(home.vacuum.error, isNull);
    });

    test('sends it out and adopts the state that comes back', () async {
      final home = backend();

      await home.vacuum.start();

      expect(home.vacuum.vacuum?.activity, VacuumActivity.cleaning);
    });

    test('sends it home again', () async {
      final home = backend();

      await home.vacuum.dock();

      expect(home.vacuum.vacuum?.activity, VacuumActivity.returning);
    });

    test('a backend that will not answer becomes a message, not a crash', () async {
      final home = backend(vacuumIsDown: true);

      await home.vacuum.load();

      expect(home.vacuum.vacuum, isNull);
      expect(home.vacuum.error, isNotNull);
    });

    test('it says when it is only a simulation', () async {
      final home = backend();

      await home.vacuum.load();

      // Decided by the backend, not the app, so the card's label cannot drift.
      expect(home.vacuum.vacuum?.isSimulated, isTrue);
    });

    test('an unfamiliar activity does not break an older app', () async {
      final robot = Vacuum.fromJson(
        jsonDecode(_vacuumJson('Mopping')) as Map<String, dynamic>,
      );

      expect(robot.activity, VacuumActivity.unknown);
    });
  });

  group('one remote, two domains', () {
    /// Same controller, same three-byte packet, two unrelated parts of the house.
    test('knob 0 dims the lights and knob 1 starts the vacuum', () async {
      final home = backend();
      await home.lights.load();

      final knob = MockControllerInput();
      ControllerBinding(
        input: knob,
        targets: {
          0: BrightnessTarget(home.lights),
          1: VacuumTarget(home.vacuum),
        },
        settleWindow: _window,
      ).attach();

      knob.rotate(2, control: 0);
      knob.press(control: 1);
      await settle();

      expect(home.calls, contains('POST /api/lights/a1/state'));
      expect(home.calls, contains('POST /api/vacuum/start'));
    });

    test('pressing the light knob leaves the vacuum alone', () async {
      final home = backend();
      await home.lights.load();

      final knob = MockControllerInput();
      ControllerBinding(
        input: knob,
        targets: {
          0: BrightnessTarget(home.lights),
          1: VacuumTarget(home.vacuum),
        },
        settleWindow: _window,
      ).attach();

      knob.press(control: 0);
      await settle();

      expect(home.calls.where((call) => call.contains('vacuum')), isEmpty);
    });

    test('turning the vacuum knob does nothing at all', () async {
      final home = backend();

      final knob = MockControllerInput();
      ControllerBinding(
        input: knob,
        targets: {1: VacuumTarget(home.vacuum)},
        settleWindow: _window,
      ).attach();

      knob.rotate(5, control: 1);
      await settle();

      // Rotation is accepted and discarded rather than given an invented meaning.
      expect(home.calls, isEmpty);
    });

    test('every event wakes the panel, even one with no effect', () async {
      final home = backend();

      var woken = 0;
      final knob = MockControllerInput();
      ControllerBinding(
        input: knob,
        targets: {1: VacuumTarget(home.vacuum)},
        onInteraction: () => woken++,
        settleWindow: _window,
      ).attach();

      knob.rotate(1, control: 1);
      knob.rotate(1, control: 7);
      await settle();

      // A hand on any knob means someone is present, which is what wakes the dimmed screen.
      expect(woken, 2);
    });
  });
}
