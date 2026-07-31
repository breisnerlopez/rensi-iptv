import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/search_detail_sheet.dart';

Playlist _pl(String id, String name) => Playlist(
      id: id,
      name: name,
      type: PlaylistType.xtream,
      url: 'https://x.com',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2026),
    );

LocalContentMatch _match(Playlist pl, String streamId, MatchStrength s) =>
    LocalContentMatch(
      playlist: pl,
      content: ContentItem(streamId, 'Rick y Morty', '', ContentType.series),
      strength: s,
    );

void main() {
  group('dedupMatchesByPlaylist ("Reproducir desde" rows)', () {
    test('collapses two owned streams from the SAME playlist to one row', () {
      final pl = _pl('pl1', 'LopezCueto3');
      final result = dedupMatchesByPlaylist([
        _match(pl, 'stream-a', MatchStrength.exact),
        _match(pl, 'stream-b', MatchStrength.fuzzy),
      ]);
      expect(result, hasLength(1),
          reason: 'the same playlist id must not appear twice');
      expect(result.single.playlist.id, 'pl1');
      expect(result.single.content.id, 'stream-a',
          reason: 'keeps the first (strongest) match seen for the playlist');
    });

    test('keeps one row per DISTINCT playlist, order preserved', () {
      final a = _pl('pl1', 'LopezCueto3');
      final b = _pl('pl2', 'LopezCueto4');
      final result = dedupMatchesByPlaylist([
        _match(a, 'stream-a', MatchStrength.exact),
        _match(b, 'stream-b', MatchStrength.exact),
        _match(a, 'stream-a2', MatchStrength.fuzzy),
      ]);
      expect(result.map((m) => m.playlist.id).toList(), ['pl1', 'pl2']);
    });

    test('empty in, empty out', () {
      expect(dedupMatchesByPlaylist(const []), isEmpty);
    });
  });
}
