import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/utils/build_media_url.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';

class ContentItem {
  final String id;
  late String url;
  final String name;
  final String imagePath;
  final String? description;
  final Duration? duration;
  final String? coverPath;
  final String? containerExtension;
  final ContentType contentType;
  final LiveStream? liveStream;
  final VodStream? vodStream;
  final SeriesStream? seriesStream;
  final int? season;
  final M3uItem? m3uItem;

  ContentItem(
    this.id,
    this.name,
    this.imagePath,
    this.contentType, {
    this.description,
    this.duration,
    this.coverPath,
    this.containerExtension,
    this.liveStream,
    this.vodStream,
    this.seriesStream,
    this.season,
    this.m3uItem,
  }) {
    url = isXtreamCode ? buildMediaUrl(this) : m3uItem?.url ?? id;
  }
}
