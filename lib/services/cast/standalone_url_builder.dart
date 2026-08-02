import '../../models/content_type.dart';

/// Reconstruye la URL de stream Xtream que la TV necesita para reproducir de
/// forma STANDALONE (sin el móvil como emisor) una fila de historial `__cast__`,
/// a partir de las credenciales que la TV persistió (`TvStandaloneCredsService`)
/// más el `streamId`/`containerExtension` guardados en la propia fila.
///
/// Espejo de [buildMediaUrl] (lib/utils/build_media_url.dart), que arma la URL
/// desde `AppState.currentPlaylist`; aquí las credenciales llegan explícitas
/// porque el proveedor de origen NO es la playlist activa de la TV. Se mantiene
/// EXACTAMENTE el mismo formato de path y el mismo trato del sufijo de
/// extensión:
///   * VOD    → `<server>/movie/<user>/<pass>/<streamId>.<ext>`
///   * series → `<server>/series/<user>/<pass>/<streamId>.<ext>`
/// Igual que [buildMediaUrl], una extensión nula/vacía OMITE el sufijo por
/// completo (un `.null` literal hacía que el panel devolviera una página de
/// error → libmpv "failed to recognize file format").
///
/// Sólo VOD/series: el modelo credenciales+streamId no reconstruye URLs live ni
/// M3U desnudas, así que [ContentType.liveStream] lanza [ArgumentError] y el
/// llamador debe caer al camino de "reenvía desde el móvil".
///
/// A diferencia de [buildMediaUrl] —que confía en que `playlist.url` no trae
/// barra final— aquí se recorta defensivamente cualquier `/` final de
/// [serverUrl]: la URL viene de la secure-storage de la TV y podría haberse
/// guardado con barra, lo que produciría un `//movie` inválido.
String buildStandaloneUrl({
  required String serverUrl,
  required String username,
  required String password,
  required String streamId,
  required String? ext,
  required ContentType contentType,
}) {
  final server = _stripTrailingSlashes(serverUrl);
  final suffix = (ext != null && ext.isNotEmpty) ? '.$ext' : '';
  switch (contentType) {
    case ContentType.vod:
      return '$server/movie/$username/$password/$streamId$suffix';
    case ContentType.series:
      return '$server/series/$username/$password/$streamId$suffix';
    case ContentType.liveStream:
      throw ArgumentError.value(
        contentType,
        'contentType',
        'El replay standalone sólo soporta VOD/series (no live).',
      );
  }
}

String _stripTrailingSlashes(String url) {
  var end = url.length;
  while (end > 0 && url.codeUnitAt(end - 1) == 0x2F /* '/' */) {
    end--;
  }
  return url.substring(0, end);
}
