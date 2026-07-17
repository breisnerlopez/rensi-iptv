import 'package:flutter/material.dart';
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
    this.scale = 1.06,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double scale;

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (focused) {
      // Pull the freshly focused tile into view across every enclosing
      // scrollable (the vertical category list *and* the horizontal
      // carousel), so D-pad travel never leaves the highlight off-screen.
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
    final ring = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : Theme.of(context).colorScheme.primary;

    return AnimatedScale(
      scale: _focused ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: radius,
          // Always a 3 px border so the surrounding layout never shifts when
          // focus arrives — only the colour changes.
          border: Border.all(
            color: _focused ? ring : Colors.transparent,
            width: 3,
          ),
          // Neutral elevation (the tile "lifts"), NOT a saturated colour glow.
          boxShadow: _focused
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
