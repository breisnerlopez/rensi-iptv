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
