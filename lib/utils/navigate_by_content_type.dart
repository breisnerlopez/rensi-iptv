import 'package:rensi_iptv/screens/m3u/series/m3u_series_screen.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import '../screens/live_stream/live_stream_screen.dart';
import '../screens/m3u/m3u_player_screen.dart';
import '../screens/movies/movie_screen.dart';
import '../screens/series/series_screen.dart';

/// Like [navigateByContentType], but a "play" intent: a VOD item jumps straight
/// into playback (the Home hero / continue-watching row) instead of opening its
/// detail page. Live already plays; series still open their episode list (no
/// single episode to resume from a poster).
void playByContentType(BuildContext context, ContentItem content) {
  final isXtreamVod = content.contentType == ContentType.vod &&
      !(isM3u && content.m3uItem != null && content.m3uItem!.groupTitle == null);
  if (isXtreamVod) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieScreen(contentItem: content, autoPlay: true),
      ),
    );
    return;
  }
  navigateByContentType(context, content);
}

void navigateByContentType(BuildContext context, ContentItem content) {
  if (isM3u &&
      ((content.m3uItem != null && content.m3uItem!.groupTitle == null) ||
          content.contentType == ContentType.series)) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => M3uPlayerScreen(
          contentItem: ContentItem(
            content.m3uItem!.id,
            content.m3uItem!.name ?? '',
            content.m3uItem!.tvgLogo ?? '',
            content.m3uItem!.contentType,
            m3uItem: content.m3uItem!,
          ),
        ),
      ),
    );

    return;
  }

  switch (content.contentType) {
    case ContentType.liveStream:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LiveStreamScreen(content: content),
        ),
      );
    case ContentType.vod:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MovieScreen(contentItem: content),
        ),
      );
    case ContentType.series:
      if (isXtreamCode) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SeriesScreen(contentItem: content),
          ),
        );
      } else if (isM3u) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => M3uSeriesScreen(contentItem: content),
          ),
        );
      }
  }
}
