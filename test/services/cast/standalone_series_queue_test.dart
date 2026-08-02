// Feature H (mejora) — AUTO-AVANCE STANDALONE DE SERIE en la TV.
//
// Cobertura de la función PURA `buildStandaloneSeriesQueue` (sin red/BD/secure-
// storage): construcción de la cola ORDENADA de episodios como ContentItems con
// su URL standalone + selección del índice del episodio actual + las guardas de
// FALLBACK (lista vacía o episodio actual ausente → null → el llamador cae al
// item único). El foco es que cada item lleve EXACTAMENTE la URL que
// buildStandaloneUrl produce (con las credenciales en el path) y que el
// seriesId quede vinculado para el historial.
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/services/cast/standalone_series_queue.dart';

void main() {
  group('buildStandaloneSeriesQueue', () {
    const server = 'http://host:8080';
    const user = 'castU';
    const pass = 'castP';
    const seriesId = 'S42';

    List<StandaloneEpisode> eps() => const [
          StandaloneEpisode(
              episodeId: 'e1', containerExtension: 'mp4', title: 'S1E1'),
          StandaloneEpisode(
              episodeId: 'e2', containerExtension: 'mkv', title: 'S1E2'),
          StandaloneEpisode(
              episodeId: 'e3', containerExtension: 'mp4', title: 'S2E1'),
        ];

    ({List<dynamic> queue, int index})? build(String currentId) =>
        buildStandaloneSeriesQueue(
          episodes: eps(),
          currentStreamId: currentId,
          serverUrl: server,
          username: user,
          password: pass,
          seriesId: seriesId,
        );

    test('builds the FULL ordered queue and finds the current index', () {
      final r = build('e2');
      expect(r, isNotNull);
      expect(r!.queue.length, 3);
      expect(r.index, 1);
      // Orden preservado (la fuente ya llega ordenada temporada/episodio).
      expect(r.queue.map((it) => it.id).toList(), ['e1', 'e2', 'e3']);
    });

    test('each item plays its OWN standalone series URL (creds in path)', () {
      final r = build('e1')!;
      // La URL de reproducción sale de m3uItem.url (contexto M3U); debe coincidir
      // byte a byte con buildStandaloneUrl para /series/<user>/<pass>/<id>.<ext>.
      expect(r.queue[0].url, '$server/series/$user/$pass/e1.mp4');
      expect(r.queue[1].url, '$server/series/$user/$pass/e2.mkv');
      expect(r.queue[2].url, '$server/series/$user/$pass/e3.mp4');
    });

    test('every item carries the seriesId (history link) and series type', () {
      final r = build('e1')!;
      for (final it in r.queue) {
        expect(it.contentType, ContentType.series);
        expect(it.seriesStream?.seriesId, seriesId);
      }
    });

    test('first episode selected when current is the first', () {
      expect(build('e1')!.index, 0);
    });

    test('last episode selected when current is the last', () {
      expect(build('e3')!.index, 2);
    });

    test('null extension omits the suffix (no ".null")', () {
      final r = buildStandaloneSeriesQueue(
        episodes: const [StandaloneEpisode(episodeId: 'e1', title: 'x')],
        currentStreamId: 'e1',
        serverUrl: server,
        username: user,
        password: pass,
        seriesId: seriesId,
      )!;
      expect(r.queue.single.url, '$server/series/$user/$pass/e1');
      expect(r.queue.single.url.contains('.null'), isFalse);
    });

    test('fallback image is used when an episode has no image', () {
      final r = buildStandaloneSeriesQueue(
        episodes: const [StandaloneEpisode(episodeId: 'e1', title: 'x')],
        currentStreamId: 'e1',
        serverUrl: server,
        username: user,
        password: pass,
        seriesId: seriesId,
        fallbackImagePath: 'http://img/poster.jpg',
      )!;
      expect(r.queue.single.imagePath, 'http://img/poster.jpg');
    });

    test("episode's own image wins over the fallback", () {
      final r = buildStandaloneSeriesQueue(
        episodes: const [
          StandaloneEpisode(episodeId: 'e1', title: 'x', imagePath: 'http://ep.jpg')
        ],
        currentStreamId: 'e1',
        serverUrl: server,
        username: user,
        password: pass,
        seriesId: seriesId,
        fallbackImagePath: 'http://fallback.jpg',
      )!;
      expect(r.queue.single.imagePath, 'http://ep.jpg');
    });

    group('FALLBACK guards → null (caller plays the single item)', () {
      test('empty episode list → null', () {
        final r = buildStandaloneSeriesQueue(
          episodes: const [],
          currentStreamId: 'e1',
          serverUrl: server,
          username: user,
          password: pass,
          seriesId: seriesId,
        );
        expect(r, isNull);
      });

      test('current episode not in the list → null', () {
        final r = build('e999');
        expect(r, isNull);
      });
    });
  });
}
