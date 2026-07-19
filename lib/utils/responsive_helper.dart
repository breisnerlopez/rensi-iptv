import 'dart:math' as math;
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

  /// Fraction of the panel a consumer TV may still crop.
  static const double overscanFraction = 0.05;

  /// Side margin that keeps content clear of a TV's overscan cut. Anything
  /// drawn at x=0 may simply not exist for the viewer — including a focus ring,
  /// which is the one thing that must never be invisible.
  ///
  /// Proportional, not fixed: overscan is a percentage of the panel. The old
  /// flat 48dp happened to equal 5% only because a 1080p TV reports 960dp; on a
  /// wider surface it silently shrank to 3.75% and content crept back into the
  /// crop zone.
  static double safeInset(BuildContext context) {
    // 24 on phones: matches the margin the screens already used, so adopting
    // this helper does not silently narrow a touch layout.
    if (!isDesktopOrTV(context)) return 24;
    final w = MediaQuery.of(context).size.width;
    // A narrow surface can report as "TV" via NavigationMode.directional (a
    // phone with a remote paired). Reserving a TV overscan margin there would
    // throw away a third of a 360dp screen, so cap the inset at a sane share.
    return math.min(w * 0.12, math.max(_tvSafe, w * overscanFraction));
  }

  /// How much [FocusHighlight] grows a focused element. Kept here because the
  /// safe-width maths below has to account for it; the two must not drift.
  static const double focusZoom = 1.06;

  /// Widest a column of content may be on a 10-foot screen and still keep its
  /// focus ring on the picture.
  ///
  /// This has to be computed, not a constant. An Android TV reports its 1080p
  /// panel as **960×540 logical dp** (dpr 2.0 at 320 dpi) — and a 4K panel
  /// reports the same 960 dp — so any figure written in pixel-sized numbers
  /// silently never binds. Worse, a naive `width - 2*inset` still overflows:
  /// [FocusHighlight] scales the focused element by [focusZoom], so a row
  /// filling the safe area grows back out past it the moment it takes focus.
  /// Dividing by the zoom is what actually keeps the ring inside the overscan
  /// margin.
  static double tvMaxContentWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return math.max(1.0, (w - 2 * safeInset(context)) / focusZoom);
  }
  static const double _tvGutter = 20;
  // 150, not 200. At 200 the grid resolved to 3 columns on a 960dp TV — Netflix,
  // Prime and Google TV all show 5-6 — and it made the same RensiPoster render
  // 149dp on Home and 229dp in Browse, a 54% difference for one component.
  static const double _tvTargetTile = 150; // desired poster width at 3 m

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
      final avail = tvMaxContentWidth(context);
      final n = ((avail + _tvGutter) / (_tvTargetTile + _tvGutter)).floor();
      return n.clamp(5, 7);
    }
    // Phones showed 2 columns where Netflix, Prime and Plex show 3, so a
    // catalogue app displayed ~40% less of the thing it sells per screen.
    if (w >= 1200) return 6;
    if (w >= 900) return 5;
    if (w >= 600) return 4;
    return 3;
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
