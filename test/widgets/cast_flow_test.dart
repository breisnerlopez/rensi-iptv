// Widget tests del flujo de casting: el modal refleja el estado del controlador
// (buscando → elegir → PIN → error) y la pantalla de control envía comandos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/widgets/cast/casting_screen.dart';

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

Widget _wrap(CastSenderController c, Widget child) => MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<CastSenderController>.value(
        value: c,
        child: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() {
    // Feature H (fase 5) — _sendLoad ahora resuelve el deviceId estable del
    // móvil vía UserPreferences.getCastDeviceId() (SharedPreferences). Sin
    // mockear la plataforma, SharedPreferences.getInstance() se queda
    // esperando una respuesta de canal que nunca llega en `flutter test`
    // (aquí no hay plugin nativo) y beginCast/submitPin cuelgan para siempre.
    // Mismo patrón que test/controllers/cast_sender_controller_test.dart.
    SharedPreferences.setMockInitialValues({});
    AppState.currentPlaylist = Playlist(
      id: 'p',
      name: 'P',
      type: PlaylistType.xtream,
      createdAt: DateTime(2026, 1, 1),
      url: 'http://h:8080',
      username: 'u',
      password: 'p',
    );
  });

  testWidgets('la pantalla de control muestra el destino y detiene el casting',
      (tester) async {
    final fake = _FakeSender(
        devices: [CastDevice(name: 'Sala', host: '10.0.0.5', port: 5000)]);
    final c = CastSenderController(senderFactory: () => fake);
    await c.beginCast(
        const CastMedia(channelId: '6519', contentType: 'live', title: 'Canal'));
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);

    await tester.pumpWidget(_wrap(c, const CastingScreen()));
    await tester.pump();

    // Muestra el nombre del TV destino y el título.
    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('Canal'), findsOneWidget);

    // El botón de play envía el comando play/pausa.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(fake.commands, contains('play_pause'));

    // "Dejar de transmitir" corta el casting: la UI pasa a idle al instante...
    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pump();
    expect(c.isCasting, isFalse);
    // ...y el teardown del socket (envío del 'stop' + cierre) ocurre después,
    // con un pequeño delay; drenarlo para no dejar timers pendientes.
    await tester.pump(const Duration(milliseconds: 200));
  });

  test('la TV avisa "ended" → el móvil sale de casting a idle sin reconectar',
      () async {
    final fake = _FakeSender(
        devices: [CastDevice(name: 'Sala', host: '10.0.0.5', port: 5000)]);
    final c = CastSenderController(senderFactory: () => fake);
    await c.beginCast(
        const CastMedia(channelId: '6519', contentType: 'live', title: 'Canal'));
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);
    // La TV cierra/para (BACK o stop en la TV) y envía 'ended': el móvil debe
    // ir a idle de inmediato, NO quedar colgado en casting ni reconectar.
    fake.onEnded?.call();
    expect(c.phase, CastPhase.idle);
    expect(c.isCasting, isFalse);
    // Drenar el teardown del socket en segundo plano (delay de 150ms).
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
}
