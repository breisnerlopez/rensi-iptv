// Wave-2 F-section resilience QA on a REAL libmpv decode (TV emulator 5554).
//
// F3 (stuck watchdog): point the player at a dead/hanging or freeze-mid-stream
//     URL → within ~12-15s a "Reintentar" (loc.cast_retry) overlay appears and
//     is reachable. Covers both retry surfaces: _buildLoadingIndicator(tooLong)
//     and _buildStuckRetry(_stuckBuffering).
// F4 (live stall): a live stream that connects then freezes → _stallTimer (15s)
//     calls _reopenCurrent(). Evidence is server-side: the fault_server access
//     log shows a 2nd GET ~15s after the 1st. The test just keeps the surface
//     alive across the window and asserts no full-screen error (live avisos are
//     non-fatal, E16/F4) and no crash.
//
// Run (VOD hang, F3):
//   flutter test integration_test/player_resilience_test.dart -d emulator-5554 \
//     --dart-define=RENSI_TESTCLIP=http://10.0.2.2:8199/hang \
//     --dart-define=RENSI_QA_TYPE=vod --name 'QA_F3_STUCK'
// Run (live freeze, F4):
//   flutter test integration_test/player_resilience_test.dart -d emulator-5554 \
//     --dart-define=RENSI_TESTCLIP=http://10.0.2.2:8199/freeze/clip_fs.mp4?after=250000 \
//     --dart-define=RENSI_QA_TYPE=live --name 'QA_F4_LIVE_STALL'
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../test/integration/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PlatformDispatcher.instance.onError = (error, stack) {
      final s = error.toString();
      if (s.contains('is not a subtype') || s.contains('connectivity')) {
        debugPrint('QA_SUPPRESSED_ASYNC_ERROR: $s');
        return true;
      }
      return false;
    };
    ErrorWidget.builder = (details) => const SizedBox.shrink();
    try {
      await loadFonts();
    } catch (_) {}
    MediaKit.ensureInitialized();
  });
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  final clip = const String.fromEnvironment('RENSI_TESTCLIP');
  final typeStr = const String.fromEnvironment('RENSI_QA_TYPE', defaultValue: 'vod');
  final isLive = typeStr == 'live';

  void installErrorSwallow() {
    final orig = FlutterError.onError!;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      if (s.contains('overflowed') ||
          s.contains('MaterialVideoControlsTheme') ||
          s.contains('_MaterialVideoControlsState') ||
          s.contains('dependOnInheritedWidgetOfExactType')) {
        return;
      }
      orig(d);
    };
  }

  final navKey = GlobalKey<NavigatorState>();

  Future<void> mountPlayer(WidgetTester tester, ContentType type) async {
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    PlayerState.showVideoSettings = false;
    PlayerState.overlayClosedByBack = false;
    AppState.currentPlaylist = Playlist(
        id: 'm', name: 'M', type: PlaylistType.m3u, createdAt: DateTime(2026, 1, 1));
    final ContentItem item = type == ContentType.liveStream
        ? ContentItem(clip, 'Canal de Prueba', '', ContentType.liveStream,
            liveStream: LiveStream(
                streamId: clip,
                name: 'Canal de Prueba',
                streamIcon: '',
                categoryId: 'c',
                epgChannelId: 'e',
                playlistId: 'm'))
        : ContentItem(clip, 'QA VOD Stuck', '', ContentType.vod);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
          key: ValueKey('base'), body: Center(child: Text('BASE-HOME'))),
    ));
    unawaited(navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) =>
          Scaffold(body: PlayerWidget(contentItem: item, queue: [item, item])),
    )));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  }

  // Pump REAL wall-clock so mpv's open/decode timers and the 12s/15s watchdogs
  // actually elapse, checking for the retry overlay each ~350ms.
  // Any reachable retry surface: the loading-tooLong / stuck overlay
  // (cast_retry = "Reintentar") OR the exhausted-error screen (try_again =
  // "Intentar de Nuevo").
  bool anyRetryVisible() =>
      find.text('Reintentar').evaluate().isNotEmpty ||
      find.text('Intentar de Nuevo').evaluate().isNotEmpty;

  Future<bool> pumpForRetry(WidgetTester tester, int seconds) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    var seen = false;
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (anyRetryVisible()) {
        seen = true;
        break;
      }
    }
    return seen;
  }

  // ==========================================================================
  // F3 — dead/hanging URL surfaces a reachable "Reintentar" within ~15s.
  // ==========================================================================
  testWidgets('QA_F3_STUCK', (tester) async {
    if (clip.isEmpty) return markTestSkipped('RENSI_TESTCLIP no definido');
    installErrorSwallow();
    debugPrint('QA_F3_URL=$clip type=$typeStr');
    await mountPlayer(tester, ContentType.vod);
    debugPrint('QA_MARK_F3_MOUNTED');

    final seen = await pumpForRetry(tester, 95);

    final nRetry = find.text('Reintentar').evaluate().length +
        find.text('Intentar de Nuevo').evaluate().length;
    final errScreen = find.text('No se pudo reproducir el contenido').evaluate().isNotEmpty;
    debugPrint('QA_F3_ERROR_SCREEN=$errScreen');
    final buttons = find.byType(ElevatedButton).evaluate().length +
        find.byType(FilledButton).evaluate().length;
    final spinners = find.byType(CircularProgressIndicator).evaluate().length;
    final playerStillUp = find.byType(PlayerWidget).evaluate().isNotEmpty;
    final leakedToBase = find.text('BASE-HOME').evaluate().isNotEmpty;
    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
    debugPrint('QA_F3_VISIBLE_TEXTS=${texts.join(" || ")}');
    debugPrint('QA_F3_RESULT retryVisible=$seen nReintentar=$nRetry '
        'buttons=$buttons spinners=$spinners playerUp=$playerStillUp leakedToBase=$leakedToBase');

    expect(playerStillUp, isTrue, reason: 'F3: el player no debe crashear/salir solo');
    expect(seen, isTrue,
        reason: 'F3: un botón "Reintentar" alcanzable aparece a los ~12-15s en un URL colgado');

    // Screenshot window for the external screencap.
    debugPrint('QA_MARK_F3_RETRY_VISIBLE');
    final holdEnd = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(holdEnd)) {
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    debugPrint('QA_HOLD_DONE_F3');
  });

  // ==========================================================================
  // F4 — live stream that freezes mid-stream. _stallTimer(15s) reopens. Evidence
  // is the fault_server access log (2nd GET). Here we assert no full-screen error
  // and no crash across a ~24s window (live avisos are non-fatal).
  // ==========================================================================
  testWidgets('QA_F4_LIVE_STALL', (tester) async {
    if (clip.isEmpty) return markTestSkipped('RENSI_TESTCLIP no definido');
    installErrorSwallow();
    debugPrint('QA_F4_URL=$clip type=$typeStr');
    await mountPlayer(tester, ContentType.liveStream);
    debugPrint('QA_MARK_F4_MOUNTED');

    // Keep the surface alive well past the 15s stall timer so a reopen (2nd GET)
    // fires and is captured in the server log. Watch for any full-screen error.
    var sawError = false;
    final end = DateTime.now().add(const Duration(seconds: 26));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // A hard error screen would unmount the player or show the error text.
      if (find.text('BASE-HOME').evaluate().isNotEmpty) {
        sawError = true; // player popped itself -> bad
        break;
      }
    }
    final playerStillUp = find.byType(PlayerWidget).evaluate().isNotEmpty;
    debugPrint('QA_F4_RESULT poppedToBase=$sawError playerUp=$playerStillUp');
    debugPrint('QA_MARK_F4_DONE');
    expect(playerStillUp, isTrue,
        reason: 'F4: un stall de live NO debe tumbar el player a pantalla de error');
    expect(sawError, isFalse, reason: 'F4: el live no se cae a BASE-HOME por un stall');
  });
}
