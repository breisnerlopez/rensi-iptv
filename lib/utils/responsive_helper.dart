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

  /// The logical width the 10-foot layout's fixed-dp sizes were tuned for. A
  /// 1080p (and 4K) Android TV reports ~960 logical dp; a box that reports
  /// fewer dp makes every fixed component eat a bigger share of the panel,
  /// which reads as "everything too big / low resolution".
  static const double tvReferenceWidth = 960.0;

  /// Scale factor for TV component sizes, derived from the ACTUAL reported
  /// logical width vs [tvReferenceWidth], so chrome/type adapt to the panel
  /// instead of being fixed. 1.0 on a 960dp TV (preserves the known-good look
  /// exactly), <1 on a smaller-dp box; clamped so nothing collapses or
  /// balloons. Returns 1.0 off TV so phones/tablets are untouched.
  static double tvScale(BuildContext context) {
    // Gate on isDesktopOrTV — the SAME signal that switches on the large TV
    // component sizes — not isTenFoot. A box whose native TV flag is unset and
    // that isn't in directional-nav mode at this moment would otherwise render
    // the big TV chrome while tvScale returned 1.0 (no adaptation), which is
    // exactly "the scale fix didn't shrink anything".
    if (!isDesktopOrTV(context)) return 1.0;
    final mq = MediaQuery.of(context);
    // Respect a user's accessibility font scale: if they've enlarged text we do
    // NOT shrink anything — not the text (would fight a11y) and not the
    // dimensional sizes (a shrunk item box under an un-shrunk label overflows).
    if (mq.textScaler.scale(100) != 100) return 1.0;
    // Only ever shrink (cap at 1.0): a ≥960dp panel keeps the tuned look; a
    // smaller-dp box — which is what reads as "everything too big" — scales
    // down proportionally. Floor stops it collapsing on a tiny logical width.
    return (mq.size.width / tvReferenceWidth).clamp(0.62, 1.0);
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

  /// Should navigation be a side rail rather than a bottom bar?
  ///
  /// Material 3 puts the switch at 600dp, and every tablet streaming app agrees
  /// — Netflix and Prime move to a side column, Plex to a rail. A 10" tablet
  /// reports 800dp and was still getting a five-tab bottom bar stretched across
  /// 1250 physical pixels, which is the clearest single tell that a layout is a
  /// phone stretched rather than a tablet design.
  static bool useNavigationRail(BuildContext context) =>
      isDesktopOrTV(context) || MediaQuery.of(context).size.width >= 600;

  /// Widest a form or a primary action should get before it stops looking like
  /// a control and starts looking like a stretched box. A "Start watching"
  /// button 600dp wide is not a better target, it is a worse one.
  static const double maxActionWidth = 480;

  /// Single source of truth for "should this render the TV / 10-foot UI?".
  /// Priority: real TV device (native) > directional navigation (D-pad) >
  /// wide screen (desktop / large tablet fallback).
  static bool isDesktopOrTV(BuildContext context) {
    if (_isTelevisionDevice) return true;
    final nav = MediaQuery.maybeOf(context)?.navigationMode;
    if (nav == NavigationMode.directional) return true;
    return MediaQuery.of(context).size.width >= 900;
  }

  /// "Is the viewer three metres away?" — distinct from [isDesktopOrTV], which
  /// also answers yes to anything 900dp wide.
  ///
  /// Layout can and should react to width: a 900dp window has room for two
  /// columns whoever is looking at it. Type size cannot, because it is a
  /// function of viewing DISTANCE, and width does not imply distance. A large
  /// phone in landscape reports ~1010dp — the player overlay lives in landscape
  /// — and a desktop window is wider still; both are read at arm's length and
  /// would be bloated by 10-foot type.
  ///
  /// Deliberately reads only `MediaQuery.maybeNavigationModeOf` and not
  /// `MediaQuery.of`: the latter subscribes the caller to the ENTIRE
  /// MediaQueryData, so a size that is resolved once per screen would rebuild
  /// that screen on every viewInsets change — and in the player the system bars
  /// appear and disappear constantly. RensiKeyArt reaches for
  /// `devicePixelRatioOf` for the same reason
  /// (lib/redesign/rensi_widgets.dart). The other helpers in THIS file still
  /// use `MediaQuery.of`, which is a live instance of the same trap and not
  /// something this doc should be read as claiming otherwise.
  static bool isTenFoot(BuildContext context) =>
      _isTelevisionDevice ||
      MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional;
}
