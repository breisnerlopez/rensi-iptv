import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/controllers/category_detail_controller.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/redesign/search_detail_sheet.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:rensi_iptv/utils/genre_utils.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

/// Above this many merged items we log the size (never truncate) so a rare
/// pathological multi-playlist catalogue is diagnosable — see [_loadFull].
const int _kLargeCatalogueLogThreshold = 30000;

/// Diacritic-folding table (mirrors TmdbService's private one, kept local so
/// Browse's chip dedup depends on no service internal).
const String _kGenreAccents =
    'àáâäãåèéêëìíîïòóôöõùúûüñçÀÁÂÄÃÅÈÉÊËÌÍÎÏÒÓÔÖÕÙÚÛÜÑÇ';
const String _kGenrePlain =
    'aaaaaaeeeeiiiiooooouuuuncaaaaaaeeeeiiiiooooouuuunc';

/// Folds a genre label for NEAR-DUPLICATE chip collapsing and its zero-loss
/// filter: lowercase, diacritics stripped, connectors ("&"/"+"/"y"/"and"/"e"/
/// "et") canonicalized to the single token "and", every other run of
/// punctuation/whitespace collapsed to one space. So "Acción"/"Accion",
/// "Action & Adventure"/"Action and Adventure" and "Sci-Fi & Fantasy"/"Sci Fi
/// and Fantasy" each fold to ONE key. Letters/digits of any script survive
/// (Cyrillic/CJK genres are not stripped).
String foldGenreLabel(String input) {
  final buf = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = _kGenreAccents.indexOf(ch);
    buf.write(i >= 0 ? _kGenrePlain[i] : ch);
  }
  var s = buf.toString().replaceAll(RegExp(r'[&+]'), ' and ');
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
  if (s.isEmpty) return s;
  const connectors = {'y', 'and', 'e', 'et'};
  return s
      .split(' ')
      .where((t) => t.isNotEmpty)
      .map((t) => connectors.contains(t) ? 'and' : t)
      .join(' ');
}

/// Wraps a horizontal chip row/list in a [ShaderMask] that fades the leading
/// and trailing ~24px to transparent, so a scrollable chip strip dissolves at
/// the edges instead of being cut off at a hard line. The gradient's alpha is
/// what matters (BlendMode.dstIn), so the RGB colour is irrelevant — it never
/// tints the theme. Painting-only: the mask does not intercept hit-testing, so
/// scrolling and taps still reach the chips underneath.
Widget _fadeEdges(Widget child) {
  const double fade = 24.0;
  return ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (Rect bounds) {
      // Rows narrower than two fade zones would fade to nothing; keep them
      // fully opaque instead.
      if (bounds.width <= fade * 2) {
        return const LinearGradient(
          colors: [Colors.black, Colors.black],
        ).createShader(bounds);
      }
      final double f = fade / bounds.width;
      return LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0.0, f, 1 - f, 1.0],
      ).createShader(bounds);
    },
    child: child,
  );
}

/// "Explorar" — type tabs (Todo / Películas / Series) + genre chips over a
/// 3-column poster grid, fed by the real catalogue.
///
/// GLOBAL across playlists: the grid merges EVERY playlist's VOD+series
/// catalogue (not just the active one), deduped and newest-first. NOTE this
/// changed the single-playlist case too: even with one playlist the grid now
/// collapses same-`tmdbId` movie copies and sorts by date-added desc, whereas
/// it previously showed the active playlist's preview order unsorted.
class BrowseRedesign extends StatefulWidget {
  const BrowseRedesign({
    super.key,
    required this.movieCategories,
    required this.seriesCategories,
    required this.onOpen,
    this.onSearch,
  });

  final List<CategoryViewModel> movieCategories;
  final List<CategoryViewModel> seriesCategories;

  /// Opens (navigates to) an item and completes when that route POPS. Awaitable
  /// on purpose: Browse repoints AppState to a cross-playlist item's origin to
  /// play it, then awaits this to restore the active playlist on return. Both
  /// mount sites already pass `navigateByContentType`, which returns exactly
  /// that pop-future, so this type is satisfied without a mount-site change.
  final Future<void> Function(ContentItem) onOpen;
  final VoidCallback? onSearch;

  @override
  State<BrowseRedesign> createState() => _BrowseRedesignState();
}

class _BrowseRedesignState extends State<BrowseRedesign> {
  String _tab = 'all'; // all | movies | series
  String _genre = 'Todos';

