import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

/// Wraps [child] with a TV-grade focus ring + slight zoom and pulls the
/// child into view whenever any descendant takes focus.
///
/// The wrapper observes its subtree with a non-focusable [Focus] node
/// (`canRequestFocus: false`), so the real focus target stays the child's
/// own button / InkWell — this keeps ripple, semantics and the theme focus
/// overlay intact while adding the loud border the framework defaults lack
/// on [Card] / [InkWell]. On phones the visual is a no-op so the heavier
/// stroke never bleeds into a touch UI.
class FocusHighlight extends StatefulWidget {
  const FocusHighlight({
    super.key,
    required this.child,
    this.borderRadius,
    this.shape,
    this.scale = ResponsiveHelper.focusZoom,
  });

  final Widget child;
  final BorderRadius? borderRadius;

  /// Overrides [borderRadius] when the child is not a plain rounded rect —
  /// a FilledButton defaults to a StadiumBorder, and ringing a pill with a
  /// 20dp rounded rectangle leaves visibly non-concentric corners.
  final OutlinedBorder? shape;
  final double scale;

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (focused && !_isFullyVisible()) {
      // Pull the freshly focused tile into view across every enclosing
      // scrollable (the vertical category list *and* the horizontal
      // carousel), so D-pad travel never leaves the highlight off-screen.
      //
      // Only when it is actually off-screen. Centring unconditionally meant
      // that simply *landing* on an already-visible control yanked the page —
      // on Home, autofocusing the hero's Play button scrolled the whole header
      // (logo, search, avatar) out of the list's build range, so it stopped
      // existing. Netflix and Google TV anchor the focused row instead of
      // recentring on every focus change.
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  /// True when this element already sits entirely inside every enclosing
  /// viewport, i.e. there is nothing to scroll into view.
  bool _isFullyVisible() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return true; // not inside a scrollable at all
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return true;

    final target = MatrixUtils.transformRect(
      box.getTransformTo(viewport as RenderObject),
      Offset.zero & box.size,
    );
    final bounds = Offset.zero & (viewport as RenderBox).size;
    return bounds.contains(target.topLeft) && bounds.contains(target.bottomRight);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(12);

    final observer = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: widget.child,
    );

    if (!ResponsiveHelper.isDesktopOrTV(context)) return observer;

    // Single, commercial-grade focus language (Netflix / Google TV): a clean
    // ring + a neutral "lift" shadow, no saturated colour glow (the old amber
    // clashed with the warm brand). White reads at 3 m on the dark theme; on the
    // light theme (white surfaces) fall back to the brand accent so the ring
    // never vanishes into a white card.
    // Same token the theme uses, so the ring cannot drift per widget.
    final ring = AppThemes.focusRing(Theme.of(context).brightness);

    return AnimatedScale(
      scale: _focused ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(3),
        decoration: ShapeDecoration(
          shape: (widget.shape ?? RoundedRectangleBorder(borderRadius: radius))
              .copyWith(
            side: BorderSide(
              color: _focused ? ring : Colors.transparent,
              width: 3,
            ),
          ),
          // Neutral elevation (the tile "lifts"), NOT a saturated colour glow.
          shadows: _focused
              ? const [
                  BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: observer,
      ),
    );
  }
}
