// ADHOC QA PROBE (not part of the regular suite) — reproduces whether casting
// a SERIES advances to the next episode automatically when one ends, for both
// a streamed queue (contentType 'series' + queue) and a single downloaded
// local file (contentType 'file', no queue). Uses the same 2-emulator debug
// bridge as cast_bridge_test.dart (see integration_test/cast_bridge.md).
//
// Run (phone), with the TV app already running + bridged, PIN read from the TV
// logcat:
//   flutter test integration_test/series_advance_probe_test.dart -d emulator-5556 \
//     --dart-define=CAST_DEBUG_HOST=127.0.0.1 --dart-define=CAST_DEBUG_PORT=47700 \
//     --dart-define=CAST_PIN=NNNNNN \
//     --dart-define=QA_SERIES_BASE=http://10.0.2.2:8299
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';

import '../test/integration/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => setUpHarness(tv: false)); // phone
  tearDown(tearDownHarness);

  const pin = String.fromEnvironment('CAST_PIN');
  const bridgeHost = String.fromEnvironment('CAST_DEBUG_HOST');
  const seriesBase =
      String.fromEnvironment('QA_SERIES_BASE', defaultValue: 'http://10.0.2.2:8299');

  void seedPlaylist() {
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'QA',
      type: PlaylistType.xtream,
      url: seriesBase,
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

  Future<void> hold(WidgetTester tester, String m, {int seconds = 7}) async {
    debugPrint('PROBE_MARK_$m t=${DateTime.now().toIso8601String()}');
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 120));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<CastSenderController> pairAndCast(WidgetTester tester,
      {required CastMedia media, List<CastMedia>? queue, int index = 0}) async {
    final c = CastSenderController();
    await c.beginCast(media, queue: queue, index: index);
    debugPrint('PROBE_PHASE_AFTER_BEGIN=${c.phase}');
    if (c.phase == CastPhase.pairing) {
      final gotPair = await waitFor(tester, () => c.phase == CastPhase.pairing);
      expect(gotPair, isTrue, reason: 'debe llegar a PIN pairing');
      await c.submitPin(pin);
    }
    final casting = await waitFor(tester, () => c.phase == CastPhase.casting);
    debugPrint('PROBE_PHASE_CASTING=$casting phase=${c.phase} err=${c.error}');
    expect(casting, isTrue, reason: 'tras el PIN debe quedar en casting');
    return c;
  }

  testWidgets('STREAMED series: does the TV auto-advance ep1 -> ep2 on completion?',
      (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();

    final ep1 = CastMedia(
      channelId: '1',
      contentType: 'series',
      title: 'QA Series - EPISODE 1',
      ext: 'mp4',
      playlistId: 'm',
      historyId: '1',
    );
    final ep2 = CastMedia(
      channelId: '2',
      contentType: 'series',
      title: 'QA Series - EPISODE 2',
      ext: 'mp4',
      playlistId: 'm',
      historyId: '2',
    );
    final queue = [ep1, ep2];

    final c = await pairAndCast(tester, media: ep1, queue: queue, index: 0);
    debugPrint('PROBE_STREAM_INITIAL channelId=${c.media?.channelId} '
        'title=${c.media?.title}');
    await hold(tester, 'STREAM_EP1_PLAYING', seconds: 3);

    // The clip is 6s; give it up to 20s total to finish + advance.
    final advanced = await waitFor(
        tester, () => c.media?.channelId == '2', seconds: 20);
    debugPrint('PROBE_STREAM_RESULT advanced=$advanced '
        'finalChannelId=${c.media?.channelId} finalTitle=${c.media?.title} '
        'phase=${c.phase}');
    await hold(tester, 'STREAM_AFTER_COMPLETION', seconds: 4);

    await c.stopCasting();
    await waitFor(tester, () => c.phase == CastPhase.idle, seconds: 6);
    c.dispose();
  });

  testWidgets('DOWNLOADED (local file) cast: does completion auto-advance without a queue?',
      (tester) async {
    if (pin.isEmpty || bridgeHost.isEmpty) {
      return markTestSkipped('pasa --dart-define CAST_PIN/CAST_DEBUG_HOST/PORT');
    }
    seedPlaylist();

    // Simulate an on-device "download": fetch the clip from the QA server into
    // the app's own documents dir, same shape as a real downloaded file (a
    // plain local path, not http).
    final dir = await getApplicationDocumentsDirectory();
    final localFile = File('${dir.path}/qa_downloaded_ep1.mp4');
    final resp = await HttpClient()
        .getUrl(Uri.parse('$seriesBase/downloads/qa_downloaded_ep1.mp4'))
        .then((r) => r.close());
    await localFile.writeAsBytes(
        await resp.fold<List<int>>([], (b, d) => b..addAll(d)));
    debugPrint('PROBE_LOCAL_FILE_BYTES=${await localFile.length()}');

    final c = CastSenderController();
    await c.castLocalFile(
      filePath: localFile.path,
      contentId: 'dl1',
      title: 'QA Downloaded EPISODE 1',
      ext: 'mp4',
      imagePath: '',
    );
    debugPrint('PROBE_LOCAL_PHASE_AFTER_BEGIN=${c.phase}');
    if (c.phase == CastPhase.pairing) {
      final gotPair = await waitFor(tester, () => c.phase == CastPhase.pairing);
      expect(gotPair, isTrue, reason: 'debe llegar a PIN pairing');
      await c.submitPin(pin);
    }
    final casting = await waitFor(tester, () => c.phase == CastPhase.casting);
    debugPrint('PROBE_LOCAL_CASTING=$casting phase=${c.phase} err=${c.error}');
    expect(casting, isTrue, reason: 'tras el PIN debe quedar en casting');

    final mediaAtStart = c.media?.channelId;
    await hold(tester, 'LOCAL_EP1_PLAYING', seconds: 3);
    // Give it well past the clip duration (6s) to see if ANYTHING changes.
    await hold(tester, 'LOCAL_AFTER_COMPLETION_WINDOW', seconds: 14);
    debugPrint('PROBE_LOCAL_RESULT startChannelId=$mediaAtStart '
        'finalChannelId=${c.media?.channelId} finalTitle=${c.media?.title} '
        'phase=${c.phase} isCasting=${c.isCasting}');

    await c.stopCasting();
    await waitFor(tester, () => c.phase == CastPhase.idle, seconds: 6);
    c.dispose();
  });
}
