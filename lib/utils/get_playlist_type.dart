import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';

PlaylistType getPlaylistType() {
  return AppState.currentPlaylist!.type;
}

bool get isXtreamCode {
  return getPlaylistType() == PlaylistType.xtream;
}

bool get isM3u {
  return getPlaylistType() == PlaylistType.m3u;
}
