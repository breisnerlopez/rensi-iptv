import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import '../services/content_service.dart';

class CategoryDetailController extends ChangeNotifier {
  final CategoryViewModel category;
  final ContentService _contentService = ContentService();

  CategoryDetailController(this.category) {
    loadContent();
  }

  // --- State ---
  List<ContentItem> _contentItems = [];
  List<ContentItem> _filteredItems = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;

  // --- Genre filtering ---
  List<String> _genres = [];
  String? _selectedGenre;

  // --- Getters ---
  List<ContentItem> get contentItems => _contentItems;
  List<ContentItem> get filteredItems => _filteredItems;
  List<ContentItem> get displayItems =>
      _isSearching ? _filteredItems : _applyGenreFilter(_contentItems);
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => displayItems.isEmpty && !_isLoading;

  List<String> get genres => _genres;
  String? get selectedGenre => _selectedGenre;

  Future<void> loadContent() async {
    try {
      _setLoading(true);
      _contentItems = await _contentService.fetchContentByCategory(category);
      _genres = _extractGenres(_contentItems);
      _selectedGenre = null;
      _setLoading(false);
      // For the synthetic "All movies" / "All series" pseudo-category, land
      // the user on a recency-first view by default — that's the whole
      // point of the screen.
      if (isAllCategorySentinel(category.category.categoryId)) {
        sortItems('date_added');
      }
    } catch (error) {
      _setError(error.toString());
    }
  }

  List<String> _extractGenres(List<ContentItem> items) {
    final Set<String> genreSet = {};

    for (final item in items) {
      final rawGenre = _getItemGenre(item);
      if (rawGenre != null && rawGenre.isNotEmpty) {
        // Split on common separators (comma, slash, backslash, pipe, ampersand, semicolon, Arabic comma) (with surrounding spaces)
        final parts = rawGenre
            .split(RegExp(r'\s*[,/\\|&;،]+\s*'))
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toSet();
        genreSet.addAll(parts);
      }
    }

    final sorted = genreSet.toList()..sort();
    return sorted;
  }

  String? _getItemGenre(ContentItem item) {
    if (item.contentType.name == "series") {
      return item.seriesStream?.genre;
    } else {
      return item.vodStream?.genre;
    }
  }

  void filterByGenre(String? genre) {
    _selectedGenre = genre;
    notifyListeners();
  }

  List<ContentItem> _applyGenreFilter(List<ContentItem> items) {
    if (_selectedGenre == null || _selectedGenre!.isEmpty) return items;

    // We compare lowercased versions to be safe
    final genreLower = _selectedGenre!.toLowerCase();
    return items.where((item) {
      final rawGenre = _getItemGenre(item);
      if (rawGenre == null) return false;

      // Use the same splitter logic to check if the item contains the selected genre
      final itemGenres = rawGenre
          .split(RegExp(r'\s*[,/\\|&;،]+\s*'))
          .map((g) => g.trim().toLowerCase());

      return itemGenres.contains(genreLower);
    }).toList();
  }

  void startSearch() {
    _isSearching = true;
    _filteredItems = [];
    notifyListeners();
  }

  void stopSearch() {
    _isSearching = false;
    _filteredItems = [];
    notifyListeners();
  }

