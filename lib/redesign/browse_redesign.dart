import 'package:flutter/material.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

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

  /// Incremented each time the heavy flatten/genre recompute runs; lets a test
  /// assert that unrelated rebuilds don't re-flatten the whole catalogue.
  @visibleForTesting
  int recomputes = 0;

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

  String? _genreOf(ContentItem it) =>
      it.vodStream?.genre ?? it.seriesStream?.genre;

  List<String> _genresFrom(List<ContentItem> items) {
    final genreSet = <String>{};
    for (final it in items) {
      final g = _genreOf(it);
      if (g != null) {
        for (final part in g.split(RegExp('[,/]'))) {
          final t = part.trim();
          if (t.isNotEmpty) genreSet.add(t);
        }
      }
    }
    return ['Todos', ...genreSet.take(12)];
  }

  /// Cheap content signature, O(categories) not O(items). The controller reuses
  /// the SAME outer List and mutates it in place, so a list-identity check
  /// wouldn't notice a reload. But every (re)load builds FRESH CategoryViewModel
  /// objects (never mutating an existing one's contentItems), so folding each
  /// category's object identity in — plus its item count — detects any reload,
  /// even one that happens to keep the same counts. Unrelated rebuilds keep the
  /// same objects → same signature → no recompute.
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
    return s;
  }

  void _ensureBase() {
    final sig = _signature();
    if (sig == _sig) return;
    _sig = sig;
    _moviesFlat = _flatten(widget.movieCategories);
    _seriesFlat = _flatten(widget.seriesCategories);
    _allFlat = [..._moviesFlat, ..._seriesFlat];
    _genresMovies = _genresFrom(_moviesFlat);
    _genresSeries = _genresFrom(_seriesFlat);
    _genresAll = _genresFrom(_allFlat);
    _filterCache.clear();
    recomputes++;
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
    final items = _filterCache.putIfAbsent('$_tab|$_genre', () {
      if (_genre == 'Todos') return base;
      final q = _genre.toLowerCase();
      return base
          .where((it) => (_genreOf(it) ?? '').toLowerCase().contains(q))
          .toList();
    });

    final cross = ResponsiveHelper.getCrossAxisCount(context);
    final sidePad = ResponsiveHelper.isDesktopOrTV(context) ? 48.0 : 20.0;

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
                  const Text('Explorar',
                      style: TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          fontSize: 26,
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
                  for (final e in const [
                    ['all', 'Todo'],
                    ['movies', 'Películas'],
                    ['series', 'Series'],
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
            // Genre chips
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 0),
                itemCount: genres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => RensiChip(
                  label: genres[i],
                  active: _genre == genres[i],
                  onTap: () => setState(() => _genre = genres[i]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('Sin resultados para este filtro',
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
