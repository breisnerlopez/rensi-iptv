import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/redesign/search_detail_sheet.dart';
import 'package:rensi_iptv/screens/settings/general_settings_section.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/tmdb_service.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/widgets/tv/tv_keyboard.dart';

/// Full-screen global search.
///
/// Unifies the user's own IPTV catalogue with TMDb discovery into three
/// reproducible-first buckets (see [GlobalSearchService]). Two surfaces share
/// one result body:
///   - TV: an on-screen [TvKeyboard] on the leading edge, results on the
///     trailing edge. Columns are derived from the RESULTS-PANEL width (after
///     the keyboard), never the screen. D-pad crosses into the first playable
///     poster; the keyboard keeps focus while typing (no focus theft).
///   - Mobile: the system IME field on top, a vertical scroll of the sections.
///
/// The constructor is unchanged on purpose — both homes push it as
/// `SearchRedesign(onOpen: ...)`. The screen owns its own service instance.
class SearchRedesign extends StatefulWidget {
  const SearchRedesign({super.key, required this.onOpen});

  final void Function(ContentItem) onOpen;

  @override
  State<SearchRedesign> createState() => _SearchRedesignState();
}

class _SearchRedesignState extends State<SearchRedesign> {
  final GlobalSearchService _service = GlobalSearchService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Wraps the TV results grid so that when TMDb arrives and an owned card is
  /// promoted from "your IPTV" to "your library" — changing its ValueKey and
  /// section, which disposes the focused element — we can put focus back on a
  /// card instead of leaving it dangling mid-navigation.
  final FocusScopeNode _resultsScope = FocusScopeNode();

  /// One per filter chip, so [_applyFilter] can scroll the active one into view.
  final List<GlobalKey> _filterKeys =
      List.generate(SearchFilter.values.length, (_) => GlobalKey());

  Timer? _debounce;

  /// Raw text of the field (TV: fed by the on-screen keyboard).
  String _query = '';
  SearchFilter _filter = SearchFilter.all;

  /// Latest result set, or null before the first query. Progressive: a
  /// local-first paint (`tmdbPending == true`) lands here first, then the final
  /// three buckets replace it. In person mode this holds the SELECTED person's
  /// filmography buckets.
  UnifiedSearchResults? _results;

  /// People matching the current query in person mode, or null before a search.
  /// Only meaningful while `_filter == SearchFilter.people`.
  List<TmdbPerson>? _people;

  /// The person whose filmography is being shown, or null while the person
  /// picker (the people list) is on screen.
  TmdbPerson? _selectedPerson;

  /// Why the person LIST search failed (typed), or null. Renders the same
  /// degradation banner/empty as a text search's `tmdbFailure`.
  TmdbFailure? _peopleFailure;

  /// A search is in flight and there is nothing to show yet (drives the only
  /// full-panel spinner — the wishlist browse / filter switch). During a text
  /// search the discover-zone skeleton is driven by `tmdbPending` instead, so
  /// local results are never hidden behind a spinner.
  bool _loading = false;

