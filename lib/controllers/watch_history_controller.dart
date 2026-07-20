import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:rensi_iptv/utils/navigate_by_content_type.dart';
import '../screens/m3u/m3u_player_screen.dart';
import '../services/service_locator.dart';
import '../screens/series/episode_screen.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';

class WatchHistoryController extends ChangeNotifier {
  /// Set once the owner is gone, so a query still in flight cannot notify a
  /// disposed notifier. Leaving the home while the history loads used to trip
  /// Flutter's "used after being disposed" assert, and the easiest way to do it
  /// was the rail's own resume handler.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  late WatchHistoryService _historyService;
  final _database = getIt<AppDatabase>();

  List<WatchHistory> _continueWatching = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Getters
  List<WatchHistory> get continueWatching => _continueWatching;





  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  WatchHistoryController() {
    _historyService = WatchHistoryService();
  }


  Future<void> loadWatchHistory() async {
    debugPrint('WatchHistoryController: loadWatchHistory başladı');
    _setLoading(true);
    _clearError();

    // Deliberately NOT clearing here. Emptying the list and notifying before
    // the query means every reload blanks the rail and repopulates it, and the
    // reload that matters happens when the viewer returns from the player —
    // i.e. while they are looking straight at it. The assignment below is
    // atomic from the UI's point of view.

    if (AppState.currentPlaylist == null) {
      debugPrint('WatchHistoryController: Aktif playlist bulunamadı');
      _setError('Aktif playlist bulunamadı');
      _setLoading(false);
      return;
    }

    final playlistId = AppState.currentPlaylist!.id;
    debugPrint('WatchHistoryController: Playlist ID: $playlistId');

    try {
      // One query, not five. This used to fetch recently-watched plus a full
      // scan per content type as well; nothing consumed those four lists, and
      // the deletion of the history screen removed their last would-be reader.
      // Left in place they would now run on every home start and every resume,
      // on a TV box, for nobody.
      _continueWatching = await _historyService.getContinueWatching(playlistId);

      _setLoading(false);
    } catch (e) {
      _setError('İzleme geçmişi yüklenirken hata oluştu: ${scrubCredentials(e)}');
      _setLoading(false);
    }
  }

  /// Returns false when the resume could not be started.
  ///
  /// The failure has to leave through the return value: a row can outlive the
  /// catalogue entry it points at, and the resulting StateError used to land in
  /// `_errorMessage`, which no widget in `lib/` ever read. The card simply did
  /// nothing on tap, with no way for the viewer to tell a dead entry from an
  /// unresponsive one.
  Future<bool> playContent(BuildContext context, WatchHistory history) async {
    try {
      switch (history.contentType) {
        case ContentType.liveStream:
          await _playLiveStream(context, history);
          break;
        case ContentType.vod:
          await _playMovie(context, history);
          break;
        case ContentType.series:
          await _playSeries(context, history);
          break;
      }
      return true;
    } catch (e) {
      _setError('Video oynatılırken hata oluştu: ${scrubCredentials(e)}');
      return false;
    }
  }

  Future<void> removeHistory(WatchHistory history) async {
    try {
      await _historyService.deleteWatchHistory(
        history.playlistId,
        history.streamId,
      );
      await loadWatchHistory();
    } catch (e) {
      _setError('Hata oluştu: ${scrubCredentials(e)}');
    }
  }

  Future<void> clearAllHistory() async {
    try {
      await _historyService.clearAllHistory();
      await loadWatchHistory();
    } catch (e) {
      // Rethrow after recording: the caller shows a confirmation, and
      // confirming a deletion that did not happen is the worst outcome on the
      // one privacy surface this screen has.
      _setError('Hata oluştu: ${scrubCredentials(e)}');
      rethrow;
    }
  }

