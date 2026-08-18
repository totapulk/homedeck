import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/api/light_feed.dart';
import 'package:homedeck/src/models/light.dart';
import 'package:homedeck/src/models/light_command.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String lightJson({
  String id = 'a1',
  String name = 'Reading lamp',
  bool isOn = true,
  int brightness = 70,
}) =>
    '{"id":"$id","name":"$name","room":"Living room","isOn":$isOn,'
    '"brightness":$brightness,"colorTempK":2700,"isReachable":true,'
    '"updatedAt":"2026-08-18T10:00:00Z"}';

Light light({
  String id = 'a1',
  String name = 'Reading lamp',
  bool isOn = true,
  int brightness = 70,
}) => Light.fromJson(
  jsonDecode(lightJson(id: id, name: name, isOn: isOn, brightness: brightness))
      as Map<String, dynamic>,
);

class FakeLightFeed implements LightFeed {
  final StreamController<RealtimeStatus> _status =
      StreamController<RealtimeStatus>.broadcast();
  final StreamController<List<Light>> _snapshots =
      StreamController<List<Light>>.broadcast();
  final StreamController<Light> _changes = StreamController<Light>.broadcast();

  bool started = false;

  @override
  Stream<RealtimeStatus> get status => _status.stream;

  @override
  Stream<List<Light>> get snapshots => _snapshots.stream;

  @override
  Stream<Light> get changes => _changes.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => started = false;

  void announce(RealtimeStatus value) => _status.add(value);
  void sendSnapshot(List<Light> lights) => _snapshots.add(lights);
  void sendChange(Light value) => _changes.add(value);
}

/// A store holding one light, with [onCommand] answering every POST.
Future<(LightStore, FakeLightFeed)> connectedStore({
  Future<http.Response> Function(http.Request)? onCommand,
}) async {
  final feed = FakeLightFeed();
  final store = LightStore(
    HomeDeckApi(
      baseUrl: Uri.parse('http://backend'),
      client: MockClient(
        (request) async => request.method == 'GET'
            ? http.Response('[${lightJson()}]', 200)
            : (onCommand ?? (_) async => http.Response(lightJson(), 200))(request),
      ),
    ),
    feed: feed,
  );

  await store.load();
  await store.connect();
  return (store, feed);
}

Light only(LightStore store) => (store.state as LightsReady).lights.single;

void main() {
  test('a pushed change lands without anyone asking for it', () async {
    final (store, feed) = await connectedStore();

    feed.sendChange(light(brightness: 15));
    await pumpEventQueue();

    expect(only(store).brightness, 15);
  });

  test('connection status is visible to the UI', () async {
    final (store, feed) = await connectedStore();

    feed.announce(RealtimeStatus.live);
    await pumpEventQueue();
    expect(store.realtime, RealtimeStatus.live);

    feed.announce(RealtimeStatus.offline);
    await pumpEventQueue();
    expect(store.realtime, RealtimeStatus.offline);
  });

  test('a snapshot replaces everything the store thought it knew', () async {
    final (store, feed) = await connectedStore();

    feed.sendSnapshot([light(brightness: 5, isOn: false)]);
    await pumpEventQueue();

    expect(only(store).brightness, 5);
    expect(only(store).isOn, isFalse);
  });

  test('a push cannot undo a command that is still in the air', () async {
    final bulb = Completer<http.Response>();
    final (store, feed) = await connectedStore(onCommand: (_) => bulb.future);

    unawaited(store.apply(only(store), const LightCommand(brightness: 100)));
    expect(only(store).brightness, 100);

    // A poll that started before the button was pressed describes the old world.
    feed.sendChange(light(brightness: 70));
    await pumpEventQueue();

    expect(only(store).brightness, 100, reason: 'the pressed button must win');

    bulb.complete(http.Response(lightJson(brightness: 100), 200));
    await pumpEventQueue();
  });

  test('a snapshot mid-command spares only the light being commanded', () async {
    final bulb = Completer<http.Response>();
    final (store, feed) = await connectedStore(onCommand: (_) => bulb.future);

    unawaited(store.apply(only(store), const LightCommand(brightness: 100)));
    feed.sendSnapshot([
      light(brightness: 70),
      light(id: 'b2', name: 'Desk', brightness: 30),
    ]);
    await pumpEventQueue();

    final lights = (store.state as LightsReady).lights;
    expect(lights.firstWhere((l) => l.id == 'a1').brightness, 100);
    expect(lights.firstWhere((l) => l.id == 'b2').brightness, 30);

    bulb.complete(http.Response(lightJson(brightness: 100), 200));
    await pumpEventQueue();
  });

  test('pushes are honoured again once the command has settled', () async {
    final (store, feed) = await connectedStore();

    await store.apply(only(store), const LightCommand(brightness: 70));
    feed.sendChange(light(brightness: 40));
    await pumpEventQueue();

    expect(only(store).brightness, 40);
  });
}