  // Memoized catalogue. Flattening (with dedup) + genre extraction (RegExp) is
  // O(N) over the whole catalogue and used to run on EVERY build. Since this
  // screen lives in an IndexedStack under a Consumer, an unrelated
  // notifyListeners rebuilt it and re-did all that work even off-screen (a short
  // freeze on tab/filter taps on a weak TV box). We now recompute only when the
  // catalogue content actually changes, keyed by a cheap signature.
  int _sig = -1;
  List<ContentItem> _moviesFlat = const [];
  List<ContentItem> _seriesFlat = const [];
  List<ContentItem> _allFlat = const [];
  List<String> _genresMovies = const ['Todos'];
  List<String> _genresSeries = const ['Todos'];
  List<String> _genresAll = const ['Todos'];
  // fold-key → every original genre spelling that folds to it (accent/connector/
  // punctuation variants). Lets a deduped chip filter the grid ZERO-LOSS: an
  // item tagged with ANY equivalent spelling still matches the one chip shown.
  Map<String, List<String>> _genreVariants = const {};
  final Map<String, List<ContentItem>> _filterCache = {};

  // GLOBAL FULL catalogue. Browse only receives PREVIEW CategoryViewModels for
  // the ACTIVE playlist (each capped at ~10 items), so genre chips built from
  // them covered a tiny slice — pick "Terror" and most horror titles were
  // missing. We now load the whole VOD + Series catalogue across EVERY playlist
  // once, via GlobalSearchService.globalCatalogue() (the same PlaylistService
  // fan-out global search uses), de-duplicate by logical title, and sort newest
  // first, then rebuild the chips and grid from these. First paint still comes
  // from the active playlist's previews so the screen is never blank while this
  // resolves; the load never blocks and degrades to preview-only on any failure
  // or when the merge is empty (e.g. a widget test with no seeded playlists).
  //
  // Each merged item is deduped/sorted here (once per catalogue change), NOT on
  // every build — see [_signature]/[_ensureBase]. The heavy fan-out + dedup +
  // date-sort therefore runs once; the memoized GlobalSearchService also caches
  // the raw per-playlist reads so a Browse rebuild never re-reads the DB.
  List<ContentItem> _fullMovies = const [];
  List<ContentItem> _fullSeries = const [];
  bool _fullLoaded = false;
  Future<void>? _loadFut;

  /// Bumped on every successful (non-empty) full (re)load and folded into
  /// [_signature], so a catalogue re-sync that swaps content while keeping the
  /// same item counts still forces exactly one recompute (a length-only
  /// signature could miss a remove+add that nets to the same totals).
  int _fullReloads = 0;

  /// Invalidate-and-reload subscription: a background catalogue re-sync emits
  /// `catalogue_changed`, on which we drop the memoized global catalogue and
  /// reload so a deleted title (dead URL) stops showing without an app restart.
  StreamSubscription<dynamic>? _catalogueSub;

  /// Shared with global search: the fan-out over ALL playlists + the memoized
  /// per-playlist catalogue live here. Held for Browse's lifetime so its cache
  /// survives tab/genre taps and unrelated rebuilds.
  final GlobalSearchService _search = GlobalSearchService();

  /// Origin playlist per merged item, so opening a card can repoint AppState to
  /// the item's ORIGIN playlist (which may not be the active one) BEFORE
  /// navigating — the exact contract of [GlobalSearchService.openLocalMatch].
  /// Identity-keyed: the same ContentItem instances flow through dedup, genre
  /// filter and the grid, so a plain map keyed on the instance is stable.
  final Map<ContentItem, Playlist> _originOf = {};

  /// Date-added per merged item, precomputed ONCE during the load so the two
  /// sorts (per-type dedup sort + the "Todo" merge sort) and the richer-wins
  /// tiebreak are O(1) lookups instead of re-deriving the timestamp O(n log n)
  /// times on the UI isolate. Identity-keyed like [_originOf].
  final Map<ContentItem, DateTime> _dateOf = {};

  /// The in-flight (or settled) full-catalogue load, so a test can await the
  /// previews→full transition deterministically instead of guessing at pumps.
  @visibleForTesting
  Future<void>? get loadFuture => _loadFut;

  /// Count of merged movies after the global dedup — for the volume/anti-ANR test.
  @visibleForTesting
  int get debugFullMovieCount => _fullMovies.length;

  /// One GlobalKey per genre chip, so [_selectGenre] can scroll the active chip
  /// fully into view on D-pad/TV and in RTL (mirrors search_redesign).
  final Map<String, GlobalKey> _chipKeys = {};

  /// Incremented each time the heavy flatten/genre recompute runs; lets a test
  /// assert that unrelated rebuilds don't re-flatten the whole catalogue.
  @visibleForTesting
  int recomputes = 0;

