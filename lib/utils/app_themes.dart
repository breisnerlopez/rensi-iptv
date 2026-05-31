import 'package:flutter/material.dart';

class AppThemes {
  // Material Red 700 — deep, elegant red that anchors the whole palette
  // (primary, secondary, tertiary, surface, error...) through ColorScheme.fromSeed.
  static const Color _seedColor = Color(0xFFD32F2F);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
  );
}
