import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResponsiveHelper {
  // Reuses the existing native channel (see MainActivity.kt).
  static const MethodChannel _platform =
      MethodChannel('info.breisner.rensi.iptv/pip');

  // Cached once at boot via [initTelevisionFlag]. On real Android TV / leanback
  // devices this is the authoritative signal; screen width is only a fallback.
  static bool _isTelevisionDevice = false;
  static bool get isTelevisionDevice => _isTelevisionDevice;

  /// Query the platform once (call from main() before runApp). Safe on every
  /// platform: non-Android hosts throw MissingPluginException → treated false.
  static Future<void> initTelevisionFlag() async {
    try {
      final result = await _platform.invokeMethod<bool>('isTelevision');
      _isTelevisionDevice = result ?? false;
    } catch (_) {
      _isTelevisionDevice = false;
    }
  }

  static double getCardWidth(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= 1200) {
      return 160;
    } else if (screenWidth >= 600) {
      return 130;
    } else {
      return 110;
    }
  }

  static double getCardHeight(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= 1200) {
      return 220;
    } else if (screenWidth >= 600) {
      return 190;
    } else {
      return 160;
    }
  }

  static int getCrossAxisCount(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= 1200) {
      return 6;
    } else if (screenWidth >= 900) {
      return 5;
    } else if (screenWidth >= 600) {
      return 4;
    } else if (screenWidth >= 400) {
      return 3;
    } else {
      return 2;
    }
  }

  /// Single source of truth for "should this render the TV / 10-foot UI?".
  /// Priority: real TV device (native) > directional navigation (D-pad) >
  /// wide screen (desktop / large tablet fallback).
  static bool isDesktopOrTV(BuildContext context) {
    if (_isTelevisionDevice) return true;
    final nav = MediaQuery.maybeOf(context)?.navigationMode;
    if (nav == NavigationMode.directional) return true;
    return MediaQuery.of(context).size.width >= 900;
  }
}