  @override
  void initState() {
    super.initState();
    // Kick off the one-shot GLOBAL full load. It fans out over every playlist
    // (not just the active one), so no mount-site change is needed.
    _loadFut = _loadFull();
    // A background catalogue re-sync (same playlists, changed rows) invalidates
    // the id-set-keyed cache and reloads the grid.
    _catalogueSub = EventBus().on<dynamic>('catalogue_changed').listen((_) {
      if (!mounted) return;
      _search.invalidateGlobalCatalogue();
      _loadFut = _loadFull();
    });
  }

  @override
  void dispose() {
    _catalogueSub?.cancel();
    super.dispose();
  }

  /// Loads the entire VOD + Series catalogue across ALL playlists via
  /// [GlobalSearchService.globalCatalogue] (the same fan-out global search
  /// uses), then de-duplicates by logical title and sorts newest-first. Wrapped
  /// in try/catch so a missing DB (widget tests) degrades to preview-only
  /// instead of throwing into the tree.
  ///
  /// State is only flipped when the merge is NON-empty: an empty result (no
  /// playlists, or a test with none seeded) leaves [_fullLoaded] false so the
  /// active-playlist previews keep the screen populated and the memoization
  /// signature does not needlessly flip.
  Future<void> _loadFull() async {
    try {
      final catalogue = await _search.globalCatalogue();
      if (!mounted || catalogue.isEmpty) return;

      // Precompute the date-added of every item ONCE (see [_dateOf]); the two
      // sorts and the richer-wins tiebreak below then only do map lookups.
      final dateOf = <ContentItem, DateTime>{
        for (final m in catalogue)
          m.content: CategoryDetailController.dateAddedFor(m.content),
      };

      // OBSERVABILITY (perf): the fan-out builds the FULL catalogue of N
      // playlists in memory, deduped + sorted ONCE here (memoized; never on
      // rebuild — see [_signature]/[_ensureBase]), so no isolate is needed while
      // the result is cached. We do NOT truncate — Browse must lose no title —
      // but we log an unusually large merge so an OOM/ANR on a weak TV box is
      // diagnosable rather than silent.
      if (catalogue.length > _kLargeCatalogueLogThreshold) {
        debugPrint('BrowseRedesign: large global catalogue '
            '(${catalogue.length} items across all playlists) — merged/sorted '
            'once and memoized; not truncated.');
      }

      // Split by type; dedup each type independently (a movie and a series that
      // share a title are distinct works and must both survive), then sort each
      // newest-first. The origin map is rebuilt from the survivors.
      final movieMatches = <LocalContentMatch>[];
      final seriesMatches = <LocalContentMatch>[];
      for (final m in catalogue) {
        switch (m.content.contentType) {
          case ContentType.vod:
            movieMatches.add(m);
            break;
          case ContentType.series:
            seriesMatches.add(m);
            break;
          case ContentType.liveStream:
            break; // Browse is movies + series only.
        }
      }

      final origin = <ContentItem, Playlist>{};
      final movies = _dedupAndSort(movieMatches, origin, dateOf);
      final series = _dedupAndSort(seriesMatches, origin, dateOf);

      setState(() {
        _fullMovies = movies;
        _fullSeries = series;
        _originOf
          ..clear()
          ..addAll(origin);
        _dateOf
          ..clear()
          ..addAll(dateOf);
        _fullReloads++;
        _fullLoaded = true; // flips the signature → recompute from full lists
      });
    } catch (_) {
      // Degrade to preview-only; never throw into a test/home without a DB.
    }
  }

  /// De-duplicates [matches] to the DISTINCT playable copies, records each
  /// survivor's origin playlist into [origin], and returns them sorted
  /// most-recently-added first (dates read from the precomputed [dateOf]).
  ///
  /// LOSSLESS dedup (point 2 — the grid has no variant selector, so a collapsed
  /// copy would be unreachable = data loss):
  ///  - Movies collapse across playlists by DEFINITIVE `tmdbId` only (the same
  ///    film; any owned copy plays it). A movie WITHOUT a tmdbId is NOT collapsed
  ///    by title — two distinct works normalize identically ("El Rey León" 1994
  ///    vs 2019) and title-collapse would silently drop one.
  ///  - Series are NEVER collapsed: distinct series_ids can be different shows
  ///    ("The Office" US/UK) OR different season-pack copies of one show (a 1-
  ///    vs a 7-season variant) the user must be able to choose between, so each
  ///    stays its own reachable card.
  ///  - M3U and anything else: keyed by stream identity, never collapsed.
  /// Only a stream reconciled in twice (identical dedupKey) is folded. When a
  /// movie tmdbId collides, the RICHER copy wins (poster, then fresher).
  List<ContentItem> _dedupAndSort(
    List<LocalContentMatch> matches,
    Map<ContentItem, Playlist> origin,
    Map<ContentItem, DateTime> dateOf,
  ) {
    final byKey = <String, LocalContentMatch>{};
    for (final m in matches) {
      final key = _dedupKey(m);
      final existing = byKey[key];
      if (existing == null || _isRicher(m, existing, dateOf)) {
        byKey[key] = m;
      }
    }
    final survivors = byKey.values.toList();
    // Newest first; M3U (and any item without a usable timestamp) sits at the
    // epoch and sinks to the bottom — its "no date sort" degradation.
    survivors.sort((a, b) =>
        _dateOfIn(dateOf, b.content).compareTo(_dateOfIn(dateOf, a.content)));
    final out = <ContentItem>[];
    for (final m in survivors) {
      origin[m.content] = m.playlist;
      out.add(m.content);
    }
    return out;
  }

