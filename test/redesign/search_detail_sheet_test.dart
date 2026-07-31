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
  group('dedupMatchesByStream ("Reproducir desde" rows)', () {
    test('keeps EVERY distinct season-pack variant within one playlist', () {
      // A title owned as three series_ids in the SAME playlist (a 1-, 6- and
      // 7-season copy). All three must be offered so the user can pick the copy
      // they want — the old one-row-per-playlist collapse hid two of them.
      final pl = _pl('pl1', 'LopezCueto3');
      final result = dedupMatchesByStream([
        _match(pl, 'series-1season', MatchStrength.exact),
        _match(pl, 'series-6season', MatchStrength.fuzzy),
        _match(pl, 'series-7season', MatchStrength.fuzzy),
      ]);
      expect(result, hasLength(3),
          reason: 'distinct streams in one playlist are distinct copies');
      expect(
        result.map((m) => m.content.id).toList(),
        ['series-1season', 'series-6season', 'series-7season'],
      );
    });

    test('folds only TRULY identical rows (same playlist + stream id + type)',
        () {
      final pl = _pl('pl1', 'LopezCueto3');
      final result = dedupMatchesByStream([
        _match(pl, 'stream-a', MatchStrength.exact),
        _match(pl, 'stream-a', MatchStrength.fuzzy), // same stream, matched twice
      ]);
      expect(result, hasLength(1),
          reason: 'the same stream reconciled twice is one row');
      expect(result.single.strength, MatchStrength.exact,
          reason: 'keeps the first (strongest) occurrence');
    });

    test('keeps every distinct playlist AND variant, order preserved', () {
      final a = _pl('pl1', 'LopezCueto3');
      final b = _pl('pl2', 'LopezCueto4');
      final result = dedupMatchesByStream([
        _match(a, 'stream-a', MatchStrength.exact),
        _match(b, 'stream-b', MatchStrength.exact),
        _match(a, 'stream-a2', MatchStrength.fuzzy),
      ]);
      expect(
        result.map((m) => '${m.playlist.id}:${m.content.id}').toList(),
        ['pl1:stream-a', 'pl2:stream-b', 'pl1:stream-a2'],
      );
    });

    test('empty in, empty out', () {
      expect(dedupMatchesByStream(const []), isEmpty);
    });
  });
}
