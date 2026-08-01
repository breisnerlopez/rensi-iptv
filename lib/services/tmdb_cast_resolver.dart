import 'dart:ui' show Locale;

import '../models/tmdb_search_result.dart';
import 'cast/cast_protocol.dart';
import 'global_search_service.dart';
import 'tmdb_service.dart';

/// Resuelve (en el MÓVIL, que sí tiene la clave TMDb) la sinopsis + el reparto de
/// un título y lo empaqueta como [CastMeta] para enviarlo con el LOAD de casting.
///
/// La TV (receptora) NO tiene clave TMDb —es por-usuario y vive en el almacén
/// seguro del móvil—, así que el enriquecimiento tiene que resolverse aquí y
/// viajar hecho. Es best-effort: ante cualquier fallo (sin clave, clave
/// rechazada, límite, red, o sin coincidencia fiable) devuelve null y el casting
/// sigue igual (el panel de pausa degrada a solo-título, como hoy).
///
/// La lógica de coincidencia por título replica DELIBERADAMENTE la de
/// `TmdbEnrichment` (widgets/tmdb_enrichment.dart) — misma limpieza de nombre,
/// mismos candidatos y el mismo guard de "coincidencia fiable" — para no mostrar
/// el reparto de la película equivocada. Se mantiene aquí, aislada, para no tocar
/// la ruta de navegación/detalle (browse). Si divergen, cotéjense ambas.
class TmdbCastResolver {
  TmdbCastResolver({TmdbService? service}) : _tmdb = service ?? TmdbService();

  final TmdbService _tmdb;

