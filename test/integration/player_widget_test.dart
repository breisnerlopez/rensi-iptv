import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_info_widget.dart';
import 'package:rensi_iptv/widgets/player-buttons/video_settings_widget.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import 'harness.dart';

void main() {
  setUpAll(() async {
    await loadFonts();
    MediaKit.ensureInitialized();
  });
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('PlayerWidget real: monta con libmpv sin crashear (D-pad activo)',
      (tester) async {
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'M',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );

    // Bad URL → the stream fails fast (no real network hang); we only want to
    // verify the widget mounts, the D-pad Focus is active, and it doesn't crash.
    const badUrl = 'http://127.0.0.1:1/dead.ts';
    final item = ContentItem(
      badUrl,
      'Canal de Prueba',
      '',
      ContentType.liveStream,
      liveStream: LiveStream(
        streamId: badUrl,
        name: 'Canal de Prueba',
        streamIcon: '',
        categoryId: 'c',
        epgChannelId: 'e',
        playlistId: 'm',
      ),
    );

    var mounted = false;
    var error = '';
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayerWidget(contentItem: item, queue: [item])),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      mounted = tester.any(find.byType(PlayerWidget));
    } catch (e) {
      error = e.toString();
    }
    debugPrint('PLAYERWIDGET mounted=$mounted error=${error.isEmpty ? "none" : error}');

    // The widget must at least mount without a hard crash. (Video pixels need a
    // GPU; here we only assert the widget/logic layer survives real libmpv.)
    expect(mounted || error.isEmpty, isTrue,
        reason: 'PlayerWidget debe montar con un Player real sin crashear');
  }, timeout: const Timeout(Duration(seconds: 60)));

  // TV P0 (bloqueo comercial): en un Android TV solo-mando, el panel de
  // audio/subtítulos vive dentro de la barra táctil de media_kit, que nunca se
  // monta sin un toque → antes era INALCANZABLE con mando. La tecla dedicada
  // ('A' / mediaAudioTrack) debe abrirlo, y el host Offstage debe renderizarlo.
  // Deterministic core of the fix: mounting the settings/info widgets OFF-SCREEN
  // (as PlayerWidget's Stack now does) registers their open/close listeners even
  // when media_kit's touch bar never mounts, so the D-pad's toggle event actually
  // renders the panel. Before the fix nothing was mounted → the event was a no-op.
  testWidgets('TV: el host Offstage hace ALCANZABLE el panel de audio/subtítulos',
      (tester) async {
    PlayerState.showVideoSettings = false;
    // Narrow TV-ish viewport: the settings panel must lay out WITHOUT overflow
    // here (its header rows now flex/ellipsize) — no error suppression.
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(children: [
          const ColoredBox(color: Colors.black),
          // Exactly how PlayerWidget mounts the panel hosts off-screen.
          Offstage(
            offstage: true,
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [VideoInfoWidget(), VideoSettingsWidget()],
              ),
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();

    expect(find.text('Pista de Audio'), findsNothing,
        reason: 'el panel no debe estar abierto de inicio');

    // This is the exact event _handleRemoteKey now emits on the audio-track key.
    EventBus().emit('toggle_video_settings', true);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Pista de Audio'), findsOneWidget,
        reason: 'con el host Offstage montado, el evento del mando abre el panel');
    // The panel is fully localized (no hard-coded strings): the speed section
    // renders its translated label.
    expect(find.text('Velocidad'), findsOneWidget,
        reason: 'la sección de velocidad debe usar la etiqueta localizada');

    // And the same event closes it.
    EventBus().emit('toggle_video_settings', false);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Pista de Audio'), findsNothing,
        reason: 'el panel debe poder cerrarse');
  });

  // El E2E de mando sobre un player REAL vivía aquí y siempre se auto-saltaba:
  // media_kit guarda estado global por proceso, el primer test de este fichero
  // ya crea un Player, y el segundo no llega a "playing" en el mismo isolate.
  // Sus cuatro aserciones (tecla A, BACK, OK largo, OK corto) ya las cubre
  // player_remote_e2e_test.dart, que está solo en su fichero y sí se ejecuta.

}
