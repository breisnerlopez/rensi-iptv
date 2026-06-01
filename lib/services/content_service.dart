import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/repositories/m3u_repository.dart';
import 'package:rensi_iptv/services/app_state.dart';
import '../models/category_type.dart';

class ContentService {
  Future<List<ContentItem>> fetchContentByCategory(
    CategoryViewModel category,
  ) async {
    final categoryId = category.category.categoryId;
    try {
      switch (AppState.currentPlaylist!.type) {
        case PlaylistType.xtream:
          return await _fetchXtreamContent(category.category.type, categoryId);
        case PlaylistType.m3u:
          return await _fetchM3uContent(category.category.type, categoryId);
      }
    } catch (e) {
      throw Exception('İçerik yüklenirken hata oluştu: $e');
    }
  }

  Future<List<ContentItem>> _fetchXtreamContent(
    CategoryType type,
    String categoryId,
  ) async {
    final repository = AppState.xtreamCodeRepository!;
    // The "View all" pseudo-category aggregates every item of its type, so
    // we omit category_id from the repository call.
    final bool isAll = isAllCategorySentinel(categoryId);
    final String? scopedCategoryId = isAll ? null : categoryId;
    final List<ContentItem> items = await _fetchXtreamContentInner(
      type,
      repository,
      scopedCategoryId,
    );
    // Drop junk rows from the aggregated view: some providers ship
    // VOD/Series entries with an empty title that render as blank cards.
    // For a real category we still show them — the user explicitly picked
    // that category and may want to know it has malformed data.
    if (!isAll) return items;
    return items.where((it) => it.name.trim().isNotEmpty).toList();
  }

  Future<List<ContentItem>> _fetchXtreamContentInner(
    CategoryType type,
    IptvRepository repository,
    String? scopedCategoryId,
  ) async {
    switch (type) {
      case CategoryType.live:
        return await _fetchGenericContent(
          () => scopedCategoryId == null
              ? repository.getLiveChannels()
              : repository.getLiveChannelsByCategoryId(
                  categoryId: scopedCategoryId,
                ),
          ContentType.liveStream,
          (item) => ContentItem(
            item.streamId,
            item.name,
            item.streamIcon,
            ContentType.liveStream,
            liveStream: item,
          ),
          'Canlı kanallar yüklenirken hata',
        );
      case CategoryType.vod:
        return await _fetchGenericContent(
          () => repository.getMovies(categoryId: scopedCategoryId),
          ContentType.vod,
          (item) => ContentItem(
            item.streamId,
            item.name,
            item.streamIcon,
            ContentType.vod,
            containerExtension: item.containerExtension,
            vodStream: item,
          ),
          'Filmler yüklenirken hata',
        );
      case CategoryType.series:
        return await _fetchGenericContent(
          () => repository.getSeries(categoryId: scopedCategoryId),
          ContentType.series,
          (item) => ContentItem(
            item.seriesId,
            item.name,
            item.cover ?? '',
            ContentType.series,
            seriesStream: item,
          ),
          'Diziler yüklenirken hata',
        );
    }
  }

  Future<List<ContentItem>> _fetchM3uContent(
    CategoryType type,
    String categoryId,
  ) async {
    final repository = M3uRepository();
    switch (type) {
      case CategoryType.live:
        return await _fetchGenericContent(
          () => repository.getM3uItemsByCategoryId(
            categoryId: categoryId,
            contentType: ContentType.liveStream,
          ),
          ContentType.liveStream,
          (item) => ContentItem(
            item.url,
            item.name ?? 'NO NAME',
            item.tvgLogo ?? '',
            ContentType.liveStream,
            m3uItem: item,
          ),
          'M3U canlı kanallar yüklenirken hata',
        );
      case CategoryType.vod:
        return await _fetchGenericContent(
          () => repository.getM3uItemsByCategoryId(
            categoryId: categoryId,
            contentType: ContentType.vod,
          ),
          ContentType.vod,
          (item) => ContentItem(
            item.url,
            item.name ?? 'NO NAME',
            item.tvgLogo ?? '',
            ContentType.vod,
            m3uItem: item,
          ),
          'M3U filmler yüklenirken hata',
        );
      case CategoryType.series:
        return await _fetchGenericContent(
          () => repository.getSeriesByCategoryId(categoryId: categoryId),
          ContentType.series,
          (item) =>
              ContentItem(item.seriesId, item.name, '', ContentType.series),
          'M3U diziler yüklenirken hata',
        );
    }
  }

  Future<List<ContentItem>> _fetchGenericContent<T>(
    Future<List<T>?> Function() fetchFunction,
    ContentType contentType,
    ContentItem Function(T) mapper,
    String errorMessage,
  ) async {
    try {
      final result = await fetchFunction();
      if (result == null) return <ContentItem>[];
      return result.map(mapper).toList();
    } catch (e) {
      throw Exception('$errorMessage: $e');
    }
  }
}
