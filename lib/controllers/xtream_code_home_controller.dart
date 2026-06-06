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

class XtreamCodeHomeController extends ChangeNotifier {
  late PageController _pageController;
  final IptvRepository _repository = AppState.xtreamCodeRepository!;
  String? _errorMessage;
  String? _errorKey;
  ViewState _viewState = ViewState.idle;

  int _currentIndex = 0;

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
    _currentIndex = initialIndex.clamp(0, 5);
    if (autoLoad) {
      _loadCategories(all);
      reloadHiddenCategoriesFromPrefs();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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
        return context.loc.history;
      case 1:
        return context.loc.live_streams;
      case 2:
        return context.loc.movies;
      case 3:
        return context.loc.series_plural;
      case 4:
        return context.loc.tmdb_global_search;
      case 5:
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
              _liveCategories.add(categoryViewModel);
            }
          } else {
            _liveCategories.add(categoryViewModel);
          }
        }
      }

      // "View all movies" pseudo-category — sits above the real list and
      // aggregates every movie of the playlist when the user opens it.
      await _prependAllCategory(
        list: _movieCategories,
        type: CategoryType.vod,
        previewLoader: () => _repository.getMovies(top: 10),
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
              _movieCategories.add(categoryViewModel);
            }
          } else {
            _movieCategories.add(categoryViewModel);
          }
        }
      }

      // "View all series" pseudo-category.
      await _prependAllCategory(
        list: _seriesCategories,
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
              _seriesCategories.add(categoryViewModel);
            }
          } else {
            _seriesCategories.add(categoryViewModel);
          }
        }
      }

      notifyListeners();
    } catch (e, st) {
      debugPrint(st.toString());
      _errorMessage = e.toString();
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
