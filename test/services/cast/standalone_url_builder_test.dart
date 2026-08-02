// Cobertura del reconstructor de URL Xtream para el replay STANDALONE de la TV
// (feature H, fase 4). Función pura → sin mocks. El foco: paridad EXACTA de
// formato con lib/utils/build_media_url.dart (path movie/series + trato del
// sufijo de extensión) y las guardas de borde (ext nula/vacía, barra final,
// live no soportado).
//
// La segunda parte reproduce la lógica de selección de rama de
// `TvReceiverHome._standaloneItemFor` (privada) con sus mismas piezas públicas
// —WatchHistory.providerId/contentType + TvStandaloneCredsService.load—: cuándo
// la fila `__cast__` toma el camino standalone y cuándo cae al fallback.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/screens/tv/tv_receiver_home.dart';
import 'package:rensi_iptv/services/cast/standalone_url_builder.dart';
import 'package:rensi_iptv/services/cast/tv_standalone_creds_service.dart';

void main() {
  group('buildStandaloneUrl', () {
    test('VOD with extension → /movie/<user>/<pass>/<id>.<ext>', () {
      final url = buildStandaloneUrl(
        serverUrl: 'http://host:8080',
        username: 'u123',
        password: 's3cr3t',
        streamId: '4567',
        ext: 'mp4',
        contentType: ContentType.vod,
      );
      expect(url, 'http://host:8080/movie/u123/s3cr3t/4567.mp4');
    });

    test('series with extension → /series/<user>/<pass>/<id>.<ext>', () {
      final url = buildStandaloneUrl(
        serverUrl: 'http://host:8080',
        username: 'u123',
        password: 's3cr3t',
        streamId: '890',
        ext: 'mkv',
        contentType: ContentType.series,
      );
      expect(url, 'http://host:8080/series/u123/s3cr3t/890.mkv');
    });

    test('null extension omits the suffix (no literal ".null")', () {
      final url = buildStandaloneUrl(
        serverUrl: 'http://host:8080',
        username: 'u',
        password: 'p',
        streamId: '1',
        ext: null,
        contentType: ContentType.vod,
      );
      expect(url, 'http://host:8080/movie/u/p/1');
      expect(url.contains('.null'), isFalse);
    });

    test('empty extension omits the suffix', () {
      final url = buildStandaloneUrl(
        serverUrl: 'http://host:8080',
        username: 'u',
        password: 'p',
        streamId: '1',
        ext: '',
        contentType: ContentType.series,
      );
      expect(url, 'http://host:8080/series/u/p/1');
    });

    test('a single trailing slash on the server URL is stripped', () {
      final url = buildStandaloneUrl(
        serverUrl: 'http://host:8080/',
        username: 'u',
        password: 'p',
        streamId: '1',
        ext: 'mp4',
        contentType: ContentType.vod,
      );
      expect(url, 'http://host:8080/movie/u/p/1.mp4');
    });

    test('multiple trailing slashes are all stripped', () {
      final url = buildStandaloneUrl(
        serverUrl: 'http://host:8080///',
        username: 'u',
        password: 'p',
        streamId: '1',
        ext: 'mp4',
        contentType: ContentType.vod,
      );
      expect(url, 'http://host:8080/movie/u/p/1.mp4');
    });

    test('a server URL with a base path keeps that path', () {
      final url = buildStandaloneUrl(
        serverUrl: 'http://host:8080/xtream',
        username: 'u',
        password: 'p',
        streamId: '1',
        ext: 'mp4',
        contentType: ContentType.vod,
      );
      expect(url, 'http://host:8080/xtream/movie/u/p/1.mp4');
    });

    test('liveStream is unsupported and throws ArgumentError', () {
      expect(
        () => buildStandaloneUrl(
          serverUrl: 'http://host:8080',
          username: 'u',
          password: 'p',
          streamId: '1',
          ext: null,
          contentType: ContentType.liveStream,
        ),
        throwsArgumentError,
      );
    });

    test('format matches build_media_url path parity for VOD and series', () {
      // build_media_url.dart builds:
      //   VOD    → <url>/movie/<user>/<pass>/<id><suffix>
      //   series → <url>/series/<user>/<pass>/<id><suffix>
      // where suffix = ".<ext>" when ext non-empty, else "".
      const server = 'http://p.example:25461';
      const user = 'castUser';
      const pass = 'castPass';
      const id = '99999';
      expect(
        buildStandaloneUrl(
          serverUrl: server,
          username: user,
          password: pass,
          streamId: id,
          ext: 'mp4',
          contentType: ContentType.vod,
        ),
        '$server/movie/$user/$pass/$id.mp4',
      );
      expect(
        buildStandaloneUrl(
          serverUrl: server,
          username: user,
          password: pass,
          streamId: id,
          ext: 'ts',
          contentType: ContentType.series,
        ),
        '$server/series/$user/$pass/$id.ts',
      );
    });
  });

  // Ejercen el CÓDIGO REAL de selección de rama: la función top-level
  // `standaloneUrlForHistory` (@visibleForTesting) de tv_receiver_home.dart —la
  // misma que llama `_replay` vía `_standaloneItemFor`—, no una copia. La rama
  // standalone sólo se toma con providerId no-null + contentType VOD/series +
  // credenciales presentes; en cualquier otro caso el replay cae al lookup M3U
  // y su hint "reenvía desde el móvil".
  group('standaloneUrlForHistory (real branch-selection code)', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    WatchHistory row({
      String? providerId,
      String? ext,
      ContentType type = ContentType.vod,
    }) =>
        WatchHistory(
          playlistId: '__cast__',
          contentType: type,
          streamId: '4567',
          lastWatched: DateTime(2026, 1, 1),
          title: 'Some Movie',
          watchDuration: const Duration(minutes: 12),
          totalDuration: const Duration(minutes: 100),
          providerId: providerId,
          containerExtension: ext,
        );

    test('providerId + creds present → standalone URL is built', () async {
      await TvStandaloneCredsService.save(
        'prov-1',
        url: 'http://host:8080',
        user: 'u',
        pass: 'p',
      );
      final url =
          await standaloneUrlForHistory(row(providerId: 'prov-1', ext: 'mp4'));
      expect(url, 'http://host:8080/movie/u/p/4567.mp4');
    });

    test('null providerId → falls back (no standalone URL)', () async {
      final url =
          await standaloneUrlForHistory(row(providerId: null, ext: 'mp4'));
      expect(url, isNull);
    });

    test('providerId set but no stored creds → falls back', () async {
      // Nothing saved for this providerId (consent never given / revoked).
      final url =
          await standaloneUrlForHistory(row(providerId: 'unknown', ext: 'mp4'));
      expect(url, isNull);
    });

    test('live content type → falls back even with creds', () async {
      await TvStandaloneCredsService.save(
        'prov-1',
        url: 'http://host:8080',
        user: 'u',
        pass: 'p',
      );
      final url = await standaloneUrlForHistory(
        row(providerId: 'prov-1', type: ContentType.liveStream),
      );
      expect(url, isNull);
    });

    test('series row with creds → standalone series URL is built', () async {
      await TvStandaloneCredsService.save(
        'prov-9',
        url: 'http://host:8080/',
        user: 'u',
        pass: 'p',
      );
      final url = await standaloneUrlForHistory(
        row(providerId: 'prov-9', type: ContentType.series, ext: 'mkv'),
      );
      expect(url, 'http://host:8080/series/u/p/4567.mkv');
    });
  });
}
