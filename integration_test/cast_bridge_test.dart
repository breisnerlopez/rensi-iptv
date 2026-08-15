// 2-emulator CAST bridge E2E — runs on the PHONE (emulator-5556) and drives the
// REAL CastSenderController across the dart-define bridge to the REAL TV app
// (emulator-5554) acting as receiver. See integration_test/cast_bridge.md for the
// full recipe (build/install/forward-reverse) this test assumes is already set up.
//
// Run (phone), with the TV app already running + bridged, PIN read from the TV
// logcat (`CAST_RECV_BOUND=47700 pin=NNNNNN`):
//   flutter test integration_test/cast_bridge_test.dart -d emulator-5556 \
//     --dart-define=CAST_DEBUG_HOST=127.0.0.1 --dart-define=CAST_DEBUG_PORT=47700 \
//     --dart-define=CAST_PIN=882440
//
// Validates: H1/H3 (PIN pair → LOAD → plays on TV), reg#1/H5 (LOAD carries resume
// position → TV starts near it, written to watch_histories), reg#7/H6 (phone track
// panel shows TV-reported tracks), H4 (TV pause panel shows synopsis + cast from
// phone-sent metadata), H8 (superseded takeover by a 2nd sender).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:drift/drift.dart' show Value;

import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';

import '../test/integration/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => setUpHarness(tv: false)); // phone
  tearDown(tearDownHarness);

  const pin = String.fromEnvironment('CAST_PIN');
  const bridgeHost = String.fromEnvironment('CAST_DEBUG_HOST');

  // A synthetic "real" playlist: the receiver builds the VOD URL as
  // `$url/movie/$user/$pass/$id.$ext`; the host range server is path-agnostic so
  // that resolves to the multitrack clip. Creds travel ENCRYPTED over the bridge.
  void seedPlaylist() {
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'QA',
      type: PlaylistType.xtream,
      url: 'http://10.0.2.2:8199',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2026, 1, 1),
    );
  }

  Future<bool> waitFor(WidgetTester tester, bool Function() cond,
      {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (cond()) return true;
    }
    return false;
  }

  Future<void> mark(WidgetTester tester, String m, {int seconds = 7}) async {
    debugPrint('CAST_MARK_$m');
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 120));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    debugPrint('CAST_HOLD_DONE_$m');
  }

  final meta = const CastMeta(
    overview:
        'Sinopsis QA de casting: un thriller donde el movil manda a la TV la ficha completa.',
    cast: [
      CastMetaMember(name: 'Actor Uno', character: 'Protagonista'),
      CastMetaMember(name: 'Actriz Dos', character: 'Antagonista'),
      CastMetaMember(name: 'Actor Tres', character: 'Secundario'),
    ],
    title: 'QA Cast Movie',
    year: 2026,
  );

  CastMedia vodMedia({int startMs = 0}) => CastMedia(
        channelId: '123',
        contentType: 'vod',
        title: 'QA Cast Movie',
        ext: 'mp4',
        playlistId: 'm',
        historyId: '123',
        imagePath: '',
        meta: meta,
        startPositionMs: startMs,
      );

  Future<CastSenderController> pairAndCast(WidgetTester tester,
      {required CastMedia media}) async {
    final c = CastSenderController();
    await c.beginCast(media); // bridge → connectTo → pairing
    debugPrint('CAST_PHASE_AFTER_BEGIN=${c.phase}');
    if (c.phase == CastPhase.pairing) {
      final gotPair = await waitFor(tester, () => c.phase == CastPhase.pairing);
      expect(gotPair, isTrue, reason: 'la sesion debe llegar a PIN pairing');
      await c.submitPin(pin);
    }
    final casting = await waitFor(tester, () => c.phase == CastPhase.casting);
    debugPrint('CAST_PHASE_CASTING=$casting phase=${c.phase} err=${c.error}');
    expect(casting, isTrue,
        reason: 'tras el PIN correcto + LOAD la sesion debe quedar en casting');
    return c;
  }

  testWidgets('H1/H3/H4/H5/H6 + reg#1 resume — full cast to the real TV',
      (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();

    // --- H1/H3: pair by PIN → LOAD real VOD → plays on TV. reg#1/H5: LOAD carries
    // a resume position (60s) so the TV starts there, NOT at 0. ---
    final c = await pairAndCast(tester, media: vodMedia(startMs: 60000));
    await mark(tester, 'H1_PLAYING_ON_TV', seconds: 8); // TV screenshot: playing

    // reg#7/H6: the phone's track panel shows the TV-reported tracks.
    c.requestTracks();
    final gotTracks = await waitFor(
        tester, () => c.audioTracks.isNotEmpty || c.subtitleTracks.isNotEmpty,
        seconds: 15);
    debugPrint('CAST_TRACKS audio=${c.audioTracks.length} '
        'sub=${c.subtitleTracks.length} '
        'audioLabels=${c.audioTracks.map((t) => t.label).toList()}');
    expect(gotTracks, isTrue,
        reason: '#7/H6: el panel del movil recibe las pistas que reporta la TV');

    // reg#1/H5: the TV forwards its position; the controller writes a
    // watch_history row from it. Because the LOAD resumed at 60s, that row's
    // position must be ~60s+, NOT ~0. Give the TV time to forward >=1 state tick.
    await mark(tester, 'H5_LET_STATE_TICK', seconds: 16);
    final h = await WatchHistoryService().getWatchHistory('m', '123');
    final posMs = h?.watchDuration?.inMilliseconds ?? -1;
    debugPrint('CAST_WATCH_HISTORY exists=${h != null} posMs=$posMs '
        'title=${h?.title}');
    expect(h != null, isTrue,
        reason: '#1/H5: el cast alimenta watch_histories (Continuar viendo)');
    expect(posMs >= 45000, isTrue,
        reason: '#1/H5: el TV arranco cerca de la posicion de resume (60s), no en 0 '
            '(posMs=$posMs)');

    // --- H4: pause the TV → its pause panel shows the synopsis + cast the phone
    // sent in the LOAD metadata. ---
    c.playPause();
    await mark(tester, 'H4_TV_PAUSE_PANEL', seconds: 9); // TV screenshot: synopsis+cast
    c.playPause(); // resume

    await c.stopCasting();
    await waitFor(tester, () => c.phase == CastPhase.idle, seconds: 6);
    debugPrint('CAST_STOPPED phase=${c.phase}');
    c.dispose();
  });

  // SERIES auto-advance across the real TV: cast episode 1 (a SHORT clip so EOF
  // arrives in seconds), let the TV reach end-of-file, and assert the phone
  // auto-advances the queue to episode 2 and re-LOADs it on the TV.
  CastMedia epMedia(String id, String title) => CastMedia(
        channelId: id,
        contentType: 'series',
        title: title,
        ext: 'mp4',
        playlistId: 'm',
        historyId: id,
        seriesId: '999',
        imagePath: '',
        meta: meta,
      );

  testWidgets('SERIES auto-advance — TV EOF advances the queue to episode 2',
      (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();
    final eps = [epMedia('e1', 'Episodio 1'), epMedia('e2', 'Episodio 2')];
    final c = CastSenderController();
    await c.beginCast(eps[0], queue: eps, index: 0);
    debugPrint('CAST_SERIES_PHASE_AFTER_BEGIN=${c.phase}');
    if (c.phase == CastPhase.pairing) {
      await waitFor(tester, () => c.phase == CastPhase.pairing);
      await c.submitPin(pin);
    }
    final casting = await waitFor(tester, () => c.phase == CastPhase.casting);
    expect(casting, isTrue, reason: 'la serie debe llegar a casting (ep 1)');
    debugPrint('CAST_SERIES_EP1 channel=${c.media?.channelId} index=casting');
    await mark(tester, 'SERIES_EP1_PLAYING', seconds: 4);

    // The clip is ~6s; give the TV up to 40s to reach EOF and the chain to run.
    final advanced =
        await waitFor(tester, () => c.media?.channelId == 'e2', seconds: 40);
    debugPrint('CAST_SERIES_ADVANCED=$advanced channel=${c.media?.channelId}');
    expect(advanced, isTrue,
        reason: 'al terminar el ep 1 en la TV, el movil debe auto-avanzar al ep 2');
    await mark(tester, 'SERIES_EP2_PLAYING', seconds: 4);

    await c.stopCasting();
    await waitFor(tester, () => c.phase == CastPhase.idle, seconds: 6);
    c.dispose();
  });

  // SERIES auto-advance via the DB FALLBACK (the user's actual failing state):
  // cast episode 1 with the in-memory queue DELIBERATELY NULL. The only path to
  // advance is `_advanceStreamedSeriesFromDb`, which resolves ep2 from the DB by
  // seriesId. Seed 2 episodes into the harness in-memory DB (the same AppDatabase
  // `getIt<AppDatabase>()` returns inside the controller), cast ep1 queue-null,
  // reach natural EOF on the real TV, and assert the phone re-LOADs ep2 on the TV
  // (proven E2E: the TV fetches ep2's series URL from the range server after EOF).
  Future<void> seedSeries() async {
    // Two episodes of series '999' on playlist 'm', ordered (season, episodeNum).
    await harnessDb.into(harnessDb.episodes).insert(EpisodesCompanion.insert(
          seriesId: '999',
          episodeId: 'e1',
          episodeNum: 1,
          title: 'Episodio 1',
          season: 1,
          playlistId: 'm',
          containerExtension: const Value('mp4'),
        ));
    await harnessDb.into(harnessDb.episodes).insert(EpisodesCompanion.insert(
          seriesId: '999',
          episodeId: 'e2',
          episodeNum: 2,
          title: 'Episodio 2',
          season: 1,
          playlistId: 'm',
          containerExtension: const Value('mp4'),
        ));
  }

  testWidgets('SERIES auto-advance DB-FALLBACK — queue NULL, TV EOF advances to ep2',
      (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();
    await seedSeries();

    final c = CastSenderController();
    // queue: null / index default — the failing state: NO in-memory queue, so the
    // only path to advance is _advanceStreamedSeriesFromDb (resolves ep2 from BD).
    await c.beginCast(epMedia('e1', 'Episodio 1'));
    debugPrint('CAST_DBFB_PHASE_AFTER_BEGIN=${c.phase}');
    if (c.phase == CastPhase.pairing) {
      await waitFor(tester, () => c.phase == CastPhase.pairing);
      await c.submitPin(pin);
    }
    final casting = await waitFor(tester, () => c.phase == CastPhase.casting);
    expect(casting, isTrue, reason: 'la serie (cola null) debe llegar a casting (ep 1)');
    debugPrint('CAST_DBFB_EP1 channel=${c.media?.channelId}');
    await mark(tester, 'DBFB_EP1_PLAYING', seconds: 4);

    // Short clip → EOF in ~15-20s; give the TV up to 45s for EOF + DB-fallback chain.
    final advanced =
        await waitFor(tester, () => c.media?.channelId == 'e2', seconds: 45);
    debugPrint('CAST_DBFB_ADVANCED=$advanced channel=${c.media?.channelId}');
    expect(advanced, isTrue,
        reason: 'cola null: al terminar ep1 en la TV, la BD debe resolver ep2 y re-LOAD');
    await mark(tester, 'DBFB_EP2_PLAYING', seconds: 5);

    await c.stopCasting();
    await waitFor(tester, () => c.phase == CastPhase.idle, seconds: 6);
    c.dispose();
  });

  testWidgets('H8 — superseded takeover by a 2nd sender', (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();
    final c1 = await pairAndCast(tester, media: vodMedia());
    await mark(tester, 'H8_FIRST_CASTING', seconds: 4);
    expect(c1.isCasting, isTrue);

    // A 2nd sender pairs + LOADs: the TV sends `superseded` to the 1st, which must
    // go idle IN SILENCE (no error, no reconnect fight).
    final c2 = await pairAndCast(tester, media: vodMedia());
    final ceded =
        await waitFor(tester, () => c1.phase == CastPhase.idle, seconds: 12);
    debugPrint('CAST_H8 firstPhase=${c1.phase} firstErr=${c1.error} '
        'secondCasting=${c2.isCasting}');
    expect(ceded, isTrue,
        reason: 'H8: el 1er emisor cede en silencio al ser reemplazado (→ idle)');
    expect(c1.error, isNull, reason: 'H8: cesion silenciosa, sin error');
    await mark(tester, 'H8_SECOND_TOOK_OVER', seconds: 4);
    await c2.stopCasting();
    c1.dispose();
    c2.dispose();
  });

  // Escenario 7 (plan): reconexión REAL sobre el bridge. Un script externo rompe
  // y restaura el `adb forward` de la TV durante la ventana `RECON_WINDOW` (entre
  // las marcas BEFORE y AFTER); el móvil debe detectar la caída (ping/liveness),
  // reconectar (re-pair con el PIN guardado) y seguir casteando con la posición
  // avanzando. Prueba el transporte real (dart:io wss + TLS re-pair) que el test
  // headless con _FakeSender no ejercita.
  testWidgets('RECONNECT — caída+restauración de socket → sigue casteando y la '
      'posición avanza', (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();
    final c = await pairAndCast(tester, media: vodMedia(startMs: 5000));
    // Deja que la reproducción se establezca y captura una posición base.
    final gotPos =
        await waitFor(tester, () => c.castPositionMs > 6000, seconds: 30);
    final posBeforeBreak = c.castPositionMs;
    debugPrint('CAST_RECON_BEFORE pos=$posBeforeBreak gotPos=$gotPos '
        'phase=${c.phase}');
    // Ventana durante la cual el script externo rompe+restaura el forward.
    await mark(tester, 'RECON_WINDOW', seconds: 32);
    final posAfter = c.castPositionMs;
    debugPrint('CAST_RECON_AFTER pos=$posAfter phase=${c.phase} '
        'casting=${c.isCasting}');
    expect(c.isCasting, isTrue,
        reason: 'tras caída+reconexión sigue casteando (no idle/error)');
    expect(posAfter, greaterThan(posBeforeBreak),
        reason: 'la reproducción continuó tras la reconexión (posición avanzó)');
    await c.stopCasting();
    await waitFor(tester, () => c.phase == CastPhase.idle, seconds: 6);
    c.dispose();
  });

  // FIX-2 — estado play/pausa AUTORITATIVO del receptor. La TV pausa POR SU
  // CUENTA (un script externo manda MEDIA_PLAY_PAUSE al emulador TV durante la
  // ventana FIX2_PAUSE_TV_NOW); el emisor NO llama playPause, así que su
  // `isTvPlaying` solo puede volverse false si el campo `playing` autoritativo
  // que emite el receptor se propaga. Verifica la MITAD RECEPTORA en device (la
  // que los gates pidieron por el precedente test-pasa/device-falla).
  testWidgets('FIX-2 receptor — pausa/reanuda round-trip REAL en device (la TV '
      'pausa de verdad y el estado se propaga)', (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();
    final c = await pairAndCast(tester, media: vodMedia(startMs: 3000));
    await waitFor(tester, () => c.castPositionMs > 4000, seconds: 25);
    expect(c.isTvPlaying, isTrue, reason: 'la TV reproduce al castear');

    // Pausar: el receptor recibe el comando, pausa el player REAL de libmpv →
    // su `stream.playing` emite false → (FIX-2) emite 'cast_player_playing' →
    // el host lo reenvía en `state`. La prueba de que la TV pausó DE VERDAD en
    // device es que la posición se CONGELA.
    c.playPause();
    await mark(tester, 'FIX2_PAUSED', seconds: 6); // deja fluir el state
    final posA = c.castPositionMs;
    await mark(tester, 'FIX2_PAUSED_HOLD', seconds: 6);
    final posB = c.castPositionMs;
    debugPrint('CAST_FIX2_PAUSE posA=$posA posB=$posB '
        'isTvPlaying=${c.isTvPlaying}');
    expect(posB - posA, lessThan(2500),
        reason: 'la TV pausó DE VERDAD en device (posición congelada)');
    expect(c.isTvPlaying, isFalse, reason: 'el móvil refleja la pausa');

    // Reanudar: la TV vuelve a reproducir → la posición avanza otra vez.
    c.playPause();
    final resumed =
        await waitFor(tester, () => c.castPositionMs > posB + 3000, seconds: 18);
    debugPrint('CAST_FIX2_RESUME pos=${c.castPositionMs} resumed=$resumed '
        'isTvPlaying=${c.isTvPlaying}');
    expect(resumed, isTrue, reason: 'la TV reanudó en device (posición avanza)');
    expect(c.isTvPlaying, isTrue, reason: 'el móvil refleja la reanudación');
    await c.stopCasting();
    c.dispose();
  });
}
