import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// Shared primitives for the cinematic redesign. They read tokens from the
/// [RensiColors] theme extension so they track the dark/light themes.

RensiColors rensi(BuildContext c) => Theme.of(c).extension<RensiColors>()!;

/// Cover image for a content item: real poster when available, otherwise a
/// generative terracotta-tinted gradient with the title (the "key-art"
/// fallback from the handoff).
class RensiKeyArt extends StatelessWidget {
  const RensiKeyArt({super.key, required this.item, this.fit = BoxFit.cover});
  final ContentItem item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (item.imagePath.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.imagePath,
        fit: fit,
        placeholder: (_, __) => _fallback(context),
        errorWidget: (_, __, ___) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final r = rensi(context);
    // Stable hue from the id so each title keeps the same art.
    final seed = item.id.hashCode;
    final g1 = HSLColor.fromAHSL(1, (seed % 360).toDouble(), 0.45, 0.22).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [g1, r.accent.withValues(alpha: 0.85)],
        ),
      ),
      child: Center(
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
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ),
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
class RensiPoster extends StatelessWidget {
  const RensiPoster({
    super.key,
    required this.item,
    this.width = 138,
    this.onTap,
    this.showMeta = true,
    this.badge,
    this.autofocus = false,
  });

  final ContentItem item;
  final double width;
  final VoidCallback? onTap;
  final bool showMeta;
  final String? badge;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final h = width * 1.48;
    final tag = badge ?? _tagFor(item);
    return FocusHighlight(
      borderRadius: BorderRadius.circular(14),
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
                          style: const TextStyle(
                            fontFamily: 'Bricolage Grotesque',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.06,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitleFor(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.78),
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
    );
  }

  static String? _tagFor(ContentItem item) => null;

  static String _subtitleFor(ContentItem item) {
    switch (item.contentType) {
      case ContentType.liveStream:
        return 'En vivo';
      case ContentType.vod:
        return 'Película';
      case ContentType.series:
        return 'Serie';
    }
  }
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
        padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 4),
        itemCount: children.length,
        separatorBuilder: (_, __) => SizedBox(width: sidePadding >= 40 ? 16 : 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}
