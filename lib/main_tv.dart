// Entrypoint del RECEPTOR Android TV (arquitectura D, feat/cast-second-screen).
//
// La misma app Flutter, arrancada con `-t lib/main_tv.dart`, se comporta como
// el televisor: anuncia el servicio por mDNS, muestra nombre + PIN, y cuando el
// móvil envía un LOAD reproduce el canal con el PlayerWidget/media_kit real.
// No usa Cast Connect → funciona por sideload (sin Google Play).
//
// Empaquetado real de TV: añadir un flavor `tv` con manifest leanback
// (LEANBACK_LAUNCHER, uses-feature leanback, banner). Para el PoC/captura basta
// `flutter run -t lib/main_tv.dart`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;

import 'l10n/app_localizations.dart';
import 'models/content_type.dart';
import 'models/live_stream.dart';
import 'models/playlist_content_model.dart';
import 'models/playlist_model.dart';
import 'services/app_state.dart';
import 'services/cast/tv_receiver_service.dart';
import 'services/service_locator.dart';
import 'utils/app_themes.dart';
import 'utils/responsive_helper.dart';
import 'widgets/player_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO(cast): el receptor real debe instalar los mismos error-guards de
  // main.dart (scrubbing de credenciales en logs/ErrorWidget) — R3. Requiere
  // exponer installErrorGuards() como API pública (hoy es @visibleForTesting).
  await ResponsiveHelper.initTelevisionFlag();
  await setupServiceLocator();
  MediaKit.ensureInitialized();
  runApp(const RensiTvReceiverApp());
}

class RensiTvReceiverApp extends StatelessWidget {
  const RensiTvReceiverApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Rensi TV',
        theme: AppThemes.darkTheme,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TvReceiverScreen(),
      );
}

class TvReceiverScreen extends StatefulWidget {
  const TvReceiverScreen({super.key});
  @override
  State<TvReceiverScreen> createState() => _TvReceiverScreenState();
}

class _TvReceiverScreenState extends State<TvReceiverScreen> {
  final _receiver = TvReceiverService(deviceName: 'Rensi TV');
  ContentItem? _playing;
  int _port = 0;
  StreamSubscription<CastLoadRequest>? _loadSub;

  // Para captura de PoC: reproducir de inmediato una URL pasada por dart-define.
  static const _autoplayUrl = String.fromEnvironment('AUTOPLAY_URL');
  static const _autoplayId =
      String.fromEnvironment('AUTOPLAY_ID', defaultValue: 'poc');

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _port = await _receiver.start(); // servidor + anuncio mDNS
    } catch (_) {
      _port = await _receiver.start(advertise: false);
    }
    _loadSub = _receiver.onLoad.listen((req) => _play(req.mediaUrl, req.channelId, req.title));
    if (_autoplayUrl.isNotEmpty) {
      _play(_autoplayUrl, _autoplayId, 'Canal $_autoplayId');
    }
    if (mounted) setState(() {});
  }

  void _play(String url, String id, String title) {
    AppState.currentPlaylist ??= Playlist(
        id: 'tv', name: 'TV', type: PlaylistType.m3u, createdAt: DateTime(2026, 1, 1));
    final item = ContentItem(url, title, '', ContentType.liveStream,
        liveStream: LiveStream(
            streamId: id,
            name: title,
            streamIcon: '',
            categoryId: 'c',
            epgChannelId: 'e',
            playlistId: 'tv'));
    setState(() => _playing = item);
  }

  @override
  void dispose() {
    _loadSub?.cancel();
    _receiver.stop();
    _receiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_playing != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: PlayerWidget(contentItem: _playing!, queue: [_playing!]),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📺  Rensi TV',
                style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const Text('Listo para recibir contenido desde tu móvil',
                style: TextStyle(color: Colors.white70, fontSize: 22)),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD2603A), width: 2),
              ),
              child: Column(
                children: [
                  const Text('Código de emparejamiento',
                      style: TextStyle(color: Colors.white54, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_receiver.pin,
                      style: const TextStyle(
                          color: Color(0xFFD2603A),
                          fontSize: 56,
                          letterSpacing: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(_port == 0 ? 'Iniciando…' : 'Descubrible en la red · puerto $_port',
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
