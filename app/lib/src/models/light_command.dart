import 'package:flutter/foundation.dart';

/// A change requested of a light. Mirrors the backend's command shape, including the relative
/// [brightnessDelta] that the rotary knob will speak once it exists.
@immutable
class LightCommand {
  const LightCommand({
    this.isOn,
    this.brightness,
    this.brightnessDelta,
    this.colorTempK,
  });

  final bool? isOn;
  final int? brightness;
  final int? brightnessDelta;
  final int? colorTempK;

  Map<String, dynamic> toJson() => {
    if (isOn != null) 'isOn': isOn,
    if (brightness != null) 'brightness': brightness,
    if (brightnessDelta != null) 'brightnessDelta': brightnessDelta,
    if (colorTempK != null) 'colorTempK': colorTempK,
  };
}
