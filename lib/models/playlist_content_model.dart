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

  /// Id de la serie a la que pertenece este ítem cuando es un episodio. Permite
  /// persistir el vínculo episodio→serie en el historial (agrupar "continuar
  /// viendo" por serie y el replay standalone en la TV), ya que los ContentItem
  /// de episodios no llevan [seriesStream].
  final String? seriesId;

  /// When set, this URL is used verbatim instead of deriving one from the
  /// content type/creds. Used for catch-up/timeshift, whose URL is a recorded
  /// window that [buildMediaUrl] can't reconstruct from id alone.
  final String? overrideUrl;

  /// True for a catch-up/timeshift playback: it plays as a seekable VOD but must
  /// NOT be persisted to "Continue watching" — the archive URL expires with the
  /// provider's retention window, so a saved resume would 404 later.
  final bool isCatchup;

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
    this.seriesId,
    this.overrideUrl,
    this.isCatchup = false,
  }) {
    url = overrideUrl ?? (isXtreamCode ? buildMediaUrl(this) : m3uItem?.url ?? id);
  }

  /// The TMDb id of the underlying owned stream, when the catalogue has one
  /// (VOD or series). Lets global search reconcile an owned title with its TMDb
  /// result by id — title-independent — instead of only by string match. Null
  /// for live/M3U items and for streams whose id hasn't been learned yet.
  int? get tmdbId => vodStream?.tmdbId ?? seriesStream?.tmdbId;
}
