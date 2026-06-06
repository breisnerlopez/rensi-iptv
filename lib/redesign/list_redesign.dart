import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';

/// "Mi lista" — saved favourites in a poster grid, with an empty state.
class ListRedesign extends StatefulWidget {
  const ListRedesign({super.key, required this.onOpen});
  final void Function(ContentItem) onOpen;

  @override
  State<ListRedesign> createState() => _ListRedesignState();
}

class _ListRedesignState extends State<ListRedesign> {
  final _repo = FavoritesRepository();
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ContentItem>> _load() async {
    final favs = await _repo.getAllFavorites();
    final out = <ContentItem>[];
    for (final f in favs) {
      final it = await _repo.getContentItemFromFavorite(f);
      if (it != null) out.add(it);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final cross = MediaQuery.of(context).size.width >= 900 ? 6 : 3;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<ContentItem>>(
          future: _future,
          builder: (context, snap) {
            final items = snap.data ?? const <ContentItem>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mi lista',
                          style: TextStyle(
                              fontFamily: 'Bricolage Grotesque',
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('${items.length} títulos guardados',
                          style: TextStyle(fontSize: 13, color: r.text3)),
                    ],
                  ),
                ),
                Expanded(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                          ? _empty(context)
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
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
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final r = rensi(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: r.surface2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.add, size: 30, color: r.text3),
          ),
          const SizedBox(height: 16),
          const Text('Tu lista está vacía',
              style: TextStyle(
                  fontFamily: 'Bricolage Grotesque',
                  fontSize: 19,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SizedBox(
            width: 250,
            child: Text(
              'Toca el + en cualquier título para guardarlo y verlo más tarde.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: r.text3),
            ),
          ),
        ],
      ),
    );
  }
}
