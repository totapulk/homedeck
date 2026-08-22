import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/homedeck_api.dart';
import '../models/vacuum.dart';

/// Everything the app knows about the robot vacuum.
///
/// Polled rather than pushed over SignalR like the lights are: a cleaning run changes state a
/// handful of times in half an hour, where a knob turned in another room has to show up within
/// the second.
class VacuumStore extends ChangeNotifier {
  VacuumStore(
    this._api, {
    this.whileOut = const Duration(seconds: 5),
    this.whileDocked = const Duration(seconds: 30),
  });

  final Duration whileOut;
  final Duration whileDocked;

  final HomeDeckApi _api;

  Vacuum? _vacuum;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  bool _watching = false;

  Vacuum? get vacuum => _vacuum;

  String? get error => _error;

  /// Whether a command is in the air. The buttons go quiet while it is.
  bool get busy => _busy;

  /// Starts keeping the state current until [dispose].
  void watch() {
    if (_watching) return;
    _watching = true;
    unawaited(load());
  }

  Future<void> load() => _run(_api.fetchVacuum);

  Future<void> start() => _run(_api.startVacuum);

  Future<void> dock() => _run(_api.dockVacuum);

  Future<void> _run(Future<Vacuum> Function() call) async {
    if (_busy) return;

    _busy = true;
    notifyListeners();

    try {
      _vacuum = await call();
      _error = null;
    } on HomeDeckApiException catch (failure) {
      _error = failure.message;
    } finally {
      _busy = false;
      _reschedule();
      notifyListeners();
    }
  }

  /// Every answer sets up the next question, closer together while the robot is moving.
  void _reschedule() {
    _poll?.cancel();
    if (!_watching) return;

    final out = _vacuum?.activity.isOut ?? false;
    _poll = Timer(out ? whileOut : whileDocked, load);
  }

  @override
  void dispose() {
    _watching = false;
    _poll?.cancel();
    super.dispose();
  }
}

/// Hands the vacuum store to the widget tree, as LightScope does for lights.
class VacuumScope extends InheritedNotifier<VacuumStore> {
  const VacuumScope({super.key, required VacuumStore store, required super.child})
    : super(notifier: store);

  static VacuumStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<VacuumScope>();
    assert(scope != null, 'No VacuumScope above this widget.');
    return scope!.notifier!;
  }
}
