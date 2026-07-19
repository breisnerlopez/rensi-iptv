import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// Shared primitives for the cinematic redesign. They read tokens from the
/// [RensiColors] theme extension so they track the dark/light themes.

RensiColors rensi(BuildContext c) => Theme.of(c).extension<RensiColors>()!;

/// Cover image for a content item: real poster when available, otherwise a
/// generative terracotta-tinted gradient with the title (the "key-art"
/// fallback from the handoff).
class RensiKeyArt extends StatelessWidget {
  const RensiKeyArt({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
    this.preferBackdrop = false,
    this.titleScale = 1.0,
  });
  final ContentItem item;
  final BoxFit fit;

  /// Use the 16:9 backdrop when the provider supplied one. Only worth it in a
  /// wide slot (the hero); in a 2:3 tile the poster is the right art.
  final bool preferBackdrop;

  /// Scales the fallback title with the slot. A fixed 14dp looked correct in a
  /// 168dp tile and absurd in an 888x520 hero.
  final double titleScale;

  String? get _backdrop {
    final b = item.seriesStream?.backdropPath;
    if (b != null && b.isNotEmpty && b.first.isNotEmpty) return b.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final source = preferBackdrop ? (_backdrop ?? item.imagePath) : item.imagePath;
    if (source.isNotEmpty) {
      // Decode posters at the slot's physical size, not full source resolution.
      // IPTV posters ship at ~600x900–1000x1500; decoding those full-res into a
      // ~190dp tile blows the ImageCache (100MB) on a TV box, causing re-decode
      // thrashing + GC pauses = the classic scroll stutter. memCacheWidth caps
      // the decode to the display width (aspect preserved). Same pattern already
      // used in global_search_screen.dart / m3u_items_screen.dart.
      return LayoutBuilder(
        builder: (context, constraints) {
          // devicePixelRatioOf (not MediaQuery.of) so a poster doesn't rebuild on
          // unrelated MediaQuery changes (keyboard insets, textScale, orientation).
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final w = (constraints.maxWidth.isFinite ? constraints.maxWidth : 200) * dpr;
          final cw = w.round();
          return CachedNetworkImage(
            imageUrl: source,
            fit: fit,
            // Guard the degenerate 0-width layout (would be an invalid decode size).
            memCacheWidth: cw > 0 ? cw : null,
            placeholder: (_, __) => _fallback(context),
            errorWidget: (_, __, ___) => _fallback(context),
          );
        },
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    // Sized to the slot: a flat 14dp read as a tiny ghost caption inside the
    // 888x520 hero, duplicating the 52dp title right below it.
    // Stable but BRAND-COHESIVE art: constrain the hue to a warm terracotta/
    // amber band (not a random 0-360° rainbow) and keep it dark, so a rail full
    // of missing posters reads as one curated system, like Plex/TiviMate.
    final seed = item.id.hashCode.abs();
    final hue = (6 + seed % 34).toDouble(); // 6°..40°, brand warm family
    final g1 = HSLColor.fromAHSL(1, hue, 0.30, 0.17).toColor();
    final g2 = HSLColor.fromAHSL(1, (hue + 10) % 360, 0.24, 0.10).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [g1, g2],
        ),
      ),
      child: titleScale <= 0
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth.isFinite ? c.maxWidth : 200.0;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      item.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Bricolage Grotesque',
                        fontWeight: FontWeight.w700,
                        fontSize: (w * 0.11 * titleScale).clamp(12.0, 34.0),
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

const _scrim = LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [Color(0xF0080808), Color(0x99080808), Color(0x00080808)],
  stops: [0.0, 0.38, 0.75],
);

/// 2:3 poster card with optional badge + meta. Wrapped in [FocusHighlight]
/// so it gets the TV focus ring/zoom for free.
class RensiPoster extends StatefulWidget {
  const RensiPoster({
    super.key,
    required this.item,
    this.width = 138,
    this.onTap,
    // Null = reveal on focus (the Google TV pattern). The old default printed
    // the title over EVERY cover, darkening its bottom 38% at 94% opacity to
    // repeat what the artwork already says. Netflix and Prime print nothing on
    // the poster; Plex puts the title below it; Google TV shows it only for the
    // item you are actually on. Pass true/false to force it either way.
    this.showMeta,
    this.badge,
    this.autofocus = false,
  });

  final ContentItem item;
  final double width;
  final VoidCallback? onTap;
  final bool? showMeta;
  final String? badge;
  final bool autofocus;

