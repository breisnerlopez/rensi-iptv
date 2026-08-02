// Construye la cola COMPLETA de episodios de una serie para el AUTO-AVANCE
// STANDALONE en la TV (feature H — mejora): cuando la TV reanuda un episodio de
// serie desde SU historial, sin el móvil, encadena episodio→episodio (cruzando
// temporadas) reproduciendo cada uno con su URL Xtream reconstruida desde las
// credenciales que la TV persistió.
//
// El núcleo aquí es una función PURA (sin red, sin BD, sin secure-storage) para
// poder unit-testear la construcción de la cola + selección de índice + las
// guardas de fallback sin montar el widget ni tocar la red. La orquestación
// (cargar credenciales + fetch de red vía getSeriesInfo) vive en
// `tv_receiver_home.dart` y la envuelve en timeout/try-catch.
import '../../models/content_type.dart';
import '../../models/m3u_item.dart';
import '../../models/playlist_content_model.dart';
import '../../models/series.dart';
import 'standalone_url_builder.dart';

/// Playlist sintética bajo la que se arman los ContentItems de la cola
/// standalone. Debe coincidir con `_castPlaylistId` de tv_receiver_home.dart /
/// tv_receiver_host.dart: el M3uItem lleva este playlistId sólo para el contexto
/// M3U (la URL de reproducción sale de `m3uItem.url`, no se deriva de él).
const String _castPlaylistId = '__cast__';

/// Datos MÍNIMOS de un episodio que la cola necesita, desacoplados de la clase
/// Drift `EpisodesData` a propósito: así [buildStandaloneSeriesQueue] es una
/// función pura unit-testeable con structs planos (sin instanciar Drift).
class StandaloneEpisode {
  /// `episode_id` de Xtream = streamId con el que se reconstruye la URL y la
  /// clave de historial del episodio (la MISMA que guarda PlayerWidget).
  final String episodeId;

  /// container_extension (mp4/mkv/…) para el sufijo de la URL. Null/vacío → la
  /// URL omite el sufijo (ver buildStandaloneUrl).
  final String? containerExtension;

  final String title;

  /// Carátula del episodio (movie_image), si la hay.
  final String? imagePath;

  const StandaloneEpisode({
    required this.episodeId,
    this.containerExtension,
    this.title = '',
    this.imagePath,
  });
}

/// Construye la cola ORDENADA de episodios (ContentItems) para el auto-avance
/// standalone de una serie en la TV, más el índice del episodio ACTUAL.
///
/// [episodes] debe llegar YA ORDENADO (temporada, episodio) — el auto-avance
/// nativo de media_kit reproduce la Playlist en ese orden hasta el final de la
/// serie. Cada ContentItem se arma en contexto M3U (url = `m3uItem.url` = URL
/// standalone del episodio) para que el player use EXACTAMENTE esa URL con las
/// credenciales, igual que el item único de `_standaloneItemFor` y que
/// `_castItemFor`. Se le adjunta un `seriesStream` con el [seriesId] para que la
/// fila de historial que escribe el player conserve el vínculo con la serie.
///
/// Devuelve null (→ el llamador cae al ITEM ÚNICO, comportamiento actual) cuando
/// la lista está vacía o el episodio actual ([currentStreamId]) no aparece en
/// ella: sin un índice válido no hay cola de la que auto-avanzar, y arrancar la
/// serie desde otro punto sería peor que reanudar sólo ese episodio.
///
/// Las credenciales (url/user/pass) se usan SÓLO para armar las URLs vía
/// [buildStandaloneUrl]; NUNCA se registran (la URL resultante lleva user/pass
/// en el path — disciplina de scrubbing).
({List<ContentItem> queue, int index})? buildStandaloneSeriesQueue({
  required List<StandaloneEpisode> episodes,
  required String currentStreamId,
  required String serverUrl,
  required String username,
  required String password,
  required String seriesId,
  String fallbackImagePath = '',
}) {
  if (episodes.isEmpty) return null;
  final index = episodes.indexWhere((e) => e.episodeId == currentStreamId);
  if (index < 0) return null;

  final queue = <ContentItem>[
    for (final e in episodes)
      ContentItem(
        e.episodeId,
        e.title,
        (e.imagePath != null && e.imagePath!.isNotEmpty)
            ? e.imagePath!
            : fallbackImagePath,
        ContentType.series,
        containerExtension: e.containerExtension,
        // Vincula la fila de historial del episodio con la serie (misma columna
        // seriesId que persiste PlayerWidget._saveWatchHistory).
        seriesStream: SeriesStream(
          playlistId: _castPlaylistId,
          seriesId: seriesId,
          name: e.title,
        ),
        m3uItem: M3uItem(
          id: e.episodeId,
          playlistId: _castPlaylistId,
          url: buildStandaloneUrl(
            serverUrl: serverUrl,
            username: username,
            password: password,
            streamId: e.episodeId,
            ext: e.containerExtension,
            contentType: ContentType.series,
          ),
          contentType: ContentType.series,
          name: e.title,
        ),
      ),
  ];
  return (queue: queue, index: index);
}

