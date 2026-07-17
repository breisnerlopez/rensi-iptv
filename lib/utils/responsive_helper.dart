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

  // 10-foot UI tuning (Android TV). Posters are sized relative to the screen so
  // they scale with the actual TV resolution instead of fixed pixels — the old
  // absolute thresholds made a 1080p box (~960 logical dp) fall to the tablet
  // branch and render tiny, cramped tiles.
  static const double _tvSafe = 48; // overscan side margin
  static const double _tvGutter = 20;
  static const double _tvTargetTile = 200; // desired poster width at 3 m

  static double getCardWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (isDesktopOrTV(context)) {
      // Larger, legible rail posters (~200dp on 1080p).
      return (w * 0.155).clamp(190.0, 240.0);
    }
    if (w >= 1200) return 160;
    if (w >= 600) return 130;
    return 110;
  }

  static double getCardHeight(BuildContext context) {
    if (isDesktopOrTV(context)) {
      return getCardWidth(context) * 1.45; // poster-ish proportion
    }
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return 220;
    if (w >= 600) return 190;
    return 160;
  }

  static int getCrossAxisCount(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (isDesktopOrTV(context)) {
      // Columns that yield ~[_tvTargetTile]dp tiles inside the safe area.
      final avail = w - 2 * _tvSafe;
      final n = ((avail + _tvGutter) / (_tvTargetTile + _tvGutter)).floor();
      return n.clamp(3, 7);
    }
    if (w >= 1200) return 6;
    if (w >= 900) return 5;
    if (w >= 600) return 4;
    if (w >= 400) return 3;
    return 2;
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
