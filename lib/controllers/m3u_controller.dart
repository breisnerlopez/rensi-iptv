import 'package:rensi_iptv/database/database.dart'
    hide M3uEpisodes, M3uSeries;
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/progress_step.dart';
import 'package:rensi_iptv/services/m3u_parser.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:uuid/uuid.dart';
import '../models/category_with_content_type.dart';
import '../models/m3u_series.dart';

class M3uController extends ChangeNotifier {
  final String playlistId;
  final List<M3uItem> m3uItems;
  final AppDatabase appDatabase = getIt<AppDatabase>();
  bool refreshAll = false;
  final uuid = Uuid();

  M3uController({
    required this.playlistId,
    required this.m3uItems,
    this.refreshAll = false,
  });

  // State
  List<M3uItem>? _allChannels;
  Map<CategoryWithContentType, List<M3uItem>>? _groupedChannels;
  List<M3uItem>? _liveChannels;
  List<M3uItem>? _movies;
  List<M3uItem>? _series;
  List<Category>? _categories;

  bool _isLoading = false;
  String? _errorMessage;
  String? _errorKey;
  ProgressStep _currentStep = ProgressStep.userInfo;

  // Getters
  List<M3uItem>? get allChannels => _allChannels;

  Map<CategoryWithContentType, List<M3uItem>>? get groupedChannels =>
      _groupedChannels;

  List<M3uItem>? get liveChannels => _liveChannels;

  List<M3uItem>? get movies => _movies;

  List<M3uItem>? get series => _series;

  List<Category>? get categories => _categories;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  String? get errorKey => _errorKey;

