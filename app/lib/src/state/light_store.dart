import 'package:flutter/widgets.dart';

import '../api/homedeck_api.dart';
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
  LightStore(this._api);

  final HomeDeckApi _api;

  /// Newest command issued per light. A reply that is not the newest is a reply to a question
  /// nobody is asking any more, and applying it would drag the UI backwards.
  final Map<String, int> _issued = <String, int>{};

  LightsState _state = const LightsLoading();

  LightsState get state => _state;

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

    _replace(_predict(light, command));

    try {
      final confirmed = await _api.applyCommand(light.id, command);
      if (_issued[light.id] == ticket) _replace(confirmed);
      return null;
    } on HomeDeckApiException catch (error) {
      if (_issued[light.id] == ticket) _replace(light);
      return error.message;
    }
  }

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
