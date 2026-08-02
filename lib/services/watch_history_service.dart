import 'package:drift/drift.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/service_locator.dart';

class WatchHistoryService {
  final _database = getIt<AppDatabase>();

  WatchHistoryService();

  Future<void> saveWatchHistory(WatchHistory history) async {
    await _database
        .into(_database.watchHistories)
        .insertOnConflictUpdate(history.toDriftCompanion());
  }

  Future<WatchHistory?> getWatchHistory(
    String playlistId,
    String streamId,
  ) async {
    final query = _database.select(_database.watchHistories)
      ..where(
        (tbl) =>
            tbl.playlistId.equals(playlistId) & tbl.streamId.equals(streamId),
      );

    final result = await query.getSingleOrNull();
    return result != null ? WatchHistory.fromDrift(result) : null;
  }

  Future<List<WatchHistory>> getWatchHistoryByContentType(
    ContentType contentType, String playlistId
  ) async {
    final query = _database.select(_database.watchHistories)
      ..where((tbl) => tbl.contentType.equals(contentType.index) & tbl.playlistId.equals(playlistId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastWatched)]);

    final results = await query.get();
    return results.map((data) => WatchHistory.fromDrift(data)).toList();
  }

  Future<List<WatchHistory>> getContinueWatching(String playlistId) async {
    final query = _database.select(_database.watchHistories)
      ..where(
        (tbl) =>
            tbl.watchDuration.isNotNull() &
            tbl.totalDuration.isNotNull() &
            tbl.playlistId.equals(playlistId),
      )
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastWatched)]);

    final results = await query.get();
    return results.map((data) => WatchHistory.fromDrift(data)).toList();
  }

  Future<void> deleteWatchHistory(String playlistId, String streamId) async {
    await (_database.delete(_database.watchHistories)..where(
          (tbl) =>
              tbl.playlistId.equals(playlistId) & tbl.streamId.equals(streamId),
        ))
        .go();
  }

  Future<void> clearAllHistory() async {
    await _database.delete(_database.watchHistories).go();
  }

  /// Feature H (fase 5) — TODAS las filas de historial de casting, de CUALQUIER
  /// dispositivo: las particiones por-dispositivo `__cast__:<deviceId>` MÁS el
  /// `__cast__` plano heredado (móvil viejo sin deviceId), ordenadas por
  /// recencia. Lo usa el rail reducido de la TV para COMBINAR lo reciente de
  /// todos los móviles y reanudar en standalone; el SYNC del progreso sigue
  /// siendo per-dispositivo (ver tv_receiver_host). El `like('__cast__%')`
  /// acota la lectura en BD; como en LIKE de SQLite `_` es comodín, un
  /// `startsWith` en Dart descarta cualquier falso positivo teórico (correcto
  /// sea cual sea el esquema de ids de playlist).
  Future<List<WatchHistory>> getCastHistoryAll() async {
    final query = _database.select(_database.watchHistories)
      ..where((tbl) => tbl.playlistId.like('__cast__%'))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastWatched)]);
    final results = await query.get();
    return [
      for (final data in results)
        if (data.playlistId.startsWith('__cast__')) WatchHistory.fromDrift(data),
    ];
  }

  // ── Feature H (fase 5) — sincronización BIDIRECCIONAL de historial ──────────

  /// Deltas de "continuar viendo" de [playlistId] mapeados al wire de sync,
  /// capados a los [kHistorySyncMaxItems] más recientes. Lo usan AMBOS lados: el
  /// móvil para enviar su playlist activa, la TV para responder con `__cast__`.
  /// NO lleva tmdb (el historial no lo persiste); el merge lo tolera (null).
  Future<List<HistorySyncItem>> historySyncDeltas(String playlistId) async {
    if (playlistId.isEmpty) return const [];
    final rows = await getContinueWatching(playlistId);
    final items = <HistorySyncItem>[];
    for (final h in rows) {
      final pos = h.watchDuration?.inMilliseconds ?? 0;
      final dur = h.totalDuration?.inMilliseconds ?? 0;
      if (h.streamId.isEmpty || pos <= 0 || dur <= 0) continue;
      items.add(HistorySyncItem(
        streamId: h.streamId,
        posMs: pos,
        durMs: dur,
        contentTypeIndex: h.contentType.index,
        lastWatchedMs: h.lastWatched.millisecondsSinceEpoch,
      ));
    }
    return capHistorySync(items);
  }

  /// Mezcla [items] entrantes en [playlistId] según la regla COMPARTIDA
  /// ([historySyncShouldWrite]): une por `streamId`, respeta el aislamiento por
  /// tipo y el cross-check TMDb, y NUNCA reduce una posición mayor existente. Al
  /// actualizar una fila existente CONSERVA su título/carátula/serie (el wire no
  /// los trae). Para una fila NUEVA (contenido que solo existía en el otro
  /// dispositivo) el wire tampoco trae título, así que se RESUELVE del catálogo
  /// LOCAL por `streamId`(+contentType) — en el móvil su propio contenido está en
  /// su catálogo del mismo proveedor. Si no se puede resolver, igual se escribe
  /// la posición (el objetivo es que el progreso llegue) pero con título vacío, y
  /// el rail filtra esas filas anónimas (no se muestran tarjetas sin título).
  /// Devuelve cuántas filas escribió. Nunca lanza por un item suelto malformado.
  /// Solo-posición: no borra nada.
  Future<int> mergeHistorySync(
      String playlistId, List<HistorySyncItem> items) async {
    if (playlistId.isEmpty) return 0;
    var written = 0;
    for (final it in items) {
      // Descarta lo inservible: sin id, sin progreso, o con un tipo fuera de
      // rango (un `ct` corrupto no debe clasificarse a ciegas).
      if (it.streamId.isEmpty || it.posMs <= 0 || it.durMs <= 0) continue;
      if (it.contentTypeIndex < 0 ||
          it.contentTypeIndex >= ContentType.values.length) {
        continue;
      }
      final contentType = ContentType.values[it.contentTypeIndex];
      final existing = await getWatchHistory(playlistId, it.streamId);
      final existingItem = existing == null
          ? null
          : HistorySyncItem(
              streamId: existing.streamId,
              posMs: existing.watchDuration?.inMilliseconds ?? 0,
              durMs: existing.totalDuration?.inMilliseconds ?? 0,
              contentTypeIndex: existing.contentType.index,
              lastWatchedMs: existing.lastWatched.millisecondsSinceEpoch,
            );
      if (!historySyncShouldWrite(it, existingItem)) continue;
      // Corrección 1 — sin tarjetas anónimas: una fila existente conserva su
      // título/carátula; una fila NUEVA los resuelve del catálogo local (el wire
      // no los trae). Si no resuelve, título vacío → el rail la filtra.
      var title = existing?.title ?? '';
      var image = existing?.imagePath;
      if (existing == null) {
        final resolved =
            await _resolveTitleImage(playlistId, it.streamId, contentType);
        title = resolved.title;
        image = resolved.image;
      }
      await saveWatchHistory(WatchHistory(
        playlistId: playlistId,
        contentType: contentType,
        streamId: it.streamId,
        seriesId: existing?.seriesId,
        watchDuration: Duration(milliseconds: it.posMs),
        totalDuration: Duration(milliseconds: it.durMs),
        lastWatched: DateTime.fromMillisecondsSinceEpoch(it.lastWatchedMs),
        imagePath: image,
        title: title,
        containerExtension: existing?.containerExtension,
        providerId: existing?.providerId,
      ));
      written++;
    }
    return written;
  }

  /// Corrección 1 — resuelve título/carátula de una fila NUEVA desde el catálogo
  /// LOCAL de [playlistId] por [streamId] (+[type]): VOD → `vodStreams`, serie →
  /// el episodio en `episodes`. Best-effort: sin catálogo (p. ej. la partición
  /// `__cast__:<deviceId>` de la TV, que no tiene catálogo, o un test sin datos)
  /// devuelve título vacío → la fila se escribe igual pero el rail la oculta.
  Future<({String title, String? image})> _resolveTitleImage(
      String playlistId, String streamId, ContentType type) async {
    try {
      if (type == ContentType.vod) {
        final m = await _database.findMovieById(streamId, playlistId);
        if (m != null) return (title: m.name, image: m.streamIcon);
      } else if (type == ContentType.series) {
        final e = await _database.findEpisodesById(streamId, playlistId);
        if (e != null) return (title: e.title, image: null);
      }
    } catch (_) {/* sin catálogo → fila anónima (el rail la filtra) */}
    return (title: '', image: null);
  }
}
