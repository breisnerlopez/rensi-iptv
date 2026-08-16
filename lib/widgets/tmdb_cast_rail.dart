import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart' show RensiRail;
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// A horizontal rail of circular actor avatars (TMDb `t/p/w185` profile photo,
/// name + character). Extracted from [TmdbEnrichment] so any surface — the
/// movie/series detail screens AND the global-search detail sheet — can render
/// the same cast rail with the same D-pad focus behaviour and RTL handling.
///
/// Presentational only: it filters out unnamed credits, caps the count, and
/// renders [SizedBox.shrink] when nothing is left, so callers can drop it in
/// under their own "Cast" header without a second emptiness guard.
///
/// Colours default to the ambient theme ([ColorScheme.onSurface]) so the rail
/// reads correctly on both the dark detail screens and a light/dark bottom
/// sheet; the enrichment passes explicit white to preserve its exact look on
/// the dark backdrop it sits on.
class TmdbCastRail extends StatelessWidget {
  const TmdbCastRail({
    super.key,
    required this.cast,
    this.height = 176,
    this.sidePadding = 0,
    this.maxCount = 20,
    this.nameColor,
    this.characterColor,
    this.onActorTap,
  });

  final List<TmdbCredit> cast;
  final double height;
  final double sidePadding;
  final int maxCount;

  /// Actor-name colour. Null → [ColorScheme.onSurface] (theme-aware).
  final Color? nameColor;

  /// Character-name colour. Null → a dimmed [ColorScheme.onSurface].
  final Color? characterColor;

  /// Invoked with the tapped cast member. When null the avatars are inert and
  /// (crucially on TV) non-focusable, so they aren't dead focus targets.
  final ValueChanged<TmdbCredit>? onActorTap;

  @override
  Widget build(BuildContext context) {
    final members =
        cast.where((c) => c.name.isNotEmpty).take(maxCount).toList();
    if (members.isEmpty) return const SizedBox.shrink();

    final onSurface = Theme.of(context).colorScheme.onSurface;
    final resolvedName = nameColor ?? onSurface;
    final resolvedChar =
        characterColor ?? onSurface.withValues(alpha: 0.66);

    return RensiRail(
      height: height,
      sidePadding: sidePadding,
      children: [
        for (final member in members)
          _CastAvatar(
            member: member,
            nameColor: resolvedName,
            characterColor: resolvedChar,
            onActorTap: onActorTap,
          ),
      ],
    );
  }
}

/// A single circular actor avatar with name + character. Wrapped in
/// [FocusHighlight] so the D-pad focus ring works on TV; the [InkWell] is the
/// real (focusable) target the highlight observes. A horizontal [RensiRail]
/// reverses itself under RTL automatically, so no manual mirroring is needed.
class _CastAvatar extends StatelessWidget {
  const _CastAvatar({
    required this.member,
    required this.nameColor,
    required this.characterColor,
    this.onActorTap,
  });

  final TmdbCredit member;
  final Color nameColor;
  final Color characterColor;
  final ValueChanged<TmdbCredit>? onActorTap;

  @override
  Widget build(BuildContext context) {
    const diameter = 84.0;
    final photo = member.profileUrl;
    return SizedBox(
      width: 104,
      child: FocusHighlight(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            // Wired to the actor's filmography when a handler is supplied; when
            // null the InkWell is disabled, so it is not a dead focus target.
            onTap: onActorTap == null ? null : () => onActorTap!(member),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: diameter,
                      height: diameter,
                      child: photo == null
                          ? _fallback()
                          : CachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.cover,
                              memCacheWidth: 240, // headshot de reparto (rail)
                              placeholder: (_, __) => _fallback(),
                              errorWidget: (_, __, ___) => _fallback(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: nameColor,
                      fontWeight: FontWeight.w600,
                      fontSize: AppThemes.tenFoot(context, 12),
                    ),
                  ),
                  if (member.character != null &&
                      member.character!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      member.character!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: characterColor,
                        fontSize: AppThemes.tenFoot(context, 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    // Derive the placeholder from the name colour so a white-on-dark rail keeps
    // its subtle white10/white38 look while a dark-on-light sheet stays visible.
    return Container(
      color: nameColor.withValues(alpha: 0.10),
      child: Icon(Icons.person, color: nameColor.withValues(alpha: 0.38), size: 40),
    );
  }
}
