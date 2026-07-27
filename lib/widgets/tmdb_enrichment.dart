import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart' show RensiRail;
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// Weaves TMDb enrichment (cast photos, a richer overview, a trailer-key
/// fallback) into an IPTV movie/series detail screen.
///
/// It NEVER blocks the host screen and NEVER surfaces an error: while it
/// resolves, and on any failure (no key, rejected key, rate-limited, http,
/// network, or simply no confident match), it renders [SizedBox.shrink]. The
/// host's own content and its play button are entirely independent of this.
///
/// Matching:
///  * If [tmdbId] is present it is trusted directly (movies carry it in the raw
///    VOD info).
///  * Otherwise it falls back to a title+year search against the typed endpoint
///    and picks a CONFIDENT match only — an exact normalized-title match, or a
///    fuzzy title whose year also matches. No confident match → renders nothing,
///    so the wrong film's cast is never shown.
class TmdbEnrichment extends StatefulWidget {
  const TmdbEnrichment({
    super.key,
    required this.title,
    required this.mediaType,
    required this.locale,
    this.year,
    this.tmdbId,
    this.existingOverview,
    this.onTrailerKey,
  });

  final String title;
  final TmdbMediaType mediaType;
  final Locale locale;
  final int? year;
  final int? tmdbId;

  /// The overview the host already renders (from the IPTV plot). When it is
  /// empty, this widget fills the gap with the TMDb overview; when the host
  /// already has one, the TMDb overview is not repeated.
  final String? existingOverview;

  /// Invoked once with the best TMDb YouTube trailer key (or null) so the host's
  /// existing trailer button can use it as a fallback source.
  final ValueChanged<String?>? onTrailerKey;

  @override
  State<TmdbEnrichment> createState() => _TmdbEnrichmentState();
}

