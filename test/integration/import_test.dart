import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/screens/playlist_screen.dart';
import 'package:rensi_iptv/services/backup_service.dart';
import 'package:rensi_iptv/services/playlist_service.dart';

import 'harness.dart';

String _backupPath() =>
    Platform.environment['RENSI_BACKUP'] ??
    '/tmp/claude-1000/-workspace-rensi-iptv/aad59248-3ca7-4d7f-93cd-0334958c2000/scratchpad/fixtures/backup.json';

void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('Importar backup real → 2 listas en DB y en pantalla',
      (tester) async {
    final f = File(_backupPath());
    if (!f.existsSync()) {
      markTestSkipped('backup fixture ausente');
      return;
    }
    // Sync read: real file IO would hang in the testWidgets FakeAsync zone.
    final bytes = Uint8List.fromList(f.readAsBytesSync());

    // 1) Import writes to DB. Real async (Drift/secure storage) must run
    // outside the widget-tester FakeAsync zone, hence tester.runAsync.
    var total = 0;
    var names = <String>[];
    await tester.runAsync(() async {
      // ignore: avoid_print
      print('DIAG: runAsync start');
      final r = await BackupService.importBytes(bytes);
      // ignore: avoid_print
      print('DIAG: imported created=${r.created} updated=${r.updated}');
      total = r.created + r.updated;
      final pls = await PlaylistService.getPlaylists();
      // ignore: avoid_print
      print('DIAG: getPlaylists -> ${pls.length}');
      names = pls.map((p) => p.name).toList();
    });
    // ignore: avoid_print
    print('DIAG: after runAsync total=$total names=$names');
    expect(total, greaterThan(0), reason: 'la importación debe escribir listas');
    expect(names.length, 2, reason: 'deben quedar 2 listas en la DB');

    // 2) The list screen renders both playlists.
    await pumpScreen(tester, const PlaylistScreen());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('LopezCueto3'), findsOneWidget);
    expect(find.text('LopezCueto5'), findsOneWidget);

    await shot(tester, 'import_1_list.png');
  }, timeout: const Timeout(Duration(seconds: 45)));
}
