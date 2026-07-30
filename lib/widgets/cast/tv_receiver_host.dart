// Integra el RECEPTOR de casting en la app cuando corre en Android TV: la misma
// app instalada (que además navega IPTV con normalidad) escucha en la LAN y,
// cuando un móvil emparejado envía un canal, lo reproduce a pantalla completa
// con el PlayerWidget/media_kit. En móvil/tablet este host es transparente.
//
// No usa Cast Connect → funciona con la app instalada por sideload.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Playlist;
import 'package:uuid/uuid.dart';

import '../../l10n/localization_extension.dart';
import '../../models/content_type.dart';
import '../../models/m3u_item.dart';
import '../../models/playlist_content_model.dart';
import '../../models/playlist_model.dart';
import '../../services/app_state.dart';
import '../../services/cast/cast_protocol.dart';
import '../../services/cast/cast_tls.dart';
import '../../services/cast/tv_receiver_service.dart';
import '../../services/event_bus.dart';
import '../../services/player_state.dart';
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
  StreamSubscription<Map<String, dynamic>>? _commandSub;
  bool _pinVisible = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    if (ResponsiveHelper.isTelevisionDevice) {
      _start();
    }
  }

  Future<CastTls?> _loadOrCreateCert() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    try {
      final cert = await storage.read(key: 'cast.tls.cert');
      final key = await storage.read(key: 'cast.tls.key');
      if (cert != null && key != null) {
        return CastTls.fromStorage({'cert': cert, 'key': key});
      }
      final tls = CastTls.generate(); // costoso: solo la 1ª vez
      await storage.write(key: 'cast.tls.cert', value: tls.certPem);
      await storage.write(key: 'cast.tls.key', value: tls.keyPem);
      return tls;
    } catch (_) {
      return null; // si falla, se sirve ws:// (degradado)
    }
  }

  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _trustTtlMs = 7 * 24 * 60 * 60 * 1000; // 7 días
  List<Map<String, dynamic>> _tokenEntries = [];

  /// Id estable de esta TV (uuid persistido).
  Future<String> _loadTvId() async {
    var id = await _store.read(key: 'cast.tv.id');
    if (id == null) {
      id = const Uuid().v4();
      await _store.write(key: 'cast.tv.id', value: id);
    }
    return id;
  }

  /// Tokens de confianza vigentes (poda los de más de 7 días).
  Future<List<String>> _loadTokens() async {
    final raw = await _store.read(key: 'cast.tv.tokens');
    final now = DateTime.now().millisecondsSinceEpoch;
    _tokenEntries = raw != null
        ? (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .where((e) => now - (e['iat'] as int) < _trustTtlMs)
            .toList()
        : [];
    return _tokenEntries.map((e) => e['t'] as String).toList();
  }

  Future<void> _start() async {
    final tls = await _loadOrCreateCert();
    String tvId = '';
    List<String> tokens = const [];
    try {
      tvId = await _loadTvId();
      tokens = await _loadTokens();
    } catch (_) {/* sin confianza persistida; se pedirá PIN */}
    final service = TvReceiverService(
      deviceName: widget.deviceName,
      tls: tls,
      tvId: tvId,
      knownTokens: tokens,
      onIssueToken: (token) {
        // Recordar el dispositivo emparejado 7 días (sin UI de gestión).
        _tokenEntries
            .add({'t': token, 'iat': DateTime.now().millisecondsSinceEpoch});
        _store.write(key: 'cast.tv.tokens', value: jsonEncode(_tokenEntries));
      },
    );
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
    _commandSub = service.onCommand.listen(_handleCommand);
  }

  /// Aplica en la TV los comandos que envía el móvil (control remoto).
  void _handleCommand(Map<String, dynamic> msg) {
    switch (msg['c']) {
      case CmdType.playPause:
        EventBus().emit('cast_play_pause', true);
        break;
      case CmdType.stop:
        if (_playing) Navigator.of(context, rootNavigator: true).maybePop();
        break;
      case CmdType.getTracks:
        _service?.sendMessage('tracks', {
          'audio': _serializeTracks(
              PlayerState.audios, PlayerState.selectedAudio.id),
          'sub': _serializeTracks(
              PlayerState.subtitles, PlayerState.selectedSubtitle.id),
        });
        break;
      case CmdType.selectAudio:
        final id = msg['id'] as String? ?? '';
        final t = PlayerState.audios.firstWhere((x) => x.id == id,
            orElse: () => AudioTrack.auto());
        EventBus().emit('audio_track_changed', t);
        break;
      case CmdType.selectSubtitle:
        final id = msg['id'] as String? ?? '';
        final t = id.isEmpty || id == 'no'
            ? SubtitleTrack.no()
            : PlayerState.subtitles.firstWhere((x) => x.id == id,
                orElse: () => SubtitleTrack.no());
        EventBus().emit('subtitle_track_changed', t);
        break;
    }
  }

  List<Map<String, dynamic>> _serializeTracks(List<dynamic> tracks, String selId) {
    return [
      for (final t in tracks)
        {
          'id': t.id as String,
          'label': (t.title ?? t.language ?? t.id) as String,
          'sel': t.id == selId,
        }
    ];
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
    _commandSub?.cancel();
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
