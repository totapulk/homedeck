import 'dart:async';

import '../models/light_command.dart';
import '../state/light_store.dart';
import 'controller_input.dart';

/// What turning a particular control is for.
enum ControlRole {
  /// Changes the selected light's brightness.
  brightness,

  /// Moves the selection from light to light, so the other knob has something to act on.
  selection,
}

/// Gives a controller's events a meaning: which control does what, and what a turn is worth.
///
/// This is the layer the ESP32 knows nothing about. Deciding that knob 1 should pick a vacuum
/// programme instead of a light is a change here and nowhere else — no reflashing, and covered
/// by tests that never touch hardware.
class ControllerBinding {
  ControllerBinding({
    required ControllerInput input,
    required LightStore store,
    this.roles = const {0: ControlRole.brightness, 1: ControlRole.selection},
    this.brightnessPerDetent = 5,
    this.settleWindow = const Duration(milliseconds: 120),
  }) : _input = input,
       _store = store;

  final Map<int, ControlRole> roles;

  /// Twenty detents per revolution at 5% each: one full turn covers the whole range, which is
  /// what a dimmer should feel like.
  final int brightnessPerDetent;

  /// A knob spun quickly emits detents far faster than a bulb can answer over UDP. Turns are
  /// collected for this long and sent as one delta, so the network sees a handful of requests
  /// instead of a hundred, and the bulb still keeps up with the hand.
  final Duration settleWindow;

  final ControllerInput _input;
  final LightStore _store;

  StreamSubscription<ControllerEvent>? _subscription;

  // Per control: two knobs turned at once must not pool their detents.
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

  void _handle(ControllerEvent event) => switch (event) {
    Rotated(:final control, :final detents) => _rotate(control, detents),
    Pressed(:final control) => _press(control),
  };

  void _rotate(int control, int detents) {
    _pendingDetents.update(control, (pending) => pending + detents, ifAbsent: () => detents);

    // Started, not restarted: a continuous turn must still produce a command every window
    // rather than nothing at all until the hand stops.
    _pendingFlush[control] ??= Timer(settleWindow, () => _flush(control));
  }

  void _flush(int control) {
    _pendingFlush.remove(control);

    final detents = _pendingDetents.remove(control) ?? 0;
    if (detents == 0) return;

    switch (roles[control] ?? ControlRole.brightness) {
      case ControlRole.brightness:
        if (_store.selected case final light?) {
          _store.apply(light, LightCommand(brightnessDelta: detents * brightnessPerDetent));
        }
      case ControlRole.selection:
        _store.selectRelative(detents);
    }
  }

  /// Pressing any control toggles whatever is selected. One press is a coarse gesture and a
  /// light being on or off is the coarsest thing about it.
  void _press(int control) {
    if (_store.selected case final light?) {
      _store.apply(light, LightCommand(isOn: !light.isOn));
    }
  }
}
