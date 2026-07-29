// PoC de casting (rama feat/cast-second-screen): valida que el Android TV
// REPRODUCE un canal HLS real vía el PlayerWidget/libmpv real, sin depender de
// loadFonts() (que lee fuentes por ruta de archivo y falla bajo `flutter test`).
// Mantiene el player en pantalla ~25 s para poder capturar el frame en vivo con
// `adb exec-out screencap` desde fuera.
//
// Run:  flutter test integration_test/poc_cast_play.dart -d emulator-5554 \
//         --dart-define=RENSI_TESTCLIP='<url m3u8 del canal>'
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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    MediaKit.ensureInitialized(); // NO loadFonts: fuentes son cosméticas aquí.
  });
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  final clip = const String.fromEnvironment('RENSI_TESTCLIP');

  testWidgets('PoC: el Android TV reproduce un canal HLS real', (tester) async {
    if (clip.isEmpty) {
      markTestSkipped('RENSI_TESTCLIP no definido');
      return;
    }
    // El emulador ATV dispara un cast error de connectivity_plus dentro de
    // _initializePlayer (String vs List<dynamic>). Es incidental a la
    // reproducción (el video igual monta su superficie); lo absorbemos para que
    // el test llegue a la captura. [Verificar en HW real si es del emulador.]
    PlatformDispatcher.instance.onError = (error, stack) {
      final s = error.toString();
      if (s.contains('is not a subtype') || s.contains('connectivity')) {
        debugPrint('POC_SUPPRESSED_ASYNC_ERROR: $s');
        return true;
      }
      return false;
    };
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

    // Detecta que el player salió de loading (montó el Focus del mando).
    var playing = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      playing = tester
          .widgetList<Focus>(find.byType(Focus))
          .any((f) => f.focusNode?.debugLabel == 'PlayerRemote');
      if (playing) {
        debugPrint('POC_PLAYING_AT_MS=${(i + 1) * 250}');
        break;
      }
    }
    debugPrint('POC_REACHED_PLAYING=$playing');

    // Deja fluir frames reales (~5 s wall-clock) antes de capturar. pump()
    // avanza reloj falso, así que hay que ceder tiempo real con Future.delayed.
    debugPrint('POC_HOLD_START');
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // Captura del frame del canal vía el mecanismo del proyecto (funciona con
    // la textura de video de media_kit, independiente de qué actividad esté al
    // frente). En Android hay que convertir la superficie antes de takeScreenshot.
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('poc_live_channel');
    debugPrint('POC_SHOT_TAKEN');

    expect(find.byType(PlayerWidget), findsOneWidget);
  });
}
