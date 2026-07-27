import 'package:flutter/material.dart';

import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'package:rensi_iptv/widgets/tmdb_cast_rail.dart';

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
      final raw = widget.title.trim();
      if (raw.isEmpty) return null;
      // Provider VOD names are dirty — "Horizonte profundo Desastre en el golfo
      // (2016).mp4" returns NOTHING from TMDb. Clean it, then progressively drop
      // trailing words so an appended subtitle/junk suffix can't block the match
      // (verified: the full string → 0 hits, "Horizonte profundo" → the film).
      for (final query in _searchCandidates(raw)) {
        final results = await _tmdb.searchTitle(
          query,
          year: widget.year,
          mediaType: widget.mediaType,
          locale: widget.locale,
        );
        final best = _pickBest(results, query, widget.year);
        if (best != null) {
          return await _tmdb.detail(
            best.id,
            widget.mediaType,
            locale: widget.locale,
            withCredits: true,
          );
        }
      }
      return null;
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

  /// Strips a provider VOD filename down to a searchable title: file extension,
  /// bracketed/parenthesised tags, a bare year, and common quality/release
  /// tokens ("4K", "1080p", "DUAL", "60 FPS", …).
  static String _cleanTitle(String s) {
    var t = s;
    t = t.replaceAll(
        RegExp(r'\.(mp4|mkv|avi|ts|m3u8|mov|flv|wmv|webm)$',
            caseSensitive: false),
        ' ');
    t = t.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');
    t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    t = t.replaceAll(
        RegExp(
            r'\b(4k|uhd|fhd|hd|sd|2160p?|1080p?|720p?|480p?|dual|lat(ino)?|'
            r'sub(s|titulad[oa])?|cam|hdrip|bdrip|web[\s-]?dl|x264|x265|hevc|'
            r'\d{2,3}\s?fps)\b',
            caseSensitive: false),
        ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Search queries to try in order: the cleaned full title, then its first 3
  /// and first 2 words. The real title almost always LEADS the provider name
  /// ("Horizonte profundo" + subtitle "Desastre en el golfo"), so trying the
  /// leading words after the full string lets an appended subtitle stop
  /// blocking the match. Capped at 3 so a miss costs a few (cached) TMDb calls;
  /// _pickBest's year gate keeps a short prefix from matching the wrong film.
  static List<String> _searchCandidates(String raw) {
    final cleaned = _cleanTitle(raw);
    final words =
        cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    void add(String q) {
      if (q.isNotEmpty && !out.contains(q)) out.add(q);
    }

    add(cleaned);
    if (words.length > 3) add(words.take(3).join(' '));
    if (words.length > 2) add(words.take(2).join(' '));
    return out.isEmpty ? [raw.trim()] : out;
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
              // Same rail, now shared with the global-search detail sheet.
              // Explicit white keeps the exact look on this dark backdrop.
              TmdbCastRail(
                cast: cast,
                nameColor: Colors.white,
                characterColor: Colors.white54,
              ),
            ],
          ],
          ),
        );
      },
    );
  }
}