  static DateTime _dateOfIn(Map<ContentItem, DateTime> dateOf, ContentItem it) =>
      dateOf[it] ?? CategoryDetailController.dateAddedFor(it);

  /// Stable, LOSSLESS dedup key for a merged item — see [_dedupAndSort].
  String _dedupKey(LocalContentMatch m) {
    final it = m.content;
    // Movies: collapse copies of the SAME film across playlists by definitive
    // tmdbId first.
    if (it.m3uItem == null && it.contentType == ContentType.vod) {
      final id = it.tmdbId;
      if (id != null && id > 0) return 'tmdb:$id';
      // No tmdbId: the same film is often re-listed only as quality variants —
      // "Supergirl 4K ULTRA HD+HDR", "Supergirl 60FPS ULTRA HD", plain
      // "Supergirl" — which the id-only rule left as 3-4 identical-looking
      // cards. Collapse them by a QUALITY-STRIPPED title key, but ONLY when the
      // name ACTUALLY carried a quality tag that was removed (base != the full
      // normalized name). A "bare" title with no tag keeps its per-stream
      // identity key, so two DISTINCT works with the same bare title and no year
      // and no tmdbId (two "The Lion King") stay separate, reachable cards — the
      // grid has no variant selector, so collapsing them would lose one
      // irrecoverably. Years are kept in the key, so "El Rey León" 1994 vs 2019
      // never collapse either. (Accepted residual: a bare copy does NOT fold
      // into its tagged siblings — one extra card, but zero loss.)
      final base = _qualityBaseKey(it.name);
      if (base != null && base.isNotEmpty) return 'movieq:$base';
    }
    // Series, M3U, and anything without a definitive id: identity-keyed, so
    // distinct streams (US/UK shows, season packs, per-provider copies) each
    // remain their own reachable card.
    return '${it.contentType}:${m.playlist.id}|${it.id}';
  }

  /// REAL quality/format tags providers pack into a movie NAME (resolution,
  /// codec, HDR, frame-rate). Deliberately EXCLUDES audio/subtitle tokens
  /// (`lat`, `latino`, `castellano`, `subtitulado`, `vose`, `dual`): those mark
  /// a DIFFERENT dub/track, not the same film, so folding "Batman Latino" into
  /// "Batman Castellano" would hide a distinct dubbing from Explorar. Kept to
  /// KNOWN tokens only — never generic words — so distinct base titles are never
  /// merged by over-stripping.
  static const _qualityTokens = <String>{
    '4k', 'uhd', 'hdr', 'hd', 'fhd', 'sd', '60fps', '1080p', '720p', '2160p',
    '4320p', 'cam', 'hevc', 'h265',
  };

