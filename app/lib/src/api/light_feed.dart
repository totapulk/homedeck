import '../models/light.dart';

enum RealtimeStatus { connecting, live, offline }

/// A live view of light state, pushed by the backend.
///
/// Named for what it does rather than for SignalR on purpose: the store should not care what
/// keeps it current, and a test needs a feed that is not a socket at all.
abstract interface class LightFeed {
  Stream<RealtimeStatus> get status;

  /// The whole picture. Arrives on connect and again after every reconnect, which is what makes
  /// a dropped connection self-healing rather than something the UI has to reason about.
  Stream<List<Light>> get snapshots;

  Stream<Light> get changes;

  Future<void> start();
  Future<void> stop();
}

/// A feed that never says anything, for tests and for running without a backend push channel.
class SilentLightFeed implements LightFeed {
  const SilentLightFeed();

  @override
  Stream<RealtimeStatus> get status => const Stream<RealtimeStatus>.empty();

  @override
  Stream<List<Light>> get snapshots => const Stream<List<Light>>.empty();

  @override
  Stream<Light> get changes => const Stream<Light>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
