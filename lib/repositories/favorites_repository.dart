import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/api_configuration_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/favorite.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/playlist_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/repositories/m3u_repository.dart';
import 'package:uuid/uuid.dart';

/// A favourite resolved to a playable [ContentItem] together with the ORIGIN
/// playlist it belongs to. "Mi lista" is unified across every playlist, so each
/// card needs its origin both to badge a copy that is NOT from the active
/// playlist and to repoint AppState to the origin's credentials in the same
/// synchronous tick as playback.
class ResolvedFavorite {
  final ContentItem content;
  final Playlist origin;
  const ResolvedFavorite(this.content, this.origin);
}

class FavoritesRepository {
  final _database = getIt<AppDatabase>();
  final _uuid = Uuid();

  FavoritesRepository();

  Future<void> addFavorite(ContentItem contentItem) async {
    final playlistId = AppState.currentPlaylist!.id;

    final isAlreadyFavorite = await _database.isFavorite(
      playlistId,
      contentItem.id,
      contentItem.contentType,
      contentItem.season != null ? contentItem.id : null,
    );

    if (isAlreadyFavorite) {
      throw Exception('Bu içerik zaten favorilerde');
    }

    final favorite = Favorite(
      id: _uuid.v4(),
      playlistId: playlistId,
      contentType: contentItem.contentType,
      streamId: contentItem.id,
      m3uItemId: contentItem.m3uItem?.id,
      name: contentItem.name,
      imagePath: contentItem.imagePath,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _database.insertFavorite(favorite);
    // "Mi lista" vive en un IndexedStack (montada, no recarga sola): avisar para
    // que se refresque al marcar un favorito.
    EventBus().emit('favorites_changed', null);
  }

  Future<void> removeFavorite(
    String streamId,
    ContentType contentType, {
    String? episodeId,
  }) async {
    final playlistId = AppState.currentPlaylist!.id;

    final favorites = await _database.getFavoritesByPlaylist(playlistId);
    final favorite = favorites.firstWhere(
      (f) =>
          f.streamId == streamId &&
          f.contentType == contentType &&
          f.episodeId == episodeId,
      orElse: () => throw Exception('Favori bulunamadı'),
    );

    await _database.deleteFavorite(favorite.id);
    EventBus().emit('favorites_changed', null);
  }

  Future<bool> isFavorite(
    String streamId,
    ContentType contentType, {
    String? episodeId,
  }) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.isFavorite(
      playlistId,
      streamId,
      contentType,
      episodeId,
    );
  }

