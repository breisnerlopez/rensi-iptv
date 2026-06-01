import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';

import 'content_item_card_widget.dart';

class CategorySection extends StatelessWidget {
  final CategoryViewModel category;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback? onSeeAllTap;
  final Function(ContentItem)? onContentTap;

  const CategorySection({
    super.key,
    required this.category,
    required this.cardWidth,
    required this.cardHeight,
    this.onSeeAllTap,
    this.onContentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SelectableText(
                    _displayTitle(context),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Text(
                    context.loc.see_all,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          ContentItemCardWidget(
            cardHeight: cardHeight,
            cardWidth: cardWidth,
            onContentTap: onContentTap,
            contentItems: category.contentItems,
            isSelectionModeEnabled: false,
            key: key,
          ),
        ],
      ),
    );
  }

  /// Returns the localised title when this section is the "View all"
  /// pseudo-category, otherwise falls back to the raw category name.
  String _displayTitle(BuildContext context) {
    if (!isAllCategorySentinel(category.category.categoryId)) {
      return category.category.categoryName;
    }
    switch (category.category.type) {
      case CategoryType.vod:
        return context.loc.view_all_movies;
      case CategoryType.series:
        return context.loc.view_all_series;
      case CategoryType.live:
        return context.loc.view_all_live;
    }
  }
}
