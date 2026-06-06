import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    List<ContentItem> items;
    if (_tab == 'movies') {
      items = _flatten(widget.movieCategories);
    } else if (_tab == 'series') {
      items = _flatten(widget.seriesCategories);
    } else {
      items = [
        ..._flatten(widget.movieCategories),
        ..._flatten(widget.seriesCategories),
      ];
    }

    // Build the genre list from the current set (cap to keep the row sane).
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
    final genres = ['Todos', ...genreSet.take(12)];

    if (_genre != 'Todos') {
      items = items
          .where((it) => (_genreOf(it) ?? '').toLowerCase().contains(_genre.toLowerCase()))
          .toList();
    }

    final cross = MediaQuery.of(context).size.width >= 900 ? 6 : 3;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
