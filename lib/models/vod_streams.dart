import 'package:drift/drift.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/utils/type_convertions.dart';

class VodStream {
  final String streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String rating;
  final double rating5based;
  final String containerExtension;
  final String? playlistId;
  final DateTime? createdAt;
  final String? youtubeTrailer;
  final String? genre;

  /// The TMDb id the provider persisted for this movie, when present. May come
  /// from the bulk get_vod_streams list (some panels ship `tmdb_id`/`tmdb`) or
  /// be backfilled lazily from get_vod_info's `info.tmdb_id`. Null when unknown.
  final int? tmdbId;

  VodStream({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.rating,
    required this.rating5based,
    required this.containerExtension,
    this.playlistId,
    required this.createdAt,
    this.youtubeTrailer,
    this.genre,
    this.tmdbId,
  });

  factory VodStream.fromJson(Map<String, dynamic> json, String playlistId) {
    return VodStream(
      streamId: safeString(json['stream_id']),
      name: safeString(json['name']),
      streamIcon: safeString(json['stream_icon']),
      categoryId: safeString(json['category_id']),
      rating: safeString(json['rating']),
      rating5based: safeDouble(json['rating_5based']) ?? 0.0,
      containerExtension: safeString(json['container_extension']),
      playlistId: safeString(playlistId),
      // The canonical Xtream Codes field for "when this entry hit the
      // provider's catalogue" is `added` — a Unix epoch in seconds
      // encoded as a numeric string. A few providers also ship
      // `created_at`, so we try both. The original code looked up
      // `createdAt` (camelCase) which is never sent by any provider,
      // so every row used to land in the DB with the column default
      // (currentDateAndTime) and "Recently added" sort collapsed to
      // import order. Verified empirically against a real provider that
      // ships `added` but leaves `created_at` null on every row.
      createdAt: safeDateTime(json['added']) ??
          safeDateTime(json['created_at']),
      youtubeTrailer: safeString(json['youtube_trailer']),
      genre: safeString(json['genre']),
      // Some Xtream panels ship a tmdb id in the BULK list (as `tmdb_id`, a few
      // as `tmdb`); most only expose it in the per-item get_vod_info `info`
      // block, which the movie screen backfills lazily. safeInt yields 0 for
      // absent/unparseable — treat 0 as "no id" so it stays NULL, not 0.
      // Prefer whichever field yields a real id: `??` alone would keep an empty
      // `tmdb_id:""` and never fall through to a populated `tmdb`.
      tmdbId: _parseTmdbId(json['tmdb_id']) ?? _parseTmdbId(json['tmdb']),
    );
  }

  static int? _parseTmdbId(dynamic raw) {
    final v = safeInt(raw);
    return v > 0 ? v : null;
  }

  // Drift'ten VodStream oluşturmak için
  factory VodStream.fromDriftVodStream(VodStreamsData driftVodStream) {
    return VodStream(
      streamId: driftVodStream.streamId,
      name: driftVodStream.name,
      streamIcon: driftVodStream.streamIcon,
      categoryId: driftVodStream.categoryId,
      rating: driftVodStream.rating,
      rating5based: driftVodStream.rating5based,
      containerExtension: driftVodStream.containerExtension,
      playlistId: driftVodStream.playlistId,
      createdAt: driftVodStream.createdAt,
      genre: driftVodStream.genre,
      tmdbId: driftVodStream.tmdbId,
    );
  }

  // Drift'e kaydetmek için
  VodStreamsCompanion toDriftCompanion() {
    return VodStreamsCompanion(
      streamId: Value(streamId),
      name: Value(name),
      streamIcon: Value(streamIcon),
      categoryId: Value(categoryId),
      rating: Value(rating),
      rating5based: Value(rating5based),
      containerExtension: Value(containerExtension),
      playlistId: Value(playlistId ?? ''),
      // Persist the provider's created_at when we have it, otherwise let
      // Drift apply the currentDateAndTime default. Without this assignment
      // the column always defaulted to import-time, which collapsed the
      // Recently-added sort.
      createdAt: createdAt != null ? Value(createdAt!) : const Value.absent(),
      youtubeTrailer: Value(youtubeTrailer ?? ''),
      genre: Value(genre ?? ''),
      // Absent (not Value(null)) when unknown so an upsert never overwrites a
      // previously backfilled id with null; only write it when we actually have
      // one from the bulk list.
      tmdbId: tmdbId != null ? Value(tmdbId) : const Value.absent(),
    );
  }
}
