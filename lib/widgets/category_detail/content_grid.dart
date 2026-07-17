import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

/// Poster grid for "See all" / category detail. Uses the modern [RensiPoster]
/// (brand tokens, title BELOW the poster — not the old ContentCard with a black
/// bar over the image) so this screen matches Explorar / the design system.
class ContentGrid extends StatelessWidget {
  final List<ContentItem> items;
  final Function(ContentItem) onItemTap;

  const ContentGrid({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final tv = ResponsiveHelper.isDesktopOrTV(context);
    final sidePad = tv ? 48.0 : 16.0;
    final gap = tv ? 16.0 : 12.0;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(sidePad, 12, sidePad, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ResponsiveHelper.getCrossAxisCount(context),
        // Poster proportion + room for the title/subtitle below.
        childAspectRatio: 1 / 1.48,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => RensiPoster(
        item: items[index],
        width: double.infinity,
        autofocus: index == 0,
        onTap: () => onItemTap(items[index]),
      ),
    );
  }
}
