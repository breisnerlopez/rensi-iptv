enum TmdbMediaType { movie, tv }

class TmdbSearchResult {
  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? releaseDate;
  final double voteAverage;

  const TmdbSearchResult({
    required this.id,
    required this.mediaType,
    required this.title,
    this.overview,
    this.posterPath,
    this.releaseDate,
    required this.voteAverage,
  });

  String get posterUrl => posterPath == null || posterPath!.isEmpty
      ? ''
      : 'https://image.tmdb.org/t/p/w342$posterPath';

  String get backdropPosterUrl => posterPath == null || posterPath!.isEmpty
      ? ''
      : 'https://image.tmdb.org/t/p/w780$posterPath';

  String get mediaTypeLabel =>
      mediaType == TmdbMediaType.movie ? 'Movie' : 'TV';

  String? get releaseYear {
    if (releaseDate == null || releaseDate!.length < 4) return null;
    return releaseDate!.substring(0, 4);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mediaType': mediaType.name,
    'title': title,
    'overview': overview,
    'posterPath': posterPath,
    'releaseDate': releaseDate,
    'voteAverage': voteAverage,
  };

  factory TmdbSearchResult.fromJson(Map<String, dynamic> json) {
    return TmdbSearchResult(
      id: (json['id'] as num).toInt(),
      mediaType: json['mediaType'] == TmdbMediaType.tv.name
          ? TmdbMediaType.tv
          : TmdbMediaType.movie,
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String?,
      posterPath: json['posterPath'] as String?,
      releaseDate: json['releaseDate'] as String?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble() ?? 0,
    );
  }

  factory TmdbSearchResult.fromTmdbJson(Map<String, dynamic> json) {
    final mediaType = json['media_type'] == 'tv'
        ? TmdbMediaType.tv
        : TmdbMediaType.movie;
    return TmdbSearchResult(
      id: (json['id'] as num).toInt(),
      mediaType: mediaType,
      title:
          (mediaType == TmdbMediaType.tv ? json['name'] : json['title'])
              as String? ??
          '',
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      releaseDate:
          (mediaType == TmdbMediaType.tv
                  ? json['first_air_date']
                  : json['release_date'])
              as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Richer payload from the TMDb detail endpoint, used by the bottom sheet.
class TmdbDetailResult {
  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final int? voteCount;
  final int? runtimeMinutes;
  final List<String> genres;
  final String? homepage;

  const TmdbDetailResult({
    required this.id,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    required this.voteAverage,
    this.voteCount,
    this.runtimeMinutes,
    this.genres = const [],
    this.homepage,
  });

  String get posterUrl => posterPath == null || posterPath!.isEmpty
      ? ''
      : 'https://image.tmdb.org/t/p/w342$posterPath';

  String get backdropUrl => backdropPath == null || backdropPath!.isEmpty
      ? (posterPath == null
            ? ''
            : 'https://image.tmdb.org/t/p/w780$posterPath')
      : 'https://image.tmdb.org/t/p/w780$backdropPath';

  String? get releaseYear {
    if (releaseDate == null || releaseDate!.length < 4) return null;
    return releaseDate!.substring(0, 4);
  }

  factory TmdbDetailResult.fromTmdbJson(
    Map<String, dynamic> json,
    TmdbMediaType mediaType,
  ) {
    final isTv = mediaType == TmdbMediaType.tv;
    final genresJson = json['genres'];
    final genres = <String>[];
    if (genresJson is List) {
      for (final g in genresJson) {
        if (g is Map && g['name'] is String) {
          genres.add(g['name'] as String);
        }
      }
    }
    int? runtime;
    if (isTv) {
      final list = json['episode_run_time'];
      if (list is List && list.isNotEmpty && list.first is num) {
        runtime = (list.first as num).toInt();
      }
    } else if (json['runtime'] is num) {
      runtime = (json['runtime'] as num).toInt();
    }
    return TmdbDetailResult(
      id: (json['id'] as num).toInt(),
      mediaType: mediaType,
      title: (isTv ? json['name'] : json['title']) as String? ?? '',
      originalTitle:
          (isTv ? json['original_name'] : json['original_title']) as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate:
          (isTv ? json['first_air_date'] : json['release_date']) as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      voteCount: (json['vote_count'] as num?)?.toInt(),
      runtimeMinutes: runtime,
      genres: genres,
      homepage: json['homepage'] as String?,
    );
  }
}
