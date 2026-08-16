// Import de archivos locales: verifica que importLocalFile crea una fila
// completa+imported con el archivo copiado, y —CRÍTICO por seguridad de datos—
// que un import NUNCA se auto-borra al verse (no es re-descargable).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/services/download_service.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rensi_import_test');
    // getApplicationSupportDirectory() → carpeta temporal (sin este mock lanza
    // MissingPluginException en flutter test).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    db = createTestDatabase();
    if (GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.unregister<AppDatabase>();
    }
    GetIt.instance.registerSingleton<AppDatabase>(db);
  });

  tearDown(() async {
    await db.close();
    if (GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.unregister<AppDatabase>();
    }
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('importLocalFile crea fila complete+imported y copia el archivo',
      () async {
    final bytes = List<int>.generate(1000, (i) => i % 256);
    final row = await DownloadService.instance.importLocalFile(
      source: Stream.fromIterable([bytes.sublist(0, 500), bytes.sublist(500)]),
      fileName: 'My Movie (2010).MKV',
      sizeBytes: 1000,
    );

    expect(row.status, 'complete');
    expect(row.imported, isTrue);
    expect(row.contentType, 'vod');
    expect(row.ext, 'mkv'); // normalizado a minúsculas
    expect(row.title, 'My Movie (2010)');
    expect(row.filePath, isNotNull);
    expect(row.contentId.startsWith('import_'), isTrue);

    final f = File(row.filePath!);
    expect(await f.exists(), isTrue);
    expect(await f.length(), 1000);
    expect(await f.readAsBytes(), bytes);
  });

  test('movePath MUEVE el archivo (rename) a la biblioteca sin dejar el origen',
      () async {
    // Simula la cache de file_picker (mismo filesystem que la carpeta destino).
    final src = File('${tempDir.path}/picker_cache.mkv');
    await src.writeAsBytes(List<int>.generate(500, (i) => i % 256));

    final row = await DownloadService.instance.importLocalFile(
      movePath: src.path,
      fileName: 'Peli.mkv',
      sizeBytes: 500,
    );

    expect(row.imported, isTrue);
    expect(row.status, 'complete');
    expect(row.filePath, isNotNull);
    expect(await File(row.filePath!).exists(), isTrue);
    expect(await File(row.filePath!).length(), 500);
    expect(await src.exists(), isFalse,
        reason: 'el origen (cache) se MOVIÓ, no quedó una copia duplicada');
  });

  test('un import visto NO se auto-borra (imported excluido del delete-watched)',
      () async {
    final row = await DownloadService.instance.importLocalFile(
      source: Stream.fromIterable([List<int>.filled(100, 1)]),
      fileName: 'clip.mp4',
      sizeBytes: 100,
    );
    final path = row.filePath!;

    // Verlo al 100% dispararía el auto-borrado de una descarga normal.
    await DownloadService.instance.markWatchedAndMaybeDelete(
      row.contentId,
      const Duration(minutes: 10),
      const Duration(minutes: 10),
    );

    final still = await DownloadService.instance.findByContentId(row.contentId);
    expect(still, isNotNull, reason: 'un import nunca se auto-borra al verlo');
    expect(still!.watched, isTrue);
    expect(await File(path).exists(), isTrue,
        reason: 'el archivo del import debe seguir en disco');
  });
}
