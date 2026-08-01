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

  // Fix #10b: one-shot CONSUMABLE flag. A BACK that closes a player overlay
  // (channel list / settings / info) can, on some Android back dispatch, ALSO
  // fire the route-level pop for the SAME press — which would then leak into
  // leaving the player (the overlay already flipped its flag, so PopScope no
  // longer sees it open). Whoever closes an overlay BY BACK sets this true; the
  // player's PopScope reads AND resets it to swallow exactly that one trailing
  // pop. A flag (not a timestamp) is timing-independent and single-use.
  static bool overlayClosedByBack = false;

  static String title = '';
  static bool backgroundPlay = true;
  static SubtitleViewConfiguration subtitleConfiguration =
  SubtitleViewConfiguration();
}