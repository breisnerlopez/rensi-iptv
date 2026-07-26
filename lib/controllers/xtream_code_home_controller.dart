import 'package:rensi_iptv/controllers/category_detail_controller.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/view_state.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/services/app_state.dart';
import '../repositories/user_preferences.dart';
import '../screens/xtream-codes/xtream_code_data_loader_screen.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';

class XtreamCodeHomeController extends ChangeNotifier {
  late PageController _pageController;
  final IptvRepository _repository = AppState.xtreamCodeRepository!;
  String? _errorMessage;
  String? _errorKey;
  ViewState _viewState = ViewState.idle;

  int _currentIndex = 0;

  // Background-refresh state. `_all` is captured so a refresh rebuilds the rails
  // the same way the initial load did. A background refresh is a multi-second
  // op that outlives the widget in some cases, so guard notifications on
  // `_disposed` (same pattern as WatchHistoryController).
  bool _all = false;
  bool _disposed = false;
  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  final List<CategoryViewModel> _liveCategories = [];
  final List<CategoryViewModel> _movieCategories = [];
  final List<CategoryViewModel> _seriesCategories = [];

  final Set<String> _hiddenMovieCategoryIds = {};
  final Set<String> _hiddenSeriesCategoryIds = {};
  final Set<String> _hiddenLiveCategoryIds = {};

  Set<String> get hiddenMovieCategoryIds => _hiddenMovieCategoryIds;
  Set<String> get hiddenSeriesCategoryIds => _hiddenSeriesCategoryIds;
  Set<String> get hiddenLiveCategoryIds => _hiddenLiveCategoryIds;

  void toggleMovieCategoryVisibility(String categoryId) {
    if (_hiddenMovieCategoryIds.contains(categoryId)) {
      _hiddenMovieCategoryIds.remove(categoryId);
    } else {
      _hiddenMovieCategoryIds.add(categoryId);
    }
    notifyListeners();
  }

  void toggleSeriesCategoryVisibility(String categoryId) {
    if (_hiddenSeriesCategoryIds.contains(categoryId)) {
      _hiddenSeriesCategoryIds.remove(categoryId);
    } else {
      _hiddenSeriesCategoryIds.add(categoryId);
    }
    notifyListeners();
  }

