// Cobertura del handoff imperativo `_popAfterCastHandoff()` en player_widget.dart:
// cuando el usuario envía el título a la TV desde el gate de casting, el player
// DEBE cerrarse (pop) e inmediatamente abrir el panel de controles de la TV
// (openCastControls), SALTÁNDOSE el guard de "confirmar salida con doble BACK"
// (`PopScope(canPop: _backExitArmed)`, Fix #10a) — ese guard es para el BACK del
// USUARIO, no para este cierre programático tras ceder la reproducción.
//
// Esto monta un PlayerWidget REAL (con Player() de media_kit real, igual que
// test/integration/player_widget_test.dart y test/integration/cast_gate_offline_test.dart
// ya hacen sin emulador/display) y recorre el camino completo por la UI: gate de
// casting → "Enviar a la TV" → descubre 1 TV falsa → PIN → casting → el player se
// cierra solo Y el panel de controles de la TV aparece automáticamente. Así se
// ejerce el mecanismo real (_onGateSendToTv → _popAfterCastHandoff(showControls:
// true) → Navigator.pop() imperativo + openCastControls), no solo su forma
// aislada.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:provider/provider.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_navigator.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/cast/casting_screen.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../integration/harness.dart';

class _FakeSender extends PhoneSenderService {
  _FakeSender({this.devices = const [], this.correctPin = '123456'});
  final List<CastDevice> devices;
  final String correctPin;
  final List<String> commands = [];
  @override
  Future<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async =>
      devices;
  @override
  Future<void> connect(String host, int port, {bool secure = false}) async {}
  @override
  Future<bool> pair(String pin) async => pin == correctPin;
  @override
  Future<void> sendLoad({
    required String channelId,
    String contentType = 'live',
    required String url,
    required String username,
    required String password,
    String title = '',
    String ext = '',
    CastMeta? meta,
    int startPositionMs = 0,
    bool standalone = false,
    String pid = '',
    String deviceId = '',
    String? seriesId,
  }) async {}
  @override
  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) =>
      commands.add(cmd);
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(() async {
    await loadFonts();
    MediaKit.ensureInitialized();
  });
  // tv:false → capa móvil, donde el gate de casting (y por tanto el handoff) aplica.
  setUp(() => setUpHarness(tv: false));
  tearDown(tearDownHarness);

  testWidgets(
      '_onGateSendToTv → tras castear con éxito, el player se cierra solo '
      '(pop programático, salta el guard de doble BACK) y se abre el panel de '
      'controles de la TV', (tester) async {
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    AppState.currentPlaylist = Playlist(
      id: 'm',
      name: 'M',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );

    final oneTv = CastDevice(name: 'Sala', host: '10.0.0.5', port: 5000);
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final cast = CastSenderController(senderFactory: () => fake);
    addTearDown(() async {
      // Drenar el teardown async del socket (delay de 150ms) para no dejar
      // timers pendientes tras el test.
      if (cast.isCasting) await cast.stopCasting();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    // URL http muerta (streamed, no local): dispara el gate de casting sin
    // depender de red real, igual que cast_gate_offline_test.dart.
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

    // navigatorKey: appNavigatorKey — _popAfterCastHandoff usa
    // appNavigatorKey.currentContext para abrir el panel de controles TRAS el
    // pop del player (su propio context ya no sirve). El Provider envuelve la
    // MaterialApp entera para que también sea visible tras un Navigator.push
    // (no solo en la ruta 'home').
    await tester.pumpWidget(
      ChangeNotifierProvider<CastSenderController>.value(
        value: cast,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      ),
    );
    await tester.pump();

    // El player se PUSHEA como una ruta más (como en la app real, nunca es la
    // ruta raíz): así Navigator.canPop() es true dentro de PlayerWidget y el
    // pop imperativo de _popAfterCastHandoff tiene algo real que hacer.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: PlayerWidget(contentItem: item, queue: [item])),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(PlayerWidget), findsOneWidget,
        reason: 'el player montó con un Player real de media_kit');

    // El stream muerto falla rápido → aparece el gate de casting.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      if (tester.any(find.text('¿Enviar esto a tu TV?'))) break;
    }
    expect(find.text('¿Enviar esto a tu TV?'), findsOneWidget,
        reason: 'contenido streameado debe mostrar el gate antes de reproducir');

    // "Enviar a la TV" → dispara _onGateSendToTv → startCastFlow (abre el modal
    // guiado de casting sobre el player).
    await tester.tap(find.text('Enviar a la TV'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // Con un solo dispositivo, el controlador conecta directo y pasa a pairing:
    // el modal muestra el campo de PIN.
    expect(find.byType(TextField), findsOneWidget,
        reason: 'una sola TV falsa → pasa directo a pedir el PIN');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Emparejar'));

    // Dejar que: el LOAD salga, el modal se auto-cierre (post-frame callback
    // al entrar en casting), _onGateSendToTv resuelva el gate, pare el player
    // local, y dispare el pop + apertura del panel de controles.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(cast.isCasting, isTrue, reason: 'el emparejamiento con el PIN correcto castea');

    // EL MECANISMO BAJO PRUEBA: el player se cerró SOLO (pop programático), sin
    // que el usuario pulsara BACK — el guard de confirmar-salida-con-doble-BACK
    // (PopScope canPop: _backExitArmed, nunca armado aquí) habría VETADO un
    // Navigator.maybePop() normal y dejado el player colgado. El pop imperativo
    // + canPop() de _popAfterCastHandoff lo salta a propósito.
    expect(find.byType(PlayerWidget), findsNothing,
        reason: 'el player se cerró programáticamente tras ceder a la TV, sin '
            'que el guard de doble-BACK lo vetara');

    // Y el panel de controles de la TV se abrió automáticamente (showControls:
    // true), reutilizando el navegador raíz vía appNavigatorKey.
    expect(find.byType(CastingScreen), findsOneWidget,
        reason: 'tras el handoff se abre el panel de controles de la TV para '
            'tenerlos a mano de inmediato');
    expect(find.text('Sala'), findsOneWidget,
        reason: 'el panel muestra el destino real del cast');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
