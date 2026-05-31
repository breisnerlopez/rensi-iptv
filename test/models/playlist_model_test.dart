import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Playlist', () {
    test('withoutSecrets removes sensitive connection fields', () {
      final playlist = Playlist(
        id: 'id-1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://provider.example.com',
        username: 'user',
        password: 'pass',
        createdAt: DateTime(2026),
      );

      final sanitized = playlist.withoutSecrets();

      expect(sanitized.id, playlist.id);
      expect(sanitized.name, playlist.name);
      expect(sanitized.type, playlist.type);
      expect(sanitized.createdAt, playlist.createdAt);
      expect(sanitized.url, isNull);
      expect(sanitized.username, isNull);
      expect(sanitized.password, isNull);
    });

    test('copyWith preserves existing values and applies overrides', () {
      final playlist = Playlist(
        id: 'id-1',
        name: 'Main',
        type: PlaylistType.m3u,
        url: 'https://old.example.com/list.m3u',
        createdAt: DateTime(2026),
      );

      final updated = playlist.copyWith(
        name: 'Updated',
        url: 'https://new.example.com/list.m3u',
      );

      expect(updated.id, 'id-1');
      expect(updated.name, 'Updated');
      expect(updated.type, PlaylistType.m3u);
      expect(updated.url, 'https://new.example.com/list.m3u');
      expect(updated.createdAt, DateTime(2026));
    });

    test('copyWith can clear optional secrets to null via sentinel', () {
      final playlist = Playlist(
        id: 'id-1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'user',
        password: 'pass',
        createdAt: DateTime(2026),
      );

      final cleared = playlist.copyWith(
        url: null,
        username: null,
        password: null,
      );

      expect(cleared.url, isNull);
      expect(cleared.username, isNull);
      expect(cleared.password, isNull);
      expect(cleared.name, 'Main'); // unrelated fields preserved
    });

    test('copyWith without args keeps existing values (sentinel default)', () {
      final playlist = Playlist(
        id: 'id-1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'user',
        password: 'pass',
        createdAt: DateTime(2026),
      );

      final copy = playlist.copyWith();
      expect(copy.url, playlist.url);
      expect(copy.username, playlist.username);
      expect(copy.password, playlist.password);
    });

    test('toJson can omit secrets when includeSecrets is false', () {
      final playlist = Playlist(
        id: 'id-1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://x.com',
        username: 'user',
        password: 'pass',
        createdAt: DateTime(2026),
      );

      final withSecrets = playlist.toJson();
      final withoutSecrets = playlist.toJson(includeSecrets: false);

      expect(withSecrets.containsKey('url'), isTrue);
      expect(withoutSecrets.containsKey('url'), isFalse);
      expect(withoutSecrets.containsKey('username'), isFalse);
      expect(withoutSecrets.containsKey('password'), isFalse);
    });

    test('serializes and deserializes JSON', () {
      final playlist = Playlist(
        id: 'id-1',
        name: 'Main',
        type: PlaylistType.xtream,
        url: 'https://provider.example.com',
        username: 'user',
        password: 'pass',
        createdAt: DateTime(2026),
      );

      final decoded = Playlist.fromJson(playlist.toJson());

      expect(decoded.id, playlist.id);
      expect(decoded.name, playlist.name);
      expect(decoded.type, playlist.type);
      expect(decoded.url, playlist.url);
      expect(decoded.username, playlist.username);
      expect(decoded.password, playlist.password);
      expect(decoded.createdAt, playlist.createdAt);
    });

    test('fromJson handles missing optional fields gracefully', () {
      final decoded = Playlist.fromJson({
        'id': 'x',
        'name': 'y',
        'type': PlaylistType.m3u.toString(),
        'createdAt': DateTime(2026).toIso8601String(),
      });
      expect(decoded.url, isNull);
      expect(decoded.username, isNull);
      expect(decoded.password, isNull);
    });
  });
}
