import 'package:flutter/material.dart';
import '../repositories/user_preferences.dart';
import '../utils/app_themes.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _amoled = false;
  AccentSet _accent = AppThemes.defaultAccent;

  ThemeProvider() {
    _loadTheme();
  }

  ThemeMode get themeMode => _themeMode;

  /// Whether the pure-black AMOLED dark theme is selected.
  bool get amoled => _amoled;

  /// F4 — el preset de acento elegido (default terracota).
  AccentSet get accent => _accent;

  Future<void> _loadTheme() async {
    _themeMode = await UserPreferences.getThemeMode();
    _amoled = await UserPreferences.getAmoled();
    _accent = _accentById(await UserPreferences.getAccentId());
    notifyListeners();
  }

  static AccentSet _accentById(String id) => AppThemes.accents.firstWhere(
        (a) => a.id == id,
        orElse: () => AppThemes.defaultAccent,
      );

  Future<void> setAccent(AccentSet accent) async {
    _accent = accent;
    await UserPreferences.setAccentId(accent.id);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    await UserPreferences.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setAmoled(bool value) async {
    _amoled = value;
    await UserPreferences.setAmoled(value);
    notifyListeners();
  }

  bool isDarkMode() => _themeMode == ThemeMode.dark;
  bool isLightMode() => _themeMode == ThemeMode.light;
  bool isSystemMode() => _themeMode == ThemeMode.system;
}
