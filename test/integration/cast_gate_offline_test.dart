// El gate de casting pre-reproducción ("¿Enviar esto a tu TV?") solo tiene
// sentido para contenido STREAMEADO (gasta datos y hay un destino plausible).
// Para un archivo LOCAL/offline (descarga, url = ruta de sistema de archivos, no
// http) es fricción inútil. Este test verifica:
//   - url http  → el gate SÍ aparece (comportamiento normal intacto).
//   - url local → el gate NO aparece (suprimido).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:provider/provider.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import 'harness.dart';

class _FakeSender extends PhoneSenderService {
  @override
  Future<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async => const [];
  @override
  Future<void> connect(String host, int port, {bool secure = false}) async {}
  @override
  Future<bool> pair(String pin) async => true;
  @override
  Future<void> sendLoad({required String channelId, String contentType = 'live', required String url, required String username, required String password, String title = '', String ext = '', CastMeta? meta, int startPositionMs = 0, bool standalone = false, String pid = '', String deviceId = ''}) async {}
  @override
  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) {}
  @override
  Future<void> close() async {}
}

ContentItem _item(String url) => ContentItem(
      url,
      'Peli',
      '',
      ContentType.vod,
    );

Widget _wrap(CastSenderController c, ContentItem item) => MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<CastSenderController>.value(
        value: c,
        child: Scaffold(body: PlayerWidget(contentItem: item, queue: [item])),
      ),
    );

void main() {
  setUpAll(() async {
    await loadFonts();
    MediaKit.ensureInitialized();
  });
  // tv:false → capa móvil, donde el gate aplica.
  setUp(() => setUpHarness(tv: false));
  tearDown(tearDownHarness);

  Future<void> registerDeps() async {
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'M',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  testWidgets('url http (streaming): el gate de casting SÍ aparece', (tester) async {
    await registerDeps();
    final c = CastSenderController(senderFactory: () => _FakeSender());

    await tester.pumpWidget(_wrap(c, _item('http://127.0.0.1:1/dead.mp4')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('¿Enviar esto a tu TV?'), findsOneWidget,
        reason: 'contenido streameado debe mostrar el gate');

    // Resolver el gate a reproducción local para no dejar timers vivos.
    await tester.tap(find.textContaining('Reproducir aquí'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('url local (offline): el gate de casting NO aparece', (tester) async {
    await registerDeps();
    final c = CastSenderController(senderFactory: () => _FakeSender());

    // Ruta de sistema de archivos (no http) → descarga offline.
    await tester.pumpWidget(_wrap(c, _item('/data/user/0/app/files/offline/peli.mp4')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('¿Enviar esto a tu TV?'), findsNothing,
        reason: 'un archivo local/offline no debe mostrar el gate');
    expect(tester.any(find.byType(PlayerWidget)), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
