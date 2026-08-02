// Feature H (fase 5) — historial de casting PER-DISPOSITIVO en la TV.
//
// Ejercita el NÚCLEO real que usa `_TvReceiverHostState._onHistorySync`:
// [mergeAndReplyHistorySync] (merge del móvil en su partición
// `__cast__:<deviceId>` + construcción de la respuesta con esa MISMA partición)
// contra una BD real en memoria — NO una simulación a mano de `sendMessage`.
// Verifica el intent del usuario: la TV sincroniza el progreso de un título SOLO
// al móvil que lo casteó, nunca cruza entre móviles de la casa.
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:rensi_iptv/widgets/cast/tv_receiver_host.dart'
    show castHistoryPlaylistId, mergeAndReplyHistorySync;

import '../../helpers/test_database.dart';

HistorySyncItem _item({
  required String cid,
  int pos = 60000,
  int dur = 600000,
  int ct = 1, // vod
  int ts = 1000,
}) =>
    HistorySyncItem(
      streamId: cid,
      posMs: pos,
      durMs: dur,
      contentTypeIndex: ct,
      lastWatchedMs: ts,
    );

void main() {
  group('castHistoryPlaylistId — partición por dispositivo', () {
    test('deviceId presente → `__cast__:<id>`; vacío → `__cast__` plano', () {
      expect(castHistoryPlaylistId('devA'), '__cast__:devA');
      expect(castHistoryPlaylistId(''), '__cast__');
    });
  });

  group('mergeAndReplyHistorySync — merge + reply per-dispositivo (BD real)', () {
    late AppDatabase db;
    late WatchHistoryService svc;
    setUp(() async {
      await getIt.reset();
      db = createTestDatabase();
      getIt.registerSingleton<AppDatabase>(db);
      svc = WatchHistoryService();
    });
    tearDown(() async {
      await getIt.reset();
      await db.close();
    });

    test('mezcla los deltas del móvil bajo SU partición `__cast__:<deviceId>`',
        () async {
      final r = await mergeAndReplyHistorySync(svc, 'devA', [
        _item(cid: '7001', pos: 60000, ts: 1000),
      ]);
      expect(r.written, 1);
      // Escribió en la partición de devA, NO en el `__cast__` plano.
      expect(await svc.getWatchHistory('__cast__:devA', '7001'), isNotNull);
      expect(await svc.getWatchHistory('__cast__', '7001'), isNull);
      // La respuesta lleva esa misma fila (para que el móvil reciba el avance
      // que la TV pudiera tener).
      expect(r.reply.map((e) => e.streamId), contains('7001'));
    });

    test('la respuesta a un dispositivo NUNCA incluye filas de OTRO', () async {
      // devA y devB castearon títulos distintos; cada uno acaba en su partición.
      await mergeAndReplyHistorySync(svc, 'devA', [_item(cid: 'A1')]);
      await mergeAndReplyHistorySync(svc, 'devB', [_item(cid: 'B1')]);

      // Un nuevo sync de devA (sin deltas nuevos): la respuesta debe traer SOLO
      // las filas de devA, jamás la de devB.
      final replyA = await mergeAndReplyHistorySync(svc, 'devA', const []);
      final idsA = replyA.reply.map((e) => e.streamId).toSet();
      expect(idsA, contains('A1'));
      expect(idsA, isNot(contains('B1')),
          reason: 'per-dispositivo: devA nunca recibe filas de devB');

      final replyB = await mergeAndReplyHistorySync(svc, 'devB', const []);
      final idsB = replyB.reply.map((e) => e.streamId).toSet();
      expect(idsB, contains('B1'));
      expect(idsB, isNot(contains('A1')));
    });

    test('lote vacío → no escribe pero SÍ responde con la partición del móvil',
        () async {
      await svc.saveWatchHistory(WatchHistory(
        playlistId: '__cast__:devA',
        contentType: ContentType.vod,
        streamId: '7001',
        watchDuration: const Duration(milliseconds: 30000),
        totalDuration: const Duration(milliseconds: 600000),
        lastWatched: DateTime.fromMillisecondsSinceEpoch(1000),
        title: 'Peli',
      ));
      final r = await mergeAndReplyHistorySync(svc, 'devA', const []);
      expect(r.written, 0);
      expect(r.reply.single.streamId, '7001');
    });

    test('el avance hecho en la TV (posición mayor) sí se responde al móvil',
        () async {
      // El móvil dejó el título en 30s; la TV lo avanzó a 120s (standalone).
      await svc.saveWatchHistory(WatchHistory(
        playlistId: '__cast__:devA',
        contentType: ContentType.vod,
        streamId: '7001',
        watchDuration: const Duration(milliseconds: 120000),
        totalDuration: const Duration(milliseconds: 600000),
        lastWatched: DateTime.fromMillisecondsSinceEpoch(500),
        title: 'Peli',
      ));
      final r = await mergeAndReplyHistorySync(svc, 'devA', [
        _item(cid: '7001', pos: 30000, ts: 9999), // móvil atrás, ts nuevo
      ]);
      // No se reduce (posición-primaria): la fila queda en 120s…
      expect(await svc.getWatchHistory('__cast__:devA', '7001')
          .then((h) => h!.watchDuration),
          const Duration(milliseconds: 120000));
      // …y la respuesta lleva los 120s para que el móvil los reciba.
      expect(r.reply.single.posMs, 120000);
    });

    test('deviceId vacío (móvil viejo) → cae al `__cast__` plano', () async {
      final r = await mergeAndReplyHistorySync(svc, '', [_item(cid: '7001')]);
      expect(r.written, 1);
      expect(await svc.getWatchHistory('__cast__', '7001'), isNotNull);
    });
  });
}
