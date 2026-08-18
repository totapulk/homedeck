import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'src/api/homedeck_api.dart';
import 'src/api/signalr_light_feed.dart';
import 'src/config.dart';
import 'src/controller/ble_controller_input.dart';
import 'src/controller/controller_binding.dart';
import 'src/controller/controller_input.dart';
import 'src/state/light_store.dart';
import 'src/ui/demo_knob.dart';
import 'src/ui/lights_page.dart';
import 'src/ui/theme.dart';

void main() => runApp(const HomeDeckApp());

class HomeDeckApp extends StatefulWidget {
  const HomeDeckApp({super.key});

  @override
  State<HomeDeckApp> createState() => _HomeDeckAppState();
}

class _HomeDeckAppState extends State<HomeDeckApp> {
  late final LightStore _store;
  late final MockControllerInput _onScreenKnob;
  late final List<ControllerInput> _controllers;
  late final List<ControllerBinding> _bindings;

  @override
  void initState() {
    super.initState();
    _store = LightStore(
      HomeDeckApi(baseUrl: HomeDeckConfig.apiBaseUrl),
      feed: SignalRLightFeed(baseUrl: HomeDeckConfig.apiBaseUrl),
    );

    // REST paints the first frame; the hub keeps it true from then on.
    _store.load();
    _store.connect();

    // Two sources of the same events: the pad on screen and, where the platform has a radio,
    // the knob on the shelf. Neither knows about the other, and the bindings do not care which
    // one a turn came from.
    _onScreenKnob = MockControllerInput();
    _controllers = [_onScreenKnob, if (!kIsWeb) BleControllerInput()];
    _bindings = [
      for (final controller in _controllers)
        ControllerBinding(input: controller, store: _store)..attach(),
    ];

    for (final controller in _controllers) {
      controller.start();
    }
  }

  @override
  void dispose() {
    for (final binding in _bindings) {
      binding.detach();
    }
    for (final controller in _controllers) {
      controller.stop();
    }
    _onScreenKnob.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HomeDeck',
    debugShowCheckedModeBanner: false,
    theme: homeDeckTheme(),
    home: LightScope(
      store: _store,
      child: kDebugMode
          ? DemoKnob(input: _onScreenKnob, child: const LightsPage())
          : const LightsPage(),
    ),
  );
}
