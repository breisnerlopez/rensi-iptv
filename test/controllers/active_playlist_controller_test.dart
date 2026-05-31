import 'package:rensi_iptv/controllers/active_playlist_controller.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AppState.currentPlaylist = null;
  });

  group('ActivePlaylistController', () {
    test('setInitialPlaylist updates active playlist and AppState', () {
      final controller = ActivePlaylistController();
      final playlist = Playlist(
        id: 'playlist-1',
        name: 'Main',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      );

      controller.setInitialPlaylist(playlist);

      expect(controller.activePlaylist, playlist);
      expect(AppState.currentPlaylist, playlist);
    });

    test('setInitialPlaylist ignores repeated playlist id', () {
      final controller = ActivePlaylistController();
      var notifications = 0;
      final playlist = Playlist(
        id: 'playlist-1',
        name: 'Main',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      );

      controller.addListener(() => notifications++);
      controller.setInitialPlaylist(playlist);
      controller.setInitialPlaylist(playlist.copyWith(name: 'Changed'));

      expect(notifications, 1);
      expect(controller.activePlaylist?.name, 'Main');
    });
  });
}
