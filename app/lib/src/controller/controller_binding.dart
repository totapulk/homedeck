import 'dart:async';

import '../models/light_command.dart';
import '../state/light_store.dart';
import 'controller_input.dart';

/// Gives a controller's events a meaning: which light they act on, and what a turn is worth.
///
/// This is the layer the ESP32 knows nothing about. Moving the knob from brightness to colour
/// temperature, or to a different room, is a change here and nowhere else.
class ControllerBinding {
  ControllerBinding({
    required ControllerInput input,
    required LightStore store,
    this.brightnessPerDetent = 5,
    this.settleWindow = const Duration(milliseconds: 120),
  }) : _input = input,
       _store = store;

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
  Timer? _pendingFlush;
  int _pendingDetents = 0;

  void attach() {
    _subscription ??= _input.events.listen(_handle);
  }

  Future<void> detach() async {
    _pendingFlush?.cancel();
    _pendingFlush = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  void _handle(ControllerEvent event) => switch (event) {
    Rotated(:final detents) => _rotate(detents),
    Pressed() => _press(),
  };

  void _rotate(int detents) {
    _pendingDetents += detents;

    // Started, not restarted: a continuous turn must still produce a command every window
    // rather than nothing at all until the hand stops.
    _pendingFlush ??= Timer(settleWindow, _flush);
  }

  void _flush() {
    _pendingFlush = null;

    final detents = _pendingDetents;
    _pendingDetents = 0;
    if (detents == 0) return;

    if (_store.selected case final light?) {
      _store.apply(light, LightCommand(brightnessDelta: detents * brightnessPerDetent));
    }
  }

  void _press() {
    if (_store.selected case final light?) {
      _store.apply(light, LightCommand(isOn: !light.isOn));
    }
  }
}
