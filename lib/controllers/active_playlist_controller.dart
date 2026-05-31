import 'package:flutter/foundation.dart';

import '../models/playlist_model.dart';
import '../repositories/user_preferences.dart';
import '../services/app_state.dart';
import '../services/playlist_service.dart';

class ActivePlaylistController extends ChangeNotifier {
  Playlist? _activePlaylist;
  List<Playlist> _playlists = const [];
  bool _isLoading = false;

  Playlist? get activePlaylist => _activePlaylist;
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isLoading => _isLoading;

  void setInitialPlaylist(Playlist? playlist) {
    if (playlist == null || _activePlaylist?.id == playlist.id) return;
    _activePlaylist = playlist;
    AppState.currentPlaylist = playlist;
    notifyListeners();
  }

  Future<List<Playlist>> loadPlaylists({bool forceRefresh = false}) async {
    if (_playlists.isNotEmpty && !forceRefresh) return _playlists;

    _isLoading = true;
    notifyListeners();
    try {
      _playlists = await PlaylistService.getPlaylists();
      return _playlists;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectPlaylist(Playlist playlist) async {
    _activePlaylist = playlist;
    AppState.currentPlaylist = playlist;
    await UserPreferences.setLastPlaylist(playlist.id);
    notifyListeners();
  }
}
