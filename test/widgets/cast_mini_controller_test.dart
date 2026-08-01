// Regression: el mini-control de casting se monta en MaterialApp.builder como
// HERMANO del Navigator, sin Overlay ancestro. Un `tooltip:` en sus IconButtons
// disparaba "No Overlay widget found" en build; el IconButton fallido se
// reemplazaba por el error widget (Text sin ancho acotado), que reventaba el Row
// con "RIGHT OVERFLOWED BY ~1940 PIXELS". Este test monta el mini-control
// EXACTAMENTE como main.dart y exige que no lance excepción ni desborde.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/widgets/cast/cast_mini_controller.dart';

class _FakeSender extends PhoneSenderService {
  _FakeSender({this.devices = const []});
  final List<CastDevice> devices;
  @override
  Future<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async => devices;
  @override
  Future<void> connect(String host, int port, {bool secure = false}) async {}
  @override
  Future<bool> pair(String pin) async => pin == '123456';
  @override
  Future<void> sendLoad({required String channelId, String contentType = 'live', required String url, required String username, required String password, String title = '', String ext = '', CastMeta? meta}) async {}
  @override
  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) {}
  @override
  Future<void> close() async {}
}

Future<CastSenderController> _casting() async {
  final fake = _FakeSender(devices: [CastDevice(name: 'Sala de estar de la casa', host: '10.0.0.5', port: 5000)]);
  final c = CastSenderController(senderFactory: () => fake);
  await c.beginCast(const CastMedia(
      channelId: '6519',
      contentType: 'live',
      title: 'Una pelicula con un titulo verdaderamente largo para estresar el layout'));
  await c.submitPin('123456');
  return c;
}

Widget _app(CastSenderController c) => ChangeNotifierProvider<CastSenderController>.value(
      value: c,
      // Reproduce main.dart: el mini-control es hermano del Navigator dentro del
      // builder de MaterialApp (sin Overlay por encima de él).
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => Stack(children: [child!, const CastMiniController()]),
        home: const Scaffold(body: Center(child: Text('home'))),
      ),
    );

void main() {
  setUp(() {
    AppState.currentPlaylist = Playlist(id: 'p', name: 'P', type: PlaylistType.xtream, createdAt: DateTime(2026, 1, 1), url: 'http://h:8080', username: 'u', password: 'p');
  });

  testWidgets('se monta sin Overlay-assert ni overflow en ancho de telefono', (tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 914));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = await _casting();
    await tester.pumpWidget(_app(c));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CastMiniController), findsOneWidget);
    // Sin "No Overlay widget found" ni "RenderFlex overflowed".
    expect(tester.takeException(), isNull);
    // El título largo se muestra elipsado (los botones no se convirtieron en
    // error widgets), y siguen presentes ambos controles.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('no desborda en un ancho muy estrecho (320)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = await _casting();
    await tester.pumpWidget(_app(c));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
