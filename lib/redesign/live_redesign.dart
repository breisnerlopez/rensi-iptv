import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// "En vivo" — channel rows (logo + name + category) grouped by category
/// chips. The backend doesn't expose now/next EPG for this provider, so the
/// rows show the channel + live badge instead of a programme guide.
class LiveRedesign extends StatefulWidget {
  const LiveRedesign({
    super.key,
    required this.liveCategories,
    required this.onPlay,
  });

  final List<CategoryViewModel> liveCategories;
  final void Function(ContentItem) onPlay;

  @override
  State<LiveRedesign> createState() => _LiveRedesignState();
}

class _LiveRedesignState extends State<LiveRedesign> {
  int _catIndex = 0;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    // Real categories (drop the synthetic "all" sentinel for the chip row;
    // index 0 = Todos aggregates everything).
    final realCats = widget.liveCategories
        .where((c) => !isAllCategorySentinel(c.category.categoryId))
        .toList();
    final chips = ['Todos', ...realCats.map((c) => c.category.categoryName)];

    List<ContentItem> channels;
    if (_catIndex == 0) {
      final seen = <String>{};
      channels = [
        for (final c in realCats)
          for (final it in c.contentItems)
            if (seen.add(it.id)) it,
      ];
      if (channels.isEmpty) {
        // fall back to whatever the all-sentinel holds
        for (final c in widget.liveCategories) {
          for (final it in c.contentItems) {
            if (seen.add(it.id)) channels.add(it);
          }
        }
      }
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('En vivo',
                      style: TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          fontSize: 26,
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
                      Text('EN DIRECTO',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: r.live)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => RensiChip(
                  label: chips[i],
                  active: _catIndex == i,
                  onTap: () => setState(() => _catIndex = i),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: channels.isEmpty
                  ? Center(
                      child: Text('Sin canales',
                          style: TextStyle(color: r.text3)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: channels.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 11),
                      itemBuilder: (_, i) => _ChannelRow(
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
  });
  final ContentItem item;
  final int index;
  final VoidCallback onTap;
  final bool autofocus;

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
                                  fontSize: 9.5,
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text('● EN VIVO',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: r.live)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      RensiProgress(value: 0.5, height: 3),
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
