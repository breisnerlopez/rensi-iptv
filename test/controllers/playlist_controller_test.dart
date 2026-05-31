import 'package:rensi_iptv/controllers/playlist_controller.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistController error keys', () {
    test('validatePlaylistData reports playlist_name_min_2 for empty name',
        () {
      final controller = PlaylistController();
      final ok = controller.validatePlaylistData(
        name: 'x',
        type: PlaylistType.m3u,
      );
      expect(ok, isFalse);
      expect(controller.errorKey, 'playlist_name_min_2');
    });

    test('validatePlaylistData reports api_url_required for missing xtream url',
        () {
      final controller = PlaylistController();
      final ok = controller.validatePlaylistData(
        name: 'name',
        type: PlaylistType.xtream,
        url: '',
        username: 'u',
        password: 'p',
      );
      expect(ok, isFalse);
      expect(controller.errorKey, 'api_url_required');
    });

    test('validatePlaylistData reports username_required when blank', () {
      final controller = PlaylistController();
      final ok = controller.validatePlaylistData(
        name: 'name',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: '',
        password: 'p',
      );
      expect(ok, isFalse);
      expect(controller.errorKey, 'username_required');
    });

    test('validatePlaylistData reports password_required when blank', () {
      final controller = PlaylistController();
      final ok = controller.validatePlaylistData(
        name: 'name',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'u',
        password: '',
      );
      expect(ok, isFalse);
      expect(controller.errorKey, 'password_required');
    });

    test('validatePlaylistData reports url_format_validate_error for bad URI',
        () {
      final controller = PlaylistController();
      final ok = controller.validatePlaylistData(
        name: 'name',
        type: PlaylistType.xtream,
        url: 'not-a-url',
        username: 'u',
        password: 'p',
      );
      expect(ok, isFalse);
      expect(controller.errorKey, 'url_format_validate_error');
    });

    test('clearError resets the error pair', () {
      final controller = PlaylistController();
      controller.setError('playlist_load_failed', 'boom');
      expect(controller.errorKey, isNotNull);
      controller.clearError();
      expect(controller.errorKey, isNull);
      expect(controller.errorDetail, isNull);
      expect(controller.error, isNull);
    });

    test('error getter falls back to English text for unknown keys', () {
      final controller = PlaylistController();
      controller.setError('totally_unknown', 'detail');
      expect(controller.error, 'totally_unknown: detail');
    });

    test('error getter renders a known key in English', () {
      final controller = PlaylistController();
      controller.setError('playlist_name_already_exists');
      expect(controller.error, 'A playlist with this name already exists');
    });
  });
}
