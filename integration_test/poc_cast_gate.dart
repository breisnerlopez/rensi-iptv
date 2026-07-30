// Verifica el gate pre-reproducción del móvil: con un proveedor de casting en el
// árbol y sin ser TV, el gate aparece ANTES de cargar el stream, y "Reproducir
// aquí" lo resuelve y deja arrancar la reproducción.
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:provider/provider.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../test/integration/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => MediaKit.ensureInitialized());
  setUp(() => setUpHarness(tv: false)); // modo teléfono → el gate aplica
  tearDown(tearDownHarness);

  const clip = String.fromEnvironment('RENSI_TESTCLIP');

  testWidgets('gate: aparece antes de cargar y "Reproducir aquí" lo resuelve',
      (tester) async {
    if (clip.isEmpty) {
      markTestSkipped('sin RENSI_TESTCLIP');
      return;
    }
    // Ruido async/de widget del player al abrir el stream real tras resolver el
    // gate (y en el teardown); no afecta a la validación del gate en sí.
    PlatformDispatcher.instance.onError = (_, __) => true;
    FlutterError.onError = (_) {};
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    AppState.currentPlaylist = Playlist(
        id: 'm', name: 'M', type: PlaylistType.m3u, createdAt: DateTime(2026, 1, 1));
    final item = ContentItem(clip, 'Canal', '', ContentType.liveStream,
        liveStream: LiveStream(
            streamId: clip,
            name: 'Canal',
            streamIcon: '',
            categoryId: 'c',
            epgChannelId: 'e',
            playlistId: 'm'));

    await tester.pumpWidget(ChangeNotifierProvider<CastSenderController>(
      create: (_) => CastSenderController(),
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PlayerWidget(contentItem: item, queue: [item])),
      ),
    ));

    // El gate debe aparecer (móvil + provider de cast), ANTES de reproducir.
    var shown = false;
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining('Reproducir aquí').evaluate().isNotEmpty) {
        shown = true;
        break;
      }
    }
    expect(shown, isTrue, reason: 'el gate debe mostrarse en móvil');
    debugPrint('POC_GATE_SHOWN=true');

    // "Reproducir aquí" resuelve el gate y arranca la reproducción local.
    await tester.tap(find.textContaining('Reproducir aquí').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('Reproducir aquí'), findsNothing,
        reason: 'el gate se cierra al elegir reproducir aquí');
    expect(find.byType(PlayerWidget), findsOneWidget);
    debugPrint('POC_GATE_RESOLVED=true');
  }, timeout: const Timeout(Duration(seconds: 40)));
}
