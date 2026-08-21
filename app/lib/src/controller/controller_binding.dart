import 'dart:async';

import '../models/light_command.dart';
import '../state/light_store.dart';
import 'controller_input.dart';

/// What turning a particular control is for.
///
/// One entry so far. The second knob is deliberately unassigned: it is destined for the vacuum,
/// and a knob that dims lights in the meantime would have to be untaught later — worse than one
/// that politely does nothing.
enum ControlRole { brightness }

/// Gives a controller's events a meaning: which control does what, and what a turn is worth.
///
/// This is the layer the ESP32 knows nothing about. Pointing knob 1 at a vacuum instead of a
/// light is a change here and nowhere else — no reflashing, and covered by tests that never
/// touch hardware.
class ControllerBinding {
  ControllerBinding({
    required ControllerInput input,
    required LightStore store,
    this.roles = const {0: ControlRole.brightness},
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

  void _handle(ControllerEvent event) {
    // Every event counts as someone being present, even one aimed at a control with no role
    // yet: a hand on the knob should wake the panel whether or not the turn changes a light.
    _store.noteInteraction();

    switch (event) {
      case Rotated(:final control, :final detents):
        _rotate(control, detents);
      case Pressed(:final control):
        _press(control);
    }
  }

  void _rotate(int control, int detents) {
    if (roles[control] != ControlRole.brightness) return;

    _pendingDetents.update(control, (pending) => pending + detents, ifAbsent: () => detents);

    // Started, not restarted: a continuous turn must still produce a command every window
    // rather than nothing at all until the hand stops.
    _pendingFlush[control] ??= Timer(settleWindow, () => _flush(control));
  }

  void _flush(int control) {
    _pendingFlush.remove(control);

    final detents = _pendingDetents.remove(control) ?? 0;
    if (detents == 0) return;

    _store.applyToSelection(
      LightCommand(brightnessDelta: detents * brightnessPerDetent),
    );
  }

  /// A press toggles the whole selection together.
  ///
  /// If anything in it is on, the press turns everything off; otherwise it turns everything on.
  /// Toggling each light independently would scatter a room into a half-lit mess, which is not
  /// what a single button should ever produce.
  void _press(int control) {
    if (roles[control] != ControlRole.brightness) return;

    final lights = _store.selectedLights;
    if (lights.isEmpty) return;

    final anyOn = lights.any((light) => light.isOn);
    _store.applyToSelection(LightCommand(isOn: !anyOn));
  }
}
