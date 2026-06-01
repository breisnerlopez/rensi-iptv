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
      // import order. Verified empirically against newlatam.mx, which
      // ships `added` but leaves `created_at` null on every row.
      createdAt: safeDateTime(json['added']) ??
          safeDateTime(json['created_at']),
      youtubeTrailer: safeString(json['youtube_trailer']),
      genre: safeString(json['genre']),
    );
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
    );
  }
}
