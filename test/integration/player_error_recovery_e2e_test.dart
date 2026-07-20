import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import 'harness.dart';
import 'player_e2e_support.dart';

// END-TO-END error recovery with a REAL libmpv Player: a dead URL must surface
// the real error screen with a D-pad-focusable Retry button — no crash, no black
// frame. Runs in its own file (own isolate) because media_kit keeps per-process
// global state and a second libmpv player in one isolate can fail to init.
void main() {
  setUpAll(() async {
    await loadFonts();
    MediaKit.ensureInitialized();
  });
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets(
    'E2E remoto: recuperación ante error — URL muerta muestra pantalla de reintento enfocada',
    (tester) async {
      installPlayerPluginFakes(tester);
      if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
        GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
      }
      AppState.currentPlaylist = Playlist(
        id: 'm',
        name: 'M',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026, 1, 1),
      );
      // VOD (not live) so error retries terminate at the error screen instead of
      // the live auto-reopen loop.
      final dead = ContentItem(
        'http://127.0.0.1:1/dead.mp4',
        'Muerto',
        '',
        ContentType.vod,
      );

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PlayerWidget(contentItem: dead, queue: [dead])),
      ));
      // Interleave frames + real time so create → open() run, libmpv fails to
      // reach the dead host, and the error handler exhausts its retries and
      // surfaces the Retry screen. Generous budget for the retry backoff.
      final state = tester.state(find.byType(PlayerWidget)) as dynamic;
      await pumpUntil(
        tester,
        // ignore: avoid_dynamic_calls
        () => state.hasError == true,
        cycles: 80,
        ms: 250,
      );

      expect(find.byType(PlayerWidget), findsOneWidget,
          reason: 'el player no debe crashear ante una URL muerta');
      // ignore: avoid_dynamic_calls
      expect(state.hasError, isTrue,
          reason: 'una URL muerta debe terminar en la pantalla de error');
      // Ambas aserciones estaban mal y nadie lo supo: este fichero moría en
      // setUpAll por falta de libmpv, así que jamás llegó a ejecutarse.
      //   - el botón decía 'Retry' en inglés fijo con la app en español;
      //   - ElevatedButton.icon construye una subclase privada, y find.byType
      //     casa por runtimeType exacto, así que nunca la habría encontrado.
      expect(find.text('Intentar de Nuevo'), findsOneWidget,
          reason: 'la pantalla de error debe ofrecer Reintentar, traducido');
      final retryBtn = tester.widget<ElevatedButton>(
        find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      expect(retryBtn.autofocus, isTrue,
          reason: 'el botón Reintentar debe tomar el foco del mando');

      await disposePlayerCleanly(tester);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
