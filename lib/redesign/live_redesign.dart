import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/widgets/tv/tv_field_traversal.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/services/epg_service.dart';
import 'package:rensi_iptv/widgets/live/now_playing_line.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

/// "En vivo" — channel rows grouped by category chips. When the panel provides
/// a schedule, each row also shows what is on now and how far through it is
/// (see [NowPlayingLine]); channels without a listing simply show the channel,
/// so a gap in the provider's data looks like a gap, not like a stuck row.
class LiveRedesign extends StatefulWidget {
  const LiveRedesign({
    this.epgService,
    super.key,
    required this.liveCategories,
    required this.onPlay,
    this.playlistSwitcher,
  });

  final List<CategoryViewModel> liveCategories;
  final void Function(ContentItem) onPlay;

  /// When present, each row shows what is on now and how far through it is.
  /// Optional so the screen still renders for M3U playlists, which have no
  /// Xtream panel to ask.
  final EpgService? epgService;

  /// The active-playlist indicator/switcher shown in the header — the SAME
  /// [PlaylistSwitcherButton] the Home header uses, so a user searching for a
  /// channel can see (and change) which list they are on. Optional so the screen
  /// still renders where it isn't threaded (e.g. the i18n widget test).
  final Widget? playlistSwitcher;

  @override
  State<LiveRedesign> createState() => _LiveRedesignState();
}

class _LiveRedesignState extends State<LiveRedesign> {
  int _catIndex = 0;

