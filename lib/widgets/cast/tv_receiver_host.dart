// Integra el RECEPTOR de casting en la app cuando corre en Android TV: la misma
// app instalada (que además navega IPTV con normalidad) escucha en la LAN y,
// cuando un móvil emparejado envía un canal, lo reproduce a pantalla completa
// con el PlayerWidget/media_kit. En móvil/tablet este host es transparente.
//
// No usa Cast Connect → funciona con la app instalada por sideload.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/localization_extension.dart';
import '../../models/content_type.dart';
import '../../models/m3u_item.dart';
import '../../models/playlist_content_model.dart';
import '../../models/playlist_model.dart';
import '../../services/app_state.dart';
import '../../services/cast/tv_receiver_service.dart';
import '../../utils/responsive_helper.dart';
import '../player_widget.dart';

const _accent = Color(0xFFD2603A);
const _castPlaylistId = '__cast__';

class TvReceiverHost extends StatefulWidget {
  const TvReceiverHost({super.key, required this.child, this.deviceName = 'Rensi TV'});
  final Widget child;
  final String deviceName;

  @override
  State<TvReceiverHost> createState() => _TvReceiverHostState();
}

class _TvReceiverHostState extends State<TvReceiverHost> {
  TvReceiverService? _service;
  StreamSubscription<void>? _connectSub;
  StreamSubscription<CastLoadRequest>? _loadSub;
  bool _pinVisible = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    if (ResponsiveHelper.isTelevisionDevice) {
      _start();
    }
  }

  Future<void> _start() async {
    final service = TvReceiverService(deviceName: widget.deviceName);
    try {
      await service.start();
    } catch (_) {
      try {
        await service.start(advertise: false);
      } catch (_) {
        return; // sin red utilizable; la app sigue funcionando normal
      }
    }
    _service = service;
    // Mostrar el PIN cuando un móvil intenta conectar; ocultarlo al reproducir.
    _connectSub = service.onClientConnected.listen((_) {
      if (mounted && !_playing) setState(() => _pinVisible = true);
    });
    _loadSub = service.onLoad.listen(_play);
  }

  Future<void> _play(CastLoadRequest req) async {
    if (!mounted) return;
    setState(() {
      _pinVisible = false;
      _playing = true;
    });

    // Reproducir la URL EXACTA que envió el móvil (con SUS credenciales), no la
    // del proveedor local: se construye el ContentItem en contexto M3U para que
    // ContentItem.url = m3uItem.url, y se restaura la playlist al cerrar.
    final saved = AppState.currentPlaylist;
    AppState.currentPlaylist = Playlist(
      id: _castPlaylistId,
      name: 'Cast',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
    final ctype = switch (req.contentType) {
      'vod' => ContentType.vod,
      'series' => ContentType.series,
      _ => ContentType.liveStream,
    };
    final item = ContentItem(
      req.channelId,
      req.title.isEmpty ? 'Cast' : req.title,
      '',
      ctype,
      m3uItem: M3uItem(
        id: req.channelId,
        playlistId: _castPlaylistId,
        url: req.mediaUrl,
        contentType: ctype,
        name: req.title,
      ),
    );

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: PlayerWidget(contentItem: item, queue: [item]),
        ),
      ),
    );
    // Al cerrar el player, restaurar la playlist del usuario.
    AppState.currentPlaylist = saved;
    if (mounted) setState(() => _playing = false);
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    _loadSub?.cancel();
    _service?.stop();
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_pinVisible && _service != null) _pinOverlay(context),
      ],
    );
  }

  Widget _pinOverlay(BuildContext context) {
    final loc = context.loc;
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast, color: _accent, size: 56),
            const SizedBox(height: 20),
            Text(loc.cast_enter_pin,
                style: const TextStyle(color: Colors.white70, fontSize: 22)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF15151A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accent, width: 2),
              ),
              child: Text(
                _service!.pin,
                style: const TextStyle(
                    color: _accent,
                    fontSize: 60,
                    letterSpacing: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => setState(() => _pinVisible = false),
              child: const Text('OK', style: TextStyle(color: Colors.white54, fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
