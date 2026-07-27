enum TmdbMediaType { movie, tv }

/// Why a TMDb call did not return results. Lives in the model layer (no
/// dependencies) so both [TmdbService] and the search results can name it
/// without a service→results import inversion.
///
/// `noKey` and `rejected` are deliberately distinct: telling a user to "activate
/// global search" right after they typed a bad token is the worst possible
/// message. `rateLimited` (429) must not read as "check your network" either —
/// the fix is "try later", not "reconnect".
enum TmdbFailure { noKey, rejected, rateLimited, httpError, network }

class TmdbSearchResult {
  final int id;
  final TmdbMediaType mediaType;
  final String title;

  /// The title in the film/show's ORIGINAL language (`original_title` for a
  /// movie, `original_name` for tv). A localized catalogue can carry the
  /// English original while TMDb returns a translated `title`, or vice-versa;
  /// matching against both lets the two reconcile.
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? releaseDate;
  final double voteAverage;

  const TmdbSearchResult({
    required this.id,
    required this.mediaType,
    required this.title,
    this.originalTitle,
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
    'originalTitle': originalTitle,
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
      originalTitle: json['originalTitle'] as String?,
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
      originalTitle:
          (mediaType == TmdbMediaType.tv
                  ? json['original_name']
                  : json['original_title'])
              as String?,
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

/// A person (actor/crew) from the TMDb `search/person` list. Deliberately tiny
/// — the person picker only renders a photo and a name, and carries the id so
/// the caller can fetch `person/{id}/combined_credits`.
class TmdbPerson {
  final int id;
  final String name;
  final String? profilePath;
  final String? knownForDepartment;

  const TmdbPerson({
    required this.id,
    required this.name,
    this.profilePath,
    this.knownForDepartment,
  });

  /// w185 is the smallest profile size that still looks sharp in the person
  /// grid on a 10-foot screen. Empty ('' not null) so it slots straight into a
  /// [TmdbSearchResult]-style `posterUrl` consumer with the same empty contract.
  String? get profileUrl => profilePath == null || profilePath!.isEmpty
      ? null
      : 'https://image.tmdb.org/t/p/w185$profilePath';

  factory TmdbPerson.fromTmdbJson(Map<String, dynamic> json) => TmdbPerson(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String? ?? '').trim(),
        profilePath: json['profile_path'] as String?,
        knownForDepartment: json['known_for_department'] as String?,
      );
}

/// A production company or network from the TMDb `search/company` list (plus a
/// curated set of networks — TMDb has no network search). Deliberately tiny,
/// mirroring [TmdbPerson]: the studio picker renders a name and carries the id
/// so the caller can run a discover query.
///
/// [isNetwork] routes discovery to `discover/tv?with_networks=` (a streaming
/// network like HBO/Netflix) rather than `discover/movie?with_companies=` (a
/// production company like A24). The two id-spaces are distinct on TMDb, so the
/// flag — not the id alone — decides the endpoint.
class TmdbCompany {
  final int id;
  final String name;
  final String? logoPath;
  final bool isNetwork;

  const TmdbCompany({
    required this.id,
    required this.name,
    this.logoPath,
    this.isNetwork = false,
  });

  /// w185 logo. Unlike a 2:3 poster this art is wide/transparent, so the UI
  /// renders a NAME-FORWARD tile rather than a bare logo. Null (not '') when
  /// absent so callers can branch cleanly, exactly like [TmdbPerson.profileUrl].
  String? get logoUrl => logoPath == null || logoPath!.isEmpty
      ? null
      : 'https://image.tmdb.org/t/p/w185$logoPath';

  factory TmdbCompany.fromTmdbJson(Map<String, dynamic> json) => TmdbCompany(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String? ?? '').trim(),
        logoPath: json['logo_path'] as String?,
      );
}

/// A single cast member from the TMDb `credits.cast` list. Deliberately tiny —
/// the detail enrichment only ever renders a photo, a name and the character.
class TmdbCredit {
  final int id;
  final String name;
  final String? character;
  final String? profilePath;

  const TmdbCredit({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
  });

  /// w185 is the smallest profile size that still looks sharp in a circular
  /// avatar on a 10-foot screen. Null (not '') so callers can branch cleanly.
  String? get profileUrl => profilePath == null || profilePath!.isEmpty
      ? null
      : 'https://image.tmdb.org/t/p/w185$profilePath';

  factory TmdbCredit.fromTmdbJson(Map<String, dynamic> json) => TmdbCredit(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String? ?? '').trim(),
        character: (json['character'] as String?)?.trim(),
        profilePath: json['profile_path'] as String?,
      );
}

