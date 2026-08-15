import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/m3u/m3u_home_screen.dart';
import 'package:rensi_iptv/screens/playlist_screen.dart';
import 'package:rensi_iptv/screens/tmdb_onboarding_screen.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/active_playlist_controller.dart';
import '../../repositories/user_preferences.dart';
import '../../services/app_state.dart';
import '../../services/playlist_service.dart';
import 'xtream-codes/xtream_code_home_screen.dart';

class AppInitializerScreen extends StatefulWidget {
  const AppInitializerScreen({super.key});

  @override
  State<AppInitializerScreen> createState() => _AppInitializerScreenState();
}

class _AppInitializerScreenState extends State<AppInitializerScreen> {
  bool _isLoading = true;
  Playlist? _lastPlaylist;
  // Show the one-time TMDb-key nudge on a COLD START when the user has a playlist
  // but no key of their own and hasn't seen it. (It does NOT appear in the same
  // session a playlist is first created — those flows pushReplacement straight to
  // the home and bypass this screen — it appears on the next launch.)
  bool _needsTmdbNudge = false;

  @override
  void initState() {
    super.initState();
    _loadLastPlaylist();
  }

  Future<void> _loadLastPlaylist() async {
    final lastPlaylistId = await UserPreferences.getLastPlaylist();

    if (lastPlaylistId != null) {
      final playlist = await PlaylistService.getPlaylistById(lastPlaylistId);
      if (playlist != null) {
        if (mounted) {
          context.read<ActivePlaylistController>().setInitialPlaylist(playlist);
        } else {
          AppState.currentPlaylist = playlist;
        }
        _lastPlaylist = playlist;
      }
    }

    // Offer the TMDb key once on cold start: only when the user already has a
    // playlist, hasn't saved their own key, and hasn't seen the nudge.
    if (_lastPlaylist != null) {
      final seen = await UserPreferences.getTmdbOnboardingSeen();
      final hasOwn = await TmdbCredentialsService.hasStoredCredential();
      _needsTmdbNudge = !seen && !hasOwn;
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_lastPlaylist == null) {
      return const PlaylistScreen();
    }

    // One-time TMDb key nudge, gated before the home so a fresh install shows
    // artwork guidance once. onDone clears it and falls through to the home.
    if (_needsTmdbNudge) {
      return TmdbOnboardingScreen(
        onDone: () => setState(() => _needsTmdbNudge = false),
      );
    }

    {
      switch (_lastPlaylist!.type) {
        case PlaylistType.xtream:
          return XtreamCodeHomeScreen(playlist: _lastPlaylist!);
        case PlaylistType.m3u:
          return M3UHomeScreen(playlist: _lastPlaylist!);
      }
    }
  }
}
