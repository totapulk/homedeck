import 'package:flutter/material.dart';

import 'src/api/homedeck_api.dart';
import 'src/config.dart';
import 'src/state/light_store.dart';
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

  @override
  void initState() {
    super.initState();
    _store = LightStore(HomeDeckApi(baseUrl: HomeDeckConfig.apiBaseUrl))..load();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HomeDeck',
    debugShowCheckedModeBanner: false,
    theme: homeDeckTheme(),
    home: LightScope(store: _store, child: const LightsPage()),
  );
}