/// A single video from the TMDb `videos.results` list. Used only to recover a
/// YouTube trailer key when the IPTV panel didn't ship one.
class TmdbVideo {
  final String key;
  final String site;
  final String type;
  final bool official;

  const TmdbVideo({
    required this.key,
    required this.site,
    required this.type,
    this.official = false,
  });

  String? get youtubeUrl =>
      site.toLowerCase() == 'youtube' && key.isNotEmpty
          ? 'https://www.youtube.com/watch?v=$key'
          : null;

  factory TmdbVideo.fromTmdbJson(Map<String, dynamic> json) => TmdbVideo(
        key: json['key'] as String? ?? '',
        site: json['site'] as String? ?? '',
        type: json['type'] as String? ?? '',
        official: json['official'] as bool? ?? false,
      );

  /// Picks the best playable trailer: a YouTube `Trailer`, preferring the
  /// official one. Returns null when there is no YouTube trailer at all, so the
  /// caller can fall back to its own source rather than launch a teaser/clip.
  static TmdbVideo? bestTrailer(List<TmdbVideo> videos) {
    final trailers = videos
        .where((v) =>
            v.site.toLowerCase() == 'youtube' &&
            v.type.toLowerCase() == 'trailer' &&
            v.key.isNotEmpty)
        .toList();
    if (trailers.isEmpty) return null;
    trailers.sort((a, b) => (b.official ? 1 : 0) - (a.official ? 1 : 0));
    return trailers.first;
  }
}

/// Richer payload from the TMDb detail endpoint, used by the bottom sheet.
class TmdbDetailResult {
  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String? originalTitle;

  /// ISO-639-1 code of the title's original language (TMDb `original_language`).
  /// Drives the overview language fallback: when the localized overview is empty
  /// the service re-fetches the synopsis in this language.
  final String? originalLanguage;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final int? voteCount;
  final int? runtimeMinutes;
  final List<String> genres;
  final String? homepage;

  /// Populated only when the detail call was made with `withCredits: true`
  /// (`append_to_response=credits,videos`); empty otherwise.
  final List<TmdbCredit> cast;
  final List<TmdbVideo> videos;

  const TmdbDetailResult({
    required this.id,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.originalLanguage,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    required this.voteAverage,
    this.voteCount,
    this.runtimeMinutes,
    this.genres = const [],
    this.homepage,
    this.cast = const [],
    this.videos = const [],
  });

  /// Returns a copy with [overview] replaced, keeping everything else (title,
  /// genres, cast, videos) as-is. Used by the overview language fallback: when a
  /// localized detail payload has an empty overview, the service splices in the
  /// original-language overview without disturbing the localized fields.
  TmdbDetailResult withOverview(String? newOverview) => TmdbDetailResult(
        id: id,
        mediaType: mediaType,
        title: title,
        originalTitle: originalTitle,
        originalLanguage: originalLanguage,
        overview: newOverview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        releaseDate: releaseDate,
        voteAverage: voteAverage,
        voteCount: voteCount,
        runtimeMinutes: runtimeMinutes,
        genres: genres,
        homepage: homepage,
        cast: cast,
        videos: videos,
      );

  /// Best YouTube trailer from [videos], or null. See [TmdbVideo.bestTrailer].
  TmdbVideo? get bestTrailer => TmdbVideo.bestTrailer(videos);

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

    // credits.cast and videos.results only exist when the caller requested
    // append_to_response=credits,videos. Parsed defensively so a plain detail
    // payload just yields empty lists.
    final cast = <TmdbCredit>[];
    final credits = json['credits'];
    if (credits is Map && credits['cast'] is List) {
      for (final c in credits['cast'] as List) {
        if (c is Map) {
          cast.add(TmdbCredit.fromTmdbJson(Map<String, dynamic>.from(c)));
        }
        if (cast.length >= 20) break; // rail never shows more than this
      }
    }
    final videos = <TmdbVideo>[];
    final videosJson = json['videos'];
    if (videosJson is Map && videosJson['results'] is List) {
      for (final v in videosJson['results'] as List) {
        if (v is Map) {
          videos.add(TmdbVideo.fromTmdbJson(Map<String, dynamic>.from(v)));
        }
      }
    }

    return TmdbDetailResult(
      id: (json['id'] as num).toInt(),
      mediaType: mediaType,
      title: (isTv ? json['name'] : json['title']) as String? ?? '',
      originalTitle:
          (isTv ? json['original_name'] : json['original_title']) as String?,
      originalLanguage: json['original_language'] as String?,
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
      cast: cast,
      videos: videos,
    );
  }
}
