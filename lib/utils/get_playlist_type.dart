import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';

PlaylistType getPlaylistType() {
  return AppState.currentPlaylist!.type;
}

// Null-safe on purpose: "is the active playlist Xtream/M3U?" is `false` when
// there is no active playlist, not a crash. The `ContentItem` constructor calls
// isXtreamCode eagerly to bake its url, so a display-only item built with no
// active playlist (a TMDb discover card in global search) used to throw a null
// check during build and take the whole results view down. Every real caller
// only reaches these on a playback path where a playlist is set, so returning
// false when it is null changes nothing for them.
bool get isXtreamCode {
  return AppState.currentPlaylist?.type == PlaylistType.xtream;
}

bool get isM3u {
  return AppState.currentPlaylist?.type == PlaylistType.m3u;
}