  /// Monotonic request id. Every async response checks it against the current
  /// value and drops itself if a newer query has since started — the guard
  /// against an out-of-order TMDb reply overwriting a fresher local paint.
  int _reqToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _resultsScope.dispose();
    super.dispose();
  }

  // --- Query lifecycle -------------------------------------------------------

  void _onChanged(String v) {
    setState(() => _query = v);
    final q = v.trim();
    _debounce?.cancel();
    // Below the local threshold on a normal search: nothing to run, and the
    // in-flight request (if any) is invalidated so a late reply can't repaint.
    if (_filter != SearchFilter.wishlist && q.length < 2) {
      _reqToken++;
      setState(() {
        _results = null;
        _resetPeople();
        _loading = false;
      });
      return;
    }
    // Spinner only when there is nothing on screen yet. In person mode the
    // "nothing yet" surface is the people list, not `_results`.
    final nothingYet =
        _filter == SearchFilter.people ? _people == null : _results == null;
    if (nothingYet) setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  /// Clears the person-mode state (picker list, selection, failure). Mutates
  /// fields only — call inside an enclosing setState.
  void _resetPeople() {
    _people = null;
    _selectedPerson = null;
    _peopleFailure = null;
  }

  void _applyFilter(SearchFilter f) {
    if (f == _filter) return;
    // Switching modes drops any person picker/selection and stale results so the
    // new mode never flashes the previous mode's cards.
    setState(() {
      _filter = f;
      _resetPeople();
      _results = null;
    });
    // Scroll the now-active chip fully into view. On a 360dp phone the four
    // chips don't fit, so the selected one — the most important label on the
    // row — was clipped at the right edge, worse in long languages.
    final idx = SearchFilter.values.indexOf(f);
    if (idx >= 0 && idx < _filterKeys.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _filterKeys[idx].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.5, duration: const Duration(milliseconds: 250));
        }
      });
    }
    _debounce?.cancel();
    final q = _query.trim();
    if (f != SearchFilter.wishlist && q.length < 2) {
      _reqToken++;
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }
    // A filter switch is a deliberate act — run it now rather than after the
    // typing debounce.
    setState(() => _loading = true);
    _run();
  }

  Future<void> _run() async {
    if (!mounted) return;
    final token = ++_reqToken;
    final q = _query.trim();
    final filter = _filter;
    final locale = Localizations.localeOf(context);

    // Wishlist is a browse of saved titles: no minimum length, single call.
    if (filter == SearchFilter.wishlist) {
      final res = await _service.search(q, filter: filter, locale: locale);
      if (!mounted || token != _reqToken) return;
      setState(() {
        _results = res;
        _loading = false;
      });
      return;
    }

    // Person mode: a query searches PEOPLE (the picker). Selecting a person is a
    // separate action (_selectPerson) that fetches their filmography; a fresh
    // query here always returns to the picker.
    if (filter == SearchFilter.people) {
      if (q.length < 2) {
        setState(() {
          _resetPeople();
          _results = null;
          _loading = false;
        });
        return;
      }
      List<TmdbPerson> people = const [];
      TmdbFailure? failure;
      try {
        people = await _service.searchPeople(q, locale: locale);
      } on TmdbException catch (e) {
        failure = e.reason;
      } catch (_) {
        failure = TmdbFailure.network;
      }
      if (!mounted || token != _reqToken) return;
      setState(() {
        _people = people;
        _peopleFailure = failure;
        _selectedPerson = null;
        _results = null;
        _loading = false;
      });
      return;
    }

    if (q.length < 2) {
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }

    // 1) Instant local-first paint so the user's own catalogue never waits on
    //    the network. `tmdbPending` is true here.
    final local = await _service.searchLocalFirst(q, filter: filter);
    if (!mounted || token != _reqToken) return;
    setState(() => _results = local);

    // 2) At exactly two characters TMDb has not armed yet (its own floor is 3).
    //    Show local + a "keep typing" hint where Discover would go — never a
    //    spinner, never an empty look.
    if (q.length < 3) {
      if (mounted && token == _reqToken) setState(() => _loading = false);
      return;
    }

    // 3) The real three-bucket result. Never throws: a TMDb failure comes back
    //    as `tmdbFailure`, the local buckets survive.
    final full = await _service.search(q, filter: filter, locale: locale);
    if (!mounted || token != _reqToken) return;
    // If the viewer had already crossed into the results on TV, this reshuffle
    // can dispose the card they were on (an owned title promoting to "your
    // library"). Reengage focus onto a card afterwards so it never ends up
    // dangling mid-navigation.
    final hadResultsFocus = _resultsScope.hasFocus;
    setState(() {
      _results = full;
      _loading = false;
    });
    if (hadResultsFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _resultsScope.hasFocus) return;
        // Focus the first focusable card in the (rebuilt) results, explicitly
        // rather than by directional geometry which has no anchor once the
        // previously-focused node is gone.
        for (final node in _resultsScope.traversalDescendants) {
          if (node.canRequestFocus && !node.skipTraversal) {
            node.requestFocus();
            break;
          }
        }
      });
    }
  }

  // --- Actions ---------------------------------------------------------------

  /// The one path that plays a locally-owned match: point AppState at the right
  /// repository, then navigate — in the SAME tick, per [openLocalMatch]'s
  /// contract, so two fast taps cannot interleave. Used for `localOnly`, a
  /// single-match `withLocal`, and the detail sheet's "play from" rows.
  void _playLocalMatch(LocalContentMatch match) {
    _service.openLocalMatch(match);
    widget.onOpen(match.content);
  }

  /// Loads and shows a selected person's filmography, cross-referenced against
  /// the local catalogue. The result rides the SAME buckets/cards as a text
  /// search; a TMDb failure degrades to `tmdbFailure` on the returned set.
  Future<void> _selectPerson(TmdbPerson person) async {
    final token = ++_reqToken;
    final locale = Localizations.localeOf(context);
    // The tapped person card lives in the results scope on TV; replacing the
    // picker with the filmography disposes it, so remember to re-anchor focus.
    final hadResultsFocus = _resultsScope.hasFocus;
    setState(() {
      _selectedPerson = person;
      _results = null;
      _loading = true;
    });
    final res = await _service.searchByPerson(person, locale: locale);
    if (!mounted || token != _reqToken) return;
    setState(() {
      _results = res;
      _loading = false;
    });
    // Re-engage D-pad focus onto a card in the rebuilt filmography grid so it
    // never dangles mid-navigation (same reanchor pattern as the text search).
    if (hadResultsFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _resultsScope.hasFocus) return;
        for (final node in _resultsScope.traversalDescendants) {
          if (node.canRequestFocus && !node.skipTraversal) {
            node.requestFocus();
            break;
          }
        }
      });
    }
  }

  /// Returns from a person's filmography to the people picker.
  void _clearSelectedPerson() {
    // Invalidate any in-flight filmography so a late reply can't repaint the
    // picker we're returning to.
    _reqToken++;
    setState(() {
      _selectedPerson = null;
      _results = null;
      _loading = false;
    });
  }

  void _openDetail(GlobalSearchResult result) {
    // SEAM: the sheet lands in parallel. This is the exact call it must accept.
    // See the module doc-comment at the bottom of this file.
    SearchDetailSheet.show(
      context,
      result: result,
      service: _service,
      onPlayLocal: _playLocalMatch,
      onToggleWishlist: () => _toggleWishlist(result),
    );
  }

  /// Optimistic wishlist flip. Toggles the store, re-stamps the visible results
  /// via [UnifiedSearchResults.withWishlistKeys] (which preserves the failure /
  /// pending flags), and confirms with a SnackBar. Returns the new saved state
  /// so the detail sheet can update its own icon. In wishlist-browse a removal
  /// drops the row, so we re-run that view.
  Future<bool> _toggleWishlist(GlobalSearchResult result) async {
    final bool nowSaved;
    final Set<String> keys;
    try {
      nowSaved = await TmdbWishlistService.toggle(result.tmdb);
      keys = await TmdbWishlistService.getKeys();
    } catch (_) {
      // A failed write must not leave the icon lying, nor throw as an unhandled
      // async error from the mobile card's onTap. Report and keep the old state.
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(context.loc.search_tmdb_error)),
          );
      }
      return result.isWishlisted;
    }
    if (!mounted) return nowSaved;
    setState(() => _results = _results?.withWishlistKeys(keys));
    // Only the search screen shows the SnackBar. When the toggle came from the
    // detail sheet (a modal route is on top), the sheet's own button IS the
    // feedback and a SnackBar would render mangled behind the sheet. And the
    // copy is a past-tense confirmation ("saved"/"removed"), not the imperative
    // button label ("save"/"remove") it used to echo.
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(nowSaved
              ? context.loc.search_saved_confirm
              : context.loc.search_removed_confirm),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    if (_filter == SearchFilter.wishlist) _run();
    return nowSaved;
  }

  void _openSettings() {
    // GeneralSettingsWidget is NOT a screen — it's a section meant to live
    // inside a Scaffold + scrollable (see m3u_playlist_settings_screen). Pushed
    // bare it has no app bar, no back button, and its Column overflows ~1600px.
    // Host it properly so the "add your TMDb key" flow — the exact reason a user
    // taps this — lands on a real, scrollable, dismissable screen.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _SettingsHostScreen()),
    );
  }

  void _clearQuery() {
    _controller.clear();
    _onChanged('');
  }

  // --- Layout ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tv = ResponsiveHelper.isDesktopOrTV(context);
    final inset = ResponsiveHelper.safeInset(context);
    // PopScope: on this two-column TV layout the on-screen back arrow is not a
    // D-pad focus target, so BACK must pop the route. `canPop: true` lets the
    // system BACK do exactly that (an open detail sheet consumes its own BACK
    // first). The arrow stays for mobile touch.
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(child: tv ? _tvLayout(inset) : _mobileLayout(inset)),
      ),
    );
  }

  Widget _mobileLayout(double sidePad) {
    return Column(
      children: [
        _mobileHeader(),
        _filters(sidePad),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) => _resultsBody(
              tv: false,
              columns: _columns(c.maxWidth, false),
              sidePad: sidePad,
              panelWidth: c.maxWidth,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tvLayout(double screenInset) {
    // Small internal padding on the right panel: the overscan margin is already
    // reserved by the column's trailing [screenInset], and the keyboard gives
    // the leading gutter, so the grid itself only needs breathing room.
    const rp = 8.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Top uses the same overscan margin as the sides — the hard-coded 12
          // put the first keyboard row and its focus ring into the TV overscan
          // band, where a real set can clip it.
          padding: EdgeInsetsDirectional.fromSTEB(screenInset, screenInset, 20, 24),
          // Scroll the keyboard on short panels so its last rows are reachable.
          child: SingleChildScrollView(child: _keyboard()),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: screenInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: screenInset),
                _tvQueryBar(rp),
                _filters(rp),
                const SizedBox(height: 10),
                Expanded(
                  child: FocusScope(
                    node: _resultsScope,
                    child: LayoutBuilder(
                      builder: (_, c) => _resultsBody(
                        tv: true,
                        columns: _columns(c.maxWidth, true),
                        sidePad: rp,
                        panelWidth: c.maxWidth,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _keyboard() {
    return TvKeyboard(
      onKey: (c) {
        _controller.text = _controller.text + c.toLowerCase();
        _onChanged(_controller.text);
      },
      onBackspace: () {
        final t = _controller.text;
        if (t.isEmpty) return;
        _controller.text = t.substring(0, t.length - 1);
        _onChanged(_controller.text);
      },
      onClear: _clearQuery,
    );
  }

  Widget _mobileHeader() {
    final r = rensi(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          // Directionality-aware; points the correct way in RTL.
          const BackButton(),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: r.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: r.text3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: context.loc.search_placeholder,
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      // 48dp minimum: the override stripped IconButton's
                      // default tap target down to ~18dp.
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      tooltip: context.loc.clear,
                      onPressed: _clearQuery,
                      icon: Icon(Icons.close, size: 18, color: r.text3),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// TV read-only echo of the query (the on-screen keyboard does not draw one).
  Widget _tvQueryBar(double sidePad) {
    final r = rensi(context);
    final empty = _query.isEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 12),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: r.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: r.hairline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.search, color: r.text3),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                empty ? context.loc.search_placeholder : _query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppThemes.bodySize,
                  color: empty
                      ? r.text3
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(double sidePad) {
    final loc = context.loc;
    final chips = <(SearchFilter, String)>[
      (SearchFilter.all, loc.search_filter_all),
      (SearchFilter.movies, loc.search_filter_movies),
      (SearchFilter.tv, loc.search_filter_tv),
      (SearchFilter.wishlist, loc.search_filter_wishlist),
      (SearchFilter.people, loc.search_filter_people),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Trailing gutter so the last chip is never flush against the edge.
        padding: EdgeInsetsDirectional.only(start: sidePad, end: sidePad),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(
          key: _filterKeys[i],
          child: RensiChip(
            label: chips[i].$2,
            active: _filter == chips[i].$1,
            onTap: () => _applyFilter(chips[i].$1),
          ),
        ),
      ),
    );
  }

  // --- Results ---------------------------------------------------------------

  int _columns(double width, bool tv) {
    final target = tv ? 160.0 : 118.0;
    const gutter = 12.0;
    final n = ((width + gutter) / (target + gutter)).floor();
    return n.clamp(tv ? 3 : 2, tv ? 7 : 6);
  }

  Widget _resultsBody({
    required bool tv,
    required int columns,
    required double sidePad,
    required double panelWidth,
  }) {
    final loc = context.loc;
    final q = _query.trim();
    final res = _results;
    final browse = _filter == SearchFilter.wishlist;
    final personMode =
        _filter == SearchFilter.people && _selectedPerson != null;

    // Person picker: the people list stands in for the results until a person is
    // chosen; the selected person's filmography then falls through to the shared
    // sections below.
    if (_filter == SearchFilter.people && _selectedPerson == null) {
      return _peopleBody(columns: columns, sidePad: sidePad);
    }

    if (res == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _centered(Icons.search_rounded, loc.search_catalog_hint);
    }

    // Total-empty. Suppressed while a local-first paint is pending (there is
    // still Discover to resolve, or a "keep typing" hint to show at 2 chars).
    if (res.isEmpty && !res.tmdbPending && !_loading) {
      if (browse) {
        return RensiEmptyState(
          icon: Icons.bookmark_border_rounded,
          title: loc.search_filter_wishlist,
          body: loc.search_wishlist_empty,
          // "Explorar catálogo", not "Todo": a primary CTA named after a filter
          // reads as a no-op; this one clears the filter back to search.
          actionLabel: loc.action_browse_catalogue,
          onAction: () => _applyFilter(SearchFilter.all),
        );
      }
      // With no local catalogue to fall back on, a TMDb failure must still be
      // told honestly here, not hidden behind a generic "no results": the
      // banner only shows when there ARE results, so this is the only place a
      // key-less/rejected/limited user learns why Discover is empty.
      final failure = res.tmdbFailure;
      // Person filmography empty: name the person, offer a way back to the
      // picker. A failure below still overrides the body/action honestly.
      String body =
          personMode ? loc.search_person_no_results : loc.search_catalog_hint;
      String actionLabel =
          personMode ? loc.search_back_to_actors : loc.clear;
      VoidCallback onAction =
          personMode ? _clearSelectedPerson : _clearQuery;
      switch (failure) {
        case TmdbFailure.noKey:
          body = loc.search_global_disabled;
          actionLabel = loc.search_enable_global;
          onAction = _openSettings;
          break;
        case TmdbFailure.rejected:
          body = loc.search_key_rejected;
          actionLabel = loc.nav_settings;
          onAction = _openSettings;
          break;
        case TmdbFailure.rateLimited:
          body = loc.search_tmdb_rate_limited;
          break;
        case TmdbFailure.httpError:
        case TmdbFailure.network:
          body = loc.search_tmdb_error;
          actionLabel = loc.try_again;
          onAction = _run;
          break;
        case null:
          break;
      }
      return RensiEmptyState(
        icon: personMode ? Icons.person_off_rounded : Icons.search_off_rounded,
        title: personMode ? _selectedPerson!.name : loc.no_results_for(q),
        body: body,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    }

    final tileWidth =
        ((panelWidth - sidePad * 2 - 12 * (columns - 1)) / columns)
            .clamp(60.0, 400.0);

    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 2)),
    ];

    // Person filmography: a focusable, RTL-aware back header returns to the
    // people picker without popping the search route.
    if (personMode) {
      slivers.add(_personHeaderSliver(_selectedPerson!, sidePad));
    }

    // Failure / no-key banner — thin, above the sections, never replacing the
    // local results.
    if (!browse && res.tmdbFailure != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 14),
            child: _banner(res.tmdbFailure!),
          ),
        ),
      );
    }

    void addSection(String title, List<Widget> cards) {
      if (cards.isEmpty) return;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SectionHeader(title: title, sidePad: sidePad),
          ),
        ),
      );
      slivers.add(_gridSliver(cards, columns, sidePad));
    }

    // Reproducible-first: library, then owned-only, then discover.
    addSection(
      loc.search_in_your_library,
      [for (final x in res.withLocal) _withLocalCard(x)],
    );
    addSection(
      loc.search_from_your_iptv,
      [for (final x in res.localOnly) _localOnlyCard(x)],
    );
    // In wishlist browse these are SAVED items, not discovery: label the section
    // "your wishlist" and badge the cards "Saved", never "not in your lists" —
    // otherwise your own wishlist tells you it is not in your lists.
    addSection(
      browse ? loc.search_filter_wishlist : loc.search_discover_tmdb,
      [for (final x in res.tmdbOnly) _tmdbOnlyCard(x, tv, browse)],
    );

    // Discover zone placeholders (never on a wishlist browse).
    if (!browse) {
      if (q.length == 2) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 8),
              child: _hintRow(
                  Icons.travel_explore_rounded, loc.search_keep_typing_global),
            ),
          ),
        );
      } else if (q.length >= 3 && res.tmdbPending) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child:
                  SectionHeader(title: loc.search_discover_tmdb, sidePad: sidePad),
            ),
          ),
        );
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 16),
              child: _skeletonRow(columns, tileWidth.toDouble()),
            ),
          ),
        );
      }
    }

    slivers.add(SliverToBoxAdapter(child: SizedBox(height: tv ? 24 : 32)));
    return CustomScrollView(slivers: slivers);
  }

  /// The poster grid sliver shared by [addSection] and the people picker, so the
  /// stable-key focus preservation and column math live in one place.
  Widget _gridSliver(List<Widget> cards, int columns, double sidePad) {
    final indexByKey = <String, int>{};
    for (var i = 0; i < cards.length; i++) {
      final k = cards[i].key;
      if (k is ValueKey<String>) indexByKey[k.value] = i;
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 1 / 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => cards[i],
          childCount: cards.length,
          // Stable keys + this callback let a poster keep its element (and its
          // focus) when the buckets reshuffle.
          findChildIndexCallback: (key) =>
              indexByKey[(key as ValueKey<String>).value],
        ),
      ),
    );
  }

  /// The person picker: a grid of people (photo + name). Reuses the same grid
  /// and the same typed-failure/empty surfaces as a text search. Selecting a
  /// person loads their filmography (see [_selectPerson]).
  Widget _peopleBody({required int columns, required double sidePad}) {
    final loc = context.loc;
    final q = _query.trim();
    final people = _people;

    if (people == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _centered(Icons.person_search_rounded, loc.search_person_hint);
    }

    if (people.isEmpty && !_loading) {
      final failure = _peopleFailure;
      String body = loc.search_person_hint;
      String actionLabel = loc.clear;
      VoidCallback onAction = _clearQuery;
      switch (failure) {
        case TmdbFailure.noKey:
          body = loc.search_global_disabled;
          actionLabel = loc.search_enable_global;
          onAction = _openSettings;
          break;
        case TmdbFailure.rejected:
          body = loc.search_key_rejected;
          actionLabel = loc.nav_settings;
          onAction = _openSettings;
          break;
        case TmdbFailure.rateLimited:
          body = loc.search_tmdb_rate_limited;
          break;
        case TmdbFailure.httpError:
        case TmdbFailure.network:
          body = loc.search_tmdb_error;
          actionLabel = loc.try_again;
          onAction = _run;
          break;
        case null:
          break;
      }
      return RensiEmptyState(
        icon: Icons.person_off_rounded,
        title: loc.no_results_for(q),
        body: body,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    }

    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 2)),
    ];
    if (_peopleFailure != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 14),
            child: _banner(_peopleFailure!),
          ),
        ),
      );
    }
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SectionHeader(title: loc.search_filter_people, sidePad: sidePad),
        ),
      ),
    );
    slivers.add(_gridSliver(
      [for (final p in people) _personCard(p)],
      columns,
      sidePad,
    ));
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return CustomScrollView(slivers: slivers);
  }

  /// A person cell: reuses [RensiPoster] (photo + always-on name label) so the
  /// picker inherits the TV focus ring/zoom and D-pad traversal for free — no
  /// new card widget. Tapping loads that person's filmography.
  Widget _personCard(TmdbPerson p) {
    return RensiPoster(
      key: ValueKey('person:${p.id}'),
      item: ContentItem(
        'person:${p.id}',
        p.name,
        p.profileUrl ?? '',
        ContentType.vod,
      ),
      width: double.infinity,
      // People need their name always visible to be picked, unlike a title
      // poster whose art already names it.
      showMeta: true,
      onTap: () => _selectPerson(p),
    );
  }

  /// Back header above a person's filmography. [BackButton] is directionality
  /// aware (flips in RTL) and D-pad focusable; it returns to the picker instead
  /// of popping the search route.
  Widget _personHeaderSliver(TmdbPerson person, double sidePad) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(sidePad, 2, sidePad, 8),
        child: Row(
          children: [
            Tooltip(
              message: context.loc.search_back_to_actors,
              child: BackButton(onPressed: _clearSelectedPerson),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppThemes.h3Size,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Cards -----------------------------------------------------------------

  /// `withLocal`: a reproducible, TMDb-enriched title. Poster is identical to
  /// Home (no badge). One match plays directly; several open the "play from"
  /// sheet so a dead copy in one list is not chosen for the user.
  Widget _withLocalCard(GlobalSearchResult res) {
    final match = res.localMatches.first; // service orders exact-first
    return RensiPoster(
      key: ValueKey('wl:${res.tmdb.id}|${res.tmdb.mediaType.name}'),
      item: match.content,
      width: double.infinity,
      onTap: () {
        if (res.localMatches.length > 1) {
          _openDetail(res);
        } else {
          _playLocalMatch(match);
        }
      },
    );
  }

  /// `localOnly`: owned, no TMDb data to show, so it plays directly. We still
  /// call [openLocalMatch] via [_playLocalMatch] because a match can come from
  /// a playlist other than the current one, and navigation reads AppState.
  Widget _localOnlyCard(LocalContentMatch m) {
    return RensiPoster(
      key: ValueKey(m.dedupKey),
      item: m.content,
      width: double.infinity,
      onTap: () => _playLocalMatch(m),
    );
  }

  /// `tmdbOnly`: not owned. NOT dimmed and with no play affordance — a neutral
  /// badge marks it as a discovery, not a disabled item. Opening it shows the
  /// save-only detail sheet. On mobile the card also carries a tappable
  /// bookmark; on TV the toggle lives in the sheet (one focus atom per cell).
  Widget _tmdbOnlyCard(GlobalSearchResult res, bool tv, bool browse) {
    final k = 'tm:${res.tmdb.id}|${res.tmdb.mediaType.name}';
    final poster = RensiPoster(
      item: _tmdbAsContentItem(res.tmdb),
      width: double.infinity,
      badge: browse ? context.loc.search_saved : context.loc.search_not_in_lists,
      badgeTone: RensiBadgeTone.neutral,
      onTap: () => _openDetail(res),
    );
    if (tv) return KeyedSubtree(key: ValueKey(k), child: poster);
    return KeyedSubtree(
      key: ValueKey(k),
      child: Stack(
        children: [
          Positioned.fill(child: poster),
          PositionedDirectional(
            bottom: 8,
            end: 8,
            child: _MobileBookmark(
              saved: res.isWishlisted,
              onTap: () => _toggleWishlist(res),
            ),
          ),
        ],
      ),
    );
  }

  /// A display-only [ContentItem] wrapping a TMDb result so it can ride in a
  /// [RensiPoster]. It is never played (tmdbOnly has no play path), so the
  /// baked-in `url` is inert; the poster reads only `imagePath`, `name`, `id`.
  ContentItem _tmdbAsContentItem(TmdbSearchResult t) => ContentItem(
        'tmdb:${t.id}',
        t.title,
        t.posterUrl,
        t.mediaType == TmdbMediaType.tv ? ContentType.series : ContentType.vod,
      );

  // --- Small pieces ----------------------------------------------------------

  Widget _banner(TmdbFailure failure) {
    final r = rensi(context);
    final loc = context.loc;
    late final String msg;
    Widget? action;
    switch (failure) {
      case TmdbFailure.noKey:
        msg = loc.search_global_disabled;
        action = _bannerButton(loc.search_enable_global, _openSettings);
        break;
      case TmdbFailure.rejected:
        msg = loc.search_key_rejected;
        action = _bannerButton(loc.nav_settings, _openSettings);
        break;
      case TmdbFailure.rateLimited:
        msg = loc.search_tmdb_rate_limited;
        break;
      case TmdbFailure.httpError:
      case TmdbFailure.network:
        msg = loc.search_tmdb_error;
        action = _bannerButton(loc.try_again, _run);
        break;
    }
    return Container(
      decoration: BoxDecoration(
        color: r.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.hairline),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: r.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: r.text2,
                fontSize: AppThemes.bodySmallSize,
                height: 1.3,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }

  Widget _bannerButton(String label, VoidCallback onTap) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(10),
      child: TextButton(
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _hintRow(IconData icon, String text) {
    final r = rensi(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: r.text3),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: r.text3, fontSize: AppThemes.bodySmallSize),
          ),
        ),
      ],
    );
  }

  Widget _skeletonRow(int columns, double tileWidth) {
    final r = rensi(context);
    final n = columns.clamp(1, 6);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < n; i++)
          SizedBox(
            width: tileWidth,
            height: tileWidth * 1.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: r.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: r.hairline),
              ),
            ),
          ),
      ],
    );
  }

  Widget _centered(IconData icon, String text) {
    final r = rensi(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: r.surface3),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: r.text3, fontSize: AppThemes.labelSize),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile-only save affordance drawn over a discovery poster. The dark chip
