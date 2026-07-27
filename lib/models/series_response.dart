import 'package:rensi_iptv/database/database.dart';

class SeriesDetailResponse {
  final SeriesInfosData seriesInfo;
  final List<SeasonsData> seasons;
  final List<EpisodesData> episodes;
  final String playlistId;

  /// The series-level `info.tmdb_id` from the raw get_series_info payload, when
  /// present. Carried in-memory only (the SeriesInfos table has no tmdb column
  /// and adding one needs a Drift migration — out of scope), so it is populated
  /// on the network fetch path and null on a DB cache hit; callers fall back to
  /// a title+year search when it is null.
  final int? tmdbId;

  SeriesDetailResponse({
    required this.seriesInfo,
    required this.seasons,
    required this.episodes,
    required this.playlistId,
    this.tmdbId,
  });
}