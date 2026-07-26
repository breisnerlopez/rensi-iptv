import 'package:rensi_iptv/widgets/tv/tv_field_traversal.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:rensi_iptv/utils/app_themes.dart';

class VideoSettingsWidget extends StatefulWidget {
  const VideoSettingsWidget({super.key});

  @override
  State<VideoSettingsWidget> createState() => _VideoSettingsWidgetState();

  static void hideOverlay() {
    _VideoSettingsWidgetState.hideOverlay();
  }
}

class _VideoSettingsWidgetState extends State<VideoSettingsWidget> {
  static OverlayEntry? _globalOverlayEntry;
  static StreamSubscription? _globalToggleSubscription;
  static BuildContext? _globalContext;

  static void hideOverlay() {
    _globalOverlayEntry?.remove();
    _globalOverlayEntry = null;
    PlayerState.showVideoSettings = false;
  }

  @override
  void initState() {
    super.initState();
    _globalContext = context;

    _globalToggleSubscription ??=
        EventBus().on<bool>('toggle_video_settings').listen((bool show) {
      if (show) {
        if (_globalContext != null) {
          _showSettings(_globalContext!);
        }
      } else {
        hideOverlay();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _globalContext = context;
    return IconButton(
      icon: const Icon(Icons.settings, color: Colors.white),
      onPressed: () {
        if (_globalOverlayEntry == null) {
          _showSettings(context);
        } else {
          hideOverlay();
        }
      },
    );
  }

  void _showSettings(BuildContext context) {
    if (_globalOverlayEntry != null) return;

    final overlayContext = _globalContext ?? context;
    OverlayState? overlay;
    try {
      overlay = Overlay.of(overlayContext, rootOverlay: true);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_globalOverlayEntry == null) {
          _showSettings(overlayContext);
        }
      });
      return;
    }

    final screenWidth = MediaQuery.of(overlayContext).size.width;
    final panelWidth = (screenWidth / 3).clamp(200.0, 400.0);

    _globalOverlayEntry = OverlayEntry(
      opaque: false,
      maintainState: true,
      builder: (context) => _VideoSettingsOverlay(
        width: panelWidth,
        onClose: hideOverlay,
      ),
    );

    overlay.insert(_globalOverlayEntry!);
    PlayerState.showVideoSettings = true;
  }
}

class _VideoSettingsOverlay extends StatefulWidget {
  final double width;
  final VoidCallback onClose;

  const _VideoSettingsOverlay({
    required this.width,
    required this.onClose,
  });

  @override
  State<_VideoSettingsOverlay> createState() => _VideoSettingsOverlayState();
}

class _VideoSettingsOverlayState extends State<_VideoSettingsOverlay> {
  late StreamSubscription subscription;
  late StreamSubscription _trackChangeSubscription;

  // When the panel is opened by a long-press of OK, that OK key is still
  // physically held on open, and its trailing key-repeats would otherwise reach
  // the auto-focused Close button and dismiss the panel the instant it appears.
  // So we swallow OK/Enter until that opening press is released — BUT only when
  // OK was actually held at open. The panel can also be opened by Menu / the
  // audio-track key / a tap (no held OK); arming immediately there keeps the
  // first deliberate OK from being eaten. Decided in initState.
  bool _activateArmed = true;

  late List<VideoTrack> videoTracks;
  late List<AudioTrack> audioTracks;
  late List<SubtitleTrack> subtitleTracks;

  late String selectedVideoTrack;
  late String selectedAudioTrack;
  late String selectedSubtitleTrack;

  @override
  void initState() {
    super.initState();
    // If OK is physically held right now, the panel was opened by a long-press
    // of OK → disarm so its trailing repeats can't dismiss it; otherwise (Menu /
    // audio-track key / tap) arm immediately so the first OK works.
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final okHeld = pressed.contains(LogicalKeyboardKey.select) ||
        pressed.contains(LogicalKeyboardKey.enter) ||
        pressed.contains(LogicalKeyboardKey.numpadEnter);
    _activateArmed = !okHeld;
    _loadTracks();

    subscription = EventBus().on<Tracks>('player_tracks').listen((Tracks data) {
      if (mounted) {
        setState(() {
          videoTracks = data.video;
          audioTracks = data.audio;
          subtitleTracks = data.subtitle;
        });
      }
    });

    _trackChangeSubscription =
        EventBus().on<dynamic>('player_track_changed').listen((_) {
      if (mounted) {
        setState(() {
          selectedVideoTrack = PlayerState.selectedVideo.id;
          selectedAudioTrack = PlayerState.selectedAudio.id;
          selectedSubtitleTrack = PlayerState.selectedSubtitle.id;
        });
      }
    });
  }