  Future<void> reloadHiddenCategoriesFromPrefs() async {
    final ids = (await UserPreferences.getHiddenCategories()).toSet();
    _hiddenLiveCategoryIds
      ..clear()
      ..addAll(ids);
    _hiddenMovieCategoryIds
      ..clear()
      ..addAll(ids);
    _hiddenSeriesCategoryIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  Future<void> refreshCategoryVisibility() async {
    await reloadHiddenCategoriesFromPrefs();
  }

  List<CategoryViewModel> get visibleMovieCategories => _movieCategories
      .where((c) => !_hiddenMovieCategoryIds.contains(c.category.categoryId))
      .toList();

  List<CategoryViewModel> get visibleSeriesCategories => _seriesCategories
      .where((c) => !_hiddenSeriesCategoryIds.contains(c.category.categoryId))
      .toList();

  PageController get pageController => _pageController;

  int get currentIndex => _currentIndex;

  String? get errorMessage => _errorMessage;

  String? get errorKey => _errorKey;

  ViewState get viewState => _viewState;

  bool get isLoading => _viewState == ViewState.loading;

  List<CategoryViewModel>? get liveCategories => _liveCategories;

  List<CategoryViewModel> get movieCategories => _movieCategories;

  List<CategoryViewModel> get seriesCategories => _seriesCategories;

  XtreamCodeHomeController(
    bool all, {
    int initialIndex = 0,
    bool autoLoad = true,
  }) {
    _pageController = PageController();
    _all = all;
    _currentIndex = initialIndex.clamp(0, 4);
    if (autoLoad) {
      _loadCategories(all);
      reloadHiddenCategoriesFromPrefs();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pageController.dispose();
    super.dispose();
  }

  // Swallow notifications after dispose: a background refresh's `_loadCategories`
  // can complete after the home screen is gone.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Refresh the catalogue quietly after a resume past the staleness threshold.
  /// Best-effort: on any fetch failure it keeps the existing data and does NOT
  /// advance lastSync, so the next resume retries. Reentrancy-guarded, and it
  /// bails if the active playlist changed underneath it.
  Future<void> refreshInBackground() async {
    if (_isRefreshing || _disposed) return;
    _isRefreshing = true;
    notifyListeners(); // set synchronously before the first await
    final pid = AppState.currentPlaylist?.id;
    try {
      if (pid == null) return;
      // The repo swallows its own errors and returns null, so a transient
      // panel 400 surfaces as null, not an exception — check each explicitly so
      // a partial refresh is never recorded as fresh. Spacing dodges the
      // burst-throttle.
      if (await _repository.getLiveChannelsFromApi() == null) return;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (await _repository.getMoviesFromApi() == null) return;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (await _repository.getSeriesFromApi() == null) return;
      if (_disposed || AppState.currentPlaylist?.id != pid) return;
      // All three landed: rebuild the rails from fresh data and stamp success.
      await _loadCategories(_all);
      await UserPreferences.setLastSync(pid, DateTime.now());
    } catch (_) {
      // Silent: keep the old, perfectly usable data.
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Test hook: re-run the same catalogue build that `refreshInBackground`
  /// invokes, without the network fetches. Lets a unit test prove the rails are
  /// rebuilt (not appended) on a second load. Not for production use.
  @visibleForTesting
  Future<void> debugReloadCategories() => _loadCategories(_all);

  void onNavigationTap(int index) {
    _currentIndex = index;
    notifyListeners();

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void onPageChanged(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  String getPageTitle(BuildContext context) {
    switch (currentIndex) {
      case 0:
        return 'Inicio';
      case 1:
        return 'Explorar';
      case 2:
        return context.loc.live_streams;
      case 3:
        return 'Mi lista';
      case 4:
        return context.loc.settings;
      default:
        return 'Rensi IPTV';
    }
  }

  void _setViewState(ViewState state) {
    _viewState = state;
    if (state != ViewState.error) {
      _errorMessage = null;
      _errorKey = null;
    }
    notifyListeners();
  }

  Future<void> _loadCategories(bool all) async {
    try {
      // Build into local lists and only swap them into the published fields at
      // the very end. This keeps `_loadCategories` idempotent — it can be
      // re-run by `refreshInBackground` without appending a second copy of
      // every rail — and, because the swap happens after all awaits succeed, a
      // mid-way failure leaves the previously loaded catalogue untouched
      // instead of stranding half-built rails.
      final tmpLive = <CategoryViewModel>[];
      final tmpMovie = <CategoryViewModel>[];
      final tmpSeries = <CategoryViewModel>[];

      var liveCategories = await _repository.getLiveCategories();
      if (liveCategories != null && liveCategories.isNotEmpty) {
        for (var liveCategory in liveCategories) {
          var liveStreams = await _repository.getLiveChannelsByCategoryId(
            categoryId: liveCategory.categoryId,
            top: 10,
          );

          if (liveStreams == null || liveStreams.isEmpty) continue;

          var categoryViewModel = CategoryViewModel(
            category: liveCategory,
            contentItems: liveStreams
                .map(
                  (x) => ContentItem(
                    x.streamId,
                    x.name,
                    x.streamIcon,
                    ContentType.liveStream,
                    liveStream: x,
                  ),
                )
                .toList(),
          );
          if (!all) {
            if (!await UserPreferences.getHiddenCategory(
              liveCategory.categoryId,
            )) {
              tmpLive.add(categoryViewModel);
            }
          } else {
            tmpLive.add(categoryViewModel);
          }
        }
      }

      // "View all movies" pseudo-category — sits above the real list and
      // aggregates every movie of the playlist when the user opens it.
      await _prependAllCategory(
        list: tmpMovie,
        type: CategoryType.vod,
        // Fetch a small SQL-limited, newest-first slice (a buffer above 10 to
        // survive the empty-name filter) instead of the whole VOD table.
        previewLoader: () => _repository.getRecentMovies(limit: 24),
        toItem: (m) => ContentItem(
          m.streamId,
          m.name,
          m.streamIcon,
          ContentType.vod,
          containerExtension: m.containerExtension,
          vodStream: m,
        ),
      );

      var movieCategories = await _repository.getVodCategories();
      if (movieCategories != null && movieCategories.isNotEmpty) {
        for (var movieCategory in movieCategories) {
          var movies = await _repository.getMovies(
            categoryId: movieCategory.categoryId,
            top: 10,
          );

          if (movies == null || movies.isEmpty) {
            continue;
          }

          var categoryViewModel = CategoryViewModel(
            category: movieCategory,
            contentItems: movies
                .map(
                  (x) => ContentItem(
                    x.streamId,
                    x.name,
                    x.streamIcon,
                    ContentType.vod,
                    containerExtension: x.containerExtension,
                    vodStream: x,
                  ),
                )
                .toList(),
          );
          if (!all) {
            if (!await UserPreferences.getHiddenCategory(
              movieCategory.categoryId,
            )) {
              tmpMovie.add(categoryViewModel);
            }
          } else {
            tmpMovie.add(categoryViewModel);
          }
        }
      }

      // "View all series" pseudo-category.
      await _prependAllCategory(
        list: tmpSeries,
        type: CategoryType.series,
        previewLoader: () => _repository.getSeries(top: 10),
        toItem: (s) => ContentItem(
          s.seriesId,
          s.name,
          s.cover ?? '',
          ContentType.series,
          seriesStream: s,
        ),
      );

      var seriesCategories = await _repository.getSeriesCategories();
      if (seriesCategories != null && seriesCategories.isNotEmpty) {
        for (var seriesCategory in seriesCategories) {
          var series = await _repository.getSeries(
            categoryId: seriesCategory.categoryId,
            top: 10,
          );

          if (series == null || series.isEmpty) {
            continue;
          }

          var categoryViewModel = CategoryViewModel(
            category: seriesCategory,
            contentItems: series
                .map(
                  (x) => ContentItem(
                    x.seriesId,
                    x.name,
                    x.cover ?? '',
                    ContentType.series,
                    seriesStream: x,
                  ),
                )
                .toList(),
          );
          if (!all) {
            if (!await UserPreferences.getHiddenCategory(
              seriesCategory.categoryId,
            )) {
              tmpSeries.add(categoryViewModel);
            }
          } else {
            tmpSeries.add(categoryViewModel);
          }
        }
      }

      // Atomic publish: replace the rails in one shot (same list instances the
      // getters expose) only after every fetch above succeeded.
      _liveCategories
        ..clear()
        ..addAll(tmpLive);
      _movieCategories
        ..clear()
        ..addAll(tmpMovie);
      _seriesCategories
        ..clear()
        ..addAll(tmpSeries);

      notifyListeners();
    } catch (e, st) {
      debugPrint(scrubCredentials(st));
      _errorMessage = scrubCredentials(e);
      _errorKey = 'preparing_categories_exception';
      _setViewState(ViewState.error);
    }
  }

  /// Predicate used to weed out garbage rows that some Xtream providers
  /// ship with empty or whitespace-only titles. Exposed at module scope
  /// so [ContentService] can apply the same filter on the detail view
  /// for the "View all" pseudo-category.
  static bool _hasUsableName(ContentItem item) => item.name.trim().isNotEmpty;

  refreshAllData(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => XtreamCodeDataLoaderScreen(
          playlist: AppState.currentPlaylist!,
          refreshAll: true,
        ),
      ),
    );
  }

  /// Builds a synthetic "View all" CategoryViewModel and inserts it at the
  /// top of [list]. The preview row shows the most recent items returned by
  /// [previewLoader]; the destination, when the user taps See all, is the
  /// existing CategoryDetailScreen — ContentService recognises the sentinel
  /// id and fetches every item of that type instead of querying a category.
  ///
  /// No-op when [previewLoader] returns null/empty so we don't render an
  /// empty "View all" row for playlists that lack the content type.
  Future<void> _prependAllCategory<T>({
    required List<CategoryViewModel> list,
    required CategoryType type,
    required Future<List<T>?> Function() previewLoader,
    required ContentItem Function(T) toItem,
  }) async {
    final preview = await previewLoader();
    if (preview == null || preview.isEmpty) return;

    // Build the full mapped list, drop junk entries, sort newest-first by
    // date-added, and keep only the first 10 for the preview strip.
    //
    // The repository ignores `top:` when called without a categoryId
    // (the SQL path returns every row for the playlist), so a catalogue
    // with thousands of items would flood the horizontal strip.
    //
    // Some providers also pollute the table with rows whose name is empty
    // (or whitespace) and no streamIcon — they'd render as blank cards.
    // Filter those out before slicing so the preview row always shows
    // real content.
    final mapped = preview.map(toItem).where(_hasUsableName).toList();
    mapped.sort((a, b) {
      final tsA = CategoryDetailController.dateAddedFor(a);
      final tsB = CategoryDetailController.dateAddedFor(b);
      return tsB.compareTo(tsA);
    });
    final previewItems = mapped.take(10).toList();
    // The SQL-limited preview buffer can be all junk-named rows; don't insert an
    // empty "View all" strip (the destination still aggregates the full type).
    if (previewItems.isEmpty) return;

    final playlistId = AppState.currentPlaylist?.id ?? '';
    final sentinel = Category(
      categoryId: kAllCategoryId,
      // The categoryName here is a placeholder — the UI replaces it with
      // the localised string when it detects the sentinel id.
      categoryName: '__ALL__',
      parentId: 0,
      playlistId: playlistId,
      type: type,
    );
    list.insert(
      0,
      CategoryViewModel(
        category: sentinel,
        contentItems: previewItems,
      ),
    );
  }
}
