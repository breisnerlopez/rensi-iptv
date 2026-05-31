import '../models/playlist_model.dart';
import 'playlist_secrets_service.dart';
import 'database_service.dart';

class PlaylistService {
  static final Map<String, Playlist> _hydratedCache = {};

  static Future<void> savePlaylist(Playlist playlist) async {
    await PlaylistSecretsService.save(playlist);
    _hydratedCache[playlist.id] = playlist;
    await DatabaseService.savePlaylist(playlist.withoutSecrets());
  }

  static Future<List<Playlist>> getPlaylists() async {
    final playlists = await DatabaseService.getPlaylists();
    return _hydrateAll(playlists);
  }

  static Future<void> deletePlaylist(String id) async {
    await PlaylistSecretsService.delete(id);
    _hydratedCache.remove(id);
    await DatabaseService.deletePlaylist(id);
  }

  static Future<void> updatePlaylist(Playlist playlist) async {
    await PlaylistSecretsService.save(playlist);
    _hydratedCache[playlist.id] = playlist;
    await DatabaseService.updatePlaylist(playlist.withoutSecrets());
  }

  static Future<Playlist?> getPlaylistById(String id) async {
    final cached = _hydratedCache[id];
    if (cached != null) return cached;
    final playlist = await DatabaseService.getPlaylistById(id);
    if (playlist == null) return null;
    final hydrated = await _hydrateAndMigrate(playlist);
    _hydratedCache[id] = hydrated;
    return hydrated;
  }

  static Future<List<Playlist>> getXStreamPlaylists() async {
    final playlists = await DatabaseService.getPlaylistsByType(
      PlaylistType.xtream,
    );
    return _hydrateAll(playlists);
  }

  static Future<List<Playlist>> getM3UPlaylists() async {
    final playlists = await DatabaseService.getPlaylistsByType(
      PlaylistType.m3u,
    );
    return _hydrateAll(playlists);
  }

  static void invalidateCache() {
    _hydratedCache.clear();
  }

  static Future<List<Playlist>> _hydrateAll(List<Playlist> playlists) async {
    final hydrated = await Future.wait(playlists.map(_hydrateAndMigrate));
    for (final playlist in hydrated) {
      _hydratedCache[playlist.id] = playlist;
    }
    return hydrated;
  }

  static Future<Playlist> _hydrateAndMigrate(Playlist playlist) async {
    final cached = _hydratedCache[playlist.id];
    if (cached != null) return cached;

    final hasLegacySecrets = playlist.url != null ||
        playlist.username != null ||
        playlist.password != null;

    if (hasLegacySecrets) {
      final alreadyMigrated = await PlaylistSecretsService.hasMigrated();
      if (!alreadyMigrated) {
        await PlaylistSecretsService.migrateLegacyIfNeeded(playlist);
      }
      await DatabaseService.updatePlaylist(playlist.withoutSecrets());
    }

    return PlaylistSecretsService.hydrate(playlist);
  }

  static Future<void> completeMigration() async {
    await PlaylistSecretsService.markMigrated();
  }
}