  /// Instant, offline channel filter. Everything is already in memory, so a
  /// non-empty query filters channels by name across ALL categories, bypassing
  /// the selected-category index.
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  /// One [GlobalKey] per category chip, so selecting a chip can scroll it into
  /// view. The list is grown lazily in [build] to match the chip count, which
  /// depends on the active playlist's categories.
  final List<GlobalKey> _chipKeys = [];

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// Select a category chip and scroll it fully into view. With many provider
  /// categories the horizontal row overflows, so the selected chip — the label
  /// the user just acted on — would otherwise stay clipped at the edge. Mirrors
  /// the search screen's filter-chip behaviour.
  void _selectCategory(int i) {
    setState(() => _catIndex = i);
    if (i < 0 || i >= _chipKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: const Duration(milliseconds: 250));
      }
    });
  }

  /// Opens the searchable category picker for large playlists and applies the
  /// pick (which also scrolls the matching chip into view).
  Future<void> _openCategoryPicker(List<String> labels) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (_) => _CategoryPickerSheet(
        labels: labels,
        activeIndex: _catIndex,
      ),
    );
    if (picked != null) _selectCategory(picked);
  }

  /// All channels across the real categories, deduped by id — the same dedup as
  /// the "Todos" chip, with the all-sentinel fallback for playlists that keep
  /// everything on the sentinel category.
  List<ContentItem> _allChannels(List<CategoryViewModel> realCats) {
    final seen = <String>{};
    final out = [
      for (final c in realCats)
        for (final it in c.contentItems)
          if (seen.add(it.id)) it,
    ];
    if (out.isEmpty) {
      for (final c in widget.liveCategories) {
        for (final it in c.contentItems) {
          if (seen.add(it.id)) out.add(it);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    // Real categories (drop the synthetic "all" sentinel for the chip row;
    // index 0 = Todos aggregates everything).
    final realCats = widget.liveCategories
        .where((c) => !isAllCategorySentinel(c.category.categoryId))
        .toList();
    final chips = ['Todos', ...realCats.map((c) => c.category.categoryName)];
    // One key per chip so _selectCategory can scroll the active one into view.
    while (_chipKeys.length < chips.length) {
      _chipKeys.add(GlobalKey());
    }
    // Display labels (chip 0 is the localized "all" sentinel), reused by the
    // jump-to-category picker so its list and the chip row read identically.
    final chipLabels = [
      context.loc.all,
      ...realCats.map((c) => c.category.categoryName),
    ];
    // A jump-to-category affordance only earns its space once the chip row can
    // no longer show everything at a glance. Below the threshold the row alone
    // is less cluttered.
    final showCategoryPicker = realCats.length > 8;

    final query = _query.trim();
    List<ContentItem> channels;
    if (query.isNotEmpty) {
      // Filter channels by name across every category, bypassing the selected
      // chip. Empty result falls through to the existing no_channels state.
      final lower = query.toLowerCase();
      channels = _allChannels(realCats)
          .where((it) => it.name.toLowerCase().contains(lower))
          .toList();
    } else if (_catIndex == 0) {
      channels = _allChannels(realCats);
    } else {
      channels = realCats[_catIndex - 1].contentItems;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // safeInset, not a hand-written 20: this screen was left out of the overscan
            // pass, so the focused row drew from x=0 to the panel edge and its ring
            // was cropped on a real TV.
            padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.safeInset(context), 8,
                ResponsiveHelper.safeInset(context), 12),
              child: Row(
                children: [
                  // Title + the active playlist, right next to it — parity with
                  // the Home header — so a channel search can't leave the user
                  // unsure which list they are on. Expanded takes the free space
                  // and the switcher's own ellipsis keeps a long name from
                  // overflowing on a narrow phone; the live indicator stays
                  // pinned to the right.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(context.loc.live,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Bricolage Grotesque',
                                  fontSize: AppThemes.h2Size,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (widget.playlistSwitcher != null) ...[
                          const SizedBox(width: 4),
                          Flexible(child: widget.playlistSwitcher!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Just the live pulse dot — the section is already titled
                      // "En vivo" on the left, so repeating the word here (now
                      // beside the playlist switcher) only read as clutter.
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: r.live,
                          boxShadow: [
                            BoxShadow(
                                color: r.live.withValues(alpha: 0.35),
                                blurRadius: 0,
                                spreadRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Instant channel filter. Wrapped in TvFieldTraversal so the D-pad
            // can escape the field (DOWN into the grid, BACK/escape to blur) on
            // a 10-foot screen. autofocus:false so the screen opens on content,
            // not the keyboard.
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                  ResponsiveHelper.safeInset(context), 0,
                  ResponsiveHelper.safeInset(context), 12),
              child: TvFieldTraversal(
                child: TextField(
                  controller: _filter,
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: context.loc.search,
                    prefixIcon: Icon(Icons.search, color: r.text3),
                    filled: true,
                    fillColor: r.surface2,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: r.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: r.hairline),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  // Jump-to-category trigger, only for large playlists. D-pad
                  // focusable (FocusHighlight, like the Browse search button)
                  // and RTL-aware (EdgeInsetsDirectional).
                  if (showCategoryPicker)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                          start: ResponsiveHelper.safeInset(context), end: 4),
                      child: _CategoryPickerButton(
                        onTap: () => _openCategoryPicker(chipLabels),
                      ),
                    ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // No leading gutter once the picker button already carries
                      // the safe inset; keep the trailing one so the last chip
                      // is never flush against the edge.
                      padding: EdgeInsetsDirectional.only(
                          start: showCategoryPicker
                              ? 0
                              : ResponsiveHelper.safeInset(context),
                          end: ResponsiveHelper.safeInset(context)),
                      itemCount: chips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => KeyedSubtree(
                        key: _chipKeys[i],
                        child: RensiChip(
                          // First chip is the "all categories" sentinel.
                          label: chipLabels[i],
                          active: _catIndex == i,
                          onTap: () => _selectCategory(i),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: channels.isEmpty
                  ? Center(
                      child: Text(context.loc.no_channels,
                          style: TextStyle(color: r.text3)))
                  // Two columns wherever there is room. One column showed four
                  // channels on a 960dp TV, where Plex and Google TV show 8-12;
                  // a 200-channel playlist was 45 presses of DOWN to reach the
                  // middle. The ~600dp of dead space in the middle of each row
                  // is what pays for the second column.
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                          ResponsiveHelper.safeInset(context), 4,
                          ResponsiveHelper.safeInset(context), 24),
                      gridDelegate:
                          SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent:
                            ResponsiveHelper.useNavigationRail(context)
                                ? 460
                                : double.infinity,
                        mainAxisExtent: 92,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 11,
                      ),
                      itemCount: channels.length,
                      itemBuilder: (_, i) => _ChannelRow(
                        epgService: widget.epgService,
                        item: channels[i],
                        index: i,
                        autofocus: i == 0,
                        onTap: () => widget.onPlay(channels[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "jump to category" trigger shown beside the chip row on large
/// playlists. Kept D-pad focusable via [FocusHighlight] (matching the Browse
/// search button) so a 10-foot remote can reach it, and tooltipped/labelled
/// with the existing `categories` string.
class _CategoryPickerButton extends StatelessWidget {
  const _CategoryPickerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return Semantics(
      button: true,
      label: context.loc.categories,
      excludeSemantics: true,
      child: Tooltip(
        message: context.loc.categories,
        child: FocusHighlight(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: r.hairline),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.category_outlined, size: 21, color: r.text2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Searchable bottom sheet listing every category, for playlists with too many
/// to scan on the chip row. Returns the chosen chip index (0 = the "all"
/// sentinel) via [Navigator.pop]; the chip row stays for quick access.
class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({required this.labels, required this.activeIndex});

  /// Display labels aligned with the chip row: index 0 is the localized "all"
  /// sentinel, the rest are provider category names.
  final List<String> labels;
  final int activeIndex;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final q = _query.trim().toLowerCase();
    // Keep original indices so a filtered pick still maps to the right chip.
    final entries = [
      for (var i = 0; i < widget.labels.length; i++)
        if (q.isEmpty || widget.labels[i].toLowerCase().contains(q)) i,
    ];
    final pad = ResponsiveHelper.safeInset(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Padding(
      // Lift the sheet above the on-screen keyboard while searching.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle.
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: r.hairline2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(pad, 6, pad, 10),
                child: Text(
                  context.loc.categories,
                  style: TextStyle(
                    fontFamily: 'Bricolage Grotesque',
                    fontSize: AppThemes.h3Size,
                    fontWeight: FontWeight.w800,
                    color: onSurface,
                  ),
                ),
              ),
              // Searchable list — same field pattern as the channel filter,
              // wrapped in TvFieldTraversal so the D-pad can escape it.
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(pad, 0, pad, 10),
                child: TvFieldTraversal(
                  child: TextField(
                    controller: _search,
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: context.loc.search,
                      prefixIcon: Icon(Icons.search, color: r.text3),
                      filled: true,
                      fillColor: r.surface2,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: r.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: r.hairline),
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: entries.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(pad),
                        child: Text(context.loc.search_no_results,
                            style: TextStyle(color: r.text3)),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final idx = entries[i];
                          final active = idx == widget.activeIndex;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: FocusHighlight(
                              borderRadius: BorderRadius.circular(12),
                              child: Material(
                                color: active
                                    ? r.surface2
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: r.hairline),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  autofocus: i == 0,
                                  onTap: () => Navigator.of(context).pop(idx),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.labels[idx],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: AppThemes.bodySmallSize,
                                              fontWeight: active
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color:
                                                  active ? onSurface : r.text2,
                                            ),
                                          ),
                                        ),
                                        if (active)
                                          Icon(Icons.check,
                                              size: 18, color: r.accent),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.item,
    required this.index,
    required this.onTap,
    this.autofocus = false,
    this.epgService,
  });
  final ContentItem item;
  final int index;
  final VoidCallback onTap;
  final bool autofocus;
  final EpgService? epgService;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return FocusHighlight(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: r.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          autofocus: autofocus,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: SizedBox(
                    width: 92,
                    height: 64,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        item.imagePath.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.imagePath,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    Container(color: r.surface3),
                              )
                            : Container(color: r.surface3),
                        Positioned(
                          left: 5,
                          bottom: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'CH ${(index + 1).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                  fontSize: AppThemes.labelSize,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Bricolage Grotesque',
                                  fontSize: AppThemes.bodySmallSize,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          // The per-row "EN VIVO" badge was removed: in a list
                          // where every item is live it discriminated nothing,
                          // used different wording from the header, and was the
                          // only saturated colour on screen five times over.
                          // Its space now carries what is actually on.
                        ],
                      ),
                      // Real EPG now, so the progress bar means something. A
                      // previous version rejected a fixed 50% bar for exactly
                      // the right reason: without data it made every channel
                      // look half-watched. NowPlayingLine renders nothing when
                      // the panel has no usable listing, so a channel without
                      // EPG still looks like one.
                      if (epgService != null)
                        NowPlayingLine(
                          streamId: item.id,
                          service: epgService!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
