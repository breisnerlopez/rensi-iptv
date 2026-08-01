import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/services/download_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    await getIt.reset();
    database = createTestDatabase();
    // DownloadService resolves its AppDatabase through GetIt; point it at the
    // in-memory test database.
    getIt.registerSingleton<AppDatabase>(database);
  });

  tearDown(() async {
    await getIt.reset();
    await database.close();
  });

  Future<int> insertCompletedDownload({
    required String playlistId,
    required String contentId,
    required String filePath,
  }) {
    return database.into(database.downloads).insert(
          DownloadsCompanion.insert(
            contentId: contentId,
            contentType: 'vod',
            title: 'A Downloaded Movie',
            addedAt: DateTime(2026).millisecondsSinceEpoch,
            playlistId: playlistId,
            status: const Value('complete'),
            filePath: Value(filePath),
          ),
        );
  }

  test(
      'deleteDownloadsForPlaylist deletes the rows AND the files on disk of '
      'that playlist only', () async {
    final dir = await Directory.systemTemp.createTemp('rensi_dl_test');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final doomedFile = File('${dir.path}/doomed.mp4');
    await doomedFile.writeAsBytes(List<int>.filled(1024, 7));
    final survivorFile = File('${dir.path}/survivor.mp4');
    await survivorFile.writeAsBytes(List<int>.filled(1024, 9));

    await insertCompletedDownload(
      playlistId: 'playlist-1',
      contentId: 'movie-1',
      filePath: doomedFile.path,
    );
    await insertCompletedDownload(
      playlistId: 'playlist-2',
      contentId: 'movie-2',
      filePath: survivorFile.path,
    );

    await DownloadService.instance.deleteDownloadsForPlaylist('playlist-1');

    // Rows of the deleted playlist are gone; the other playlist's row stays.
    final remaining = await database.select(database.downloads).get();
    expect(remaining.map((r) => r.playlistId), ['playlist-2']);

    // The file on disk was deleted, not just the row — this is the bug fixed.
    expect(await doomedFile.exists(), isFalse,
        reason: 'the downloaded file must be removed from disk, not orphaned');
    // The untouched playlist keeps its file.
    expect(await survivorFile.exists(), isTrue);
  });

  test('deleteDownloadsForPlaylist survives a missing file (best-effort)',
      () async {
    await insertCompletedDownload(
      playlistId: 'playlist-1',
      contentId: 'movie-1',
      filePath: '/nonexistent/path/gone.mp4',
    );

    // A file already gone from disk must neither throw nor block row cleanup.
    await DownloadService.instance.deleteDownloadsForPlaylist('playlist-1');

    expect(await database.select(database.downloads).get(), isEmpty);
  });

  test('deleteDownloadsForPlaylist is a no-op when the playlist has none',
      () async {
    await insertCompletedDownload(
      playlistId: 'playlist-2',
      contentId: 'movie-2',
      filePath: '/tmp/keep.mp4',
    );

    await DownloadService.instance.deleteDownloadsForPlaylist('playlist-1');

    final remaining = await database.select(database.downloads).get();
    expect(remaining.map((r) => r.playlistId), ['playlist-2']);
  });
}