class _TmdbEnrichmentState extends State<TmdbEnrichment> {
  final TmdbService _tmdb = TmdbService();
  late Future<TmdbDetailResult?> _future;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant TmdbEnrichment old) {
    super.didUpdateWidget(old);
    // Only re-resolve (and re-notify the trailer key) when the match inputs
    // actually change. A parent setState triggered by our own onTrailerKey
    // callback keeps the inputs identical, so this must NOT restart the fetch.
    if (old.tmdbId != widget.tmdbId ||
        old.title != widget.title ||
        old.year != widget.year ||
        old.mediaType != widget.mediaType ||
        old.locale != widget.locale) {
      _start();
    }
  }

  void _start() {
    _future = _resolve();
    _future.then((detail) {
      if (!mounted) return;
      widget.onTrailerKey?.call(detail?.bestTrailer?.key);
    });
  }

  Future<TmdbDetailResult?> _resolve() async {
    try {
      final id = widget.tmdbId;
      if (id != null && id > 0) {
        return await _tmdb.detail(
          id,
          widget.mediaType,
          locale: widget.locale,
          withCredits: true,
        );
      }
      final title = widget.title.trim();
      if (title.isEmpty) return null;
      final results = await _tmdb.searchTitle(
        title,
        year: widget.year,
        mediaType: widget.mediaType,
        locale: widget.locale,
      );
      final best = _pickBest(results, title, widget.year);
      if (best == null) return null;
      return await _tmdb.detail(
        best.id,
        widget.mediaType,
        locale: widget.locale,
        withCredits: true,
      );
    } on TmdbException {
      // Typed failures (noKey/rejected/rateLimited/httpError/network) degrade
      // silently — this is enrichment, not a feature the user asked for.
      return null;
    } catch (e) {
      // Scrub before logging: a raw SocketException/timeout can embed the
      // request URI, and the v3 api_key rides in that query string.
      debugPrint('TMDb enrichment failed: ${scrubCredentials(e)}');
      return null;
    }
  }

  /// Picks a confident match, or null. Accepts on EITHER of two signals, and
  /// rejects only when there is neither a title nor a year signal:
  ///
  ///  1. A title match (fuzzy or exact) against the TMDb result's localized
  ///     title OR its original-language title — ranked exact-first, then
  ///     year-confirmed, then by TMDb's own relevance order.
  ///  2. No title match at all → trust TMDb's own search relevance for its TOP
  ///     result, but ONLY when the release year confirms it (±1). This lets a
  ///     localized catalogue title (e.g. "Horizonte Profundo") reconcile with a
  ///     differently-named TMDb title ("Marea negra") that TMDb's search already
  ///     surfaced as the best hit. Requiring the year here keeps the wrong film
  ///     out when the title gives no signal.
  TmdbSearchResult? _pickBest(
    List<TmdbSearchResult> results,
    String title,
    int? year,
  ) {
    final typed =
        results.where((r) => r.mediaType == widget.mediaType).toList();
    if (typed.isEmpty) return null;

    bool exactMatch(TmdbSearchResult r) =>
        GlobalSearchService.isExactTitleMatch(title, r.title) ||
        (r.originalTitle != null &&
            GlobalSearchService.isExactTitleMatch(title, r.originalTitle!));
    bool fuzzyMatch(TmdbSearchResult r) =>
        GlobalSearchService.isFuzzyTitleMatch(title, r.title) ||
        (r.originalTitle != null &&
            GlobalSearchService.isFuzzyTitleMatch(title, r.originalTitle!));
    bool yearMatch(TmdbSearchResult r) {
      final y = _yearOf(r);
      return year != null && y != null && (y - year).abs() <= 1;
    }

    // 1) Title signal present: rank exact-first, then year-confirmed, then keep
    //    TMDb's popularity/relevance order as the tie-break.
    final titled = typed.where(fuzzyMatch).toList();
    if (titled.isNotEmpty) {
      int rank(TmdbSearchResult r) =>
          (exactMatch(r) ? 2 : 0) + (yearMatch(r) ? 1 : 0);
      titled.sort((a, b) {
        final byRank = rank(b).compareTo(rank(a));
        if (byRank != 0) return byRank;
        return typed.indexOf(a).compareTo(typed.indexOf(b));
      });
      final best = titled.first;
      // A FUZZY-only title with no year is too weak to enrich with — a bare
      // substring ("Halloween" ~ "Halloween Kills") would show the wrong film's
      // cast. Trust it only when the title is exact OR the year confirms it;
      // otherwise fall through to the year-gated top-hit branch below.
      if (exactMatch(best) || yearMatch(best)) return best;
    }

    // 2) No title signal: accept TMDb's top hit only if the year confirms it.
    final top = typed.first;
    if (yearMatch(top)) return top;

    return null;
  }

  int? _yearOf(TmdbSearchResult r) {
    final y = r.releaseYear;
    return y == null ? null : int.tryParse(y);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TmdbDetailResult?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final detail = snapshot.data;
        if (detail == null) return const SizedBox.shrink();

        final cast =
            detail.cast.where((c) => c.name.isNotEmpty).take(20).toList();
        final hostOverview = widget.existingOverview?.trim() ?? '';
        final tmdbOverview = detail.overview?.trim() ?? '';
        final showOverview = hostOverview.isEmpty && tmdbOverview.isNotEmpty;

        if (cast.isEmpty && !showOverview) return const SizedBox.shrink();

        final theme = Theme.of(context);
        // Own the bottom gap so the host can drop the widget in unconditionally:
        // when nothing renders it is a zero-size shrink with no phantom spacing.
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showOverview) ...[
              Text(
                context.loc.description,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tmdbOverview,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
              if (cast.isNotEmpty) const SizedBox(height: 24),
            ],
            if (cast.isNotEmpty) ...[
              Text(
                context.loc.cast,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
              RensiRail(
                height: 176,
                sidePadding: 0,
                children: [
                  for (final member in cast) _CastAvatar(member: member),
                ],
              ),
            ],
          ],
          ),
        );
      },
    );
  }
}

/// A single circular actor avatar with name + character. Wrapped in
/// [FocusHighlight] so the D-pad focus ring works on TV; the [InkWell] is the
/// real (focusable) target the highlight observes. A horizontal [RensiRail]
/// reverses itself under RTL automatically, so no manual mirroring is needed.
class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.member});

  final TmdbCredit member;

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
            // Focusable, but intentionally inert: Phase 1 has no actor page.
            onTap: () {},
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
                          ? _fallback(context)
                          : CachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _fallback(context),
                              errorWidget: (_, __, ___) => _fallback(context),
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
                      color: Colors.white,
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
                        color: Colors.white54,
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

  Widget _fallback(BuildContext context) {
    return Container(
      color: Colors.white10,
      child: const Icon(Icons.person, color: Colors.white38, size: 40),
    );
  }
}
