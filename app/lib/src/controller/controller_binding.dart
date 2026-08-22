import 'dart:async';

import 'package:flutter/foundation.dart';

import 'control_target.dart';
import 'controller_input.dart';

/// Batches detents and routes events to whatever each control is wired to. Knows nothing about
/// lights or vacuums — two knobs drive two unrelated parts of the house through this same class.
class ControllerBinding {
  ControllerBinding({
    required ControllerInput input,
    required this.targets,
    this.onInteraction,
    this.settleWindow = const Duration(milliseconds: 120),
  }) : _input = input;

  /// Control index to what it drives. A control with no entry is ignored.
  final Map<int, ControlTarget> targets;

  /// Called for every event, including ones aimed at an unmapped control: a hand on any knob
  /// means someone is present, which is what wakes the dimmed panel.
  final VoidCallback? onInteraction;

  /// A knob spun quickly emits detents far faster than a bulb can answer over UDP, so turns are
  /// collected for this long and sent as one delta.
  final Duration settleWindow;

  final ControllerInput _input;

  StreamSubscription<ControllerEvent>? _subscription;

  // Per control, so two knobs turned at once do not pool their detents.
  final Map<int, int> _pendingDetents = <int, int>{};
  final Map<int, Timer> _pendingFlush = <int, Timer>{};

  void attach() {
    _subscription ??= _input.events.listen(_handle);
  }

  Future<void> detach() async {
    for (final timer in _pendingFlush.values) {
      timer.cancel();
    }
    _pendingFlush.clear();
    _pendingDetents.clear();

    await _subscription?.cancel();
    _subscription = null;
  }

  void _handle(ControllerEvent event) {
    onInteraction?.call();

    switch (event) {
      case Rotated(:final control, :final detents):
        _rotate(control, detents);
      case Pressed(:final control):
        targets[control]?.press();
    }
  }

  void _rotate(int control, int detents) {
    if (!targets.containsKey(control)) return;

    _pendingDetents.update(control, (pending) => pending + detents, ifAbsent: () => detents);

    // Started, not restarted, so a continuous turn still produces a command every window.
    _pendingFlush[control] ??= Timer(settleWindow, () => _flush(control));
  }

  void _flush(int control) {
    _pendingFlush.remove(control);

    final detents = _pendingDetents.remove(control) ?? 0;
    if (detents == 0) return;

    targets[control]?.rotate(detents);
  }
}
