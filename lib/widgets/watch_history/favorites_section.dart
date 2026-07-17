import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/favorite.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/navigate_by_content_type.dart';
import 'package:rensi_iptv/utils/build_media_url.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import '../../repositories/favorites_repository.dart';

class FavoritesSection extends StatelessWidget {
  final List<Favorite> favorites;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback? onSeeAllTap;
  final Function(Favorite)? onFavoriteRemove;

  const FavoritesSection({
    super.key,
    required this.favorites,
    required this.cardWidth,
    required this.cardHeight,
    this.onSeeAllTap,
    this.onFavoriteRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) {
      return SizedBox.shrink();
    }

    final recentFavorites = favorites.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.loc.favorites,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (onSeeAllTap != null && favorites.length > 10)
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Text(context.loc.see_all_favorites),
                ),
            ],
          ),
        ),
        SizedBox(
          height: cardWidth * 1.48 + 16,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12),
            itemCount: recentFavorites.length,
            itemBuilder: (context, index) {
              final favorite = recentFavorites[index];
              return _buildFavoriteCard(context, favorite);
            },
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFavoriteCard(BuildContext context, Favorite favorite) {
    final h = cardWidth * 1.48; // matches RensiPoster's intrinsic height
    return Container(
      width: cardWidth,
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        children: [
          // RensiPoster brings its own FocusHighlight ring, so it isn't wrapped
          // in another one (that would double the ring).
          FutureBuilder<ContentItem?>(
            future: _getContentItemFromFavorite(favorite),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  width: cardWidth,
                  height: h,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              final contentItem =
                  snapshot.data ?? _convertFavoriteToContentItem(favorite);

              return RensiPoster(
                item: contentItem,
                width: cardWidth,
                onTap: () => _navigateToContent(context, contentItem),
              );
            },
          ),
          if (onFavoriteRemove != null)
            Positioned(
              top: 8,
              right: 8,
              // Focusable so the D-pad can remove a favorite on Android TV.
              child: FocusHighlight(
                borderRadius: BorderRadius.circular(12),
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    onPressed: () => onFavoriteRemove?.call(favorite),
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: 'Quitar de favoritos',
                    icon: const Icon(Icons.favorite, color: Colors.red),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ContentItem _convertFavoriteToContentItem(Favorite favorite) {
    if (isXtreamCode) {
      switch (favorite.contentType) {
        case ContentType.liveStream:
          final liveStream = LiveStream(
            streamId: favorite.streamId,
            name: favorite.name,
            streamIcon: favorite.imagePath ?? '',
            categoryId: '',
            epgChannelId: '',
          );
          return ContentItem(
            favorite.streamId,
            favorite.name,
            favorite.imagePath ?? '',
            favorite.contentType,
            liveStream: liveStream,
          );

        case ContentType.vod:
          final vodStream = VodStream(
            streamId: favorite.streamId,
            name: favorite.name,
            streamIcon: favorite.imagePath ?? '',
            categoryId: '',
            rating: '',
            rating5based: 0.0,
            containerExtension: '',
            createdAt: DateTime.now(),
          );
          return ContentItem(
            favorite.streamId,
            favorite.name,
            favorite.imagePath ?? '',
            favorite.contentType,
            vodStream: vodStream,
          );

        case ContentType.series:
          final seriesStream = SeriesStream(
            seriesId: favorite.streamId,
            name: favorite.name,
            cover: favorite.imagePath ?? '',
            categoryId: '',
            playlistId: favorite.playlistId,
          );
          return ContentItem(
            favorite.streamId,
            favorite.name,
            favorite.imagePath ?? '',
            favorite.contentType,
            seriesStream: seriesStream,
          );
      }
    }
    else if (isM3u) {
      final m3uItem = M3uItem(
        id: favorite.m3uItemId ?? favorite.streamId,
        playlistId: favorite.playlistId,
        url: favorite.streamId,
        contentType: favorite.contentType,
        name: favorite.name,
        tvgLogo: favorite.imagePath,
      );
      return ContentItem(
        favorite.streamId,
        favorite.name,
        favorite.imagePath ?? '',
        favorite.contentType,
        m3uItem: m3uItem,
      );
    }

    return ContentItem(
      favorite.streamId,
      favorite.name,
      favorite.imagePath ?? '',
      favorite.contentType,
    );
  }

  Future<ContentItem?> _getContentItemFromFavorite(Favorite favorite) async {
    final repository = FavoritesRepository();
    return await repository.getContentItemFromFavorite(favorite);
  }

  void _navigateToContent(BuildContext context, ContentItem contentItem) {
    navigateByContentType(context, contentItem);
  }
}
