import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    await getIt.reset();
    database = createTestDatabase();
    getIt.registerSingleton<AppDatabase>(database);
  });

  tearDown(() async {
    await getIt.reset();
    await database.close();
  });

  group('WatchHistoryService', () {
    test('saves and retrieves a history row', () async {
      final service = WatchHistoryService();
      await service.saveWatchHistory(
        WatchHistory(
          playlistId: 'playlist-1',
          contentType: ContentType.vod,
          streamId: 'stream-1',
          watchDuration: const Duration(minutes: 3),
          totalDuration: const Duration(minutes: 90),
          lastWatched: DateTime(2026),
          title: 'Movie',
        ),
      );

      final history = await service.getWatchHistory('playlist-1', 'stream-1');

      expect(history, isNotNull);
      expect(history!.watchDuration, const Duration(minutes: 3));
      expect(history.totalDuration, const Duration(minutes: 90));
    });

    test('orders recent history by last watched descending', () async {
      final service = WatchHistoryService();
      await service.saveWatchHistory(
        WatchHistory(
          playlistId: 'playlist-1',
          contentType: ContentType.vod,
          streamId: 'old',
          lastWatched: DateTime(2026),
          title: 'Old',
        ),
      );
      await service.saveWatchHistory(
        WatchHistory(
          playlistId: 'playlist-1',
          contentType: ContentType.vod,
          streamId: 'new',
          lastWatched: DateTime(2026, 1, 2),
          title: 'New',
        ),
      );

      final history = await service.getRecentlyWatched('playlist-1');

      expect(history.map((item) => item.streamId), ['new', 'old']);
    });
  });
}
