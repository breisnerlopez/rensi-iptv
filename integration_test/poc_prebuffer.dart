// Pre-buffer: pausa el video, llena caché, muestra velocidad/buffer y
// auto-reproduce al alcanzar la meta. Requiere proveedor activo.
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
import 'package:rensi_iptv/utils/audio_handler.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';
import '../test/integration/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => MediaKit.ensureInitialized());
  setUp(() => setUpHarness(tv: false));
  tearDown(tearDownHarness);
  const clip = String.fromEnvironment('RENSI_TESTCLIP');

  testWidgets('pre-buffer muestra carga y auto-reproduce', (tester) async {
    if (clip.isEmpty) return;
    PlatformDispatcher.instance.onError = (_, __) => true;
    final origOnError = FlutterError.onError; // ruido del player en teardown
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = origOnError);
    if (!GetIt.instance.isRegistered<MyAudioHandler>()) {
      GetIt.instance.registerSingleton<MyAudioHandler>(MyAudioHandler());
    }
    AppState.currentPlaylist = Playlist(id: 'm', name: 'M', type: PlaylistType.m3u, createdAt: DateTime(2026, 1, 1));
    final item = ContentItem(clip, 'Canal', '', ContentType.liveStream,
        liveStream: LiveStream(streamId: clip, name: 'Canal', streamIcon: '', categoryId: 'c', epgChannelId: 'e', playlistId: 'm'));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PlayerWidget(contentItem: item, queue: [item])),
    ));
    var shown = false;
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.textContaining('MB/s').evaluate().isNotEmpty) { shown = true; break; }
    }
    expect(shown, isTrue, reason: 'muestra preparación');
    debugPrint('POC_PREBUFFER_SHOWN=true');
    var resolved = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (find.textContaining('MB/s').evaluate().isEmpty) { resolved = true; break; }
    }
    expect(resolved, isTrue, reason: 'auto-reproduce al llenar caché');
    debugPrint('POC_PREBUFFER_RESOLVED=true');
  }, timeout: const Timeout(Duration(seconds: 70)));
}
