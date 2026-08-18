import 'dart:async';

/// What a physical controller can say. Deliberately tiny: a knob reports that it moved, not
/// what it moved. Deciding that a turn means brightness is the app's job, which is why the
/// firmware never needs reflashing when the product changes its mind.
sealed class ControllerEvent {
  const ControllerEvent(this.control);

  /// Which physical control moved. The firmware numbers them and says nothing about what any
  /// of them is for; [ControllerBinding] is where an index acquires a meaning.
  final int control;
}

/// A relative turn, in detents. Positive is clockwise.
///
/// Relative on purpose: a delta cannot disagree with a change made from the phone or the wall,
/// where an absolute reading from a potentiometer would fight it.
class Rotated extends ControllerEvent {
  const Rotated(super.control, this.detents);

  final int detents;

  @override
  String toString() => 'Rotated(control: $control, detents: $detents)';
}

class Pressed extends ControllerEvent {
  const Pressed(super.control);

  @override
  String toString() => 'Pressed(control: $control)';
}

enum ControllerStatus { disconnected, searching, connected }

abstract interface class ControllerInput {
  Stream<ControllerEvent> get events;
  Stream<ControllerStatus> get status;

  Future<void> start();
  Future<void> stop();
}

/// A controller with no hardware behind it.
///
/// This is what lets the whole pipeline — event, intent, request, confirmed state — be built
/// and tested before the ESP32 exists, and demonstrated if it ever stops working.
class MockControllerInput implements ControllerInput {
  final StreamController<ControllerEvent> _events =
      StreamController<ControllerEvent>.broadcast();
  final StreamController<ControllerStatus> _status =
      StreamController<ControllerStatus>.broadcast();

  @override
  Stream<ControllerEvent> get events => _events.stream;

  @override
  Stream<ControllerStatus> get status => _status.stream;

  @override
  Future<void> start() async => _status.add(ControllerStatus.connected);

  @override
  Future<void> stop() async => _status.add(ControllerStatus.disconnected);

  void rotate(int detents, {int control = 0}) => _events.add(Rotated(control, detents));

  void press({int control = 0}) => _events.add(Pressed(control));

  Future<void> dispose() async {
    await _events.close();
    await _status.close();
  }
}
