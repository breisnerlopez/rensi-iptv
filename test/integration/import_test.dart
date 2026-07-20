import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/playlist_screen.dart';
import 'package:rensi_iptv/services/backup_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';

import 'harness.dart';

/// Optional: point at a real .json/.aipbak backup to exercise this path against
/// production data. Unset — the normal case — the test builds its own backup
/// through the real export code instead of skipping.
String? _realBackupPath() => Platform.environment['RENSI_BACKUP'];

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  // Was: read a fixture from an absolute /tmp path belonging to a long-dead
  // session and markTestSkipped when it was missing — so this guard could never
  // run again, and its default outcome was "checked nothing". It also pinned the
  // assertions to the owner's own playlist names, which meant the only way to
  // revive it was to keep a real backup (with real panel credentials) on disk.
  //
  // Now the backup is produced by the same exportBytes() the app ships, so the
  // test covers the real round trip and depends on no secrets.
  testWidgets('Backup round-trip → 2 listas en DB y en pantalla',
      (tester) async {
    var total = 0;
    var names = <String>[];

    await tester.runAsync(() async {
      final Uint8List bytes;
      final realPath = _realBackupPath();
      if (realPath != null && File(realPath).existsSync()) {
        bytes = Uint8List.fromList(File(realPath).readAsBytesSync());
      } else {
        // Export two playlists through the shipping path, then wipe the DB so
        // the import has to be what puts them back — otherwise the assertions
        // below would pass on the rows the seed left behind.
        for (final spec in [
          ('backup-1', 'Lista Uno', PlaylistType.xtream),
          ('backup-2', 'Lista Dos', PlaylistType.m3u),
        ]) {
          await PlaylistService.savePlaylist(Playlist(
            id: spec.$1,
            name: spec.$2,
            type: spec.$3,
            url: 'https://example.invalid/${spec.$1}',
            username: 'u-${spec.$1}',
            password: 'p-${spec.$1}',
            createdAt: DateTime(2026, 1, 1),
          ));
        }
        bytes = await BackupService.exportBytes();

        for (final id in ['backup-1', 'backup-2']) {
          await PlaylistService.deletePlaylist(id);
        }
        PlaylistService.invalidateCache();
        expect(await PlaylistService.getPlaylists(), isEmpty,
            reason: 'precondition: the import, not the seed, must be what '
                'puts the playlists back');
      }

      final r = await BackupService.importBytes(bytes);
      total = r.created + r.updated;
      PlaylistService.invalidateCache();
      final pls = await PlaylistService.getPlaylists();
      names = pls.map((p) => p.name).toList();
    });

    expect(total, greaterThan(0), reason: 'la importación debe escribir listas');
    expect(names.length, 2, reason: 'deben quedar 2 listas en la DB');

    // The list screen renders both playlists.
    await pumpScreen(tester, const PlaylistScreen());
    await tester.pump(const Duration(seconds: 1));
    for (final name in names) {
      expect(find.text(name), findsOneWidget,
          reason: 'la lista importada "$name" debe aparecer en pantalla');
    }

    await shot(tester, 'import_1_list.png');
  }, timeout: const Timeout(Duration(seconds: 45)));
}