/// Credenciales Xtream ya resueltas (mismo shape que
/// `TvStandaloneCredsService.load`), inyectadas para que
/// [resolveStandaloneSeriesQueue] no dependa de flutter_secure_storage.
typedef StandaloneCredsLoader = Future<({String url, String user, String pass})?>
    Function(String providerId);

/// Fetch de red de los episodios YA ORDENADOS de una serie (mismo shape que el
/// wrapper de `IptvRepository.getSeriesInfo` en `tv_receiver_home.dart`),
/// inyectado para que [resolveStandaloneSeriesQueue] no dependa de la red ni de
/// Drift. Null → serie no encontrada / episodios vacíos (el llamador cae al
/// item único, igual que una lista vacía).
typedef StandaloneEpisodesFetcher = Future<List<StandaloneEpisode>?> Function({
  required String url,
  required String user,
  required String pass,
  required String seriesId,
  required String playlistId,
});

/// Timeout duro por defecto para [resolveStandaloneSeriesQueue] — igual
/// disciplina que `_resolveStartPosition`/`_advanceStreamedSeriesFromDb` en
/// `tv_receiver_home.dart`: una TV NUNCA debe quedarse colgada esperando una
/// red lenta. Configurable (parámetro `timeout`) sólo para que los tests no
/// tengan que esperar 12s reales.
const Duration kStandaloneSeriesQueueTimeout = Duration(seconds: 12);

/// Orquesta la resolución de la cola COMPLETA de episodios (creds + fetch de
/// red) para el auto-avance standalone de serie, con las dependencias
/// (secure-storage, red) INYECTADAS vía [loadCreds]/[fetchEpisodes] — el seam
/// que permite testear unitariamente cada camino de fallo (sin creds, red
/// caída, timeout, respuesta vacía/corta, episodio actual ausente) SIN montar
/// el widget, sin emulador y sin esperar el timeout real.
///
/// Extraído de `_TvReceiverHomeState._resolveStandaloneSeriesQueue` +
/// `_standaloneSeriesQueue` (que antes envolvían las dependencias REALES
/// directamente, sin seam): la orquestación en sí (creds → fetch → construir
/// cola) es idéntica, sólo cambia de dónde vienen las creds/episodios.
///
/// Contrato idéntico al de siempre: CUALQUIER fallo (null de [loadCreds], el
/// conjunto completo excediendo [timeout], [fetchEpisodes] lanzando o
/// devolviendo null/vacío, o el episodio actual ausente de la lista — este
/// último vía [buildStandaloneSeriesQueue]) → null, nunca lanza, nunca cuelga
/// más allá de [timeout]. No se loguea ninguna excepción: podría llevar datos
/// del path con credenciales.
Future<({List<ContentItem> queue, int index})?> resolveStandaloneSeriesQueue({
  required String providerId,
  required String seriesId,
  required String currentStreamId,
  required String playlistId,
  required String fallbackImagePath,
  required StandaloneCredsLoader loadCreds,
  required StandaloneEpisodesFetcher fetchEpisodes,
  Duration timeout = kStandaloneSeriesQueueTimeout,
}) async {
  try {
    return await _resolveStandaloneSeriesQueueCore(
      providerId: providerId,
      seriesId: seriesId,
      currentStreamId: currentStreamId,
      playlistId: playlistId,
      fallbackImagePath: fallbackImagePath,
      loadCreds: loadCreds,
      fetchEpisodes: fetchEpisodes,
    ).timeout(timeout);
  } catch (_) {
    // Sin creds / red / timeout / serie no encontrada → item único (null). No
    // se loguea la excepción para no arriesgar filtrar el path con
    // credenciales (mismo criterio que el resto de este archivo).
    return null;
  }
}

/// Núcleo (sin timeout ni try/catch propios — los pone el llamador,
/// [resolveStandaloneSeriesQueue], envolviendo la llamada ENTERA) de la
/// resolución: carga credenciales, pide los episodios y arma la cola vía la
/// función pura [buildStandaloneSeriesQueue].
Future<({List<ContentItem> queue, int index})?>
    _resolveStandaloneSeriesQueueCore({
  required String providerId,
  required String seriesId,
  required String currentStreamId,
  required String playlistId,
  required String fallbackImagePath,
  required StandaloneCredsLoader loadCreds,
  required StandaloneEpisodesFetcher fetchEpisodes,
}) async {
  final creds = await loadCreds(providerId);
  if (creds == null) return null;
  final episodes = await fetchEpisodes(
    url: creds.url,
    user: creds.user,
    pass: creds.pass,
    seriesId: seriesId,
    playlistId: playlistId,
  );
  if (episodes == null || episodes.isEmpty) return null;
  return buildStandaloneSeriesQueue(
    episodes: episodes,
    currentStreamId: currentStreamId,
    serverUrl: creds.url,
    username: creds.user,
    password: creds.pass,
    seriesId: seriesId,
    fallbackImagePath: fallbackImagePath,
  );
}