  /// Resuelve el meta para un título. Para SERIES pásese el nombre de la SERIE
  /// (no el del episodio) en [title] y `TmdbMediaType.tv`; para películas, el
  /// título de la peli y `movie`. Si [tmdbId] es conocido (lo persiste el
  /// proveedor para VOD/serie) se usa directo, sin búsqueda ni matching.
  Future<CastMeta?> resolve({
    required String title,
    required TmdbMediaType mediaType,
    required Locale locale,
    int? year,
    int? tmdbId,
  }) async {
    try {
      final detail = await _resolveDetail(
        title: title,
        mediaType: mediaType,
        locale: locale,
        year: year,
        tmdbId: tmdbId,
      );
      if (detail == null) return null;
      final meta = _toMeta(detail);
      return meta.isEmpty ? null : meta;
    } on TmdbException {
      // Fallos tipados (noKey/rejected/rateLimited/httpError/network) degradan en
      // silencio — esto es enriquecimiento, no algo que el usuario pidió.
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<TmdbDetailResult?> _resolveDetail({
    required String title,
    required TmdbMediaType mediaType,
    required Locale locale,
    int? year,
    int? tmdbId,
  }) async {
    if (tmdbId != null && tmdbId > 0) {
      return _tmdb.detail(tmdbId, mediaType, locale: locale, withCredits: true);
    }
    final raw = title.trim();
    if (raw.isEmpty) return null;
    for (final query in searchCandidates(raw)) {
      final results = await _tmdb.searchTitle(
        query,
        year: year,
        mediaType: mediaType,
        locale: locale,
      );
      final best = pickBest(results, query, year, mediaType);
      if (best != null) {
        return _tmdb.detail(best.id, mediaType,
            locale: locale, withCredits: true);
      }
    }
    return null;
  }

  // El póster y las fotos de reparto viajan como FRAGMENTO crudo de TMDb
  // (poster_path / profile_path), NO como URL: el receptor los reconstruye contra
  // un host fijo, así el emisor no puede apuntar a un host arbitrario (ver nota en
  // CastMeta). No se envía backdrop. Un `null` en posterPath (título sin póster
  // TMDb / sin datos) hace que la TV mantenga su degradado, sin URL del proveedor.
  CastMeta _toMeta(TmdbDetailResult d) => CastMeta(
        overview: d.overview?.trim() ?? '',
        cast: [
          for (final c in d.cast.where((c) => c.name.isNotEmpty).take(20))
            CastMetaMember(
              name: c.name,
              character: c.character ?? '',
              profilePath: c.profilePath,
            )
        ],
        title: d.title,
        year: int.tryParse(d.releaseYear ?? ''),
        posterPath: d.posterPath,
      );

  // --- Matching (espejo de TmdbEnrichment; ver nota de clase) ---------------

  /// Limpia un nombre de VOD del proveedor a un título buscable: extensión,
  /// etiquetas entre paréntesis/corchetes, un año suelto y tokens de calidad.
  static String cleanTitle(String s) {
    var t = s;
    t = t.replaceAll(
        RegExp(r'\.(mp4|mkv|avi|ts|m3u8|mov|flv|wmv|webm)$',
            caseSensitive: false),
        ' ');
    t = t.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');
    t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    t = t.replaceAll(
        RegExp(
            r'\b(4k|uhd|fhd|hd|sd|2160p?|1080p?|720p?|480p?|dual|lat(ino)?|'
            r'sub(s|titulad[oa])?|cam|hdrip|bdrip|web[\s-]?dl|x264|x265|hevc|'
            r'\d{2,3}\s?fps)\b',
            caseSensitive: false),
        ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Consultas a probar en orden: el título limpio y sus 3 y 2 primeras palabras
  /// (el título real casi siempre encabeza el nombre del proveedor).
  static List<String> searchCandidates(String raw) {
    final cleaned = cleanTitle(raw);
    final words =
        cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    void add(String q) {
      if (q.isNotEmpty && !out.contains(q)) out.add(q);
    }

    add(cleaned);
    if (words.length > 3) add(words.take(3).join(' '));
    if (words.length > 2) add(words.take(2).join(' '));
    return out.isEmpty ? [raw.trim()] : out;
  }

  /// Escoge una coincidencia FIABLE o null. Igual criterio que TmdbEnrichment:
  /// acepta con señal de título (exacta, o difusa confirmada por año) o, sin
  /// señal de título, el top-hit SOLO si el año confirma (±1).
  static TmdbSearchResult? pickBest(
    List<TmdbSearchResult> results,
    String title,
    int? year,
    TmdbMediaType mediaType,
  ) {
    final typed = results.where((r) => r.mediaType == mediaType).toList();
    if (typed.isEmpty) return null;

    bool exactMatch(TmdbSearchResult r) =>
        GlobalSearchService.isExactTitleMatch(title, r.title) ||
        (r.originalTitle != null &&
            GlobalSearchService.isExactTitleMatch(title, r.originalTitle!));
    bool fuzzyMatch(TmdbSearchResult r) =>
        GlobalSearchService.isFuzzyTitleMatch(title, r.title) ||
        (r.originalTitle != null &&
            GlobalSearchService.isFuzzyTitleMatch(title, r.originalTitle!));
    bool yearMatch(TmdbSearchResult r) {
      final y = _yearOf(r);
      return year != null && y != null && (y - year).abs() <= 1;
    }

    final titled = typed.where(fuzzyMatch).toList();
    if (titled.isNotEmpty) {
      int rank(TmdbSearchResult r) =>
          (exactMatch(r) ? 2 : 0) + (yearMatch(r) ? 1 : 0);
      titled.sort((a, b) {
        final byRank = rank(b).compareTo(rank(a));
        if (byRank != 0) return byRank;
        return typed.indexOf(a).compareTo(typed.indexOf(b));
      });
      final best = titled.first;
      if (exactMatch(best) || yearMatch(best)) return best;
    }

    final top = typed.first;
    if (yearMatch(top)) return top;
    return null;
  }

  static int? _yearOf(TmdbSearchResult r) {
    final y = r.releaseYear;
    return y == null ? null : int.tryParse(y);
  }
}
