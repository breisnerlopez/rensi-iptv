import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:rensi_iptv/utils/navigate_by_content_type.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _searchController = TextEditingController();
  final _credentialController = TextEditingController();
  final _service = GlobalSearchService();

  bool _isLoading = false;
  bool _hasCredential = false;
  String? _error;
  UnifiedSearchResults? _results;
  List<String> _searchHistory = [];
  SearchFilter _filter = SearchFilter.all;
  String _lastQuery = '';

  /// Monotonic counter used to discard out-of-order search results.
  int _searchSeq = 0;

  static const _historyKey = 'tmdb.search.history';
  static const int _maxHistory = 5;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _credentialController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final credential = await TmdbCredentialsService.getCredential();
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    if (!mounted) return;
    setState(() {
      _hasCredential = credential != null;
      _searchHistory = history;
    });
  }

  Future<void> _saveCredential() async {
    await TmdbCredentialsService.saveCredential(_credentialController.text);
    _credentialController.clear();
    await _loadState();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.loc.tmdb_credential_saved)));
  }

  Future<void> _runSearch(String query) async {
    _lastQuery = query;
    if (_filter == SearchFilter.wishlist) {
      // Wishlist view doesn't need 3+ chars.
    } else if (query.length < 3) {
      // Reset visible results when the user shortens the query below 3 chars
      // outside of the wishlist view.
      setState(() {
        _results = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }
    final seq = ++_searchSeq;
    setState(() {
      _isLoading = true;
      _error = null;
      _results = null;
    });
    try {
      final locale = Localizations.localeOf(context);
      final results = await _service.search(
        query,
        filter: _filter,
        locale: locale,
      );
      if (!mounted || seq != _searchSeq) return;
      if (query.isNotEmpty && _filter != SearchFilter.wishlist) {
        await _saveSearchToHistory(query);
      }
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _onSearchSubmit() async {
    final query = _searchController.text.trim();
    await _runSearch(query);
  }

  void _onFilterSelected(SearchFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    // For wishlist, immediately re-run with empty query so the saved
    // titles show up. For other filters, only re-run if there is a query.
    if (filter == SearchFilter.wishlist) {
      _runSearch('');
    } else if (_lastQuery.isNotEmpty && _lastQuery.length >= 3) {
      _runSearch(_lastQuery);
    } else {
      setState(() => _results = null);
    }
  }

  Future<void> _toggleWishlist(TmdbSearchResult item) async {
    final added = await TmdbWishlistService.toggle(item);
    if (!mounted) return;
    // Update the rendered cards immediately instead of refetching everything.
    final results = _results;
    if (results != null) {
      final keys = await TmdbWishlistService.getKeys();
      if (!mounted) return;
      setState(() => _results = results.withWishlistKeys(keys));
    }
    final messenger = ScaffoldMessenger.of(context);
    final loc = context.loc;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added ? loc.added_to_favorites : loc.removed_from_favorites,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    // If we're in wishlist mode and we just removed something, refresh.
    if (!added && _filter == SearchFilter.wishlist) {
      _runSearch(_lastQuery);
    }
  }

  void _openMatch(LocalContentMatch match) {
    // Synchronous mutation + navigation in the same tick so concurrent taps
    // can't interleave repository assignments.
    _service.openLocalMatch(match);
    navigateByContentType(context, match.content);
  }

  Future<void> _saveSearchToHistory(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    history.remove(query);
    history.insert(0, query);
    if (history.length > _maxHistory) history.removeLast();
    await prefs.setStringList(_historyKey, history);
    if (!mounted) return;
    setState(() => _searchHistory = history);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.loc.search_clear_history_confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.loc.clear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (!mounted) return;
    setState(() => _searchHistory = []);
  }

  void _searchFromHistory(String query) {
    _searchController.text = query;
    _runSearch(query);
  }

  Future<void> _showDetail(TmdbSearchResult item) async {
    final locale = Localizations.localeOf(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return _TmdbDetailSheet(
              item: item,
              service: _service,
              locale: locale,
              scrollController: scrollController,
              currentResults: _results,
              onOpenMatch: _openMatch,
              onToggleWishlist: _toggleWishlist,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.tmdb_global_search)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildCredentialCard(),
          if (_hasCredential) ...[
            const SizedBox(height: 12),
            _buildSearchBox(),
            const SizedBox(height: 12),
            _buildFilters(),
            if (_searchHistory.isNotEmpty &&
                _filter != SearchFilter.wishlist) ...[
              const SizedBox(height: 8),
              _buildSearchHistory(),
            ],
          ],
          if (_isLoading) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[const SizedBox(height: 16), _buildError()],
          if (results != null && results.isEmpty) _buildEmpty(),
          if (results != null && !results.isEmpty) ...[
            const SizedBox(height: 16),
            _buildSections(results),
          ],
        ],
      ),
    );
  }

  Widget _buildCredentialCard() {
    if (_hasCredential) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key),
                const SizedBox(width: 8),
                Expanded(child: Text(context.loc.tmdb_credential_missing)),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.loc.tmdb_search_description),
            const SizedBox(height: 8),
            TextField(
              controller: _credentialController,
              autofocus: true,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveCredential(),
              decoration: InputDecoration(
                labelText: context.loc.tmdb_credential_field_label,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saveCredential,
                child: Text(context.loc.tmdb_credential_save),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _onSearchSubmit(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: context.loc.tmdb_search_hint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _onSearchSubmit,
          child: Text(context.loc.tmdb_search_button),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    final loc = context.loc;
    return Wrap(
      spacing: 8,
      children: [
        for (final filter in SearchFilter.values)
          ChoiceChip(
            label: Text(_filterLabel(filter, loc)),
            selected: _filter == filter,
            onSelected: (_) => _onFilterSelected(filter),
          ),
      ],
    );
  }

  String _filterLabel(SearchFilter filter, dynamic loc) {
    switch (filter) {
      case SearchFilter.all:
        return loc.search_filter_all;
      case SearchFilter.movies:
        return loc.search_filter_movies;
      case SearchFilter.tv:
        return loc.search_filter_tv;
      case SearchFilter.wishlist:
        return loc.search_filter_wishlist;
    }
  }

  Widget _buildSearchHistory() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _searchHistory
                .map(
                  (query) => ActionChip(
                    avatar: const Icon(Icons.history, size: 16),
                    label: Text(query),
                    onPressed: () => _searchFromHistory(query),
                  ),
                )
                .toList(),
          ),
        ),
        IconButton(
          tooltip: context.loc.search_clear_history,
          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          onPressed: _clearHistory,
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    if (_filter == SearchFilter.wishlist) {
      return Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.bookmark_border,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  context.loc.search_wishlist_empty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              context.loc.search_no_results,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSections(UnifiedSearchResults results) {
    final loc = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (results.withLocal.isNotEmpty) ...[
          _sectionHeader(
            Icons.check_circle_outline,
            loc.search_in_your_lists,
            results.withLocal.length,
          ),
          const SizedBox(height: 8),
          ...results.withLocal.map(_buildTmdbCard),
          const SizedBox(height: 16),
        ],
        if (results.localOnly.isNotEmpty) ...[
          _sectionHeader(
            Icons.live_tv,
            loc.search_from_your_iptv,
            results.localOnly.length,
          ),
          const SizedBox(height: 8),
          ...results.localOnly.map(_buildLocalOnlyCard),
          const SizedBox(height: 16),
        ],
        if (results.tmdbOnly.isNotEmpty) ...[
          _sectionHeader(
            Icons.theaters,
            loc.search_tmdb_section,
            results.tmdbOnly.length,
          ),
          const SizedBox(height: 8),
          ...results.tmdbOnly.map(_buildTmdbCard),
        ],
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String title, int count) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildTmdbCard(GlobalSearchResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showDetail(result.tmdb),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _poster(result.tmdb.posterUrl, 64, 96),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            result.tmdb.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            result.isWishlisted
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            size: 20,
                            color: result.isWishlisted
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          onPressed: () => _toggleWishlist(result.tmdb),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          '${result.tmdb.mediaTypeLabel}  ${result.tmdb.releaseYear ?? ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        Text(
                          ' ${result.tmdb.voteAverage.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (result.hasExactMatch)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              context.loc.tmdb_exact_match,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (result.localMatches.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...result.localMatches.map(
                        (match) => SizedBox(
                          height: 32,
                          child: OutlinedButton.icon(
                            icon: Icon(
                              match.isExactMatch
                                  ? Icons.check_circle
                                  : Icons.play_arrow,
                              size: 16,
                            ),
                            label: Text(
                              '${match.playlist.name}: ${match.content.name}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 32),
                            ),
                            onPressed: () => _openMatch(match),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalOnlyCard(LocalContentMatch match) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openMatch(match),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _poster(null, 56, 84),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.content.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      match.playlist.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 32,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: Text(
                          context.loc.search_watch_action,
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                        ),
                        onPressed: () => _openMatch(match),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster(String? url, double w, double h) {
    if (url == null || url.isEmpty) {
      return SizedBox(
        width: w,
        height: h,
        child: Container(
          color: Colors.grey.shade200,
          child: Icon(Icons.movie, size: 28, color: Colors.grey.shade400),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        memCacheWidth: (w * 2).toInt(),
        memCacheHeight: (h * 2).toInt(),
        placeholder: (_, __) => Container(
          color: Colors.grey.shade200,
          width: w,
          height: h,
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          width: w,
          height: h,
          child: Icon(Icons.broken_image, color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
    );
  }
}

/// Bottom sheet showing the full TMDb detail for a single result. Loads the
/// payload lazily via [TmdbService.detail] and falls back to whatever fields
/// the search result already had if the network call fails.
class _TmdbDetailSheet extends StatefulWidget {
  final TmdbSearchResult item;
  final GlobalSearchService service;
  final Locale locale;
  final ScrollController scrollController;
  final UnifiedSearchResults? currentResults;
  final void Function(LocalContentMatch) onOpenMatch;
  final void Function(TmdbSearchResult) onToggleWishlist;

  const _TmdbDetailSheet({
    required this.item,
    required this.service,
    required this.locale,
    required this.scrollController,
    required this.currentResults,
    required this.onOpenMatch,
    required this.onToggleWishlist,
  });

  @override
  State<_TmdbDetailSheet> createState() => _TmdbDetailSheetState();
}

class _TmdbDetailSheetState extends State<_TmdbDetailSheet> {
  TmdbDetailResult? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.service.getDetail(
        widget.item,
        locale: widget.locale,
      );
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<LocalContentMatch> _matchesForItem() {
    final results = widget.currentResults;
    if (results == null) return const [];
    for (final r in results.withLocal) {
      if (r.tmdb.id == widget.item.id &&
          r.tmdb.mediaType == widget.item.mediaType) {
        return r.localMatches;
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final colorScheme = Theme.of(context).colorScheme;
    final detail = _detail;
    final matches = _matchesForItem();
    final overview = detail?.overview ?? widget.item.overview;
    final genres = detail?.genres ?? const <String>[];
    final runtime = detail?.runtimeMinutes;
    final backdrop = detail?.backdropUrl.isNotEmpty == true
        ? detail!.backdropUrl
        : widget.item.backdropPosterUrl;
    final year = detail?.releaseYear ?? widget.item.releaseYear;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.zero,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: backdrop.isEmpty
                    ? Container(color: Colors.grey.shade300)
                    : CachedNetworkImage(
                        imageUrl: backdrop,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.grey.shade300),
                      ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        colorScheme.surface.withOpacity(0.95),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surface.withOpacity(0.6),
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => widget.onToggleWishlist(widget.item),
                      icon: const Icon(Icons.bookmark_border),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      widget.item.mediaTypeLabel,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    if (year != null) ...[
                      const Text('  ·  '),
                      Text(year, style: TextStyle(color: Colors.grey.shade600)),
                    ],
                    if (runtime != null) ...[
                      const Text('  ·  '),
                      Text(
                        loc.search_detail_runtime(runtime),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                    const Spacer(),
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(widget.item.voteAverage.toStringAsFixed(1)),
                  ],
                ),
                if (genres.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    loc.search_detail_genres,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: genres
                        .map(
                          (g) => Chip(
                            label: Text(g),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (overview != null && overview.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    loc.search_detail_overview,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(overview, style: const TextStyle(height: 1.4)),
                ],
                const SizedBox(height: 20),
                if (matches.isNotEmpty)
                  ...matches.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            loc.search_detail_open_in_playlist(
                              m.playlist.name,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onOpenMatch(m);
                          },
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    loc.search_detail_not_in_playlists,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (_loading) ...[
                  const SizedBox(height: 12),
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: colorScheme.error, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
