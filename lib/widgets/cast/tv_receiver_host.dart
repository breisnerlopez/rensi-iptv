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

  // Reenvío de posición TV→móvil (para "continuar viendo" en el teléfono).
  StreamSubscription<Map<String, dynamic>>? _positionSub;
  DateTime? _lastStateSent; // throttle: como mucho 1 envío cada ~5s
  int _lastPos = 0;
  int _lastDur = 0;
  String _currentChannelId = '';

  // Fin-de-título → móvil (para auto-avance de series). El PlayerWidget de la TV
  // emite 'cast_player_completed' al acabar un VOD/serie; lo reenviamos como
  // MsgType.completed. Distinto de MsgType.ended (BACK/stop cierra la ruta).
  StreamSubscription<String>? _completedSub;
  bool _completedSent = false;

  // Reemplazo de reproducción EN EL MISMO SITIO: un re-LOAD (zapping, auto-avance
  // o reenvío) NO empuja otra ruta de player encima (eso apilaba reproductores y
  // dejaba uno viejo "Preparando…" detrás al hacer BACK). En su lugar se cambia
  // el contenido del player ya montado a través de este notifier.
  // El valor lleva un contador monótono de LOAD además del request: la key del
  // PlayerWidget se deriva del contador (no de identityHashCode, que podría
  // colisionar entre dos requests y NO reinicializar el player en el swap).
  ValueNotifier<(int, CastLoadRequest)>? _loadNotifier;
  int _loadSeq = 0;
  bool _castRouteOpen = false;

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
        if (_playing) {
          _stopPositionForwarding(sendFinal: true);
          Navigator.of(context, rootNavigator: true).maybePop();
        }
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
    // (Re)empezar a reenviar posición/fin-de-título al móvil. Se llama en CADA
    // LOAD (incluido el re-LOAD de auto-avance/zapping) para reengancharse al
    // nuevo contenido.
    _completedSent = false;
    _startPositionForwarding(req.channelId);

    // Re-LOAD sobre una sesión ya abierta (zapping en vivo, auto-avance de serie
    // o reenvío): cambiar el contenido del player YA montado en vez de empujar
    // otra ruta encima. Así no se apilan reproductores (causa de "vuelve al
    // contador Preparando… al hacer BACK") ni se envía `ended` (la sesión sigue).
    if (_castRouteOpen && _loadNotifier != null) {
      _loadNotifier!.value = (++_loadSeq, req);
      return;
    }

    // Primer LOAD de la sesión: reproducir la URL EXACTA que envió el móvil (con
    // SUS credenciales), no la del proveedor local. El ContentItem se arma en
    // contexto M3U (ContentItem.url = m3uItem.url) bajo la playlist sintética
    // '__cast__', y se restaura la playlist del usuario al cerrar.
    final saved = AppState.currentPlaylist;
    AppState.currentPlaylist = Playlist(
      id: _castPlaylistId,
      name: 'Cast',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
    final notifier =
        _loadNotifier = ValueNotifier<(int, CastLoadRequest)>((++_loadSeq, req));
    _castRouteOpen = true;

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _CastPlayerScreen(loadNotifier: notifier),
      ),
    );
    // Al CERRAR la ruta del player (BACK en la TV o stop del móvil), enviar una
    // última posición, avisar al móvil que la TV DEJÓ de reproducir (para que
    // salga de "casting" y no entre en bucle de reconexión), cortar el reenvío,
    // y restaurar la playlist del usuario.
    _castRouteOpen = false;
    _loadNotifier = null;
    notifier.dispose();
    _stopPositionForwarding(sendFinal: true);
    _service?.sendMessage(MsgType.ended, const {});
    AppState.currentPlaylist = saved;
    // El home reducido de la TV lee el historial una sola vez; avisarle de que
    // acaba de reproducirse algo (guardado bajo '__cast__') para que lo recargue
    // y el contenido casteado aparezca en su rail de "historial".
    EventBus().emit('tv_history_changed', null);
    if (mounted) setState(() => _playing = false);
  }

  /// Suscribe el reenvío de posición mientras un cast está en curso. El player
  /// (que corre aquí, en la TV) emite 'cast_player_position'; lo mandamos al
  /// móvil como MsgType.state throttled a como mucho 1 vez cada ~5s.
  void _startPositionForwarding(String channelId) {
    _currentChannelId = channelId;
    _lastStateSent = null;
    _lastPos = 0;
    _lastDur = 0;
    // Fin-de-título: el player de la TV emite 'cast_player_completed' al acabar
    // un VOD/serie. Reenviarlo UNA vez por episodio (el guard evita duplicados
    // si el stream 'completed' de media_kit reemite) para que el móvil decida el
    // auto-avance. No se envía en vivo (ese caso reabre en el propio player).
    _completedSub?.cancel();
    _completedSub =
        EventBus().on<String>('cast_player_completed').listen((_) {
      if (!_playing || _completedSent) return;
      _completedSent = true;
      _service?.sendMessage(MsgType.completed, {'id': _currentChannelId});
    });
    _positionSub?.cancel();
    _positionSub =
        EventBus().on<Map<String, dynamic>>('cast_player_position').listen((e) {
      final pos = (e['pos'] as num?)?.toInt() ?? 0;
      final dur = (e['dur'] as num?)?.toInt() ?? 0;
      // Simetría con el receptor en el móvil: sin duración fiable no hay nada
      // que registrar en "continuar viendo" (evita mandar dur:0 en vivo).
      if (pos <= 0 || dur <= 0) return;
      _lastPos = pos;
      _lastDur = dur;
      final now = DateTime.now();
      final last = _lastStateSent;
      if (last != null && now.difference(last) < const Duration(seconds: 5)) {
        return;
      }
      _lastStateSent = now;
      _sendState(pos, dur);
    });
  }

  /// Corta el reenvío de posición; si [sendFinal], manda una última posición
  /// (para que un título casi terminado quede bien registrado en el móvil).
  void _stopPositionForwarding({bool sendFinal = false}) {
    _positionSub?.cancel();
    _positionSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    if (sendFinal && _lastPos > 0) {
      _sendState(_lastPos, _lastDur);
    }
  }

  void _sendState(int pos, int dur) {
    _service?.sendMessage(MsgType.state, {
      'status': 'playing',
      'pos': pos,
      'dur': dur,
      'id': _currentChannelId,
    });
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    _loadSub?.cancel();
    _commandSub?.cancel();
    _positionSub?.cancel();
    _completedSub?.cancel();
    _loadNotifier?.dispose();
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

/// Ruta ÚNICA del player receptor durante una sesión de casting. En vez de
/// empujar una ruta nueva por cada LOAD, esta pantalla observa un notifier y
/// reconstruye el [PlayerWidget] con una key nueva cuando llega otro contenido
/// (zapping / auto-avance de serie). Así el BACK siempre vuelve al home de la TV
/// (no a un player viejo apilado) y no hay doble audio.
class _CastPlayerScreen extends StatelessWidget {
  const _CastPlayerScreen({required this.loadNotifier});

  final ValueNotifier<(int, CastLoadRequest)> loadNotifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<(int, CastLoadRequest)>(
      valueListenable: loadNotifier,
      builder: (context, value, _) {
        final (seq, req) = value;
        final item = _castItemFor(req);
        return Scaffold(
          backgroundColor: Colors.black,
          // Key por el contador monótono del LOAD: cada re-LOAD tiene un seq
          // distinto, así el player se reinicializa por completo con el nuevo
          // contenido (sin riesgo de colisión de identityHashCode).
          body: PlayerWidget(
            key: ValueKey('cast-$seq'),
            contentItem: item,
            queue: [item],
            // Ficha TMDb (sinopsis + reparto) que envió el móvil con el LOAD; el
            // panel de pausa la pinta sin llamar a TMDb (la TV no tiene clave).
            castMeta: req.meta,
            // Resume: reanudar donde el móvil lo dejó (0 → desde el principio).
            // La TV no tiene el historial local del móvil, así que sin esto un
            // título a medias arrancaría siempre en 0.
            startPositionMs: req.startPositionMs,
          ),
        );
      },
    );
  }
}

/// Reconstruye un [ContentItem] reproducible desde un LOAD del móvil. Se arma en
/// contexto M3U para que ContentItem.url resuelva a la URL EXACTA que envió el
/// móvil (con sus credenciales), no una URL Xtream del proveedor local.
ContentItem _castItemFor(CastLoadRequest req) {
  final ctype = switch (req.contentType) {
    'vod' => ContentType.vod,
    'series' => ContentType.series,
    // Archivo local (descarga offline) enviado por LAN: tratarlo como VOD para
    // que el player ofrezca barra de progreso/seek.
    'file' => ContentType.vod,
    _ => ContentType.liveStream,
  };
  return ContentItem(
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
}
