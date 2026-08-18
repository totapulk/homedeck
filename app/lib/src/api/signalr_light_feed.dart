import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

import '../models/light.dart';
import 'light_feed.dart';

class SignalRLightFeed implements LightFeed {
  SignalRLightFeed({required Uri baseUrl})
    : _hubUrl = baseUrl.resolve('hubs/lights').toString();

  /// Backing off rather than hammering: a backend that is down stays down for a while, and a
  /// wall panel retrying every 100 ms would still be doing it in the morning.
  static const List<int> _retryDelays = [0, 2000, 5000, 10000, 30000];

  final String _hubUrl;

  final StreamController<RealtimeStatus> _status =
      StreamController<RealtimeStatus>.broadcast();
  final StreamController<List<Light>> _snapshots =
      StreamController<List<Light>>.broadcast();
  final StreamController<Light> _changes = StreamController<Light>.broadcast();

  HubConnection? _connection;
  StreamSubscription<HubConnectionState>? _stateSubscription;

  @override
  Stream<RealtimeStatus> get status => _status.stream;

  @override
  Stream<List<Light>> get snapshots => _snapshots.stream;

  @override
  Stream<Light> get changes => _changes.stream;

  @override
  Future<void> start() async {
    final connection = HubConnectionBuilder()
        .withUrl(_hubUrl)
        .withAutomaticReconnect(retryDelays: _retryDelays)
        .build();

    // Method names match ILightClient on the server, which is the whole point of declaring
    // that contract as an interface there.
    connection.on('LightsSnapshot', _receiveSnapshot);
    connection.on('LightChanged', _receiveChange);

    _stateSubscription = connection.stateStream.listen(
      (state) => _status.add(_translate(state)),
    );
    _connection = connection;
    _status.add(RealtimeStatus.connecting);

    try {
      await connection.start();
    } catch (_) {
      // The retry policy takes it from here; the UI only needs to know it is not live.
      _status.add(RealtimeStatus.offline);
    }
  }

  @override
  Future<void> stop() async {
    await _stateSubscription?.cancel();
    await _connection?.stop();
    _connection = null;

    await _status.close();
    await _snapshots.close();
    await _changes.close();
  }

  void _receiveSnapshot(List<Object?>? arguments) {
    if (_firstArgument(arguments) case final List<Object?> payload) {
      _snapshots.add([for (final entry in payload) _toLight(entry)]);
    }
  }

  void _receiveChange(List<Object?>? arguments) {
    if (_firstArgument(arguments) case final Map<Object?, Object?> payload) {
      _changes.add(_toLight(payload));
    }
  }

  static Object? _firstArgument(List<Object?>? arguments) =>
      arguments == null || arguments.isEmpty ? null : arguments.first;

  static Light _toLight(Object? entry) =>
      Light.fromJson((entry as Map).cast<String, dynamic>());

  static RealtimeStatus _translate(HubConnectionState state) => switch (state) {
    HubConnectionState.Connected => RealtimeStatus.live,
    HubConnectionState.Connecting ||
    HubConnectionState.Reconnecting => RealtimeStatus.connecting,
    HubConnectionState.Disconnected ||
    HubConnectionState.Disconnecting => RealtimeStatus.offline,
  };
}
