import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import 'harness.dart';
import 'player_e2e_support.dart';

// END-TO-END player validation with a REAL libmpv Player and REAL remote key
// events — the closest headless equivalent to on-device Android-TV testing.
//
// The ONLY thing faked is the `com.alexmercerind/media_kit_video` texture
// channel: `flutter test` ships no native registrant for it, so
// `VideoController.create` throws MissingPluginException and the widget never
// leaves the loading spinner. On a real device that channel returns a texture
// id; here we deliver one via the same `VideoOutput.Resize` callback the native
// side uses. Everything else — decode, track detection, the D-pad handler,
// channel switching, overlays, play/pause — is the real code path.
//
// Opt-in: RENSI_TESTCLIP=/abs/path/to/clip.mp4 (a short local H.264+AAC file).
// Without it the test skips, so CI (which has no clip) stays green.
const String _kClip = String.fromEnvironment('RENSI_TESTCLIP');

void main() {
  setUpAll(() async {
    await loadFonts();
    MediaKit.ensureInitialized();
  });
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets(
    'E2E remoto: player real reproduce, panel audio/subs, play/pausa y cambio de canal',
    (tester) async {
      if (_kClip.isEmpty) {
        markTestSkipped('RENSI_TESTCLIP no definido — se omite E2E real');
        return;
      }
      installPlayerPluginFakes(tester);
      if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
        GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
      }
      PlayerState.showVideoSettings = false;
      AppState.currentPlaylist = Playlist(
        id: 'm',
        name: 'M',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026, 1, 1),
      );

      // Headless there is no GPU surface, so the default GPU video output stalls
      // Player.open(). The software decoder opens without one — the D-pad /
      // channel-switch logic under test is identical across decoders.
      await UserPreferences.setVideoDecoder('software');

      // Two live "channels" over the same local clip — distinct names prove the
      // switch actually reopened a different queue entry.
      final chA = liveItem(_kClip, 'Canal A');
      final chB = liveItem(_kClip, 'Canal B');

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlayerWidget(contentItem: chA, queue: [chA, chB]),
        ),
      ));
      // Warm up until the player leaves `isLoading` (post-frame → create →
      // texture → open() resolves), interleaving frames and real time.
      await pumpUntil(tester, () {
        final s = tester.state(find.byType(PlayerWidget)) as dynamic;
        // ignore: avoid_dynamic_calls
        return s.isLoading == false;
      });

      // 1) The real player initialized without error: it left the loading
      //    spinner (only happens once VideoController.create resolved on the real
      //    Player and Player.open() completed — i.e. real libmpv decode is live)
      //    and mounted the D-pad Focus.
      final st = tester.state(find.byType(PlayerWidget)) as dynamic;
      // ignore: avoid_dynamic_calls
      expect(st.isLoading, isFalse,
          reason: 'el player real debe completar la carga con libmpv');
      // ignore: avoid_dynamic_calls
      expect(st.hasError, isFalse,
          reason: 'un clip válido no debe caer en la pantalla de error');
      final remote = remoteFocus(tester);
      expect(remote, isNotNull,
          reason: 'el player real debe salir de "cargando" y montar el mando');
      expect(find.byType(PlayerWidget), findsOneWidget);
      remote!.focusNode!.requestFocus();
      await tester.pump();

      // 2) Audio/subtitle panel is reachable by remote ("A" / mediaAudioTrack).
      expect(find.text('Pista de Audio'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await pumpReal(tester, cycles: 6, ms: 150);
      expect(PlayerState.showVideoSettings, isTrue);
      expect(find.text('Pista de Audio'), findsOneWidget,
          reason: 'la tecla de audio debe abrir el panel');

      // 3) BACK closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpReal(tester, cycles: 6, ms: 150);
      expect(find.text('Pista de Audio'), findsNothing,
          reason: 'BACK debe cerrar el panel');

      // 4) Long-press OK opens it (universal route on any remote).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 500)); // > 450ms hold
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await pumpReal(tester, cycles: 6, ms: 150);
      expect(find.text('Pista de Audio'), findsOneWidget,
          reason: 'mantener OK debe abrir el panel');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpReal(tester, cycles: 6, ms: 150);
      expect(find.text('Pista de Audio'), findsNothing);

      // 5) Short OK = play/pause, never opens the panel.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await pumpReal(tester, cycles: 5, ms: 150);
      expect(PlayerState.showVideoSettings, isFalse,
          reason: 'un toque corto de OK no abre opciones');

      // 6) Channel switch (cambio de canales): D-pad up advances the queue.
      //    _changeChannel debounces ~350ms then reopens the new channel; the
      //    live-stream path sets PlayerState.currentContent to the new item.
      expect(PlayerState.currentContent?.name, 'Canal A');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      // Cross the 350ms debounce (a FakeAsync Timer) so it fires and emits the
      // index-changed event; the live-stream listener then sets currentContent
      // to the new channel synchronously (before its own await open()).
      await tester.pump(const Duration(milliseconds: 400));
      await pumpReal(tester, cycles: 6, ms: 150); // let the emit's listener run
      expect(PlayerState.currentContent?.name, 'Canal B',
          reason: 'D-pad arriba debe cambiar al siguiente canal de la cola');

      await disposePlayerCleanly(tester);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
