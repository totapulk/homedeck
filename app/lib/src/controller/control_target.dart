import '../models/light_command.dart';
import '../state/light_store.dart';
import '../state/vacuum_store.dart';

/// What one control on the physical remote is wired to.
///
/// The ESP32 sends `[control, event, delta]` and knows nothing about what it means; so does
/// ControllerBinding. Meaning is assigned here, which is why pointing a knob at something else
/// needs no reflashing.
abstract interface class ControlTarget {
  /// Called once per settle window with the detents accumulated in it.
  void rotate(int detents);

  void press();
}

/// Turning dims the current light selection; pressing toggles it.
class BrightnessTarget implements ControlTarget {
  const BrightnessTarget(this._store, {this.percentPerDetent = 5});

  final LightStore _store;

  /// Twenty detents per revolution at 5% each, so one full turn covers the range.
  final int percentPerDetent;

  @override
  void rotate(int detents) => _store.applyToSelection(
    LightCommand(brightnessDelta: detents * percentPerDetent),
  );

  /// Toggles the selection together — per-light toggling would leave a room half lit.
  @override
  void press() {
    final lights = _store.selectedLights;
    if (lights.isEmpty) return;

    final anyOn = lights.any((light) => light.isOn);
    _store.applyToSelection(LightCommand(isOn: !anyOn));
  }
}

/// Pressing sends the robot out.
class VacuumTarget implements ControlTarget {
  const VacuumTarget(this._store);

  final VacuumStore _store;

  /// Nothing: suction and rooms are set once in the vendor's app, so there is no dial here
  /// worth reaching for from the sofa.
  @override
  void rotate(int detents) {}

  @override
  void press() => _store.start();
}
