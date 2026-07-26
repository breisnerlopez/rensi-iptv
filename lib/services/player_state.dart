import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// --- FIX: ADD REQUIRED IMPORT ---
import '../models/playlist_content_model.dart';
// ---------------------------------

abstract class PlayerState {
  static List<VideoTrack> videos = [];
  static VideoTrack selectedVideo = VideoTrack.auto();

  static List<AudioTrack> audios = [];
  static AudioTrack selectedAudio = AudioTrack.auto();

  static List<SubtitleTrack> subtitles = [];
  static SubtitleTrack selectedSubtitle = SubtitleTrack.auto();

  // --- FIX: ADD GLOBAL CONTENT ITEM VARIABLE ---
  static ContentItem? currentContent;
  // ---------------------------------------------

  static List<ContentItem>? queue;
  static int currentIndex = 0;

  /// True while a PlayerWidget is mounted. Reliable (set in initState, cleared
  /// in dispose) — unlike [currentContent], which is never nulled. Used to skip
  /// a background catalogue refresh while the user is watching (incl. PiP).
  static bool isPlayerActive = false;
  static bool showChannelList = false;
  static bool showVideoInfo = false;
  static bool showVideoSettings = false;

  static String title = '';
  static bool backgroundPlay = true;
  static SubtitleViewConfiguration subtitleConfiguration =
  SubtitleViewConfiguration();
}