import 'package:flutter/foundation.dart';

import 'light.dart';

/// What the knob is currently pointed at.
///
/// Three widths, chosen on the touchscreen: the whole home, one room, or one light. The knob
/// itself never changes this — it is a dimmer, not a selector — which is what leaves the second
/// knob free for something that has nothing to do with lights.
@immutable
sealed class LightSelection {
  const LightSelection();

  /// The lights this selection resolves to, given what is currently known.
  ///
  /// Falls back to everything when a remembered room or light is no longer there, because a
  /// knob that silently does nothing is worse than one that does something obvious.
  List<Light> resolve(List<Light> lights);

  /// How to describe this on screen.
  String describe(List<Light> lights);
}

class AllLights extends LightSelection {
  const AllLights();

  @override
  List<Light> resolve(List<Light> lights) => lights;

  @override
  String describe(List<Light> lights) => 'All lights';

  @override
  bool operator ==(Object other) => other is AllLights;

  @override
  int get hashCode => 0;
}

class RoomSelection extends LightSelection {
  const RoomSelection(this.room);

  final String room;

  @override
  List<Light> resolve(List<Light> lights) {
    final inRoom = [for (final light in lights) if (light.room == room) light];
    return inRoom.isEmpty ? lights : inRoom;
  }

  @override
  String describe(List<Light> lights) =>
      resolve(lights).isEmpty || lights.every((light) => light.room != room)
      ? 'All lights'
      : room;

  @override
  bool operator ==(Object other) => other is RoomSelection && other.room == room;

  @override
  int get hashCode => room.hashCode;
}

/// Every bulb of one physical lamp.
class FixtureSelection extends LightSelection {
  const FixtureSelection(this.fixture);

  final String fixture;

  @override
  List<Light> resolve(List<Light> lights) {
    final bulbs = [for (final light in lights) if (light.fixture == fixture) light];
    return bulbs.isEmpty ? lights : bulbs;
  }

  @override
  String describe(List<Light> lights) =>
      lights.any((light) => light.fixture == fixture) ? fixture : 'All lights';

  @override
  bool operator ==(Object other) =>
      other is FixtureSelection && other.fixture == fixture;

  @override
  int get hashCode => fixture.hashCode;
}

class SingleLight extends LightSelection {
  const SingleLight(this.id);

  final String id;

  @override
  List<Light> resolve(List<Light> lights) {
    for (final light in lights) {
      if (light.id == id) return [light];
    }
    return lights;
  }

  @override
  String describe(List<Light> lights) {
    for (final light in lights) {
      if (light.id == id) return light.name;
    }
    return 'All lights';
  }

  @override
  bool operator ==(Object other) => other is SingleLight && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
