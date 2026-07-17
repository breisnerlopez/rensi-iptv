// Real-hardware integration test — RUN ON A REAL ANDROID TV DEVICE / EMULATOR,
// where media_kit's hardware video decoder and the Flutter engine actually
// render (this cannot run under `flutter test` headless — no GPU surface — nor
// on Linux desktop — the app's Android-only plugins/media_kit GL segfault there;
// both verified). It drives the Android-TV remote flow end to end with REAL key
// events: reproduction, the long-press-OK route to audio/subtitles, short-press
// play/pause, channel switching and BACK.
//
// Run:  flutter test integration_test/player_tv_test.dart -d <android-device> \
//         --dart-define=RENSI_TESTCLIP=/sdcard/clip.mp4   (or a real stream URL)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    await loadFonts();
    MediaKit.ensureInitialized();
  });
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  final clip = const String.fromEnvironment('RENSI_TESTCLIP');

  Future<bool> pumpUntilPlaying(WidgetTester tester) async {
    // Suppress the settings panel's cosmetic row overflow at odd window sizes.
    final orig = FlutterError.onError!;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      orig(d);
    };
    addTearDown(() => FlutterError.onError = orig);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      final ready = tester
          .widgetList<Focus>(find.byType(Focus))
          .any((f) => f.focusNode?.debugLabel == 'PlayerRemote');
      if (ready) return true;
    }
    return false;
  }

  FocusNode remoteNode(WidgetTester tester) => tester
      .widgetList<Focus>(find.byType(Focus))
      .firstWhere((f) => f.focusNode?.debugLabel == 'PlayerRemote')
      .focusNode!;

  Future<void> mountPlayer(WidgetTester tester) async {
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    PlayerState.showVideoSettings = false;
    AppState.currentPlaylist = Playlist(
        id: 'm', name: 'M', type: PlaylistType.m3u, createdAt: DateTime(2026, 1, 1));
    final item = ContentItem(clip, 'Canal de Prueba', '', ContentType.liveStream,
        liveStream: LiveStream(
            streamId: clip,
            name: 'Canal de Prueba',
            streamIcon: '',
            categoryId: 'c',
            epgChannelId: 'e',
            playlistId: 'm'));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: PlayerWidget(contentItem: item, queue: [item, item])),
    ));
  }

  testWidgets('TV real: reproduce, long-press OK abre audio/subs, short-press = play/pausa, BACK cierra',
      (tester) async {
    if (clip.isEmpty) {
      markTestSkipped('RENSI_TESTCLIP no definido');
      return;
    }
    await mountPlayer(tester);
    final ready = await pumpUntilPlaying(tester);
    expect(ready, isTrue,
        reason: 'con render real el player debe salir de isLoading y montar el Focus del mando');

    remoteNode(tester).requestFocus();
    await tester.pump();

    // --- LONG-PRESS OK opens the audio/subtitle panel (universal remote route). ---
    expect(find.text('Pista de Audio'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600)); // exceed 450ms hold
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(PlayerState.showVideoSettings, isTrue,
        reason: 'mantener OK debe emitir toggle_video_settings');
    expect(find.text('Pista de Audio'), findsOneWidget,
        reason: 'el panel de audio/subtítulos debe renderizarse');

    // BACK closes it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Pista de Audio'), findsNothing, reason: 'BACK cierra el panel');

    // --- SHORT press does NOT open settings (it toggles play/pause). ---
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(PlayerState.showVideoSettings, isFalse,
        reason: 'un toque corto de OK no abre opciones');

    // --- Channel switch (D-pad up/down on live with a 2-item queue). ---
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    // Still alive & not crashed after zapping.
    expect(find.byType(PlayerWidget), findsOneWidget);
  });
}
