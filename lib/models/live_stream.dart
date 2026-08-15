import 'package:drift/drift.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/utils/type_convertions.dart';

class LiveStream {
  final String streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String epgChannelId;
  final String? playlistId;

  /// Catch-up: 1 when the provider keeps an archive for this channel, else 0.
  final int tvArchive;

  /// How many days of archive the provider retains (0 when none).
  final int tvArchiveDuration;

  /// Whether this channel supports timeshift/catch-up playback.
  bool get hasArchive => tvArchive > 0 && tvArchiveDuration > 0;

  LiveStream({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.epgChannelId,
    this.playlistId,
    this.tvArchive = 0,
    this.tvArchiveDuration = 0,
  });

  factory LiveStream.fromJson(Map<String, dynamic> json, String playlistId) {
    return LiveStream(
      streamId: safeString(json['stream_id']),
      name: safeString(json['name']),
      streamIcon: safeString(json['stream_icon']),
      categoryId: safeString(json['category_id']),
      epgChannelId: safeString(json['epg_channel_id']),
      playlistId: safeString(playlistId),
      tvArchive: _asInt(json['tv_archive']),
      tvArchiveDuration: _asInt(json['tv_archive_duration']),
    );
  }

  factory LiveStream.fromDriftLiveStream(LiveStreamsData driftLiveStream) {
    return LiveStream(
      streamId: driftLiveStream.streamId,
      name: driftLiveStream.name,
      streamIcon: driftLiveStream.streamIcon,
      categoryId: driftLiveStream.categoryId,
      epgChannelId: driftLiveStream.epgChannelId,
      playlistId: driftLiveStream.playlistId,
      tvArchive: driftLiveStream.tvArchive,
      tvArchiveDuration: driftLiveStream.tvArchiveDuration,
    );
  }

  LiveStreamsCompanion toDriftCompanion(String playlistId) {
    return LiveStreamsCompanion(
      streamId: Value(streamId),
      name: Value(name),
      streamIcon: Value(streamIcon),
      categoryId: Value(categoryId),
      epgChannelId: Value(epgChannelId),
      playlistId: Value(playlistId),
      tvArchive: Value(tvArchive),
      tvArchiveDuration: Value(tvArchiveDuration),
    );
  }

  /// Xtream returns these as either ints or numeric strings ("0"/"1"/"7").
  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }
}