  void _loadTracks() {
    videoTracks = PlayerState.videos;
    audioTracks = PlayerState.audios;
    subtitleTracks = PlayerState.subtitles;

    selectedVideoTrack = PlayerState.selectedVideo.id;
    selectedAudioTrack = PlayerState.selectedAudio.id;
    selectedSubtitleTrack = PlayerState.selectedSubtitle.id;
  }

  @override
  void dispose() {
    subscription.cancel();
    _trackChangeSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Colors.black.withOpacity(0.95);

    // The overlay lives in the root Overlay (outside the player's Focus), so it
    // must GRAB focus on open or the D-pad keeps driving the video behind it.
    // FocusScope + autofocus pulls focus into the panel; BACK closes it.
    return Positioned.fill(
      child: FocusScope(
        child: Focus(
          // canRequestFocus:false so this full-screen wrapper does NOT trap the
          // directional traversal — it only bubbles BACK to close. The first
          // actionable item (the close button) autofocuses to pull focus in.
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            final key = event.logicalKey;
            if (event is KeyDownEvent &&
                (key == LogicalKeyboardKey.goBack ||
                    key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.browserBack)) {
              widget.onClose();
              return KeyEventResult.handled;
            }
            // Swallow the still-held opening OK press (down + repeats) until it
            // is released, so it can't activate the auto-focused Close button
            // and flash the panel shut. Returning `handled` stops the event
            // bubbling to the app-level select→Activate shortcut.
            final isActivate = key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter;
            if (isActivate && !_activateArmed) {
              if (event is KeyUpEvent) _activateArmed = true;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: backgroundColor,
              elevation: 8,
              child: Container(
                width: widget.width,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: _buildMainSettings(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainSettings(BuildContext context) {
    final cardColor = Colors.black.withOpacity(0.8);
    const textColor = Colors.white;
    final dividerColor = Colors.grey[800]!;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(
              bottom: BorderSide(color: dividerColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.loc.settings,
                  style: TextStyle(
                    fontSize: AppThemes.bodySize,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                autofocus: true,
                icon: Icon(Icons.close, color: textColor, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTrackSectionGeneric<VideoTrack>(
                  context,
                  icon: Icons.video_settings,
                  title: context.loc.video_track,
                  tracks: videoTracks,
                  labelBuilder: _formatVideoTrack,
                  isSelected: (track) => track.id == selectedVideoTrack,
                  onTrackSelected: (track) {
                    EventBus().emit('video_track_changed', track);
                    if (mounted) {
                      setState(() {
                        selectedVideoTrack = track.id;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildTrackSectionGeneric<AudioTrack>(
                  context,
                  icon: Icons.audiotrack,
                  title: context.loc.audio_track,
                  tracks: audioTracks,
                  labelBuilder: _formatAudioTrack,
                  isSelected: (track) => track.id == selectedAudioTrack,
                  onTrackSelected: (track) {
                    EventBus().emit('audio_track_changed', track);
                    if (mounted) {
                      setState(() {
                        selectedAudioTrack = track.id;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildTrackSectionGeneric<SubtitleTrack>(
                  context,
                  icon: Icons.subtitles,
                  title: context.loc.subtitle_track,
                  tracks: subtitleTracks,
                  labelBuilder: _formatSubtitleTrack,
                  isSelected: (track) => track.id == selectedSubtitleTrack,
                  onTrackSelected: (track) {
                    EventBus().emit('subtitle_track_changed', track);
                    if (mounted) {
                      setState(() {
                        selectedSubtitleTrack = track.id;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildExternalSubtitleButton(context),
                const SizedBox(height: 16),
                _buildSpeedSection(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExternalSubtitleButton(BuildContext context) {
    return InkWell(
      onTap: () async {
        final controller = TextEditingController();
        final url = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(context.loc.external_subtitle),
            content: TvFieldTraversal(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://…/subtitulo.srt',
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(context.loc.cancel)),
              FilledButton(
                  onPressed: () => Navigator.pop(c, controller.text.trim()),
                  child: Text(context.loc.load)),
            ],
          ),
        );
        if (url != null && url.isNotEmpty) {
          EventBus().emit('load_external_subtitle_uri', url);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.subtitles_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(context.loc.external_subtitle_url,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: AppThemes.labelSize)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedSection(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.speed, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(context.loc.speed,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppThemes.labelSize,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final s in speeds)
              ActionChip(
                label: Text(s == 1.0 ? context.loc.normal : '${s}x'),
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                labelStyle: const TextStyle(color: Colors.white),
                onPressed: () =>
                    EventBus().emit('playback_speed_changed', s),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrackSectionGeneric<T>(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<T> tracks,
    required String Function(T) labelBuilder,
    required Function(T) onTrackSelected,
    required bool Function(T) isSelected,
  }) {
    const textColor = Colors.white;
    const secondaryTextColor = Colors.grey;
    final dividerColor = Colors.grey[800]!;
    const primaryColor = Colors.blue;
    final cardBackground = Colors.white.withOpacity(0.05);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: primaryColor),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppThemes.labelSize,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...tracks.map((track) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildTrackItem(
                    context,
                    title: labelBuilder(track),
                    isSelected: isSelected(track),
                    onTap: () => onTrackSelected(track),
                  ),
                )),
          ] else
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 8),
              child: Text(
                context.loc.no_tracks_available,
                style: TextStyle(
                  fontSize: AppThemes.tenFoot(context, 12),
                  color: secondaryTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(
    BuildContext context, {
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return _TrackItem(title: title, isSelected: isSelected, onTap: onTap);
  }

  String _formatVideoTrack(VideoTrack track) {
    if (track.id == 'auto') return 'Auto';
    if (track.id == 'no') return 'Disabled';

    final parts = <String>[];

    if (track.title != null && track.title!.isNotEmpty) {
      parts.add(track.title!);
    }

    if (track.w != null && track.h != null && track.w! > 0 && track.h! > 0) {
      parts.add('${track.w}x${track.h}');
    }

    if (track.fps != null && track.fps! > 0) {
      parts.add('${track.fps!.toStringAsFixed(2)} fps');
    }

    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!);
    }

    if (track.bitrate != null && track.bitrate! > 0) {
      parts.add('${(track.bitrate! / 1000).round()} kbps');
    }

    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' • ');
  }

  String _formatAudioTrack(AudioTrack track) {
    if (track.id == 'auto') return 'Auto';
    if (track.id == 'no') return 'Disabled';

    final parts = <String>[];

    if (track.title != null && track.title!.isNotEmpty) {
      parts.add(track.title!);
    }

    if (track.language != null && track.language!.isNotEmpty) {
      parts.add(track.language!);
    }

    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!);
    }

    if (track.channelscount != null && track.channelscount! > 0) {
      parts.add('${track.channelscount}ch');
    }

    if (track.samplerate != null && track.samplerate! > 0) {
      parts.add('${track.samplerate} Hz');
    }

    if (track.bitrate != null && track.bitrate! > 0) {
      parts.add('${(track.bitrate! / 1000).round()} kbps');
    }

    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' • ');
  }

  String _formatSubtitleTrack(SubtitleTrack track) {
    if (track.id == 'auto') return 'Auto';
    if (track.id == 'no') return 'Disabled';

    final parts = <String>[];

    if (track.title != null && track.title!.isNotEmpty) {
      parts.add(track.title!);
    }

    if (track.language != null && track.language!.isNotEmpty) {
      parts.add(track.language!);
    }

    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!);
    }

    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' • ');
  }
}

/// A track row in the audio/subtitle panel with a STRONG D-pad focus highlight.
/// The default InkWell focus tint was almost invisible on a TV, so the user
/// couldn't tell which option the remote was on. When focused it fills a bright
/// background and a thick white border; the blue "selected" (currently active)
/// state is drawn independently via a check + tint.
class _TrackItem extends StatefulWidget {
  const _TrackItem({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_TrackItem> createState() => _TrackItemState();
}

class _TrackItemState extends State<_TrackItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    const textColor = Colors.white;
    final dividerColor = Colors.grey[800]!;
    const primaryColor = Colors.blue;
    final selectedBackground = Colors.blue.withOpacity(0.18);
    final unselectedBackground = Colors.white.withOpacity(0.03);

    final Color bg = _focused
        ? Colors.white.withOpacity(0.22)
        : (widget.isSelected ? selectedBackground : unselectedBackground);
    final Color borderColor = _focused
        ? Colors.white
        : (widget.isSelected ? primaryColor : dividerColor);
    final double borderWidth = _focused
        ? 2.5
        : (widget.isSelected ? 1.5 : 0.5);

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6),
      onFocusChange: (f) {
        if (f != _focused) setState(() => _focused = f);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: AppThemes.tenFoot(context, 13),
                  fontWeight: (widget.isSelected || _focused)
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),
            if (widget.isSelected)
              const Icon(Icons.check_circle, color: primaryColor, size: 18),
          ],
        ),
      ),
    );
  }
}
