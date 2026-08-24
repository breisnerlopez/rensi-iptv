import 'package:drift/drift.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';

/// Entries worth offering to resume, most recent first.
///
/// Lives here rather than in each home screen because it was duplicated in
/// both, which meant the wiring test covered one copy and the other could drift
/// with nothing noticing.
///
/// The query behind continue-watching only asks that both durations exist, so
/// unfiltered it keeps offering titles watched to the credits. The bounds are
/// what Netflix, Plex and Google TV all apply: drop the finished, and drop the
/// barely-started, which is a title opened by accident rather than one you are
/// partway through. Live is excluded outright — a channel has no position, and
/// a DVR window gives it a duration that makes the progress bar lie.
///
/// Floor: a title is offered once you've watched **≥ [_kResumeMinSeconds]s OR
/// ≥ 2%**, whichever comes first. The bare 2% floor hid real short viewings —
/// on a 90-min movie 2% is ~1.8 min, so a legitimate few-minutes-in play never
/// showed; the absolute-seconds floor fixes that while an accidental 3-second
/// tap still stays out. The 95% ceiling keeps hiding the near-finished.
const int _kResumeMinSeconds = 30;

List<WatchHistory> resumableFrom(List<WatchHistory> all) => all.where((h) {
      if (h.contentType == ContentType.liveStream) return false;
      // Feature H (fase 5) / Corrección 1 — sin tarjetas anónimas: una fila que
      // llegó por el sync de historial de cast y no pudo resolver su título del
      // catálogo local queda con título vacío. Se conserva su posición en BD
      // (por si luego aparece en el catálogo) pero NUNCA se ofrece en el rail.
      if (h.title.trim().isEmpty) return false;
      final total = h.totalDuration?.inSeconds ?? 0;
      if (total <= 0) return false;
      final watched = h.watchDuration?.inSeconds ?? 0;
      final progress = watched / total;
      return (watched >= _kResumeMinSeconds || progress > 0.02) &&
          progress < 0.95;
    }).toList();

/// Colapsa el "continuar viendo" para el rail del home: de una serie con varios
/// episodios resumibles deja solo el MÁS RECIENTE (una tarjeta por serie), en
/// vez de una tarjeta por episodio. Requiere [items] ordenado por `lastWatched`
/// descendente (como lo entrega `getContinueWatching`). Las filas de serie sin
/// `seriesId` (historial local previo a poblar el vínculo episodio→serie) no se
/// agrupan y se conservan tal cual.
List<WatchHistory> collapseSeriesByLatest(List<WatchHistory> items) {
  final seenSeries = <String>{};
  final out = <WatchHistory>[];
  for (final h in items) {
    if (h.contentType == ContentType.series && h.seriesId != null) {
      if (!seenSeries.add(h.seriesId!)) continue;
    }
    out.add(h);
  }
  return out;
}

class WatchHistory {
  late String playlistId;
  late ContentType contentType;
  late String streamId;
  late String? seriesId;
  late Duration? watchDuration;
  late Duration? totalDuration;
  late DateTime lastWatched;
  late String? imagePath;
  late String title;

  /// container_extension (mp4/mkv/…) del stream. Opcional (default null): sólo
  /// lo rellenan las filas que necesitan reconstruir una URL Xtream autónoma en
  /// la TV (feature H). Los constructores/callers existentes no lo pasan.
  late String? containerExtension;

  /// providerId (playlist Xtream de origen) de las credenciales para la URL
  /// autónoma. Opcional (default null), mismo motivo que [containerExtension].
  late String? providerId;

  WatchHistory({
    required this.playlistId,
    required this.contentType,
    required this.streamId,
    this.seriesId,
    this.watchDuration,
    this.totalDuration,
    required this.lastWatched,
    this.imagePath,
    required this.title,
    this.containerExtension,
    this.providerId,
  });

  WatchHistory.fromDrift(WatchHistoriesData data) {
    playlistId = data.playlistId;
    contentType = data.contentType;
    streamId = data.streamId;
    seriesId = data.seriesId;
    watchDuration = data.watchDuration != null
        ? Duration(milliseconds: data.watchDuration!)
        : null;
    totalDuration = data.totalDuration != null
        ? Duration(milliseconds: data.totalDuration!)
        : null;
    lastWatched = data.lastWatched;
    imagePath = data.imagePath;
    title = data.title;
    containerExtension = data.containerExtension;
    providerId = data.providerId;
  }

  /// Serialización para backup. `contentType` como índice del enum, duraciones
  /// en ms, `lastWatched` en ISO-8601 UTC. Incluye containerExtension/providerId
  /// para no perder la reconstrucción de URL autónoma en la TV al restaurar.
  Map<String, dynamic> toJson() {
    return {
      'playlist_id': playlistId,
      'content_type': contentType.index,
      'stream_id': streamId,
      'series_id': seriesId,
      'watch_duration': watchDuration?.inMilliseconds,
      'total_duration': totalDuration?.inMilliseconds,
      'last_watched': lastWatched.toUtc().toIso8601String(),
      'image_path': imagePath,
      'title': title,
      'container_extension': containerExtension,
      'provider_id': providerId,
    };
  }

  factory WatchHistory.fromJson(Map<String, dynamic> json) {
    final rawType = json['content_type'];
    final typeIndex =
        rawType is int ? rawType : int.tryParse('${rawType ?? ''}') ?? 0;
    final safeIndex = (typeIndex >= 0 && typeIndex < ContentType.values.length)
        ? typeIndex
        : 0;
    int? asMs(dynamic v) =>
        v == null ? null : (v is int ? v : int.tryParse('$v'));
    return WatchHistory(
      playlistId: json['playlist_id'] as String,
      contentType: ContentType.values[safeIndex],
      streamId: json['stream_id'] as String,
      seriesId: json['series_id'] as String?,
      watchDuration: asMs(json['watch_duration']) != null
          ? Duration(milliseconds: asMs(json['watch_duration'])!)
          : null,
      totalDuration: asMs(json['total_duration']) != null
          ? Duration(milliseconds: asMs(json['total_duration'])!)
          : null,
      lastWatched:
          DateTime.tryParse('${json['last_watched'] ?? ''}')?.toLocal() ??
          DateTime.now(),
      imagePath: json['image_path'] as String?,
      title: (json['title'] as String?) ?? '',
      containerExtension: json['container_extension'] as String?,
      providerId: json['provider_id'] as String?,
    );
  }

  WatchHistoriesCompanion toDriftCompanion() {
    return WatchHistoriesCompanion(
      playlistId: Value(playlistId),
      contentType: Value(contentType),
      streamId: Value(streamId),
      seriesId: Value(seriesId),
      watchDuration: Value(watchDuration?.inMilliseconds),
      totalDuration: Value(totalDuration?.inMilliseconds),
      lastWatched: Value(lastWatched),
      imagePath: Value(imagePath),
      title: Value(title),
      containerExtension: Value(containerExtension),
      providerId: Value(providerId),
    );
  }
}
