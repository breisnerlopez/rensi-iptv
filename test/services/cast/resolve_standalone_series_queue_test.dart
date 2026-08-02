// Cobertura de la ORQUESTACIÓN (creds + fetch de red + timeout + try/catch) de
// `resolveStandaloneSeriesQueue` — el seam inyectable extraído de
// `_TvReceiverHomeState._standaloneSeriesQueue` / `_resolveStandaloneSeriesQueue`
// (gate correction 2, `tv_receiver_home.dart`). Antes SÓLO la función pura
// `buildStandaloneSeriesQueue` tenía tests unitarios; la orquestación real que
// carga credenciales y hace un fetch de red con timeout de 12s no tenía
// NINGUNA cobertura. Aquí se inyectan fakes de [StandaloneCredsLoader] /
// [StandaloneEpisodesFetcher] para forzar cada camino de fallo SIN red real,
// sin secure storage y sin esperar el timeout real de producción, probando
// que TODOS caen al item único (null) sin lanzar ni colgar — el contrato que
// `_replay` (en `tv_receiver_home.dart`) depende de para nunca dejar la TV
// atascada.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/standalone_series_queue.dart';

void main() {
  group('resolveStandaloneSeriesQueue', () {
    const providerId = 'prov1';
    const seriesId = 'S42';
    // Partición fase-5 (`__cast__:<deviceId>`), a propósito distinta del
    // `__cast__` plano: prueba que el playlistId de la fila de historial viaja
    // intacto hasta el fetch inyectado (ver el test "happy path" más abajo).
    const playlistId = '__cast__:dev1';

    List<StandaloneEpisode> threeEpisodes() => const [
          StandaloneEpisode(
              episodeId: 'e1', containerExtension: 'mp4', title: 'S1E1'),
          StandaloneEpisode(
              episodeId: 'e2', containerExtension: 'mp4', title: 'S1E2'),
          StandaloneEpisode(
              episodeId: 'e3', containerExtension: 'mp4', title: 'S2E1'),
        ];

    test('(a) creds absent -> null, and the network fetch is never attempted',
        () async {
      var fetchCalled = false;
      final r = await resolveStandaloneSeriesQueue(
        providerId: providerId,
        seriesId: seriesId,
        currentStreamId: 'e1',
        playlistId: playlistId,
        fallbackImagePath: '',
        timeout: const Duration(milliseconds: 200),
        loadCreds: (_) async => null,
        fetchEpisodes: ({
          required url,
          required user,
          required pass,
          required seriesId,
          required playlistId,
        }) async {
          fetchCalled = true;
          return threeEpisodes();
        },
      );
      expect(r, isNull);
      expect(fetchCalled, isFalse);
    });

    test('(b) fetch exceeding the timeout -> TimeoutException swallowed -> null',
        () async {
      final r = await resolveStandaloneSeriesQueue(
        providerId: providerId,
        seriesId: seriesId,
        currentStreamId: 'e1',
        playlistId: playlistId,
        fallbackImagePath: '',
        // Ventana de test corta (no los 12s reales) — sólo prueba que EL
        // TIMEOUT en sí gobierna, no que sea exactamente 12s (eso lo fija
        // `_seriesQueueTimeout` en tv_receiver_home.dart al llamar con el
        // default de producción).
        timeout: const Duration(milliseconds: 50),
        loadCreds: (_) async => (url: 'http://h', user: 'u', pass: 'p'),
        fetchEpisodes: ({
          required url,
          required user,
          required pass,
          required seriesId,
          required playlistId,
        }) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return threeEpisodes();
        },
      );
      expect(r, isNull);
    });

    test('(c) empty episode list -> null', () async {
      final r = await resolveStandaloneSeriesQueue(
        providerId: providerId,
        seriesId: seriesId,
        currentStreamId: 'e1',
        playlistId: playlistId,
        fallbackImagePath: '',
        timeout: const Duration(milliseconds: 200),
        loadCreds: (_) async => (url: 'http://h', user: 'u', pass: 'p'),
        fetchEpisodes: ({
          required url,
          required user,
          required pass,
          required seriesId,
          required playlistId,
        }) async =>
            const [],
      );
      expect(r, isNull);
    });

    test('(d) fetch throws (e.g. SocketException) -> caught -> null', () async {
      final r = await resolveStandaloneSeriesQueue(
        providerId: providerId,
        seriesId: seriesId,
        currentStreamId: 'e1',
        playlistId: playlistId,
        fallbackImagePath: '',
        timeout: const Duration(milliseconds: 200),
        loadCreds: (_) async => (url: 'http://h', user: 'u', pass: 'p'),
        fetchEpisodes: ({
          required url,
          required user,
          required pass,
          required seriesId,
          required playlistId,
        }) async {
          throw const SocketException('network unreachable');
        },
      );
      expect(r, isNull);
    });

    test(
        '(e) current streamId absent from the fetched list -> null '
        '(delegated to the already-tested pure builder)', () async {
      final r = await resolveStandaloneSeriesQueue(
        providerId: providerId,
        seriesId: seriesId,
        currentStreamId: 'not-in-list',
        playlistId: playlistId,
        fallbackImagePath: '',
        timeout: const Duration(milliseconds: 200),
        loadCreds: (_) async => (url: 'http://h', user: 'u', pass: 'p'),
        fetchEpisodes: ({
          required url,
          required user,
          required pass,
          required seriesId,
          required playlistId,
        }) async =>
            threeEpisodes(),
      );
      expect(r, isNull);
    });

    test('happy path: resolves the full ordered queue + correct index, '
        'and forwards the ORIGINAL playlistId/seriesId to the fetch seam',
        () async {
      final capturedArgs = <String, String>{};
      final r = await resolveStandaloneSeriesQueue(
        providerId: providerId,
        seriesId: seriesId,
        currentStreamId: 'e2',
        playlistId: playlistId,
        fallbackImagePath: '',
        timeout: const Duration(milliseconds: 200),
        loadCreds: (id) async {
          expect(id, providerId);
          return (url: 'http://host:80', user: 'u', pass: 'p');
        },
        fetchEpisodes: ({
          required url,
          required user,
          required pass,
          required seriesId,
          required playlistId,
        }) async {
          capturedArgs['url'] = url;
          capturedArgs['user'] = user;
          capturedArgs['pass'] = pass;
          capturedArgs['seriesId'] = seriesId;
          capturedArgs['playlistId'] = playlistId;
          return threeEpisodes();
        },
      );
      expect(r, isNotNull);
      expect(r!.queue.map((it) => it.id).toList(), ['e1', 'e2', 'e3']);
      expect(r.index, 1);
      expect(capturedArgs['seriesId'], seriesId);
      // El playlistId inyectado es el de la FILA de historial (la partición
      // fase-5, p.ej. `__cast__:dev1`), no una constante fija — así
      // `getSeriesInfo` (en producción) lee/escribe en la misma partición.
      expect(capturedArgs['playlistId'], playlistId);
    });

    test(
        'never leaves the returned future pending, even when the injected '
        'fetch rejects asynchronously after a delay (no silent hang)',
        () async {
      await expectLater(
        resolveStandaloneSeriesQueue(
          providerId: providerId,
          seriesId: seriesId,
          currentStreamId: 'e1',
          playlistId: playlistId,
          fallbackImagePath: '',
          timeout: const Duration(milliseconds: 200),
          loadCreds: (_) async => (url: 'http://h', user: 'u', pass: 'p'),
          fetchEpisodes: ({
            required url,
            required user,
            required pass,
            required seriesId,
            required playlistId,
          }) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw Exception('boom');
          },
        ),
        completion(isNull),
      );
    });
  });
}
