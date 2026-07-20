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
List<WatchHistory> resumableFrom(List<WatchHistory> all) => all.where((h) {
      if (h.contentType == ContentType.liveStream) return false;
      final total = h.totalDuration?.inSeconds ?? 0;
      if (total <= 0) return false;
      final progress = (h.watchDuration?.inSeconds ?? 0) / total;
      return progress > 0.02 && progress < 0.95;
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
    );
  }
}