/// reads on any artwork; the active state uses the brand accent (gold is
/// reserved for ratings). Positioned start/end-aware for RTL.
class _MobileBookmark extends StatelessWidget {
  const _MobileBookmark({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    // A 48x48 tap target (WCAG/Material minimum) around a ~32dp visible chip:
    // "save" is the primary action here and the small circle alone was ~32dp,
    // hard to hit with a thumb. Semantics announces name + saved/unsaved state
    // (an icon-only button was "button" with no cue to TalkBack).
    return Semantics(
      button: true,
      toggled: saved,
      label: saved
          ? context.loc.search_remove_from_wishlist
          : context.loc.search_add_to_wishlist,
      excludeSemantics: true,
      child: SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xCC080808),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(6),
              child: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                size: 20,
                color: saved ? r.accent : Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Hosts [GeneralSettingsWidget] as a real, scrollable, dismissable screen.
/// The section widget is not a page on its own — bare it has no app bar and its
/// Column overflows — so the "add your TMDb key" banner opens this instead.
class _SettingsHostScreen extends StatelessWidget {
  const _SettingsHostScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.settings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          children: const [GeneralSettingsWidget()],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// INTEGRATION SEAM — SearchDetailSheet (lib/redesign/search_detail_sheet.dart)
//
// This screen calls exactly:
//
//   SearchDetailSheet.show(
//     context,
//     result: <GlobalSearchResult>,
//     service: <GlobalSearchService>,     // for service.getDetail(result.tmdb)
//     onPlayLocal: (LocalContentMatch m) { ... },   // plays one owned copy
//     onToggleWishlist: () async => <bool>,         // returns new saved state
//   );
//
// Expected static signature on SearchDetailSheet:
//
//   static Future<void> show(
//     BuildContext context, {
//     required GlobalSearchResult result,
//     required GlobalSearchService service,
//     required void Function(LocalContentMatch match) onPlayLocal,
//     required Future<bool> Function() onToggleWishlist,
//   });
//
// Sheet responsibilities (per the design gate):
//   - tmdbOnly result  -> overview / rating / genres via service.getDetail;
//     ONE primary action = wishlist toggle (no play); show search_not_available_body.
//   - withLocal result -> a "Reproducir desde" list (search_play_from) of
//     result.localMatches, each row calling onPlayLocal(match).
//   - The bookmark is the wishlist toggle on both surfaces; call
//     onToggleWishlist() and reflect the returned bool.
//   - Takes focus on open; BACK returns to the originating card.
// -----------------------------------------------------------------------------
