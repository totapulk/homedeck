import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/models/light.dart';
import 'package:homedeck/src/models/light_command.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String lightJson({bool isOn = true, int brightness = 70, bool isReachable = true}) =>
    '{"id":"a1","name":"Reading lamp","room":"Living room","isOn":$isOn,'
    '"brightness":$brightness,"colorTempK":2700,"isReachable":$isReachable,'
    '"updatedAt":"2026-08-17T12:59:49Z"}';

LightStore storeAnswering(Future<http.Response> Function(http.Request) handler) =>
    LightStore(HomeDeckApi(baseUrl: Uri.parse('http://backend'), client: MockClient(handler)));

/// A store that already holds one light, with [onCommand] answering every POST.
Future<LightStore> loadedStore(
  Future<http.Response> Function(http.Request) onCommand,
) async {
  final store = storeAnswering(
    (request) async => request.method == 'GET'
        ? http.Response('[${lightJson()}]', 200)
        : onCommand(request),
  );

  await store.load();
  return store;
}

Light only(LightStore store) => (store.state as LightsReady).lights.single;

void main() {
  group('loading', () {
    test('reaches a ready state with the lights the backend returned', () async {
      final store = storeAnswering((_) async => http.Response('[${lightJson()}]', 200));

      await store.load();

      expect(store.state, isA<LightsReady>());
      expect(only(store).name, 'Reading lamp');
    });

    test('a backend that is not there is a state, not a crash', () async {
      final store = storeAnswering((_) async => throw http.ClientException('refused'));

      await store.load();

      expect(store.state, isA<LightsUnavailable>());
      expect((store.state as LightsUnavailable).message, contains('backend'));
    });

    test('a server error surfaces its status code', () async {
      final store = storeAnswering((_) async => http.Response('boom', 500));

      await store.load();

      expect((store.state as LightsUnavailable).message, contains('500'));
    });
  });

  group('commands', () {
    test('shows the requested state before the bulb has confirmed it', () async {
      final bulb = Completer<http.Response>();
      final store = await loadedStore((_) => bulb.future);

      final pending = store.apply(only(store), const LightCommand(brightness: 20));
      expect(only(store).brightness, 20, reason: 'the UI must not wait for a round trip');

      // The bulb rounds to what it can actually do, and that answer outranks the guess.
      bulb.complete(http.Response(lightJson(brightness: 25), 200));
      await pending;

      expect(only(store).brightness, 25);
    });

    test('winding brightness to zero reads as off without asking the backend first', () async {
      final store = await loadedStore((_) => Completer<http.Response>().future);

      unawaited(store.apply(only(store), const LightCommand(brightness: 0)));

      expect(only(store).isOn, isFalse);
    });

    test('a relative delta is predicted the same way the backend resolves it', () async {
      final store = await loadedStore((_) => Completer<http.Response>().future);

      unawaited(store.apply(only(store), const LightCommand(brightnessDelta: -90)));

      expect(only(store).brightness, 0);
      expect(only(store).isOn, isFalse);
    });

    test('a late reply to a superseded command is ignored', () async {
      final slow = Completer<http.Response>();
      var commands = 0;
      final store = await loadedStore((_) async {
        commands++;
        return commands == 1 ? slow.future : http.Response(lightJson(brightness: 90), 200);
      });

      final first = store.apply(only(store), const LightCommand(brightness: 10));
      await store.apply(only(store), const LightCommand(brightness: 90));
      expect(only(store).brightness, 90);

      slow.complete(http.Response(lightJson(brightness: 10), 200));
      await first;

      expect(only(store).brightness, 90, reason: 'the older answer must not win');
    });

    test('a failed command puts the light back where it was', () async {
      final store = await loadedStore((_) async => throw http.ClientException('refused'));

      final failure = await store.apply(only(store), const LightCommand(isOn: false));

      expect(only(store).isOn, isTrue);
      expect(failure, contains('backend'));
    });

    test('an unreachable bulb answers 503 and that state is kept', () async {
      final store = await loadedStore(
        (_) async => http.Response(lightJson(isReachable: false), 503),
      );

      final failure = await store.apply(only(store), const LightCommand(isOn: false));

      expect(failure, isNull, reason: '503 carries a light, so it is not an error to report');
      expect(only(store).isReachable, isFalse);
    });
  });
}