  @override
  State<RensiPoster> createState() => _RensiPosterState();
}

class _RensiPosterState extends State<RensiPoster> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final width = widget.width;
    final autofocus = widget.autofocus;
    final onTap = widget.onTap;
    final showMeta = widget.showMeta ?? _focused;
    final r = rensi(context);
    final h = width * 1.5; // true 2:3; was 1.48, cropping the artwork 1.3%
    final tag = widget.badge ?? _tagFor(item);
    return FocusHighlight(
      borderRadius: BorderRadius.circular(14),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) {
          if (f != _focused) setState(() => _focused = f);
        },
        child: SizedBox(
        width: width,
        height: h,
        child: Material(
          color: Colors.black,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: r.hairline),
          ),
          child: InkWell(
            onTap: onTap,
            autofocus: autofocus,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RensiKeyArt(item: item),
                if (showMeta || tag != null)
                  const DecoratedBox(decoration: BoxDecoration(gradient: _scrim)),
                if (tag != null)
                  Positioned(
                    top: 9,
                    left: 9,
                    child: _Badge(text: tag),
                  ),
                if (showMeta)
                  Positioned(
                    left: 11,
                    right: 11,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Bricolage Grotesque',
                            // Larger at a 3 m viewing distance on TV.
                            fontSize:
                                ResponsiveHelper.isDesktopOrTV(context) ? 18 : 15,
                            fontWeight: FontWeight.w700,
                            height: 1.06,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  static String? _tagFor(ContentItem item) => null;

}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: r.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: r.onAccent,
        ),
      ),
    );
  }
}

/// Slim progress bar (continue-watching / live progress).
class RensiProgress extends StatelessWidget {
  const RensiProgress({super.key, required this.value, this.height = 4, this.track});
  final double value;
  final double height;
  final Color? track;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: track ?? r.surface3,
        valueColor: AlwaysStoppedAnimation(r.accent),
      ),
    );
  }
}

/// Pill chip used for genre / category filters.
class RensiChip extends StatelessWidget {
  const RensiChip({super.key, required this.label, required this.active, this.onTap});
  final String label;
  final bool active;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final theme = Theme.of(context);
    return FocusHighlight(
      borderRadius: BorderRadius.circular(999),
      child: Material(
        color: active ? theme.colorScheme.onSurface : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: active ? Colors.transparent : r.hairline2),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: active ? theme.colorScheme.surface : r.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header with optional "Ver todo" action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
      {super.key,
      required this.title,
      this.actionLabel,
      this.onAction,
      this.sidePad = 20});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double sidePad;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final big = sidePad >= 40;
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Bricolage Grotesque',
              fontSize: big ? 24 : 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (actionLabel != null)
            FocusHighlight(
              borderRadius: BorderRadius.circular(8),
              child: TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: r.text3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal rail of posters.
class RensiRail extends StatelessWidget {
  const RensiRail(
      {super.key,
      required this.children,
      this.height,
      this.sidePadding = 20,
      this.posterWidth = 138});
  final List<Widget> children;
  final double? height;
  final double sidePadding;
  final double posterWidth;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? posterWidth * 1.48 + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Pre-build a few posters beyond the viewport so D-pad focus can jump
        // to the next tile without waiting for the scroll to catch up.
        cacheExtent: 1200,
        padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 4),
        itemCount: children.length,
        separatorBuilder: (_, __) => SizedBox(width: sidePadding >= 40 ? 16 : 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// Keeps a column of content inside the TV-safe area and off the overscan cut.
///
/// On a phone this is a plain padded box. On a 10-foot screen it also caps the
/// measure at [ResponsiveHelper.tvMaxContentWidth] and centres it: full-bleed
/// content on a 1920 px panel puts the focus ring — grown 6% by
/// [FocusHighlight] — past the edge of the picture, where a consumer TV simply
/// does not draw it. A focus indicator the viewer cannot see is the same as no
/// focus indicator at all.
class RensiSafeColumn extends StatelessWidget {
  const RensiSafeColumn({
    super.key,
    required this.child,
    this.verticalPadding = 24,
  });

  final Widget child;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveHelper.isDesktopOrTV(context)) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.safeInset(context),
          vertical: verticalPadding,
        ),
        child: child,
      );
    }
    // On TV the cap already reserves the overscan margin, and centring is what
    // turns it into whitespace. Adding horizontal padding on top would subtract
    // the inset twice and leave the column needlessly narrow.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.tvMaxContentWidth(context),
        ),
        child: Padding(
          // Overscan crops the top and bottom too. 24dp is under the 5% of a
          // 540dp-tall TV surface, so derive it the same way as the sides.
          padding: EdgeInsets.symmetric(
            vertical: math.max(
              verticalPadding,
              MediaQuery.of(context).size.height *
                  ResponsiveHelper.overscanFraction,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
