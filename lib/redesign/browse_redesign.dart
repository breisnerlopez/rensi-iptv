import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/content_service.dart';
import 'package:rensi_iptv/utils/genre_utils.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

/// "Explorar" — type tabs (Todo / Películas / Series) + genre chips over a
/// 3-column poster grid, fed by the real catalogue.
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
  final void Function(ContentItem) onOpen;
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
  final Map<String, List<ContentItem>> _filterCache = {};

  // FULL catalogue. Browse only receives PREVIEW CategoryViewModels (each
  // capped at ~10 items by the home controller), so genre chips built from them
  // covered a tiny slice of the catalogue — pick "Terror" and most horror
  // titles were missing. We load the whole VOD + Series catalogue once, via the
  // exact same sentinel path "Ver todo" uses (ContentService recognises the
  // kAllCategoryId sentinel and aggregates every row of the type), then rebuild
  // the chips and grid from these. First paint still comes from the previews so
  // the screen is never blank while this resolves; the load never blocks and
  // degrades to preview-only on any failure (e.g. a widget test with no DB).
  List<ContentItem> _fullMovies = const [];
  List<ContentItem> _fullSeries = const [];
  bool _fullLoaded = false;
  Future<void>? _loadFut;

  /// The in-flight (or settled) full-catalogue load, so a test can await the
  /// previews→full transition deterministically instead of guessing at pumps.
  @visibleForTesting
  Future<void>? get loadFuture => _loadFut;

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
    // Kick off the one-shot full load. It reads AppState.currentPlaylist (set
    // before Browse is mounted), so no mount-site change is needed.
    _loadFut = _loadFull();
  }

  /// Loads the entire VOD and Series catalogue through the "Ver todo" sentinel
  /// path — the same accepted route CategoryDetail uses — for Xtream and M3U
  /// alike. Wrapped in try/catch so a missing repository/DB (widget tests, or a
  /// home mounted before a playlist is ready) degrades to preview-only instead
  /// of throwing into the tree.
  Future<void> _loadFull() async {
    final playlistId = AppState.currentPlaylist?.id ?? '';
    CategoryViewModel sentinel(CategoryType type) => CategoryViewModel(
          category: Category(
            categoryId: kAllCategoryId,
            categoryName: '__ALL__',
            parentId: 0,
            playlistId: playlistId,
            type: type,
          ),
          contentItems: const [],
        );
    try {
      final service = ContentService();
      final movies = await service.fetchContentByCategory(sentinel(CategoryType.vod));
      final series = await service.fetchContentByCategory(sentinel(CategoryType.series));
      if (!mounted) return;
      setState(() {
        _fullMovies = movies;
        _fullSeries = series;
        _fullLoaded = true; // flips the signature → recompute from full lists
      });
    } catch (_) {
      // Degrade to preview-only; never throw into a test/home without a DB.
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
  /// genre_utils helper. No arbitrary cap — the full catalogue's genres show.
  List<String> _genresFrom(List<ContentItem> items) {
    return ['Todos', ...enumerateGenres(items)];
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
    return s;
  }

  void _ensureBase() {
    final sig = _signature();
    if (sig == _sig) return;
    _sig = sig;
    // Once the full catalogue is in, chips and grid come from it; until then the
    // previews keep the screen populated (instant first paint). Guard against an
    // EMPTY full result (e.g. M3U, whose "all" sentinel path returns nothing):
    // adopting empty lists would blank the grid — a regression vs the previous
    // preview-flattening — so fall back to previews when the full load is empty.
    final useFull = _fullLoaded && (_fullMovies.isNotEmpty || _fullSeries.isNotEmpty);
    _moviesFlat = useFull ? _fullMovies : _flatten(widget.movieCategories);
    _seriesFlat = useFull ? _fullSeries : _flatten(widget.seriesCategories);
    _allFlat = [..._moviesFlat, ..._seriesFlat];
    _genresMovies = _genresFrom(_moviesFlat);
    _genresSeries = _genresFrom(_seriesFlat);
    _genresAll = _genresFrom(_allFlat);
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
      return base.where((it) => itemHasGenre(it, _genre)).toList();
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
              child: Row(
                children: [
                  for (final e in [
                    ['all', context.loc.search_filter_all],
                    ['movies', context.loc.search_filter_movies],
                    ['series', context.loc.series_plural],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
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
              ),
            ),
            // Genre chips — hidden entirely when the catalogue carries no
            // genres (only the 'Todos' sentinel), so we never show an empty row.
            if (genres.length > 1) ...[
              SizedBox(
                height: 60,
                child: ListView.separated(
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
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                        onTap: () => widget.onOpen(items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
