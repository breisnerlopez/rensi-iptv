// Feature H (fase 5) — sincronización BIDIRECCIONAL de "continuar viendo".
// Cubre: (1) la REGLA DE MERGE pura (idéntica en ambos lados), (2) el wire
// (encode/parse defensivo + cap), y (3) la orquestación sobre la BD
// (WatchHistoryService.mergeHistorySync / historySyncDeltas).
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';

import '../../helpers/test_database.dart';

HistorySyncItem _item({
  String cid = '7001',
  int? tmdb,
  int pos = 30000,
  int dur = 600000,
  int ct = 1, // vod
  int ts = 1000,
}) =>
    HistorySyncItem(
      streamId: cid,
      tmdbId: tmdb,
      posMs: pos,
      durMs: dur,
      contentTypeIndex: ct,
      lastWatchedMs: ts,
    );

void main() {
  group('historySyncShouldWrite — regla de merge (idéntica en ambos lados)', () {
    test('sin fila existente → escribe (fila nueva)', () {
      expect(historySyncShouldWrite(_item(), null), isTrue);
    });

    test('posición-primaria: una posición mayor gana (ts más reciente)', () {
      final existing = _item(pos: 30000, ts: 1000);
      final incoming = _item(pos: 90000, ts: 2000);
      expect(historySyncShouldWrite(incoming, existing), isTrue);
    });

    test('posición-primaria (drift-immune): una posición MAYOR gana AUNQUE su '
        'ts sea más VIEJO — un reloj sin RTC de la TV no debe descartar avance',
        () {
      final existing = _item(pos: 30000, ts: 2000);
      final incoming = _item(pos: 90000, ts: 1000);
      expect(historySyncShouldWrite(incoming, existing), isTrue,
          reason: 'gana la posición más lejana, sin mirar el ts');
    });

    test('empate EXACTO de posición → desempata el ts más reciente', () {
      final existing = _item(pos: 45000, ts: 1500);
      // Misma posición, ts más nuevo → gana.
      expect(historySyncShouldWrite(_item(pos: 45000, ts: 1600), existing),
          isTrue);
      // Misma posición, ts más viejo o igual → no escribe.
      expect(historySyncShouldWrite(_item(pos: 45000, ts: 1400), existing),
          isFalse);
      expect(historySyncShouldWrite(_item(pos: 45000, ts: 1500), existing),
          isFalse);
    });

    test('posición mayor gana sobre una menor con cualquier ts', () {
      final existing = _item(pos: 30000, ts: 1500);
      final incoming = _item(pos: 45000, ts: 1500);
      expect(historySyncShouldWrite(incoming, existing), isTrue);
      // …y la más CORTA nunca gana (no reduce).
      expect(historySyncShouldWrite(_item(pos: 20000, ts: 9999), existing),
          isFalse);
    });

    test('guarda "no reducir": una posición menor NUNCA se escribe, aun más '
        'reciente', () {
      final existing = _item(pos: 500000, ts: 1000);
      final incoming = _item(pos: 100000, ts: 9999);
      expect(historySyncShouldWrite(incoming, existing), isFalse,
          reason: 'castear/ver a medias no debe resetear el progreso mayor');
    });

    test('cross-check TMDb: mismo streamId pero tmdb DISTINTO → no mezcla', () {
      final existing = _item(tmdb: 111, pos: 30000, ts: 1000);
      final incoming = _item(tmdb: 222, pos: 90000, ts: 2000);
      expect(historySyncShouldWrite(incoming, existing), isFalse,
          reason: 'colisión de streamId entre proveedores → contenido distinto');
    });

    test('cross-check TMDb: mismo tmdb → reconcilia (mezcla si avanza)', () {
      final existing = _item(tmdb: 111, pos: 30000, ts: 1000);
      final incoming = _item(tmdb: 111, pos: 90000, ts: 2000);
      expect(historySyncShouldWrite(incoming, existing), isTrue);
    });

    test('cross-check TMDb: si falta en algún lado, se une solo por streamId', () {
      // Existente sin tmdb (el historial no lo persiste), entrante con tmdb.
      final existing = _item(tmdb: null, pos: 30000, ts: 1000);
      final incoming = _item(tmdb: 999, pos: 90000, ts: 2000);
      expect(historySyncShouldWrite(incoming, existing), isTrue,
          reason: 'sin ambos tmdb el cross-check no aplica; une por streamId');
    });

    test('aislamiento por contentType: distinto ct → no mezcla', () {
      final existing = _item(ct: ContentType.vod.index, pos: 30000, ts: 1000);
      final incoming =
          _item(ct: ContentType.series.index, pos: 90000, ts: 2000);
      expect(historySyncShouldWrite(incoming, existing), isFalse,
          reason: 'no degradar serie↔vod bajo el mismo streamId');
    });
  });

  group('wire: encode/parse defensivo + cap', () {
    test('round-trip de un item conserva todos los campos', () {
      final body = encodeHistorySyncBody([
        const HistorySyncItem(
          streamId: '7001',
          tmdbId: 42,
          posMs: 30000,
          durMs: 600000,
          contentTypeIndex: 1,
          lastWatchedMs: 1717000000000,
        ),
      ], done: true);
      final parsed = parseHistorySyncItems(body);
      expect(parsed.single.streamId, '7001');
      expect(parsed.single.tmdbId, 42);
      expect(parsed.single.posMs, 30000);
      expect(parsed.single.durMs, 600000);
      expect(parsed.single.contentTypeIndex, 1);
      expect(parsed.single.lastWatchedMs, 1717000000000);
    });

    test('sin tmdb: el campo se omite y decodifica a null', () {
      final body = encodeHistorySyncBody([_item(tmdb: null)]);
      expect((body['items'] as List).single.containsKey('tmdb'), isFalse);
      expect(parseHistorySyncItems(body).single.tmdbId, isNull);
    });

    test('parse defensivo: items ausente/entradas no-Map → tolerante', () {
      expect(parseHistorySyncItems(const {}), isEmpty);
      expect(parseHistorySyncItems({'items': 'nope'}), isEmpty);
      final mixed = parseHistorySyncItems({
        'items': [
          {'cid': 'a', 'pos': 10, 'dur': 100, 'ct': 1, 'ts': 5},
          'basura',
          42,
        ],
      });
      expect(mixed.map((e) => e.streamId), ['a']);
    });

    test('cap: un lote > kHistorySyncMaxItems se recorta a los más recientes', () {
      final many = [
        for (var i = 0; i < kHistorySyncMaxItems + 50; i++)
          _item(cid: 'c$i', ts: i) // ts creciente
      ];
      final capped = capHistorySync(many);
      expect(capped.length, kHistorySyncMaxItems);
      // Ordenados por ts desc → el primero es el ts más alto.
      expect(capped.first.lastWatchedMs, kHistorySyncMaxItems + 50 - 1);
      // El ts más viejo (0) NO sobrevive al cap.
      expect(capped.any((e) => e.lastWatchedMs == 0), isFalse);
    });

    test('parse acotado por índice CRUDO: una lista gigante de basura no-Map no '
        'itera sin límite (anti-ANR)', () {
      // 10x el tope, TODO basura no-Map: sin el tope por índice crudo esto se
      // iteraría entero. Debe cortar y devolver vacío sin colgarse.
      final junk = List<Object>.filled(kHistorySyncMaxItems * 10, 'x');
      final parsed = parseHistorySyncItems({'items': junk});
      expect(parsed, isEmpty);
    });
  });

  group('WatchHistoryService — mergeHistorySync / historySyncDeltas (BD)', () {
    late AppDatabase db;
    setUp(() async {
      await getIt.reset();
      db = createTestDatabase();
      getIt.registerSingleton<AppDatabase>(db);
    });
    tearDown(() async {
      await getIt.reset();
      await db.close();
    });

    test('fila nueva: escribe la posición aunque no haya título en el wire',
        () async {
      final svc = WatchHistoryService();
      final n = await svc.mergeHistorySync('p', [
        _item(cid: '7001', pos: 60000, dur: 600000, ct: 1, ts: 1000),
      ]);
      expect(n, 1);
      final row = await svc.getWatchHistory('p', '7001');
      expect(row!.watchDuration, const Duration(milliseconds: 60000));
      expect(row.totalDuration, const Duration(milliseconds: 600000));
      expect(row.contentType, ContentType.vod);
    });

    test('actualiza una fila existente CONSERVANDO título/carátula', () async {
      final svc = WatchHistoryService();
      await svc.saveWatchHistory(WatchHistory(
        playlistId: 'p',
        contentType: ContentType.vod,
        streamId: '7001',
        watchDuration: const Duration(milliseconds: 30000),
        totalDuration: const Duration(milliseconds: 600000),
        lastWatched: DateTime.fromMillisecondsSinceEpoch(1000),
        title: 'Peli buena',
        imagePath: 'http://img/x.jpg',
      ));
      // Entrante más reciente y con más posición → gana.
      final n = await svc.mergeHistorySync('p', [
        _item(cid: '7001', pos: 90000, dur: 600000, ct: 1, ts: 2000),
      ]);
      expect(n, 1);
      final row = await svc.getWatchHistory('p', '7001');
      expect(row!.watchDuration, const Duration(milliseconds: 90000));
      expect(row.title, 'Peli buena', reason: 'no se pisa el título con vacío');
      expect(row.imagePath, 'http://img/x.jpg');
    });

    test('no reduce: un entrante con menos posición no toca la fila', () async {
      final svc = WatchHistoryService();
      await svc.saveWatchHistory(WatchHistory(
        playlistId: 'p',
        contentType: ContentType.vod,
        streamId: '7001',
        watchDuration: const Duration(milliseconds: 500000),
        totalDuration: const Duration(milliseconds: 600000),
        lastWatched: DateTime.fromMillisecondsSinceEpoch(1000),
        title: 'Peli',
      ));
      final n = await svc.mergeHistorySync('p', [
        _item(cid: '7001', pos: 100000, dur: 600000, ct: 1, ts: 9999),
      ]);
      expect(n, 0);
      final row = await svc.getWatchHistory('p', '7001');
      expect(row!.watchDuration, const Duration(milliseconds: 500000));
    });

    test('descarta items con ct fuera de rango o sin progreso', () async {
      final svc = WatchHistoryService();
      final n = await svc.mergeHistorySync('p', [
        _item(cid: 'bad-ct', ct: 99),
        _item(cid: 'no-pos', pos: 0),
        _item(cid: 'no-dur', dur: 0),
        const HistorySyncItem(
            streamId: '', posMs: 1, durMs: 1, contentTypeIndex: 1, lastWatchedMs: 1),
      ]);
      expect(n, 0);
    });

    test('historySyncDeltas: mapea continue-watching y capa', () async {
      final svc = WatchHistoryService();
      await svc.saveWatchHistory(WatchHistory(
        playlistId: 'p',
        contentType: ContentType.series,
        streamId: 'e1',
        watchDuration: const Duration(milliseconds: 45000),
        totalDuration: const Duration(milliseconds: 1200000),
        lastWatched: DateTime.fromMillisecondsSinceEpoch(5000),
        title: 'Serie',
      ));
      final deltas = await svc.historySyncDeltas('p');
      expect(deltas.single.streamId, 'e1');
      expect(deltas.single.posMs, 45000);
      expect(deltas.single.durMs, 1200000);
      expect(deltas.single.contentTypeIndex, ContentType.series.index);
      expect(deltas.single.lastWatchedMs, 5000);
    });

    test('historySyncDeltas: playlist vacía → lista vacía', () async {
      expect(await WatchHistoryService().historySyncDeltas('p'), isEmpty);
      expect(await WatchHistoryService().historySyncDeltas(''), isEmpty);
    });

    test('Corrección 1 — fila nueva SIN catálogo queda con título vacío '
        '(anónima, luego filtrada del rail)', () async {
      final svc = WatchHistoryService();
      await svc.mergeHistorySync('p', [
        _item(cid: '7001', pos: 60000, dur: 600000, ct: 1, ts: 1000),
      ]);
      final row = await svc.getWatchHistory('p', '7001');
      expect(row!.title, isEmpty, reason: 'sin catálogo no hay título que poner');
    });

    test('Corrección 1 — fila nueva RESUELVE título/carátula del catálogo VOD '
        'local por streamId', () async {
      // Sembrar la película en el catálogo de la playlist 'p' (mismo proveedor).
      await db.into(db.vodStreams).insert(VodStreamsCompanion.insert(
            streamId: '7001',
            name: 'Marea negra',
            streamIcon: 'http://img/marea.jpg',
            categoryId: 'c1',
            rating: '8',
            rating5based: 4,
            containerExtension: 'mp4',
            playlistId: 'p',
          ));
      final svc = WatchHistoryService();
      await svc.mergeHistorySync('p', [
        _item(cid: '7001', pos: 60000, dur: 600000, ct: 1, ts: 1000),
      ]);
      final row = await svc.getWatchHistory('p', '7001');
      expect(row!.title, 'Marea negra');
      expect(row.imagePath, 'http://img/marea.jpg');
    });

    test('getCastHistoryAll: reúne TODAS las particiones __cast__ y excluye las '
        'ajenas', () async {
      final svc = WatchHistoryService();
      Future<void> seed(String pid, String cid, int ts) => svc.saveWatchHistory(
            WatchHistory(
              playlistId: pid,
              contentType: ContentType.vod,
              streamId: cid,
              watchDuration: const Duration(milliseconds: 30000),
              totalDuration: const Duration(milliseconds: 600000),
              lastWatched: DateTime.fromMillisecondsSinceEpoch(ts),
              title: 't$cid',
            ),
          );
      await seed('__cast__:devA', 'a', 3000);
      await seed('__cast__:devB', 'b', 2000);
      await seed('__cast__', 'legacy', 1000); // plano heredado
      await seed('real-playlist', 'z', 4000); // NO es de casting

      final all = await svc.getCastHistoryAll();
      expect(all.map((e) => e.streamId).toSet(), {'a', 'b', 'legacy'});
      // Orden por recencia desc.
      expect(all.first.streamId, 'a');
    });
  });
}
