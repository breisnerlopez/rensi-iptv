import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/widgets/save_to_list_button.dart';
import '../../models/content_type.dart';
import '../../models/playlist_content_model.dart';

/// In-player "save to My List" toggle. Delegates the icon/colour/toggle
/// logic entirely to the shared [SaveToListButton] — this widget's only job
/// is tracking which [ContentItem] is currently playing (via [PlayerState]
/// + the `player_content_item` event) and deciding whether the toggle
/// should be shown at all (live TV and VOD only, not series episodes).
class VideoFavoriteWidget extends StatefulWidget {
  const VideoFavoriteWidget({super.key});

  @override
  State<VideoFavoriteWidget> createState() => _VideoFavoriteWidgetState();
}

class _VideoFavoriteWidgetState extends State<VideoFavoriteWidget> {
  StreamSubscription? _contentItemSubscription;

  @override
  void initState() {
    super.initState();

    // ContentItem değiştiğinde (yeni bölüm/kanal) yeniden çiz — SaveToListButton
    // kendi didUpdateWidget'ında yeni item için favori durumunu tazeler.
    _contentItemSubscription = EventBus()
        .on<ContentItem>('player_content_item')
        .listen((ContentItem item) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _contentItemSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentContent = PlayerState.currentContent;

    // Sadece canlı yayın ve filmler için göster
    if (currentContent == null ||
        (currentContent.contentType != ContentType.liveStream &&
            currentContent.contentType != ContentType.vod)) {
      return const SizedBox.shrink();
    }

    return SaveToListButton(item: currentContent, overArtwork: true);
  }
}
