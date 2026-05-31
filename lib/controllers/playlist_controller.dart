import 'package:rensi_iptv/screens/m3u/m3u_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'active_playlist_controller.dart';
import '../models/playlist_model.dart';
import '../screens/xtream-codes/xtream_code_home_screen.dart';
import '../services/playlist_service.dart';

class PlaylistController extends ChangeNotifier {
  List<Playlist> _playlists = [];
  bool _isLoading = false;
  String? _errorKey;
  String? _errorDetail;
  bool _hasInitialized = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  bool get isLoading => _isLoading;

  /// Localization key for the last error (e.g. `playlist_load_failed`). Use
  /// with `errorDetail` to render a translated message in the UI.
  String? get errorKey => _errorKey;

  /// Optional detail (often an exception string) appended to a localized
  /// message via the `{error}` placeholder.
  String? get errorDetail => _errorDetail;

  /// Plain-English fallback. UI code should prefer translating `errorKey`
  /// against the app localization, falling back to this when no translation
  /// exists.
  String? get error => _errorKey == null
      ? null
      : (_errorDetail == null
          ? _englishFor(_errorKey!)
          : '${_englishFor(_errorKey!)}: $_errorDetail');

  bool get hasInitialized => _hasInitialized;

  int get playlistCount => _playlists.length;

  int get xtreamCount =>
      _playlists.where((p) => p.type == PlaylistType.xtream).length;

  int get m3uCount =>
      _playlists.where((p) => p.type == PlaylistType.m3u).length;

  List<Playlist> get xtreamPlaylists => getPlaylistsByType(PlaylistType.xtream);

  List<Playlist> get m3uPlaylists => getPlaylistsByType(PlaylistType.m3u);

