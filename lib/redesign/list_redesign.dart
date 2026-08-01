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
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

/// One unified-list favourite card: the resolved [content] plus the [origin]
/// playlist it belongs to. "Mi lista" is now GLOBAL across every playlist, so a
/// card must remember its origin to (a) badge a copy that is NOT from the active
/// playlist and (b) repoint AppState to the origin's credentials right before
/// playback. [fromActivePlaylist] is precomputed once against the active list.
class _FavCard {
  final ContentItem content;
  final Playlist origin;
  final bool fromActivePlaylist;
  const _FavCard(this.content, this.origin, this.fromActivePlaylist);
}

/// The two kinds of card "Mi lista" renders: an owned IPTV favourite (plays on
/// tap) and a saved TMDb wishlist title (opens the discover sheet on tap).
class _ListData {
  final List<_FavCard> favorites;
  final List<TmdbSearchResult> wishlist;
  const _ListData(this.favorites, this.wishlist);

  bool get isEmpty => favorites.isEmpty && wishlist.isEmpty;
  int get length => favorites.length + wishlist.length;
}

/// "Mi lista" — the user's IPTV favourites AND their TMDb wishlist in a single
/// poster grid, with a shared empty state.
class ListRedesign extends StatefulWidget {
  const ListRedesign({super.key, required this.onOpen, this.onBrowse});

  /// Opens/plays a card. Returns a Future that completes when the pushed player
  /// route pops — the unified list awaits it so a cross-playlist favourite can
  /// RESTORE the active playlist afterwards (see [_ListRedesignState._openFav]).
  final Future<void> Function(ContentItem) onOpen;

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
    final activeId = AppState.currentPlaylist?.id;
    // GLOBAL read: favourites from EVERY playlist, newest first.
    final favs = await _repo.getAllFavoritesAcrossPlaylists();

    // Dedup by the SAME year-aware title key search/browse use
    // (GlobalSearchService.titleDedupKey → _titleKey): connector/"&"→"and",
    // script-safe, and — crucially — a BRACKETED release year is folded back in,
    // so the SAME title favourited in two playlists collapses to ONE card while
    // "The Lion King (1994)" vs "(2019)" stay TWO cards (neither hidden) and a
    // bare "Blade Runner 2049" is never split. Preference: the copy whose origin
    // == the active playlist (it plays without a repoint); otherwise the most
    // recent — favs arrive createdAt desc, so the FIRST-seen copy is the most
    // recent and wins by default.
    final byKey = <String, _FavCard>{};
    final order = <String>[];
    for (final f in favs) {
      final resolved = await _repo.resolveFavorite(f);
      // Null => origin playlist was deleted: skip rather than show a card that
      // would resolve/play against the wrong (active) playlist.
      if (resolved == null) continue;
      final fromActive = resolved.origin.id == activeId;
      final card = _FavCard(resolved.content, resolved.origin, fromActive);
      final key = GlobalSearchService.titleDedupKey(
        card.content.name,
        card.content.contentType,
      );
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = card;
        order.add(key);
      } else if (fromActive && !existing.fromActivePlaylist) {
        // A later (older) active-playlist copy replaces the kept non-active one,
        // keeping its first-seen position, so the local copy plays directly.
        byKey[key] = card;
      }
      // else keep existing (already active, or first-seen = most recent).
    }
    final out = [for (final k in order) byKey[k]!];

    // Dedup the TMDb wishlist against owned favourites, keyed the same way:
    // a title the user OWNS (IPTV favourite) AND saved on TMDb showed up twice.
    // Prefer the owned copy — drop the wishlist duplicate.
    final favKeys = byKey.keys.toSet();
    final wishAll = await TmdbWishlistService.getItems();
    final wishlist = wishAll.where((t) {
      final type = t.mediaType == TmdbMediaType.tv
          ? ContentType.series
          : ContentType.vod;
      return !favKeys.contains(GlobalSearchService.titleDedupKey(t.title, type));
    }).toList();
    return _ListData(out, wishlist);
  }

  /// Opens a unified-list favourite. A card from the ACTIVE playlist opens
  /// directly. A card from ANOTHER playlist repoints AppState to its ORIGIN
  /// (credentials + repository) in the SAME synchronous tick before navigating —
  /// the sanctioned [GlobalSearchService.openLocalMatch]/`repointTo` contract, so
  /// playback and the watch history saved DURING it use the origin's creds — then
  /// RESTORES the active playlist once the player route pops, so Home's
  /// continue-watching reload and a favourite toggle keep targeting the right
  /// list (mirrors browse_redesign's `_playLocalAndRestore`).
  Future<void> _openFav(_FavCard card) async {
    if (card.fromActivePlaylist) {
      await widget.onOpen(card.content);
      return;
    }
    final previous = AppState.currentPlaylist;
    _service.repointTo(card.origin);
    try {
      await widget.onOpen(card.content);
    } finally {
      if (mounted && previous != null) _service.repointTo(previous);
    }
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
                                  final card = favs[i];
                                  return RensiPoster(
                                    key: ValueKey(
                                        'fav:${card.origin.id}:${card.content.id}'),
                                    item: card.content,
                                    width: double.infinity,
                                    autofocus: i == 0,
                                    // Neutral origin chip ONLY for a favourite
                                    // from another playlist — same tone as the
                                    // wishlist "Saved" badge; same-playlist
                                    // favourites keep their bare poster.
                                    badge: card.fromActivePlaylist
                                        ? null
                                        : card.origin.name,
                                    badgeTone: RensiBadgeTone.neutral,
                                    onTap: () => _openFav(card),
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
