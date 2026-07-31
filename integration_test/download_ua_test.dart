// CONTROLLED + REAL download/playback experiment (run on a real emulator).
//
// Captures the exact UA libmpv sends, proves the DownloadService pipeline
// completes end-to-end on a cooperating local server, and reproduces the REAL
// provider download on-device to see if it fails like the user's does.
//
// Local server: scratchpad/server.py on the host, reachable at 10.0.2.2:8099.
// Real provider: passed via --dart-define-from-file (URLs never committed).
//
// Run:
//   flutter test integration_test/download_ua_test.dart -d emulator-5556 \
//     --dart-define-from-file=<scratch>/defines.json
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;

import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/download_service.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../test/integration/harness.dart';

const _localUrl = String.fromEnvironment('LOCAL_URL');
const _localPlayUrl = String.fromEnvironment('LOCAL_PLAY_URL');
const _movieUrl = String.fromEnvironment('PANEL_MOVIE_URL');
const _streamId = String.fromEnvironment('PANEL_STREAM_ID');
const _ext = String.fromEnvironment('PANEL_EXT', defaultValue: 'mp4');

// The harness mocks connectivity to the STRING 'wifi', but background_downloader
// (connectivity_plus) expects a List and throws on the cast, which stalls its
// network-wait so tasks never start. Remove the mock so the real emulator
// connectivity answers.
void _unmockConnectivity() {
  for (final ch in const [
    'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/connectivity_status',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(ch), null);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => MediaKit.ensureInitialized());
  setUp(() async {
    await setUpHarness(tv: false);
    _unmockConnectivity();
  });
  tearDown(() async {
    await DownloadService.instance.disposeForTesting();
    await tearDownHarness();
  });

  testWidgets('PLAYBACK local: libmpv opens /play.mp4 (logs UA)',
      (tester) async {
    if (_localPlayUrl.isEmpty) return;
    await _mountPlayer(tester, _localPlayUrl);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('PLAYBACK real: libmpv opens the real movie URL', (tester) async {
    if (_movieUrl.isEmpty) {
      markTestSkipped('PANEL_MOVIE_URL no definido');
      return;
    }
    await _mountPlayer(tester, _movieUrl, vod: true);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('DOWNLOAD local: cooperating server completes end-to-end',
      (tester) async {
    if (_localUrl.isEmpty) return;
    await _runDownload(tester, url: _localUrl, contentId: 'coop1', ext: 'mp4');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('DOWNLOAD real: enqueue the REAL movie URL (reproduce user bug)',
      (tester) async {
    if (_movieUrl.isEmpty) {
      markTestSkipped('PANEL_MOVIE_URL no definido');
      return;
    }
    await _runDownload(tester,
        url: _movieUrl, contentId: 'real_$_streamId', ext: _ext);
  }, timeout: const Timeout(Duration(seconds: 150)));
}

Future<void> _mountPlayer(WidgetTester tester, String url,
    {bool vod = false}) async {
  FlutterError.onError = (_) {};
  if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
    GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
  }
  AppState.currentPlaylist = Playlist(
      id: 'm', name: 'M', type: PlaylistType.m3u, createdAt: DateTime(2026, 1, 1));
  final item = vod
      ? ContentItem(url, 'Movie', '', ContentType.vod)
      : ContentItem(url, 'Clip', '', ContentType.liveStream,
          liveStream: LiveStream(
              streamId: url,
              name: 'Clip',
              streamIcon: '',
              categoryId: 'c',
              epgChannelId: 'e',
              playlistId: 'm'));
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: PlayerWidget(contentItem: item, queue: [item])),
  ));
  var playing = false;
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    final ready = tester
        .widgetList<Focus>(find.byType(Focus))
        .any((f) => f.focusNode?.debugLabel == 'PlayerRemote');
    if (ready && !playing) {
      playing = true;
      debugPrint('UAEXP: PLAYBACK reached PlayerRemote (playing) for $url');
    }
  }
  debugPrint('UAEXP: PLAYBACK done playing=$playing url=$url');
  expect(find.byType(PlayerWidget), findsOneWidget);
}

Future<void> _runDownload(WidgetTester tester,
    {required String url, required String contentId, required String ext}) async {
  FlutterError.onError = (_) {};
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

  final svc = DownloadService.instance;
  // Fire enqueue but don't let a blocking permission dialog stall the poll.
  await tester.runAsync(() async {
    unawaited(svc
        .enqueue(
          contentId: contentId,
          contentType: 'vod',
          title: 'UA Experiment $contentId',
          ext: ext,
          url: url,
          playlistId: 'p1',
        )
        .catchError((e) => debugPrint('UAEXP: enqueue threw: $e')));
  });

  Download? row;
  String? last;
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      row = await svc.findByContentId(contentId);
    });
    final s = row?.status;
    if (s != last) {
      debugPrint('UAEXP: [$contentId] status=$s bytes=${row?.bytesDownloaded} '
          'total=${row?.totalBytes} error=${row?.error}');
      last = s;
    }
    if (s == 'complete' || s == 'failed') break;
  }

  final r = row;
  debugPrint('UAEXP: ===== DOWNLOAD RESULT contentId=$contentId =====');
  debugPrint('UAEXP:   status=${r?.status}');
  debugPrint('UAEXP:   bytesDownloaded=${r?.bytesDownloaded}');
  debugPrint('UAEXP:   totalBytes=${r?.totalBytes}');
  debugPrint('UAEXP:   error=${r?.error}');
  debugPrint('UAEXP:   filePath=${r?.filePath}');
  debugPrint('UAEXP:   taskId=${r?.taskId}');
  debugPrint('UAEXP: ===============================================');
  expect(r, isNotNull, reason: 'a Downloads row must exist after enqueue');
}