  static final RegExp _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// A movie title reduced to its base for quality-variant dedup: lowercased,
  /// split into alphanumeric tokens (years and every non-quality word kept),
  /// with the known [_qualityTokens] removed. The one two-word tag, "ULTRA HD",
  /// is dropped as a unit so a stray "ultra" is never left behind.
  ///
  /// Returns null when NO quality token was present (a "bare" title): the caller
  /// then keeps the per-stream identity key so two distinct bare titles never
  /// collapse. A non-null base is the stripped title (years survive as ordinary
  /// tokens, which is what keeps two same-titled works of different years apart).
  static String? _qualityBaseKey(String name) {
    final tokens = name
        .toLowerCase()
        .replaceAll(_nonAlnum, ' ')
        .trim()
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    final out = <String>[];
    var strippedAny = false;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      // "ultra hd" is the only multi-word tag; drop the pair together.
      if (t == 'ultra' && i + 1 < tokens.length && tokens[i + 1] == 'hd') {
        i++;
        strippedAny = true;
        continue;
      }
      if (_qualityTokens.contains(t)) {
        strippedAny = true;
        continue;
      }
      out.add(t);
    }
    // Only collapse when a tag was actually removed; a bare title falls through
    // to the identity key (zero loss for distinct same-titled, untagged works).
    if (!strippedAny) return null;
    return out.join(' ');
  }

  /// True when [a] carries richer metadata than [b] for a collapsed movie card:
  /// prefer a poster/cover image, then the more-recently-added (so the survivor
  /// is both the richest and the freshest). Both sides already share a tmdbId.
  bool _isRicher(
    LocalContentMatch a,
    LocalContentMatch b,
    Map<ContentItem, DateTime> dateOf,
  ) {
    int score(LocalContentMatch m) => m.content.imagePath.isNotEmpty ? 1 : 0;
    final sa = score(a);
    final sb = score(b);
    if (sa != sb) return sa > sb;
    return _dateOfIn(dateOf, a.content).isAfter(_dateOfIn(dateOf, b.content));
  }

  /// Opens a merged item. For a cross-playlist item it plays through the
  /// restore-aware path ([_playLocalAndRestore]); in preview-fallback mode the
  /// origin is unknown (items come from the already-active playlist), so it just
  /// opens against the active playlist — the old single-playlist behavior.
  void _openItem(ContentItem item) {
    final origin = _originOf[item];
    if (origin != null) {
      _playLocalAndRestore(LocalContentMatch(playlist: origin, content: item));
    } else {
      widget.onOpen(item);
    }
  }

  /// Plays [match] from its ORIGIN playlist, then RESTORES the active playlist
  /// once the player route pops. Repoint-before-navigate is the
  /// [GlobalSearchService.openLocalMatch] contract (so playback — and the watch
  /// history saved DURING it — use the origin's creds); the restore afterwards
  /// fixes the data bug where the active playlist stayed on the origin, so
  /// Home's continue-watching reload and a favorite toggle then targeted the
  /// wrong list. Mirrors the save→act→restore idiom used across the app.
  Future<void> _playLocalAndRestore(LocalContentMatch match) async {
    final previous = AppState.currentPlaylist;
    _search.openLocalMatch(match);
    try {
      await widget.onOpen(match.content);
    } finally {
      if (mounted && previous != null) _search.repointTo(previous);
    }
  }

  List<ContentItem> _flatten(List<CategoryViewModel> cats) {
    final seen = <String>{};
    final out = <ContentItem>[];
    for (final c in cats) {
      for (final it in c.contentItems) {
        if (seen.add(it.id)) out.add(it);
      }
    }
    return out;
  }

  /// Genre chip labels for [items]: the localized "all" sentinel first, then
  /// every distinct genre in the catalogue (accent-safe, sorted) via the shared
  /// genre_utils helper — with NEAR-DUPLICATES collapsed by [foldGenreLabel] so
  /// the same genre written two ways (a provider's "Acción" and a TMDb-style
  /// "Action & Adventure"/"Action and Adventure" pair, or accent/case/spacing
  /// variants) shows ONE chip. The first-seen spelling is the representative;
  /// the grid filter still reaches every variant via [_genreVariants] (zero
  /// loss). No arbitrary cap — the full catalogue's genres show.
  List<String> _genresFrom(List<ContentItem> items) {
    final seen = <String>{};
    final out = <String>['Todos'];
    for (final g in enumerateGenres(items)) {
      if (seen.add(foldGenreLabel(g))) out.add(g);
    }
    return out;
  }

  /// Cheap content signature, O(categories) not O(items). The controller reuses
  /// the SAME outer List and mutates it in place, so a list-identity check
  /// wouldn't notice a reload. But every (re)load builds FRESH CategoryViewModel
  /// objects (never mutating an existing one's contentItems), so folding each
  /// category's object identity in — plus its item count — detects any reload,
  /// even one that happens to keep the same counts. Unrelated rebuilds keep the
  /// same objects → same signature → no recompute. The full-load state is folded
  /// in too, so the previews→full transition triggers exactly one recompute.
  int _signature() {
    var s = widget.movieCategories.length * 31 + widget.seriesCategories.length;
    for (final c in widget.movieCategories) {
      s = s * 31 + identityHashCode(c);
      s = s * 31 + c.contentItems.length;
    }
    for (final c in widget.seriesCategories) {
      s = s * 31 + identityHashCode(c);
      s = s * 31 + c.contentItems.length;
    }
    s = s * 31 + (_fullLoaded ? 1 : 0);
    s = s * 31 + _fullMovies.length;
    s = s * 31 + _fullSeries.length;
    // A re-sync can swap content while keeping the same counts; the reload
    // counter guarantees the signature still changes so the grid refreshes.
    s = s * 31 + _fullReloads;
    return s;
  }

  void _ensureBase() {
    final sig = _signature();
    if (sig == _sig) return;
    _sig = sig;
    // Once the full catalogue is in, chips and grid come from it; until then the
    // previews keep the screen populated (instant first paint). Guard against an
    // EMPTY full result (e.g. a widget test with no seeded playlists, or every
    // playlist empty): adopting empty lists would blank the grid — a regression
    // vs preview-flattening — so fall back to previews when the load is empty.
    // (M3U playlists DO contribute now, via _m3uCatalogue; they only degrade —
    // no genre chip / no tmdb-dedup / epoch date — they are not dropped.)
    final useFull = _fullLoaded && (_fullMovies.isNotEmpty || _fullSeries.isNotEmpty);
    _moviesFlat = useFull ? _fullMovies : _flatten(widget.movieCategories);
    _seriesFlat = useFull ? _fullSeries : _flatten(widget.seriesCategories);
    _allFlat = [..._moviesFlat, ..._seriesFlat];
    // The per-type lists are already newest-first in full mode; the merged "Todo"
    // list must be re-sorted so the two types interleave by date rather than
    // showing all movies then all series. Dates come from the precomputed map
    // (O(1) lookups). Preview-fallback mode keeps the old unsorted concatenation
    // (previews carry no reliable date) to preserve single-playlist behavior.
    if (useFull) {
      _allFlat.sort((a, b) =>
          _dateOfIn(_dateOf, b).compareTo(_dateOfIn(_dateOf, a)));
    }
    _genresMovies = _genresFrom(_moviesFlat);
    _genresSeries = _genresFrom(_seriesFlat);
    _genresAll = _genresFrom(_allFlat);
    // Group every genre spelling by its fold key across the WHOLE catalogue, so
    // selecting a deduped chip matches items tagged with any equivalent
    // spelling (zero loss). An item only carries its own genres, so a global
    // map is safe for every tab.
    final variants = <String, List<String>>{};
    for (final g in enumerateGenres(_allFlat)) {
      variants.putIfAbsent(foldGenreLabel(g), () => <String>[]).add(g);
    }
    _genreVariants = variants;
    _filterCache.clear();
    recomputes++;
  }

  /// Select a genre chip and scroll it fully into view (D-pad/TV + RTL): on a
  /// narrow row the active chip — the most important label — was otherwise
  /// clipped at the edge.
  void _selectGenre(String g) {
    setState(() => _genre = g);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[g]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: const Duration(milliseconds: 250));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    _ensureBase();

    final base = _tab == 'movies'
        ? _moviesFlat
        : _tab == 'series'
            ? _seriesFlat
            : _allFlat;
    final genres = _tab == 'movies'
        ? _genresMovies
        : _tab == 'series'
            ? _genresSeries
            : _genresAll;
    // Genre filter is cheap but keyed-cached so an off-screen rebuild reuses it.
    // Exact-token, accent-safe match via the shared helper — "Drama" never
    // catches "Melodrama", "Acción" matches "Acción".
    final items = _filterCache.putIfAbsent('$_tab|$_genre', () {
      if (_genre == 'Todos') return base;
      // Match ANY spelling that folds to the selected chip (zero loss), each via
      // the exact-token, accent-safe helper — so "Drama" never catches
      // "Melodrama" while an item tagged "Action and Adventure" still shows
      // under the "Action & Adventure" chip.
      final variants = _genreVariants[foldGenreLabel(_genre)] ?? [_genre];
      return base
          .where((it) => variants.any((v) => itemHasGenre(it, v)))
          .toList();
    });

    final cross = ResponsiveHelper.getCrossAxisCount(context);
    // safeInset, not a duplicated 48/20: the hand-written pair gave 20dp on
    // phones where every other screen uses 24, and did not scale with wider
    // surfaces the way the overscan margin has to.
    final sidePad = ResponsiveHelper.safeInset(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(sidePad, 8, sidePad, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.loc.nav_browse,
                      style: TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          fontSize: AppThemes.h2Size,
                          fontWeight: FontWeight.w800)),
                  FocusHighlight(
                    borderRadius: BorderRadius.circular(12),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: r.hairline),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.onSearch,
                        child: const SizedBox(
                            width: 40, height: 40, child: Icon(Icons.search, size: 21)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Type tabs
            Padding(
              padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 12),
              child: _fadeEdges(Row(
                children: [
                  for (final e in [
                    ['all', context.loc.search_filter_all],
                    ['movies', context.loc.search_filter_movies],
                    ['series', context.loc.series_plural],
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: RensiChip(
                        label: e[1],
                        active: _tab == e[0],
                        onTap: () => setState(() {
                          _tab = e[0];
                          _genre = 'Todos';
                        }),
                      ),
                    ),
                ],
              )),
            ),
            // Genre chips — hidden entirely when the catalogue carries no
            // genres (only the 'Todos' sentinel), so we never show an empty row.
            if (genres.length > 1) ...[
              SizedBox(
                height: 60,
                child: _fadeEdges(ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsetsDirectional.fromSTEB(sidePad, 0, sidePad, 0),
                  itemCount: genres.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final g = genres[i];
                    return RensiChip(
                      // A stable key per genre lets _selectGenre scroll the
                      // active chip into view (D-pad/TV + RTL).
                      key: _chipKeys.putIfAbsent(g, () => GlobalKey()),
                      // 'Todos' is the internal "all genres" sentinel; show it
                      // localized. Real genre names come from the panel and stay.
                      label: g == 'Todos' ? context.loc.all : g,
                      // Case-insensitive so the highlight survives a display-casing
                      // shift when the genre list moves from previews to the full
                      // catalogue (first-seen casing can differ between the two).
                      active: _genre.toLowerCase() == g.toLowerCase(),
                      onTap: () => _selectGenre(g),
                    );
                  },
                )),
              ),
              const SizedBox(height: 12),
            ],
            // "Populares por género" — ADDITIVE discovery rail shown ABOVE the
            // local grid ONLY when a real genre chip is active (never on the
            // 'Todos' sentinel) and NOT on the Series tab (the rail is movies-
            // only, mirroring the Home Popular rail, so pairing it with a series
            // filter would mismatch). Self-hiding: no TMDb key / a chip that maps
            // to no TMDb movie genre / an empty page / any network failure all
            // collapse it to zero height, leaving exactly the local grid below —
            // the graceful-degradation contract. Keyed by tab+genre so switching
            // genre reloads the rail for the new one.
            if (_genre != 'Todos' && _tab != 'series')
              _BrowseGenrePopular(
                key: ValueKey('genrePop|$_tab|$_genre'),
                genreName: _genre,
                service: _search,
                onPlayLocal: _playLocalAndRestore,
                sidePad: sidePad,
                posterWidth:
                    ResponsiveHelper.isDesktopOrTV(context) ? 168.0 : 138.0,
              ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(context.loc.no_results_filter,
                          style: TextStyle(color: r.text3)))
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cross,
                        childAspectRatio: 1 / 1.48,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => RensiPoster(
                        item: items[i],
                        width: double.infinity,
                        autofocus: i == 0,
                        onTap: () => _openItem(items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Browse "Populares por género" rail: the Home Popular rail, scoped to the
/// active genre chip. Self-contained and self-hiding exactly like `_PopularRail`
/// in home_redesign — it probes for a TMDb key on init and renders nothing
/// (`SizedBox.shrink`) when there is none, and degrades a TMDb failure, an
/// unmapped genre name, or an empty window to the same silent hide (Browse never
/// shows an error banner for an optional discovery rail). It is remounted with a
/// fresh key on every genre change, so a genre switch reloads from month.
///
/// MOVIES-ONLY, mirroring the Home rail and [GlobalSearchService.popularByGenre]
/// (which resolves the chip against TMDb's MOVIE genre list). Reuses Browse's
/// [GlobalSearchService] instance so the cross-playlist catalogue cache is
/// shared with the grid.
class _BrowseGenrePopular extends StatefulWidget {
  const _BrowseGenrePopular({
    super.key,
    required this.genreName,
    required this.service,
    required this.onPlayLocal,
    required this.sidePad,
    required this.posterWidth,
  });

  final String genreName;
  final GlobalSearchService service;

  /// Restore-aware play of an owned copy: repoints AppState to the copy's origin
  /// playlist, navigates, and restores the active playlist on return. Shared
  /// with the grid so the rail never leaves the active playlist on the origin.
  final Future<void> Function(LocalContentMatch) onPlayLocal;
  final double sidePad;
  final double posterWidth;

  @override
  State<_BrowseGenrePopular> createState() => _BrowseGenrePopularState();
}

class _BrowseGenrePopularState extends State<_BrowseGenrePopular> {
  /// Wraps the rail so a window switch — which rebuilds the ListView children
  /// with new keys and disposes the focused poster's element — can re-anchor
  /// D-pad focus onto a card instead of leaving it dangling (mirrors the Home
  /// rail's identical concern).
  final FocusScopeNode _railScope = FocusScopeNode();

  PopularWindow _window = PopularWindow.month;

  /// Latest results for the active window, or null before the first paint.
  List<GlobalSearchResult>? _results;

  /// Once true the rail renders nothing for the rest of this genre's mount: no
  /// key, or the first window came back empty. A per-switch empty keeps the old
  /// list rather than yanking the rail out from under the viewer.
  bool _hidden = false;

  /// Monotonic request id: a stale window's late reply drops itself.
  int _reqToken = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _railScope.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    String? credential;
    try {
      credential = await TmdbCredentialsService.getCredential();
    } catch (_) {
      // A secure-storage read failure is treated exactly like "no key": hide the
      // optional rail, surface no error.
      credential = null;
    }
    if (!mounted) return;
    if (credential == null) {
      setState(() => _hidden = true);
      return;
    }
    _load(_window);
  }

  Future<void> _load(PopularWindow window) async {
    final token = ++_reqToken;
    final locale = Localizations.localeOf(context);
    final hadFocus = _railScope.hasFocus;
    // popularByGenre already degrades EVERY soft failure (no key, unmapped
    // genre, empty page, TmdbException) to []; the broad guard also covers a
    // storage/DB error on the local-catalogue side so the rail can never throw
    // an unhandled async error out of the Browse tree.
    List<GlobalSearchResult> results;
    try {
      results = await widget.service
          .popularByGenre(widget.genreName, window, locale: locale);
    } catch (_) {
      results = const [];
    }
    if (!mounted || token != _reqToken) return;
    if (results.isEmpty) {
      // Empty only hides when there is nothing already on screen; a window
      // switch that resolves empty keeps the previous list.
      if (_results == null || _results!.isEmpty) {
        setState(() => _hidden = true);
      }
      return;
    }
    setState(() => _results = results);
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _railScope.hasFocus) return;
        for (final node in _railScope.traversalDescendants) {
          if (node.canRequestFocus && !node.skipTraversal) {
            node.requestFocus();
            break;
          }
        }
      });
    }
  }

  void _onWindow(PopularWindow window) {
    if (window == _window) return;
    setState(() => _window = window);
    _load(window);
  }

  void _openResult(GlobalSearchResult gsr) {
    if (gsr.localMatches.isNotEmpty) {
      final match = gsr.localMatches.first; // service orders exact-first
      // A popular title can be owned in a playlist other than the active one;
      // play (repoint) and restore the active playlist on return.
      widget.onPlayLocal(match);
    } else {
      SearchDetailSheet.show(
        context,
        result: gsr,
        service: widget.service,
        onPlayLocal: (m) => widget.onPlayLocal(m),
        onToggleWishlist: () => _toggleWishlist(gsr),
      );
    }
  }

  /// Local wishlist toggle for the Discover detail sheet — flips the store and
  /// re-stamps the saved flag on the matching card. A failed write keeps the old
  /// state (no throw out of onTap).
  Future<bool> _toggleWishlist(GlobalSearchResult gsr) async {
    final bool nowSaved;
    try {
      nowSaved = await TmdbWishlistService.toggle(gsr.tmdb);
    } catch (_) {
      return gsr.isWishlisted;
    }
    if (mounted) {
      setState(() {
        _results = _results
            ?.map((r) => r.tmdb.id == gsr.tmdb.id &&
                    r.tmdb.mediaType == gsr.tmdb.mediaType
                ? r.copyWith(isWishlisted: nowSaved)
                : r)
            .toList();
      });
    }
    return nowSaved;
  }

  ContentItem _tmdbAsContentItem(TmdbSearchResult t) => ContentItem(
        'tmdb:${t.id}',
        t.title,
        t.posterUrl,
        t.mediaType == TmdbMediaType.tv ? ContentType.series : ContentType.vod,
      );

  Widget _poster(GlobalSearchResult gsr) {
    final owned = gsr.localMatches.isNotEmpty;
    final item =
        owned ? gsr.localMatches.first.content : _tmdbAsContentItem(gsr.tmdb);
    return RensiPoster(
      key: ValueKey('genrePop:${gsr.tmdb.id}|${gsr.tmdb.mediaType.name}'),
      item: item,
      width: widget.posterWidth,
      // Owned popular titles look like any poster; Discover ones carry the same
      // neutral "not in your lists" badge as search + the Home rail.
      badge: owned ? null : context.loc.search_not_in_lists,
      badgeTone: RensiBadgeTone.neutral,
      onTap: () => _openResult(gsr),
    );
  }

  Widget _chipRow() {
    final loc = context.loc;
    final chips = <(PopularWindow, String)>[
      (PopularWindow.month, loc.popular_window_month),
      (PopularWindow.year, loc.popular_window_year),
      (PopularWindow.allTime, loc.popular_window_all_time),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.sidePad, 0, widget.sidePad, 12),
      child: Row(
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: RensiChip(
                label: c.$2,
                active: _window == c.$1,
                onTap: () => _onWindow(c.$1),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to show yet (still probing the key / loading the first window) or
    // permanently hidden (no key / unmapped genre / empty): render zero-height
    // so the local grid below is the ONLY thing on screen and no banner appears.
    if (_hidden) return const SizedBox.shrink();
    final results = _results;
    if (results == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
            title: context.loc.popular_section_title, sidePad: widget.sidePad),
        _chipRow(),
        FocusScope(
          node: _railScope,
          child: RensiRail(
            sidePadding: widget.sidePad,
            posterWidth: widget.posterWidth,
            children: [for (final gsr in results) _poster(gsr)],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
