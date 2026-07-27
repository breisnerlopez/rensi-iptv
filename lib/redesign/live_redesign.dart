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
  });

  final List<CategoryViewModel> liveCategories;
  final void Function(ContentItem) onPlay;

  /// When present, each row shows what is on now and how far through it is.
  /// Optional so the screen still renders for M3U playlists, which have no
  /// Xtream panel to ask.
  final EpgService? epgService;

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

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.loc.live,
                      style: TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          fontSize: AppThemes.h2Size,
                          fontWeight: FontWeight.w800)),
                  Row(
                    children: [
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
                      const SizedBox(width: 8),
                      Text(context.loc.live,
                          style: TextStyle(
                              fontSize: AppThemes.labelSize,
                              fontWeight: FontWeight.w700,
                              color: r.live)),
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
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.safeInset(context)),
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => RensiChip(
                  // First chip is the "all categories" sentinel; localize it.
                  label: i == 0 ? context.loc.all : chips[i],
                  active: _catIndex == i,
                  onTap: () => setState(() => _catIndex = i),
                ),
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