  Future<List<Favorite>> getAllFavorites() async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoritesByPlaylist(playlistId);
  }

  /// UNIFIED "Mi lista" READ: every favourite across ALL playlists, newest
  /// first. Only the listing goes global — SAVE/toggle/isFavorite stay
  /// active-playlist-scoped (see [getAllFavorites]/[isFavorite]/[toggleFavorite])
  /// so detail screens keep their per-playlist authority.
  Future<List<Favorite>> getAllFavoritesAcrossPlaylists() async {
    return await _database.getAllFavoritesAcrossPlaylists();
  }

  /// Persist a manual drag order: favourite row id → position. Same position is
  /// written to every row of a deduplicated card by the caller.
  Future<void> setSortOrders(Map<String, int> orders) async {
    await _database.setFavoriteSortOrders(orders);
  }

  Future<List<Favorite>> getFavoritesByContentType(
    ContentType contentType,
  ) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoritesByContentType(playlistId, contentType);
  }

  Future<List<Favorite>> getLiveStreamFavorites() async {
    return await getFavoritesByContentType(ContentType.liveStream);
  }

  Future<List<Favorite>> getMovieFavorites() async {
    return await getFavoritesByContentType(ContentType.vod);
  }

  Future<List<Favorite>> getSeriesFavorites() async {
    return await getFavoritesByContentType(ContentType.series);
  }

  Future<int> getFavoriteCount() async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoriteCount(playlistId);
  }

  Future<int> getFavoriteCountByContentType(ContentType contentType) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoriteCountByContentType(
      playlistId,
      contentType,
    );
  }

  Future<bool> toggleFavorite(ContentItem contentItem) async {
    final playlistId = AppState.currentPlaylist!.id;
    final isCurrentlyFavorite = await _database.isFavorite(
      playlistId,
      contentItem.id,
      contentItem.contentType,
      null
    );

    if (isCurrentlyFavorite) {
      await removeFavorite(
        contentItem.id,
        contentItem.contentType
      );
      return false;
    } else {
      await addFavorite(contentItem);
      return true;
    }
  }

  Future<void> updateFavorite(Favorite favorite) async {
    await _database.updateFavorite(favorite);
  }

  Future<void> clearAllFavorites() async {
    final playlistId = AppState.currentPlaylist!.id;
    final favorites = await _database.getFavoritesByPlaylist(playlistId);

    for (final favorite in favorites) {
      await _database.deleteFavorite(favorite.id);
    }
    if (favorites.isNotEmpty) EventBus().emit('favorites_changed', null);
  }

  /// Resolves [favorite] against ITS OWN playlist ([Favorite.playlistId]) — the
  /// unified-list read path. Returns null when the origin playlist no longer
  /// exists (deleted): the caller SKIPS the card rather than falling back to a
  /// wrong-playlist lookup. See [_resolveContent] for the concurrency contract.
  Future<ResolvedFavorite?> resolveFavorite(Favorite favorite) async {
    final origin = await PlaylistService.getPlaylistById(favorite.playlistId);
    // Origin playlist was deleted (or its secrets were purged): there is no
    // correct list to resolve against, so skip instead of resolving against the
    // active playlist and playing/naming the wrong stream.
    if (origin == null) return null;
    final content = await _resolveContent(favorite, origin);
    return ResolvedFavorite(content, origin);
  }

  /// Content-only resolution against the favourite's OWN playlist. Kept for
  /// backward compatibility; prefer [resolveFavorite] when the origin playlist
  /// is needed (origin badge + cross-playlist playback). Null when the origin
  /// playlist was deleted.
  Future<ContentItem?> getContentItemFromFavorite(Favorite favorite) async {
    final resolved = await resolveFavorite(favorite);
    return resolved?.content;
  }

  /// Resolves a favourite's playable [ContentItem] against the EXPLICIT
  /// [playlist] it belongs to.
  ///
  /// CONCURRENCY CONTRACT (mandatory for the unified list): every catalogue
  /// lookup here is keyed by [playlist] passed as an explicit parameter — a
  /// per-playlist [IptvRepository]/[M3uRepository] or a playlist-scoped DB call
  /// — so NO `await` in this method runs while global AppState points at a
  /// different playlist. The ONLY touch of global state is the fully
  /// SYNCHRONOUS [_bakeForPlaylist] used to construct the final ContentItem
  /// (whose url baking reads `AppState.currentPlaylist`): it swaps and restores
  /// within one microtask with no `await` in between, so a concurrent reader
  /// (isFavorite badges, cast, home) can never observe the swapped value — the
  /// same sanctioned pattern as `GlobalSearchService._contentForPlaylist`.
  Future<ContentItem> _resolveContent(
    Favorite favorite,
    Playlist playlist,
  ) async {
    try {
      if (playlist.type == PlaylistType.xtream) {
        // A repository bound to the ORIGIN playlist's id + credentials, not the
        // active one — every DB read below is scoped to `playlist.id`.
        final repository = IptvRepository(
          ApiConfig(
            baseUrl: playlist.url ?? '',
            username: playlist.username ?? '',
            password: playlist.password ?? '',
          ),
          playlist.id,
        );

        switch (favorite.contentType) {
          case ContentType.liveStream:
            final liveStream =
                await repository.findLiveStreamById(favorite.streamId);
            if (liveStream != null) {
              return _bakeForPlaylist(
                playlist,
                () => ContentItem(
                  liveStream.streamId,
                  liveStream.name,
                  liveStream.streamIcon,
                  ContentType.liveStream,
                  liveStream: liveStream,
                ),
              );
            }
            break;

          case ContentType.vod:
            final movie =
                await _database.findMovieById(favorite.streamId, playlist.id);
            if (movie != null) {
              return _bakeForPlaylist(
                playlist,
                () => ContentItem(
                  favorite.streamId,
                  favorite.name,
                  favorite.imagePath ?? '',
                  ContentType.vod,
                  containerExtension: movie.containerExtension,
                  vodStream: movie,
                ),
              );
            }
            break;

          case ContentType.series:
            // Direct by-id lookup against the ORIGIN playlist — symmetric to the
            // VOD `findMovieById` above. Replaces the old
            // `repository.getSeries(categoryId: '')`, whose empty-string category
            // never matched a real series (category_id is non-empty), so that
            // branch was dead and every series favourite fell to the best-effort
            // fallback; this also avoids the N+1 of scanning the whole series
            // table once per favourite.
            final seriesStream =
                await _database.findSeriesById(favorite.streamId, playlist.id);
            if (seriesStream != null) {
              return _bakeForPlaylist(
                playlist,
                () => ContentItem(
                  seriesStream.seriesId,
                  seriesStream.name,
                  seriesStream.cover ?? '',
                  ContentType.series,
                  seriesStream: seriesStream,
                ),
              );
            }
            break;
        }
      } else if (playlist.type == PlaylistType.m3u) {
        // M3uRepository bound to the ORIGIN playlist's id (explicit param) so
        // getM3uItemById reads `playlist.id`'s rows, not the active list's.
        final repository = M3uRepository(playlist.id);
        final m3uItem =
            await repository.getM3uItemById(id: favorite.m3uItemId ?? '');
        if (m3uItem != null) {
          switch (favorite.contentType) {
            case ContentType.liveStream:
              return _bakeForPlaylist(
                playlist,
                () => ContentItem(
                  m3uItem.url,
                  m3uItem.name ?? 'NO NAME',
                  m3uItem.tvgLogo ?? '',
                  ContentType.liveStream,
                  m3uItem: m3uItem,
                ),
              );
            case ContentType.vod:
              return _bakeForPlaylist(
                playlist,
                () => ContentItem(
                  m3uItem.url,
                  m3uItem.name ?? 'NO NAME',
                  m3uItem.tvgLogo ?? '',
                  ContentType.vod,
                  m3uItem: m3uItem,
                ),
              );
            case ContentType.series:
              return _bakeForPlaylist(
                playlist,
                () => ContentItem(
                  m3uItem.id,
                  m3uItem.name ?? '',
                  m3uItem.tvgLogo ?? '',
                  ContentType.series,
                  m3uItem: m3uItem,
                ),
              );
          }
        }
      }
    } catch (_) {
      // Fall through to the origin-scoped fallback below.
    }

    // Origin playlist EXISTS but the specific stream row isn't synced yet (or a
    // lookup failed): degrade to a best-effort card baked against the ORIGIN's
    // credentials — never the active playlist's. For Xtream the origin url+creds
    // still yield a valid stream URL; for an unsynced M3U row the url is inert
    // (the id), so the saved title still shows without a wrong-playlist lookup.
    return _bakeForPlaylist(
      playlist,
      () => ContentItem(
        favorite.streamId,
        favorite.name,
        favorite.imagePath ?? '',
        favorite.contentType,
      ),
    );
  }

  /// Constructs a [ContentItem] whose url must bake with [playlist]'s
  /// credentials — the constructor reads `AppState.currentPlaylist` through
  /// `buildMediaUrl`/`isXtreamCode`. SYNCHRONOUS by construction: swap the
  /// global, run [build], restore, with NO `await` in between. Dart runs this to
  /// completion before any other microtask, so no concurrent reader ever
  /// observes the swapped value. This is the ONLY place resolution touches
  /// global state and it never spans an await, satisfying the unified-list
  /// concurrency rule (mirrors `GlobalSearchService._contentForPlaylist`).
  ContentItem _bakeForPlaylist(
    Playlist playlist,
    ContentItem Function() build,
  ) {
    final previous = AppState.currentPlaylist;
    AppState.currentPlaylist = playlist;
    try {
      return build();
    } finally {
      AppState.currentPlaylist = previous;
    }
  }
}
