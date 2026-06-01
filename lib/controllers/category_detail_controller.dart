import 'package:flutter/material.dart';
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
    final list = displayItems;

    switch (order) {
      case "ascending":
        list.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
        break;
      case "descending":
        list.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));
        break;
      case "release_date":
        list.sort((a, b) {
          final dateA;
          final dateB;
          if (a.contentType.name == "series") {
            dateA = DateTime.tryParse(a.seriesStream?.releaseDate ?? '') ?? DateTime(1970);
            dateB = DateTime.tryParse(b.seriesStream?.releaseDate ?? '') ?? DateTime(1970);
          } else {
            dateA = a.vodStream?.createdAt?.millisecondsSinceEpoch.toDouble() ?? 0.0;
            dateB = b.vodStream?.createdAt?.millisecondsSinceEpoch.toDouble() ?? 0.0;
          }
          return dateB.compareTo(dateA);
        });
        break;
      case "rating":
        list.sort((a, b) {
          final ratingA;
          final ratingB;
          if (a.contentType.name == "series") {
            ratingA = double.tryParse(a.seriesStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.seriesStream?.rating ?? '0') ?? 0.0;
          } else {
            ratingA = double.tryParse(a.vodStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.vodStream?.rating ?? '0') ?? 0.0;
          }
          return ratingB.compareTo(ratingA);
        });
        break;
      case "date_added":
        // "Recently added" — newest first. For VOD we use the Xtream
        // server's createdAt (DateTime). For Series, lastModified is the
        // best proxy: Xtream sends it as a "YYYY-MM-DD HH:mm:ss" string
        // (sometimes a Unix epoch in seconds). Items without a usable
        // timestamp fall back to the epoch and end up at the bottom.
        list.sort((a, b) {
          final tsA = _dateAddedFor(a);
          final tsB = _dateAddedFor(b);
          return tsB.compareTo(tsA);
        });
        break;
    }

    notifyListeners();
  }

  /// Best-effort "date added" extraction shared by the `date_added` sort.
  ///
  /// Returns the epoch (`DateTime(1970)`) when no usable timestamp exists,
  /// so items without metadata sink to the bottom of a descending sort.
  @visibleForTesting
  static DateTime dateAddedFor(ContentItem item) => _dateAddedFor(item);

  static DateTime _dateAddedFor(ContentItem item) {
    if (item.contentType.name == "series") {
      final raw = item.seriesStream?.lastModified;
      return _parseFlexibleDate(raw);
    }
    // VOD (and anything else that ships a vodStream).
    final dt = item.vodStream?.createdAt;
    return dt ?? DateTime(1970);
  }

  @visibleForTesting
  static DateTime parseFlexibleDate(String? raw) => _parseFlexibleDate(raw);

  /// Parses Xtream-style date strings: a Unix epoch in seconds, ISO 8601,
  /// or "YYYY-MM-DD HH:mm:ss". Returns `DateTime(1970)` on anything we
  /// cannot interpret.
  ///
  /// Note on ordering: we check for an all-digit string first, because
  /// `DateTime.tryParse` happily reads a 10-digit number as the *year*
  /// (so "1700000000" would become year-1700000000 instead of
  /// 2023-11-14). Treat pure-digit strings as Unix seconds before
  /// falling back to DateTime parsing.
  static DateTime _parseFlexibleDate(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime(1970);
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      final unixSeconds = int.tryParse(raw);
      if (unixSeconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
      }
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
