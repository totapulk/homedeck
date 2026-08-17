import 'package:flutter/material.dart';

/// Warm amber on near-black: the app is meant to sit on a wall in a dim room, where a bright
/// surface is a lamp of its own.
ThemeData homeDeckTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFFB74D),
    brightness: Brightness.dark,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF101014),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF101014),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1A20),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
