import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPreferences {
  static const String _keyLastPlaylist = 'last_playlist';
  static const String _keyVolume = 'volume';
  static const String _keyAudioTrack = 'audio_track';
  static const String _keySubtitleTrack = 'subtitle_track';
  static const String _keyVideoQuality = 'video_quality';
  static const String _keyBackgroundPlay = 'background_play';
  static const String _keySubtitleFontSize = 'subtitle_font_size';
  static const String _keySubtitleHeight = 'subtitle_height';
  static const String _keySubtitleLetterSpacing = 'subtitle_letter_spacing';
  static const String _keySubtitleWordSpacing = 'subtitle_word_spacing';
  static const String _keySubtitleTextColor = 'subtitle_text_color';
  static const String _keySubtitleBackgroundColor = 'subtitle_background_color';
  static const String _keySubtitleFontWeight = 'subtitle_font_weight';
  static const String _keySubtitleTextAlign = 'subtitle_text_align';
  static const String _keySubtitlePadding = 'subtitle_padding';
  static const String _keyLocale = 'locale';
  static const String _hiddenCategoriesKey = 'hidden_categories';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyBrightnessGesture = 'brightness_gesture';
  static const String _keyVolumeGesture = 'volume_gesture';
  static const String _keySeekGesture = 'seek_gesture';
  static const String _keySpeedUpOnLongPress = 'speed_up_on_long_press';
  static const String _keySeekOnDoubleTap = 'seek_on_double_tap';
  static const String _keyAutoPipOnHome = 'auto_pip_on_home';

  static const List<String> _backupKeys = [
    _keyLastPlaylist,
    _keyVolume,
    _keyAudioTrack,
    _keySubtitleTrack,
    _keyVideoQuality,
    _keyBackgroundPlay,
    _keySubtitleFontSize,
    _keySubtitleHeight,
    _keySubtitleLetterSpacing,
    _keySubtitleWordSpacing,
    _keySubtitleTextColor,
    _keySubtitleBackgroundColor,
    _keySubtitleFontWeight,
    _keySubtitleTextAlign,
    _keySubtitlePadding,
    _keyLocale,
    _hiddenCategoriesKey,
    _keyThemeMode,
    _keyBrightnessGesture,
    _keyVolumeGesture,
    _keySeekGesture,
    _keySpeedUpOnLongPress,
    _keySeekOnDoubleTap,
    _keyAutoPipOnHome,
  ];

  static Future<Map<String, Object>> exportSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, Object>{};
    for (final key in _backupKeys) {
      final value = prefs.get(key);
      if (value is Object) {
        values[key] = value;
      }
    }
    return values;
  }

  /// Per-key validators applied before persisting an imported value. A
  /// validator may coerce the value to a safe one, or return null to skip
  /// the key entirely. Only keys with sane bounds are listed; keys without
  /// a validator are imported as-is (typed).
  static final Map<String, Object? Function(Object?)> _importValidators = {
    _keyVolume: (v) {
      if (v is num) return v.toDouble().clamp(0.0, 100.0);
      return null;
    },
    _keySubtitleFontSize: (v) {
      if (v is num) return v.toDouble().clamp(8.0, 96.0);
      return null;
    },
    _keySubtitleHeight: (v) {
      if (v is num) return v.toDouble().clamp(0.8, 3.0);
      return null;
    },
    _keySubtitleLetterSpacing: (v) {
      if (v is num) return v.toDouble().clamp(-2.0, 8.0);
      return null;
    },
    _keySubtitleWordSpacing: (v) {
      if (v is num) return v.toDouble().clamp(-2.0, 16.0);
      return null;
    },
    _keySubtitlePadding: (v) {
      if (v is num) return v.toDouble().clamp(0.0, 96.0);
      return null;
    },
    _keySubtitleFontWeight: (v) {
      if (v is num) {
        final i = v.toInt();
        if (i < 0 || i >= FontWeight.values.length) return null;
        return i;
      }
      return null;
    },
    _keySubtitleTextAlign: (v) {
      if (v is num) {
        final i = v.toInt();
        if (i < 0 || i >= TextAlign.values.length) return null;
        return i;
      }
      return null;
    },
    _keyThemeMode: (v) {
      if (v is String && (v == 'system' || v == 'light' || v == 'dark')) {
        return v;
      }
      return null;
    },
  };

  static Future<void> importSettings(Map<String, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _backupKeys) {
      if (!values.containsKey(key)) continue;
      var value = values[key];

      final validator = _importValidators[key];
      if (validator != null) {
        value = validator(value);
        if (value == null) continue;
      }

      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is num) {
        await prefs.setDouble(key, value.toDouble());
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.map((item) => '$item').toList());
      }
    }
  }

  static Future<void> setLastPlaylist(String playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastPlaylist, playlistId);
  }

  static Future<String?> getLastPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastPlaylist);
  }

  static Future<void> removeLastPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastPlaylist);
  }

  static Future<void> setVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVolume, volume);
  }

  static Future<double> getVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyVolume) ?? 100;
  }

  static Future<void> setAudioTrack(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioTrack, language);
  }

  static Future<String> getAudioTrack() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAudioTrack) ?? 'auto';
  }

  static Future<void> setSubtitleTrack(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubtitleTrack, language);
  }

  static Future<String> getSubtitleTrack() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySubtitleTrack) ?? 'auto';
  }

  static Future<void> setVideoTrack(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVideoQuality, id);
  }

  static Future<String> getVideoTrack() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVideoQuality) ?? 'auto';
  }

  static Future<void> setBackgroundPlay(bool backgroundPlay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackgroundPlay, backgroundPlay);
  }

  static Future<bool> getBackgroundPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackgroundPlay) ?? true;
  }

  static Future<void> setAutoPipOnHome(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoPipOnHome, enabled);
  }

  static Future<bool> getAutoPipOnHome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoPipOnHome) ?? true;
  }

  static Future<double> getSubtitleFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleFontSize) ?? 32.0;
  }

  static Future<void> setSubtitleFontSize(double fontSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleFontSize, fontSize);
  }

  static Future<double> getSubtitleHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleHeight) ?? 1.4;
  }

  static Future<void> setSubtitleHeight(double height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleHeight, height);
  }

  static Future<double> getSubtitleLetterSpacing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleLetterSpacing) ?? 0.0;
  }

  static Future<void> setSubtitleLetterSpacing(double letterSpacing) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleLetterSpacing, letterSpacing);
  }

  static Future<double> getSubtitleWordSpacing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleWordSpacing) ?? 0.0;
  }

  static Future<void> setSubtitleWordSpacing(double wordSpacing) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleWordSpacing, wordSpacing);
  }

  static Future<Color> getSubtitleTextColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_keySubtitleTextColor) ?? 0xffffffff;
    return Color(colorValue);
  }

  static Future<void> setSubtitleTextColor(Color textColor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleTextColor, textColor.value);
  }

  static Future<Color> getSubtitleBackgroundColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_keySubtitleBackgroundColor) ?? 0xaa000000;
    return Color(colorValue);
  }

  static Future<void> setSubtitleBackgroundColor(Color backgroundColor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleBackgroundColor, backgroundColor.value);
  }

  static Future<FontWeight> getSubtitleFontWeight() async {
    final prefs = await SharedPreferences.getInstance();
    final weightIndex =
        prefs.getInt(_keySubtitleFontWeight) ?? FontWeight.normal.index;
    return FontWeight.values[weightIndex];
  }

  static Future<void> setSubtitleFontWeight(FontWeight fontWeight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleFontWeight, fontWeight.index);
  }

  static Future<TextAlign> getSubtitleTextAlign() async {
    final prefs = await SharedPreferences.getInstance();
    final alignIndex =
        prefs.getInt(_keySubtitleTextAlign) ?? TextAlign.center.index;
    return TextAlign.values[alignIndex];
  }

  static Future<void> setSubtitleTextAlign(TextAlign textAlign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleTextAlign, textAlign.index);
  }

  static Future<double> getSubtitlePadding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitlePadding) ?? 24.0;
  }

  static Future<void> setSubtitlePadding(double padding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitlePadding, padding);
  }

  static Future<String?> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocale);
  }

  static Future<void> setLocale(String locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale);
  }

  static Future<void> removeLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLocale);
  }

  static Future<void> setHiddenCategories(List<String> categoryIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenCategoriesKey, categoryIds);
  }

  static Future<bool> getHiddenCategory(String categoryId) async {
    final hidden = await getHiddenCategories();
    return hidden.contains(categoryId);
  }

  static Future<List<String>> getHiddenCategories() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_hiddenCategoriesKey) ?? [];
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.toString().split('.').last);
  }

  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyThemeMode) ?? 'system';
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  // Player gesture settings
  static Future<bool> getBrightnessGesture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBrightnessGesture) ?? false;
  }

  static Future<void> setBrightnessGesture(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBrightnessGesture, value);
  }

  static Future<bool> getVolumeGesture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVolumeGesture) ?? false;
  }

  static Future<void> setVolumeGesture(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVolumeGesture, value);
  }

  static Future<bool> getSeekGesture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySeekGesture) ?? false;
  }

  static Future<void> setSeekGesture(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySeekGesture, value);
  }

  static Future<bool> getSpeedUpOnLongPress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySpeedUpOnLongPress) ?? true;
  }

  static Future<void> setSpeedUpOnLongPress(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySpeedUpOnLongPress, value);
  }

  static Future<bool> getSeekOnDoubleTap() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySeekOnDoubleTap) ?? true;
  }

  static Future<void> setSeekOnDoubleTap(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySeekOnDoubleTap, value);
  }
}
