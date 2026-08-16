// Parser best-effort del NOMBRE de un archivo importado por el usuario →
// (título probable, año, ¿es episodio de serie?). Se usa solo para intentar un
// match en TMDb (póster/título): si falla, la app degrada al nombre del archivo.
// Puro (sin Flutter/IO) → testeable headless.

class ImportedFilenameInfo {
  const ImportedFilenameInfo({
    required this.title,
    required this.isEpisode,
    this.year,
  });

  /// Título limpio para buscar en TMDb (nombre sin tags de release/año/episodio).
  final String title;

  /// Año detectado (1900–2099) o null.
  final int? year;

  /// True si el nombre trae un patrón de episodio (SxxExx o 1x02) → buscar como
  /// serie (tv) en vez de película (movie).
  final bool isEpisode;
}

// Tags de "release" habituales: donde empiece el primero, ahí termina el título.
final RegExp _tagRe = RegExp(
  r'\b(1080p|2160p|720p|480p|4k|uhd|hdr|x264|x265|h264|h265|hevc|bluray|'
  r'brrip|bdrip|webrip|web-?dl|hdrip|dvdrip|xvid|divx|aac|ac3|dts|remux|'
  r'proper|repack|cam|hdcam|latino|castellano|dual|vose|multi)\b',
  caseSensitive: false,
);
final RegExp _episodeRe = RegExp(
  r'(s\d{1,2}\s*e\d{1,2}|\b\d{1,2}x\d{2}\b)',
  caseSensitive: false,
);
final RegExp _yearRe = RegExp(r'(?:19|20)\d{2}');

/// Extrae metadatos aproximados de [fileName] (con o sin extensión).
ImportedFilenameInfo parseImportedFilename(String fileName) {
  var name = fileName.trim();
  // Quitar la extensión (hasta 5 chars tras el último punto: .mkv/.mp4/.webm…).
  final dot = name.lastIndexOf('.');
  if (dot > 0 && name.length - dot <= 5) {
    name = name.substring(0, dot);
  }
  // Normalizar separadores típicos de nombres de archivo.
  name = name
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final epMatch = _episodeRe.firstMatch(name);
  final isEpisode = epMatch != null;

  final yearMatch = _yearRe.firstMatch(name);
  final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;

  // El título es lo que hay ANTES del primer marcador (episodio / año / tag).
  var cut = name.length;
  for (final start in <int?>[
    epMatch?.start,
    yearMatch?.start,
    _tagRe.firstMatch(name)?.start,
  ]) {
    if (start != null && start >= 0 && start < cut) cut = start;
  }

  var title = name.substring(0, cut).trim();
  // Limpiar separadores/corchetes colgando en los bordes.
  title = title.replaceAll(RegExp(r'^[\s\-\(\)\[\]{}]+|[\s\-\(\)\[\]{}]+$'), '');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.isEmpty) title = name; // sin nada útil → el nombre normalizado

  return ImportedFilenameInfo(
    title: title,
    year: year,
    isEpisode: isEpisode,
  );
}
