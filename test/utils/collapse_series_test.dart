import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';

WatchHistory _h({
  required String stream,
  required ContentType type,
  String? seriesId,
  required int day,
}) {
  return WatchHistory(
    playlistId: 'pl-1',
    contentType: type,
    streamId: stream,
    seriesId: seriesId,
    watchDuration: const Duration(minutes: 1),
    totalDuration: const Duration(minutes: 10),
    lastWatched: DateTime.utc(2026, 1, day),
    title: stream,
  );
}

/// Fix 2 (residual): el rail agrupa los episodios de una serie en una sola
/// tarjeta (la más reciente), en vez de una por episodio.
void main() {
  test('colapsa episodios de una misma serie a la entrada más reciente', () {
    final input = [
      _h(stream: 's9-e3', type: ContentType.series, seriesId: 'S9', day: 5),
      _h(stream: 'movie-1', type: ContentType.vod, day: 4),
      _h(stream: 's9-e2', type: ContentType.series, seriesId: 'S9', day: 3),
      _h(stream: 's7-e1', type: ContentType.series, seriesId: 'S7', day: 2),
      _h(stream: 's9-e1', type: ContentType.series, seriesId: 'S9', day: 1),
    ];

    final out = collapseSeriesByLatest(input);

    expect(
      out.map((h) => h.streamId).toList(),
      ['s9-e3', 'movie-1', 's7-e1'],
    );
  });

  test('no agrupa series sin seriesId (historial local antiguo)', () {
    final input = [
      _h(stream: 'a', type: ContentType.series, seriesId: null, day: 3),
      _h(stream: 'b', type: ContentType.series, seriesId: null, day: 2),
    ];
    expect(collapseSeriesByLatest(input), hasLength(2));
  });
}