  ProgressStep get currentStep => _currentStep;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error, [String? errorKey]) {
    _errorMessage = error;
    _errorKey = errorKey;
    notifyListeners();
  }

  void _setCurrentStep(ProgressStep step) {
    _currentStep = step;
    notifyListeners();
  }

  Future<bool> loadM3uData() async {
    try {
      _setCurrentStep(ProgressStep.userInfo);
      _setError(null);

      if (m3uItems.isEmpty) {
        throw Exception('preparing_m3u_exception_empty');
      }

      _allChannels = m3uItems;
      // Todo: Save db
      return true;
    } catch (e) {
      if (e.toString().contains('preparing_m3u_exception_no_source')) {
        _setError(e.toString(), 'preparing_m3u_exception_no_source');
      } else if (e.toString().contains('preparing_m3u_exception_empty')) {
        _setError(e.toString(), 'preparing_m3u_exception_empty');
      } else {
        _setError(
          'preparing_m3u_exception_parse',
          'preparing_m3u_exception_parse',
        );
      }
      return false;
    }
  }

  Future<bool> loadCategories() async {
    try {
      _setCurrentStep(ProgressStep.categories);

      if (_allChannels == null) return false;
      _groupedChannels = _groupChannels(_allChannels!);

      _categories = [
        ..._generateCategories(
          contentType: ContentType.liveStream,
          categoryType: CategoryType.live,
          playlistId: playlistId,
        ),
        ..._generateCategories(
          contentType: ContentType.vod,
          categoryType: CategoryType.vod,
          playlistId: playlistId,
        ),
        ..._generateCategories(
          contentType: ContentType.series,
          categoryType: CategoryType.series,
          playlistId: playlistId,
        ),
      ];

      await appDatabase.insertCategories(_categories!);

      notifyListeners();
      return true;
    } catch (e) {
      _setError(
        'preparing_categories_exception',
        'preparing_categories_exception',
      );
      return false;
    }
  }

  List<Category> _generateCategories({
    required ContentType contentType,
    required CategoryType categoryType,
    required String playlistId,
  }) {
    return _groupedChannels!.keys
        .where((x) => x.contentType == contentType)
        .map(
          (x) => Category(
            categoryId: uuid.v4(),
            categoryName: x.categoryName,
            type: categoryType,
            parentId: 0,
            playlistId: playlistId,
          ),
        )
        .toList();
  }

  Future<bool> loadLiveChannels() async {
    try {
      _setCurrentStep(ProgressStep.liveChannels);
      _setError(null);

      if (_allChannels == null) return false;

      _liveChannels = _allChannels!
          .where((item) => item.contentType == ContentType.liveStream)
          .map((x) {
            x.categoryId = findCategoryId(x.groupTitle, CategoryType.live);
            return x;
          })
          .toList();

      await appDatabase.insertM3uItems(_liveChannels!);

      return true;
    } catch (e) {
      _setError(
        'preparing_live_streams_exception_2',
        'preparing_live_streams_exception_2',
      );
      return false;
    }
  }

  Future<bool> loadMovies() async {
    try {
      _setCurrentStep(ProgressStep.movies);
      _setError(null);

      if (_allChannels == null) return false;

      _movies = _allChannels!
          .where((item) => item.contentType == ContentType.vod)
          .map((x) {
            x.categoryId = findCategoryId(x.groupTitle, CategoryType.vod);
            return x;
          })
          .toList();

      await appDatabase.insertM3uItems(_movies!);

      return true;
    } catch (e) {
      _setError('preparing_movies_exception_2', 'preparing_movies_exception_2');
      return false;
    }
  }

  Future<bool> loadSeries() async {
    try {
      _setCurrentStep(ProgressStep.series);
      _setError(null);

      if (_allChannels == null) return false;

      _series = _allChannels!
          .where((item) => item.contentType == ContentType.series)
          .map((x) {
            x.categoryId = findCategoryId(x.groupTitle, CategoryType.series);
            return x;
          })
          .toList();

      await appDatabase.insertM3uItems(_series!);

      var m3uTempSeries = _series!
          .map((x) {
            return SeriesParser.parse(x);
          })
          .where((item) => item != null)
          .cast<M3uTempSeries>()
          .toList();

      if (m3uTempSeries.isNotEmpty) {
        var grouped = groupByName(m3uTempSeries);
        var m3uSeries = convertToSeriesStreams(playlistId, grouped);
        var m3uEpisodes = m3uTempSeries.map((x) {
          return M3uEpisode(
            playlistId: playlistId,
            seriesId: m3uSeries.firstWhere((series) {
              return series.name == x.name;
            }).seriesId,
            seasonNumber: x.seasonNumber,
            episodeNumber: x.episodeNumber,
            name: x.m3uItem.name!,
            url: x.m3uItem.url,
            cover: x.m3uItem.tvgLogo,
          );
        }).toList();

        await appDatabase.insertM3uSeries(
          m3uSeries.map((x) {
            return x.toCompanion();
          }).toList(),
        );

        await appDatabase.insertM3uEpisodes(
          m3uEpisodes.map((x) {
            return x.toCompanion();
          }).toList(),
        );
      }

      return true;
    } catch (e) {
      _setError('preparing_series_exception_2', 'preparing_series_exception_2');
      return false;
    }
  }

  Future<bool> loadAllData() async {
    _setLoading(true);

    bool success = true;

    success &= await loadM3uData();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadCategories();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadLiveChannels();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadMovies();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadSeries();

    _setLoading(false);
    return success;
  }

  Map<CategoryWithContentType, List<M3uItem>> _groupChannels(
    List<M3uItem> channels,
  ) {
    final grouped = <CategoryWithContentType, List<M3uItem>>{};

    for (final channel in channels.where(
      (x) => x.groupTitle != null && x.groupTitle!.isNotEmpty,
    )) {
      final group = channel.groupTitle ?? 'not_categorized';
      final contentType = channel.contentType;

      final categoryWithContentType = CategoryWithContentType(
        categoryName: group,
        contentType: contentType,
      );

      grouped.putIfAbsent(categoryWithContentType, () => []).add(channel);
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final groupComparison = a.categoryName.compareTo(b.categoryName);
        if (groupComparison != 0) return groupComparison;
        return a.contentType.index.compareTo(b.contentType.index);
      });

    final sortedGrouped = <CategoryWithContentType, List<M3uItem>>{};
    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
    }

    return sortedGrouped;
  }

  // Kategori bazlı filtreleme metodları
  List<M3uItem> getChannelsByGroup(String groupTitle) {
    return _groupedChannels?[groupTitle] ?? [];
  }

  List<M3uItem> getChannelsByContentType(ContentType contentType) {
    return _allChannels
            ?.where((item) => item.contentType == contentType)
            .toList() ??
        [];
  }

  void retry() {
    _setError(null);
    _setCurrentStep(ProgressStep.userInfo);
    loadAllData();
  }

  void reset() {
    _allChannels = null;
    _groupedChannels = null;
    _liveChannels = null;
    _movies = null;
    _series = null;
    _categories = null;
    _isLoading = false;
    _errorMessage = null;
    _errorKey = null;
    _currentStep = ProgressStep.userInfo;
    notifyListeners();
  }

  String? findCategoryId(String? groupTitle, CategoryType categoryType) {
    if (groupTitle == null) return null;
    final category = categories?.firstWhereOrNull(
      (x) => x.categoryName == groupTitle && x.type == categoryType,
    );
    return category?.categoryId;
  }

  Map<String, List<M3uTempSeries>> groupByName(List<M3uTempSeries> list) {
    var map = <String, List<M3uTempSeries>>{};
    for (var series in list) {
      if (!map.containsKey(series.name)) {
        map[series.name] = [];
      }
      map[series.name]!.add(series);
    }
    return map;
  }

  List<M3uSerie> convertToSeriesStreams(
    String playlistId,
    Map<String, List<M3uTempSeries>> grouped,
  ) {
    List<M3uSerie> result = [];

    grouped.forEach((name, episodes) {
      final first = episodes.first;

      result.add(
        M3uSerie(
          playlistId: playlistId,
          categoryId: first.m3uItem.categoryId,
          name: name,
          seriesId: uuid.v4(),
        ),
      );
    });

    return result;
  }
}