  // Private methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _playLiveStream(
    BuildContext context,
    WatchHistory history,
  ) async {
    if (isXtreamCode) {
      final liveStream = await _database.findLiveStreamById(
        history.streamId,
        AppState.currentPlaylist!.id,
      );

      if (!context.mounted) return;
      await navigateByContentType(
        context,
        ContentItem(
          history.streamId,
          history.title,
          history.imagePath ?? '',
          history.contentType,
          liveStream: liveStream,
        ),
      );
    } else if (isM3u) {
      final liveStream = await _database.getM3uItemsByIdAndPlaylist(
        AppState.currentPlaylist!.id,
        history.streamId,
      );
      if (liveStream == null) {
        throw StateError('watch history points at an item no longer in the '
            'playlist: ${history.streamId}');
      }

      if (!context.mounted) return;
      await navigateByContentType(
        context,
        ContentItem(
          liveStream.url,
          history.title,
          history.imagePath ?? '',
          history.contentType,
          m3uItem: liveStream,
        ),
      );
    }
  }

  Future<void> _playMovie(BuildContext context, WatchHistory history) async {
    if (isXtreamCode) {
      final movie = await _database.findMovieById(
        history.streamId,
        AppState.currentPlaylist!.id,
      );
      // A row can outlive the catalogue entry it points at — a refresh drops
      // titles. Force-unwrapping it threw into playContent's catch, which set
      // an error string nobody reads, so the card simply did nothing on tap.
      if (movie == null) {
        throw StateError('watch history points at a title no longer in the '
            'catalogue: ${history.streamId}');
      }

      if (!context.mounted) return;
      await playByContentType(
        context,
        ContentItem(
          history.streamId,
          history.title,
          history.imagePath ?? '',
          history.contentType,
          containerExtension: movie.containerExtension,
          vodStream: movie,
        ),
      );
    } else if (isM3u) {
      var movie = await _database.getM3uItemsByIdAndPlaylist(
        AppState.currentPlaylist!.id,
        history.streamId,
      );
      if (movie == null) {
        throw StateError('watch history points at an item no longer in the '
            'playlist: ${history.streamId}');
      }

      if (!context.mounted) return;
      await playByContentType(
        context,
        ContentItem(
          movie.url,
          history.title,
          history.imagePath ?? '',
          history.contentType,
          m3uItem: movie,
        ),
      );
    }
  }

  Future<void> _playSeries(BuildContext context, WatchHistory history) async {
    if (isXtreamCode) {
      final episode = await _database.findEpisodesById(
        history.streamId,
        AppState.currentPlaylist!.id,
      );

      if (episode == null) {
        throw StateError('watch history points at an episode no longer in the '
            'catalogue: ${history.streamId}');
      }
      final seriesResponse = await AppState.xtreamCodeRepository!.getSeriesInfo(
        episode.seriesId,
      );
      if (seriesResponse == null) {
        throw StateError('the panel returned no series info for '
            '${episode.seriesId}');
      }
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EpisodeScreen(
            seriesInfo: seriesResponse.seriesInfo,
            seasons: seriesResponse.seasons,
            episodes: seriesResponse.episodes,
            contentItem: ContentItem(
              episode.episodeId.toString(),
              history.title,
              history.imagePath ?? "",
              ContentType.series,
              containerExtension: episode.containerExtension,
              season: episode.season,
            ),
            watchHistory: history,
          ),
        ),
      );
    } else if (isM3u) {
      var m3uItem = await _database.getM3uItemsByIdAndPlaylist(
        AppState.currentPlaylist!.id,
        history.streamId,
      );
      if (m3uItem == null) {
        throw StateError('watch history points at an item no longer in the '
            'playlist: ${history.streamId}');
      }
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => M3uPlayerScreen(
            contentItem: ContentItem(
              m3uItem.id,
              m3uItem.name ?? '',
              m3uItem.tvgLogo ?? '',
              m3uItem.contentType,
              m3uItem: m3uItem,
            ),
          ),
        ),
      );
    }
  }
}
