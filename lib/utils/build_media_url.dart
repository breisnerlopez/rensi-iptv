import 'package:rensi_iptv/services/app_state.dart';

import '../models/content_type.dart';
import '../models/playlist_content_model.dart';

String buildMediaUrl(ContentItem contentItem) {
  var playlist = AppState.currentPlaylist!;
  // A null/empty extension used to interpolate the literal ".null", which the
  // panel answers with an HTML error page → libmpv "failed to recognize file
  // format". Omit the suffix entirely when there's no extension (series items
  // never carry one — they open an episode list, not the player).
  final ext = contentItem.containerExtension;
  final suffix = (ext != null && ext.isNotEmpty) ? '.$ext' : '';
  switch (contentItem.contentType) {
    case ContentType.liveStream:
      return '${playlist.url}/${playlist.username}/${playlist.password}/${contentItem.id}';
    case ContentType.vod:
      return '${playlist.url}/movie/${playlist.username}/${playlist.password}/${contentItem.id}$suffix';
    case ContentType.series:
      return '${playlist.url}/series/${playlist.username}/${playlist.password}/${contentItem.id}$suffix';
  }
}

/// Builds an Xtream **timeshift / catch-up** URL for replaying a past programme
/// on an archive-enabled live channel:
///   `{host}/timeshift/{user}/{pass}/{durationMinutes}/{YYYY-MM-DD:HH-MM}/{streamId}.ts`
///
/// [start] is the programme's start time and [durationMinutes] its length; the
/// panel serves the recorded window from that instant. The date/time is encoded
/// in the provider's expected `YYYY-MM-DD:HH-MM` shape. Returns null when there
/// is no current playlist (nothing to authenticate against).
String? buildTimeshiftUrl({
  required String streamId,
  required DateTime start,
  required int durationMinutes,
}) {
  final playlist = AppState.currentPlaylist;
  if (playlist == null) return null;
  // Xtream timeshift expects the START in the SERVER/local wall-clock the panel
  // records against; use local time (the same basis the EPG is displayed in).
  final t = start.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${t.year}-${two(t.month)}-${two(t.day)}:${two(t.hour)}-${two(t.minute)}';
  final dur = durationMinutes <= 0 ? 1 : durationMinutes;
  return '${playlist.url}/timeshift/${playlist.username}/${playlist.password}/$dur/$stamp/$streamId.ts';
}

/// The container extensions to try, in order, when a VOD fails to demux because
/// the cached extension is stale (provider re-encoded the title). Kept small: 2
/// alternates cap the worst-case retry latency at ~a few seconds.
const List<String> kVodExtensionCandidates = ['mp4', 'mkv', 'avi'];

/// Returns [url] with its trailing `.ext` replaced by [ext]. If the url has no
/// recognizable extension, appends one.
String swapUrlExtension(String url, String ext) {
  final q = url.indexOf('?');
  final base = q >= 0 ? url.substring(0, q) : url;
  final tail = q >= 0 ? url.substring(q) : '';
  final dot = base.lastIndexOf('.');
  final slash = base.lastIndexOf('/');
  if (dot > slash) {
    return '${base.substring(0, dot)}.$ext$tail';
  }
  return '$base.$ext$tail';
}
