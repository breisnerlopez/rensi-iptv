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

import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
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
}
