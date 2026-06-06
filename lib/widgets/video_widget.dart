import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/widgets/player-buttons/back_button_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_channel_selector_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_favorite_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_info_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/sleep_timer_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_settings_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_title_widget.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoWidget extends StatefulWidget {
  final VideoController controller;
  final SubtitleViewConfiguration subtitleViewConfiguration;

  const VideoWidget({
    super.key,
    required this.controller,
    required this.subtitleViewConfiguration,
  });

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  bool _brightnessGesture = false;
  bool _volumeGesture = false;
  bool _seekGesture = false;
  bool _speedUpOnLongPress = true;
  bool _seekOnDoubleTap = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final brightnessGesture = await UserPreferences.getBrightnessGesture();
    final volumeGesture = await UserPreferences.getVolumeGesture();
    final seekGesture = await UserPreferences.getSeekGesture();
    final speedUpOnLongPress = await UserPreferences.getSpeedUpOnLongPress();
    final seekOnDoubleTap = await UserPreferences.getSeekOnDoubleTap();
    if (mounted) {
      setState(() {
        _brightnessGesture = brightnessGesture;
        _volumeGesture = volumeGesture;
        _seekGesture = seekGesture;
        _speedUpOnLongPress = speedUpOnLongPress;
        _seekOnDoubleTap = seekOnDoubleTap;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Keep the on-video controls clear of the status bar / gesture-nav area
    // when playing inline (non-fullscreen) on a phone.
    final insets = MediaQuery.of(context).padding;

    // Live has no real timeline — hide the seek bar so it doesn't animate
    // constantly (and waste battery redrawing) when controls are shown.
    final isLive =
        PlayerState.currentContent?.contentType == ContentType.liveStream;

    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return MaterialVideoControlsTheme(
          normal: MaterialVideoControlsThemeData().copyWith(
            brightnessGesture: _brightnessGesture,
            volumeGesture: _volumeGesture,
            seekGesture: _seekGesture,
            speedUpOnLongPress: _speedUpOnLongPress,
            seekOnDoubleTap: _seekOnDoubleTap,
            topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoInfoWidget(),
            VideoChannelSelectorWidget(
              queue: PlayerState.queue,
              currentIndex: PlayerState.currentIndex,
            ),
            VideoFavoriteWidget(),
            SleepTimerWidget(),
            VideoSettingsWidget(),
          ],
          displaySeekBar: !isLive,
          topButtonBarMargin:
              EdgeInsets.only(top: insets.top + 8, left: 8, right: 8),
          bottomButtonBar: isLive
              ? const [Spacer(), _LiveBadge()]
              : const [MaterialPositionIndicator()],
          bottomButtonBarMargin:
              EdgeInsets.only(left: 16, right: 16, bottom: insets.bottom + 8),
          seekBarMargin:
              EdgeInsets.only(left: 16, right: 16, bottom: insets.bottom + 8),
        ),
        fullscreen: MaterialVideoControlsThemeData().copyWith(
          brightnessGesture: _brightnessGesture,
          volumeGesture: _volumeGesture,
          seekGesture: _seekGesture,
          speedUpOnLongPress: _speedUpOnLongPress,
          seekOnDoubleTap: _seekOnDoubleTap,
          topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoInfoWidget(),
            VideoChannelSelectorWidget(
              queue: PlayerState.queue,
              currentIndex: PlayerState.currentIndex,
            ),
            VideoFavoriteWidget(),
            SleepTimerWidget(),
            VideoSettingsWidget(),
          ],
          displaySeekBar: !isLive,
          bottomButtonBar: isLive
              ? const [Spacer(), _LiveBadge()]
              : const [MaterialPositionIndicator()],
          seekBarMargin: EdgeInsets.fromLTRB(0, 0, 0, 10),
        ),
        child: Scaffold(
          body: Video(
            controller: widget.controller,
            resumeUponEnteringForegroundMode: true,
            pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
            subtitleViewConfiguration: widget.subtitleViewConfiguration,
          ),
        ),
      );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return MaterialDesktopVideoControlsTheme(
          normal: MaterialDesktopVideoControlsThemeData().copyWith(
            modifyVolumeOnScroll: false,
            toggleFullscreenOnDoublePress: true,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoFavoriteWidget(),
              SleepTimerWidget(),
              VideoSettingsWidget(),
            ],
          ),
          fullscreen: MaterialDesktopVideoControlsThemeData().copyWith(
            modifyVolumeOnScroll: false,
            toggleFullscreenOnDoublePress: true,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoFavoriteWidget(),
              SleepTimerWidget(),
              VideoSettingsWidget(),
            ],
          ),
          child: Scaffold(
            body: Video(
              controller: widget.controller,
              resumeUponEnteringForegroundMode: true,
              pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
              subtitleViewConfiguration: widget.subtitleViewConfiguration,
            ),
          ),
        );
      default:
        return Video(
          controller: widget.controller,
          controls: NoVideoControls,
          resumeUponEnteringForegroundMode: true,
          pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
          subtitleViewConfiguration: widget.subtitleViewConfiguration,
        );
    }
  }
}

// Backward compatibility wrapper
Widget getVideo(
  BuildContext context,
  VideoController controller,
  SubtitleViewConfiguration subtitleViewConfiguration,
) {
  return VideoWidget(
    controller: controller,
    subtitleViewConfiguration: subtitleViewConfiguration,
  );
}

/// Small static "EN VIVO" badge used instead of the seek bar for live
/// streams (which have no meaningful timeline).
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE0E0563E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, size: 10, color: Colors.white),
          SizedBox(width: 6),
          Text('EN VIVO',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
