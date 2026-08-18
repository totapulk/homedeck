import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/homedeck_api.dart';
import '../api/light_feed.dart';
import '../models/light.dart';
import '../models/light_command.dart';

sealed class LightsState {
  const LightsState();
}

class LightsLoading extends LightsState {
  const LightsLoading();
}

class LightsReady extends LightsState {
  const LightsReady(this.lights);

  final List<Light> lights;
}

class LightsUnavailable extends LightsState {
  const LightsUnavailable(this.message);

  final String message;
}

class LightStore extends ChangeNotifier {
  LightStore(this._api, {LightFeed feed = const SilentLightFeed()}) : _feed = feed;

  final HomeDeckApi _api;
  final LightFeed _feed;

  /// Newest command issued per light. A reply that is not the newest is a reply to a question
  /// nobody is asking any more, and applying it would drag the UI backwards.
  final Map<String, int> _issued = <String, int>{};

  /// Commands still in the air, per light. While one is, the backend's pushes describe a world
  /// that predates the button the user just pressed.
  final Map<String, int> _inFlight = <String, int>{};

  final List<StreamSubscription<void>> _subscriptions = [];

  LightsState _state = const LightsLoading();
  RealtimeStatus _realtime = RealtimeStatus.connecting;
  String? _selectedId;

  LightsState get state => _state;

  RealtimeStatus get realtime => _realtime;

  /// The light a physical controller acts on.
  ///
  /// Falls back to the first reachable light rather than to nothing, because a knob that does
  /// nothing until you have used the app first is a knob that looks broken.
  Light? get selected {
    final lights = _lights;
    if (lights.isEmpty) return null;

    if (_selectedId case final id?) {
      for (final light in lights) {
        if (light.id == id) return light;
      }
    }

    return lights.firstWhere((light) => light.isReachable, orElse: () => lights.first);
  }

  void select(String id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Moves the selection along the list, wrapping at both ends. A knob has no end stops, so
  /// neither does this.
  void selectRelative(int offset) {
    final lights = _lights;
    if (lights.isEmpty || offset == 0) return;

    final current = selected;
    final index = current == null
        ? 0
        : lights.indexWhere((light) => light.id == current.id);

    _selectedId = lights[(index + offset) % lights.length].id;
    notifyListeners();
  }

  /// Subscribes to backend pushes. Independent of [load]: the app is usable over REST alone,
  /// it just stops noticing changes it did not make.
  Future<void> connect() async {
    _subscriptions.addAll([
      _feed.status.listen(_receiveStatus),
      _feed.snapshots.listen(_receiveSnapshot),
      _feed.changes.listen(_receiveChange),
    ]);

    await _feed.start();
  }

  Future<void> load() async {
    if (_state is! LightsReady) _publish(const LightsLoading());

    try {
      _publish(LightsReady(await _api.fetchLights()));
    } on HomeDeckApiException catch (error) {
      _publish(LightsUnavailable(error.message));
    }
  }

  /// Shows the expected result immediately, then settles on whatever the bulb confirms.
  /// Returns null on success, or a message to put in front of the user.
  Future<String?> apply(Light light, LightCommand command) async {
    final ticket = (_issued[light.id] ?? 0) + 1;
    _issued[light.id] = ticket;
    _inFlight.update(light.id, (count) => count + 1, ifAbsent: () => 1);

    _replace(_predict(light, command));

    try {
      final confirmed = await _api.applyCommand(light.id, command);
      if (_issued[light.id] == ticket) _replace(confirmed);
      return null;
    } on HomeDeckApiException catch (error) {
      if (_issued[light.id] == ticket) _replace(light);
      return error.message;
    } finally {
      final remaining = (_inFlight[light.id] ?? 1) - 1;
      if (remaining > 0) {
        _inFlight[light.id] = remaining;
      } else {
        _inFlight.remove(light.id);
      }
    }
  }

  void _receiveStatus(RealtimeStatus status) {
    if (_realtime == status) return;
    _realtime = status;
    notifyListeners();
  }

  /// Adopts the backend's whole picture, except for lights the user is currently commanding —
  /// a snapshot assembled before the button was pressed would undo it on screen.
  void _receiveSnapshot(List<Light> lights) {
    final held = {
      for (final light in _lights)
        if (_isCommanding(light.id)) light.id: light,
    };

    _publish(LightsReady([for (final light in lights) held[light.id] ?? light]));
  }

  void _receiveChange(Light light) {
    if (_isCommanding(light.id)) return;
    _replace(light);
  }

  bool _isCommanding(String id) => _inFlight.containsKey(id);

  List<Light> get _lights => switch (_state) {
    LightsReady(:final lights) => lights,
    _ => const <Light>[],
  };

  /// The guess the UI runs on until the backend confirms. It deliberately repeats the backend's
  /// rule that brightness and on/off are the same dial — a knob wound to zero is a light off —
  /// because a guess that disagrees with the server produces a visible flicker on every command.
  static Light _predict(Light light, LightCommand command) {
    final delta = command.brightnessDelta;
    final brightness =
        command.brightness ??
        (delta == null ? light.brightness : (light.brightness + delta).clamp(0, 100));
    final touchesBrightness = command.brightness != null || delta != null;

    return light.copyWith(
      isOn: command.isOn ?? (touchesBrightness ? brightness > 0 : light.isOn),
      brightness: brightness,
      colorTempK: command.colorTempK,
    );
  }

  void _replace(Light light) {
    if (_state case LightsReady(:final lights)) {
      _publish(
        LightsReady([
          for (final existing in lights) existing.id == light.id ? light : existing,
        ]),
      );
    }
  }

  void _publish(LightsState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _feed.stop();
    _api.dispose();
    super.dispose();
  }
}

/// Hands the store to the widget tree without a state-management package: an
/// [InheritedNotifier] already rebuilds exactly the widgets that read it.
class LightScope extends InheritedNotifier<LightStore> {
  const LightScope({super.key, required LightStore store, required super.child})
    : super(notifier: store);

  static LightStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LightScope>();
    assert(scope != null, 'No LightScope above this widget.');
    return scope!.notifier!;
  }
}