  Future<void> loadPlaylists(BuildContext context) async {
    _setLoading(true);
    _clearError();

    try {
      _playlists = await PlaylistService.getPlaylists();
      _sortPlaylists();
      _hasInitialized = true;
    } catch (e) {
      _setError('playlist_load_failed', e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> openPlaylist(BuildContext context, Playlist playlist) async {
    await UserPreferences.setLastPlaylist(playlist.id);
    AppState.currentPlaylist = playlist;
    context.read<ActivePlaylistController>().setInitialPlaylist(playlist);

    if (context.mounted) {
      switch (playlist.type) {
        case PlaylistType.xtream:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => XtreamCodeHomeScreen(playlist: playlist),
            ),
          );
        case PlaylistType.m3u:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => M3UHomeScreen(playlist: playlist),
            ),
          );
      }
    }
  }

  Future<Playlist?> createPlaylist({
    required String name,
    required PlaylistType type,
    String? url,
    String? username,
    String? password,
  }) async {
    if (!_validateInput(name, type, url, username, password)) {
      return null;
    }

    _setLoading(true);
    _clearError();

    try {
      final playlist = Playlist(
        id: _generateUniqueId(),
        name: name.trim(),
        type: type,
        url: url?.trim(),
        username: username?.trim(),
        password: password?.trim(),
        createdAt: DateTime.now(),
      );

      await PlaylistService.savePlaylist(playlist);
      _playlists.add(playlist);
      _sortPlaylists();

      return playlist;
    } catch (e) {
      _setError('playlist_save_failed', e.toString());
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deletePlaylist(String id) async {
    try {
      await PlaylistService.deletePlaylist(id);
      _playlists.removeWhere((playlist) => playlist.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _setError('playlist_delete_failed', e.toString());
      return false;
    }
  }

  Future<bool> deleteMultiplePlaylists(List<String> ids) async {
    _setLoading(true);
    _clearError();

    try {
      for (final id in ids) {
        await PlaylistService.deletePlaylist(id);
        _playlists.removeWhere((playlist) => playlist.id == id);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _setError('playlist_delete_failed', e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updatePlaylist(Playlist updatedPlaylist) async {
    _setLoading(true);
    _clearError();

    try {
      if (_isDuplicateName(updatedPlaylist)) {
        _setError('playlist_name_already_exists');
        return false;
      }

      await PlaylistService.updatePlaylist(updatedPlaylist);

      final index = _playlists.indexWhere((p) => p.id == updatedPlaylist.id);
      if (index != -1) {
        _playlists[index] = updatedPlaylist;
        _sortPlaylists();
      }

      return true;
    } catch (e) {
      _setError('playlist_update_failed', e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Playlist? getPlaylistById(String id) {
    try {
      return _playlists.firstWhere((playlist) => playlist.id == id);
    } catch (e) {
      return null;
    }
  }

  List<Playlist> getPlaylistsByType(PlaylistType type) {
    return _playlists.where((playlist) => playlist.type == type).toList();
  }

  List<Playlist> searchPlaylists(String query) {
    if (query.trim().isEmpty) return _playlists;

    final lowercaseQuery = query.toLowerCase();
    return _playlists.where((playlist) {
      return playlist.name.toLowerCase().contains(lowercaseQuery) ||
          (playlist.url?.toLowerCase().contains(lowercaseQuery) ?? false) ||
          (playlist.username?.toLowerCase().contains(lowercaseQuery) ?? false);
    }).toList();
  }

  Map<String, int> getPlaylistStats() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeek = now.subtract(const Duration(days: 7));
    final thisMonth = DateTime(now.year, now.month, 1);

    return {
      'total': _playlists.length,
      'xstream': xtreamCount,
      'm3u': m3uCount,
      'createdToday': _playlists.where((p) {
        final playlistDate = DateTime(
          p.createdAt.year,
          p.createdAt.month,
          p.createdAt.day,
        );
        return playlistDate.isAtSameMomentAs(today);
      }).length,
      'createdThisWeek': _playlists
          .where((p) => p.createdAt.isAfter(thisWeek))
          .length,
      'createdThisMonth': _playlists
          .where((p) => p.createdAt.isAfter(thisMonth))
          .length,
    };
  }

  bool validatePlaylistData({
    required String name,
    required PlaylistType type,
    String? url,
    String? username,
    String? password,
  }) {
    return _validateInput(name, type, url, username, password);
  }

  void clearError() => _clearError();

  /// Set a localizable error directly (use l10n keys defined in app.arb).
  void setError(String errorKey, [String? detail]) {
    _setError(errorKey, detail);
  }

  Future<void> refreshPlaylists(BuildContext context) async {
    await loadPlaylists(context);
  }

  bool _validateInput(
    String name,
    PlaylistType type,
    String? url,
    String? username,
    String? password,
  ) {
    if (name.trim().isEmpty || name.trim().length < 2) {
      _setError('playlist_name_min_2');
      return false;
    }

    if (_playlists.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      _setError('playlist_name_already_exists');
      return false;
    }

    if (type == PlaylistType.xtream) {
      if (url?.trim().isEmpty ?? true) {
        _setError('api_url_required');
        return false;
      }
      if (username?.trim().isEmpty ?? true) {
        _setError('username_required');
        return false;
      }
      if (password?.trim().isEmpty ?? true) {
        _setError('password_required');
        return false;
      }

      final uri = Uri.tryParse(url!.trim());
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        _setError('url_format_validate_error');
        return false;
      }
    }

    return true;
  }

  bool _isDuplicateName(Playlist playlist) {
    return _playlists.any(
      (p) =>
          p.id != playlist.id &&
          p.name.toLowerCase() == playlist.name.toLowerCase(),
    );
  }

  void _sortPlaylists() {
    _playlists.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String errorKey, [String? detail]) {
    _errorKey = errorKey;
    _errorDetail = detail;
    _isLoading = false;
    notifyListeners();
  }

  void _clearError() {
    if (_errorKey != null || _errorDetail != null) {
      _errorKey = null;
      _errorDetail = null;
      notifyListeners();
    }
  }

  String _generateUniqueId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_playlists.length}';
  }

  static String _englishFor(String key) {
    switch (key) {
      case 'playlist_load_failed':
        return 'Failed to load playlists';
      case 'playlist_save_failed':
        return 'Failed to save playlist';
      case 'playlist_update_failed':
        return 'Failed to update playlist';
      case 'playlist_delete_failed':
        return 'Failed to delete playlist';
      case 'playlist_name_min_2':
        return 'Playlist name must be at least 2 characters';
      case 'playlist_name_already_exists':
        return 'A playlist with this name already exists';
      case 'api_url_required':
        return 'API URL required';
      case 'username_required':
        return 'Username is required';
      case 'password_required':
        return 'Password is required';
      case 'url_format_validate_error':
        return 'Please enter a valid URL (must start with http:// or https://)';
      default:
        return key;
    }
  }

  @override
  void dispose() {
    _playlists.clear();
    super.dispose();
  }
}
