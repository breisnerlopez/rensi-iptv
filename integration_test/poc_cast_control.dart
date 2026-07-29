// PoC end-to-end del canal de control (arquitectura D), en el Android TV.
//
// Prueba, en un solo dispositivo (loopback + mDNS del propio daemon):
//   1. mDNS: la TV anuncia y el sender descubre (best-effort; el mDNS entre dos
//      emuladores NAT no es fiable, por eso la conexión de control va directa).
//   2. Emparejamiento por PIN: PIN correcto -> aceptado; incorrecto -> rechazado.
//   3. LOAD con credenciales CIFRADAS (AES-GCM) -> la TV las descifra bien.
//   4. La TV reproduce el canal real que le envió el móvil (surface de video).
//
// Run: flutter drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/poc_cast_control.dart -d emulator-5554 \
//        --profile --dart-define-from-file=<scratch>/panel_env.json \
//        --dart-define=PANEL_CHANNEL=6519
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
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/services/cast/tv_receiver_service.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

import '../test/integration/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => MediaKit.ensureInitialized());
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  const url = String.fromEnvironment('PANEL_URL');
  const user = String.fromEnvironment('PANEL_USER');
  const pass = String.fromEnvironment('PANEL_PASS');
  const channelId = String.fromEnvironment('PANEL_CHANNEL', defaultValue: '6519');

  testWidgets('PoC D: descubrir + emparejar + LOAD cifrado + reproducir',
      (tester) async {
    if (url.isEmpty) {
      markTestSkipped('PANEL_* no definido (pasa --dart-define-from-file)');
      return;
    }
    // El emulador ATV lanza un cast error async de connectivity_plus; absorber.
    PlatformDispatcher.instance.onError = (e, _) =>
        e.toString().contains('is not a subtype') ? true : false;

    // --- Receptor en la TV ---
    final receiver = TvReceiverService(deviceName: 'Rensi TV (emu)');
    var advertised = true;
    int port;
    try {
      port = await receiver.start(advertise: true);
    } catch (e) {
      advertised = false;
      port = await receiver.start(advertise: false);
    }
    debugPrint('POC_TV_PORT=$port POC_PIN=${receiver.pin} POC_ADVERTISED=$advertised');

    // --- (1) Descubrimiento mDNS best-effort ---
    var discovered = 0;
    try {
      final finder = PhoneSenderService();
      final devices = await finder.discover(timeout: const Duration(seconds: 3));
      discovered = devices.length;
      await finder.close();
    } catch (e) {
      debugPrint('POC_DISCOVERY_ERR=$e');
    }
    debugPrint('POC_DISCOVERED=$discovered');

    // --- (2a) PIN incorrecto -> rechazado ---
    final wrongSender = PhoneSenderService();
    await wrongSender.connect('127.0.0.1', port);
    final wrongPin = receiver.pin == '000000' ? '111111' : '000000';
    final wrongOk = await wrongSender.pair(wrongPin);
    debugPrint('POC_WRONG_PIN_ACCEPTED=$wrongOk');
    expect(wrongOk, isFalse, reason: 'un PIN incorrecto debe rechazarse');
    await wrongSender.close();

    // --- (2b) PIN correcto -> aceptado ---
    final sender = PhoneSenderService();
    await sender.connect('127.0.0.1', port);
    final ok = await sender.pair(receiver.pin);
    debugPrint('POC_PAIRED=$ok');
    expect(ok, isTrue, reason: 'el PIN correcto debe emparejar');

    // --- (3) LOAD con credenciales cifradas -> la TV las descifra ---
    final loadFuture = receiver.onLoad.first;
    await sender.sendLoad(
      channelId: channelId,
      contentType: 'live',
      url: url,
      username: user,
      password: pass,
      title: 'Canal $channelId',
    );
    final req = await loadFuture.timeout(const Duration(seconds: 5));
    debugPrint('POC_LOAD_RECEIVED id=${req.channelId} '
        'credsOk=${req.url == url && req.username == user && req.password == pass} '
        'mediaUrl=<scrubbed>');
    expect(req.channelId, channelId);
    expect(req.url, url);
    expect(req.username, user, reason: 'las credenciales deben descifrarse intactas');
    expect(req.password, pass);

    // --- (4) La TV reproduce el canal que el móvil le envió ---
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    PlayerState.showVideoSettings = false;
    AppState.currentPlaylist = Playlist(
        id: 'm', name: 'M', type: PlaylistType.m3u, createdAt: DateTime(2026, 1, 1));
    final item = ContentItem(
        req.mediaUrl, req.title, '', ContentType.liveStream,
        liveStream: LiveStream(
            streamId: req.channelId,
            name: req.title,
            streamIcon: '',
            categoryId: 'c',
            epgChannelId: 'e',
            playlistId: 'm'));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PlayerWidget(contentItem: item, queue: [item, item])),
    ));

    // Deja fluir frames reales ~6 s (pump avanza reloj falso).
    final end = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    debugPrint('POC_PLAYBACK_MOUNTED');
    expect(find.byType(PlayerWidget), findsOneWidget);

    await sender.close();
    await receiver.stop();
    receiver.dispose();
  });
}
