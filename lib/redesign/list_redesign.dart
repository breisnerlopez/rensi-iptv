import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/redesign/search_detail_sheet.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

/// The two kinds of card "Mi lista" renders: an owned IPTV favourite (plays on
/// tap) and a saved TMDb wishlist title (opens the discover sheet on tap).
class _ListData {
  final List<ContentItem> favorites;
  final List<TmdbSearchResult> wishlist;
  const _ListData(this.favorites, this.wishlist);

  bool get isEmpty => favorites.isEmpty && wishlist.isEmpty;
  int get length => favorites.length + wishlist.length;
}

/// "Mi lista" — the user's IPTV favourites AND their TMDb wishlist in a single
/// poster grid, with a shared empty state.
class ListRedesign extends StatefulWidget {
  const ListRedesign({super.key, required this.onOpen, this.onBrowse});
  final void Function(ContentItem) onOpen;

  /// Where the empty state's primary action goes.
  final VoidCallback? onBrowse;

  @override
  State<ListRedesign> createState() => _ListRedesignState();
}

class _ListRedesignState extends State<ListRedesign> {
  final _repo = FavoritesRepository();
  final _service = GlobalSearchService();
  late Future<_ListData> _future;
  StreamSubscription<dynamic>? _favSub;
  StreamSubscription<dynamic>? _wishSub;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // "Mi lista" vive en un IndexedStack (montada, no recarga al cambiar de
    // pestaña): recargar cuando se marca/desmarca un favorito IPTV…
    _favSub = EventBus()
        .on<dynamic>('favorites_changed')
        .listen((_) => mounted ? setState(() => _future = _load()) : null);
    // …o cuando cambia la lista de deseos TMDb (añadir/quitar desde cualquier
    // pantalla, incluida la hoja de detalle que abrimos aquí).
    _wishSub = EventBus()
        .on<dynamic>('tmdb_wishlist_changed')
        .listen((_) => mounted ? setState(() => _future = _load()) : null);
  }

  @override
  void dispose() {
    _favSub?.cancel();
    _wishSub?.cancel();
    super.dispose();
  }

  Future<_ListData> _load() async {
    final favs = await _repo.getAllFavorites();
    final out = <ContentItem>[];
    for (final f in favs) {
      final it = await _repo.getContentItemFromFavorite(f);
      if (it != null) out.add(it);
    }
    final wishlist = await TmdbWishlistService.getItems();
    return _ListData(out, wishlist);
  }

  /// A display-only [ContentItem] wrapping a TMDb wishlist result so it can ride
  /// in a [RensiPoster], exactly like the search screen's discover cards. Never
  /// played (the tap opens the detail sheet), so the baked-in url is inert.
  ContentItem _tmdbAsContentItem(TmdbSearchResult t) => ContentItem(
        'tmdb:${t.id}',
        t.title,
        t.posterUrl,
        t.mediaType == TmdbMediaType.tv ? ContentType.series : ContentType.vod,
      );

  /// Opens the TMDb discover sheet for a wishlist title — the same sheet the
  /// search screen uses. localMatches is empty (this is a saved-only card), so
  /// the sheet shows synopsis + the wishlist toggle. Removing it there fires
  /// `tmdb_wishlist_changed`, which reloads this grid.
  void _openTmdb(TmdbSearchResult t) {
    final result = GlobalSearchResult(
      tmdb: t,
      localMatches: const [],
      isWishlisted: true,
    );
    SearchDetailSheet.show(
      context,
      result: result,
      service: _service,
      onPlayLocal: (m) {
        _service.openLocalMatch(m);
        widget.onOpen(m.content);
      },
      onToggleWishlist: () => TmdbWishlistService.toggle(t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final cross = ResponsiveHelper.getCrossAxisCount(context);
    // safeInset, not a duplicated 48/20: the hand-written pair gave 20dp on
    // phones where every other screen uses 24, and did not scale with wider
    // surfaces the way the overscan margin has to.
    final sidePad = ResponsiveHelper.safeInset(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_ListData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data ?? const _ListData([], []);
            final favs = data.favorites;
            final wishlist = data.wishlist;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.loc.nav_my_list,
                          style: TextStyle(
                              fontFamily: 'Bricolage Grotesque',
                              fontSize: AppThemes.h2Size,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(context.loc.saved_titles_count(data.length),
                          style: TextStyle(fontSize: AppThemes.bodySmallSize, color: r.text3)),
                    ],
                  ),
                ),
                Expanded(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : data.isEmpty
                          ? _empty(context)
                          : GridView.builder(
                              padding: EdgeInsets.fromLTRB(sidePad, 12, sidePad, 24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cross,
                                childAspectRatio: 1 / 1.48,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              // IPTV favourites first, then TMDb wishlist cards —
                              // the latter carry a "Saved" badge so the two are
                              // visually distinct within one grid.
                              itemCount: data.length,
                              itemBuilder: (_, i) {
                                if (i < favs.length) {
                                  final item = favs[i];
                                  return RensiPoster(
                                    key: ValueKey('fav:${item.id}'),
                                    item: item,
                                    width: double.infinity,
                                    autofocus: i == 0,
                                    onTap: () => widget.onOpen(item),
                                  );
                                }
                                final t = wishlist[i - favs.length];
                                return RensiPoster(
                                  key: ValueKey(
                                      'wish:${t.id}|${t.mediaType.name}'),
                                  item: _tmdbAsContentItem(t),
                                  width: double.infinity,
                                  autofocus: favs.isEmpty && i == 0,
                                  badge: context.loc.search_saved,
                                  badgeTone: RensiBadgeTone.neutral,
                                  onTap: () => _openTmdb(t),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => RensiEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: context.loc.empty_list_title,
        body: context.loc.empty_list_body,
        actionLabel: context.loc.action_browse_catalogue,
        // Without an action this screen had no focusable element at all: on a
        // remote the user arrived and had nothing to press.
        onAction: widget.onBrowse ?? () {},
      );
}
