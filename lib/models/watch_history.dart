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