  void searchContent(String query) {
    if (query.trim().isEmpty) {
      _filteredItems = [];
    } else {
      _filteredItems = _contentItems
          .where((item) =>
          (item.name ?? '').toLowerCase().contains(query.trim().toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  void sortItems(String order) {
    // Sort the master list (and the search-result list when searching) so
    // the new order persists across re-renders. Sorting `displayItems`
    // directly was a no-op when a genre filter was active because
    // `_applyGenreFilter` returns a fresh `.where().toList()` copy whose
    // sort never made it back to `_contentItems`.
    final lists = <List<ContentItem>>[
      _contentItems,
      if (_isSearching) _filteredItems,
    ];

    int Function(ContentItem a, ContentItem b)? cmp;
    switch (order) {
      case "ascending":
        cmp = (a, b) => (a.name ?? '').compareTo(b.name ?? '');
        break;
      case "descending":
        cmp = (a, b) => (b.name ?? '').compareTo(a.name ?? '');
        break;
      case "release_date":
        cmp = (a, b) {
          final DateTime dateA;
          final DateTime dateB;
          if (a.contentType.name == "series") {
            dateA = DateTime.tryParse(a.seriesStream?.releaseDate ?? '') ??
                DateTime(1970);
            dateB = DateTime.tryParse(b.seriesStream?.releaseDate ?? '') ??
                DateTime(1970);
          } else {
            dateA = a.vodStream?.createdAt ?? DateTime(1970);
            dateB = b.vodStream?.createdAt ?? DateTime(1970);
          }
          return dateB.compareTo(dateA);
        };
        break;
      case "rating":
        cmp = (a, b) {
          final double ratingA;
          final double ratingB;
          if (a.contentType.name == "series") {
            ratingA = double.tryParse(a.seriesStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.seriesStream?.rating ?? '0') ?? 0.0;
          } else {
            ratingA = double.tryParse(a.vodStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.vodStream?.rating ?? '0') ?? 0.0;
          }
          return ratingB.compareTo(ratingA);
        };
        break;
      case "date_added":
        // "Recently added" — newest first. For VOD we use the Xtream
        // server's createdAt (DateTime). For Series, lastModified is the
        // best proxy: Xtream sends it as a "YYYY-MM-DD HH:mm:ss" string
        // (sometimes a Unix epoch in seconds). Items without a usable
        // timestamp fall back to the epoch and end up at the bottom.
        cmp = (a, b) {
          final tsA = dateAddedFor(a);
          final tsB = dateAddedFor(b);
          return tsB.compareTo(tsA);
        };
        break;
    }

    if (cmp != null) {
      for (final l in lists) {
        l.sort(cmp);
      }
    }
    notifyListeners();
  }

  /// "Date added" extraction for the `date_added` sort and the "View all"
  /// pseudo-category preview.
  ///
  /// Strategy is deliberately *unmixed* — only the canonical "when this
  /// item entered the catalogue" field is consulted:
  ///   - VOD:    vodStream.createdAt    (Xtream `created_at`)
  ///   - Series: seriesStream.lastModified (Xtream `last_modified`)
  ///
  /// Items where the canonical field is null/empty fall to the epoch
  /// (`DateTime(1970)`) and sit at the bottom of a descending sort. Using
  /// releaseDate / other proxies as a fallback was tried briefly but it
  /// muddied the ordering: a freshly added 1995 movie ended up next to a
  /// 1995 release that had been in the catalogue for years.
  static DateTime dateAddedFor(ContentItem item) {
    if (item.contentType.name == "series") {
      return _parseFlexibleDate(item.seriesStream?.lastModified);
    }
    // VOD (and anything else that ships a vodStream).
    final dt = item.vodStream?.createdAt;
    return dt ?? DateTime(1970);
  }

  @visibleForTesting
  static DateTime parseFlexibleDate(String? raw) => _parseFlexibleDate(raw);

  /// Parses Xtream-style date strings: a Unix epoch in seconds, a bare
  /// 4-digit year ("2019"), ISO 8601, or "YYYY-MM-DD HH:mm:ss". Returns
  /// `DateTime(1970)` on anything we cannot interpret.
  ///
  /// Note on ordering: we check for an all-digit string first, because
  /// `DateTime.tryParse` happily reads a 10-digit number as the *year*
  /// (so "1700000000" would become year-1700000000 instead of
  /// 2023-11-14). Inside the digits branch, a 4-digit string in the
  /// 1000-9999 range is treated as a calendar year (releaseDate often
  /// arrives this way); longer strings are Unix epoch seconds.
  static DateTime _parseFlexibleDate(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime(1970);
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      final n = int.tryParse(raw);
      if (n == null) return DateTime(1970);
      if (raw.length == 4 && n >= 1000 && n <= 9999) {
        return DateTime(n);
      }
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    return DateTime(1970);
  }

  // --- State helpers ---
  void _setLoading(bool loading) {
    _isLoading = loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String error) {
    _isLoading = false;
    _errorMessage = error;
    notifyListeners();
  }
}
