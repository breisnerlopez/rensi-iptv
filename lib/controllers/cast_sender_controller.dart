// Controlador de casting del lado móvil (arquitectura D). Orquesta el ciclo
// completo que consume la UI: descubrir TVs → conectar → emparejar por PIN →
// enviar el canal (LOAD) → controlar (zap/pausa/stop). Envuelve
// PhoneSenderService y expone un estado observable (ChangeNotifier).
//
// Las credenciales del proveedor salen de la playlist activa (hidratada con
// secretos) y viajan cifradas por el canal de control; nunca a un backend.
import 'package:flutter/foundation.dart';

import '../services/app_state.dart';
import '../services/cast/cast_protocol.dart';
import '../services/cast/cast_trust_store.dart';
import '../services/cast/local_file_server.dart';
import '../services/cast/phone_sender_service.dart';

enum CastPhase {
  idle, // sin castear
  discovering, // buscando TVs en la red
  devicesFound, // hay TVs; el usuario elige
  connecting, // abriendo el canal con la TV elegida
  pairing, // esperando/validando el PIN
  casting, // reproduciendo en la TV; el móvil es control
  error,
}

/// Descripción de un contenido a castear (independiente de los modelos de UI).
class CastMedia {
  final String channelId;
  final String contentType; // 'live' | 'vod' | 'series'
  final String title;
  final String ext; // container_extension para VOD/series (vacío en vivo)
  const CastMedia({
    required this.channelId,
    required this.contentType,
    required this.title,
    this.ext = '',
  });
}

/// Una pista (audio o subtítulo) que la TV reporta, para el selector del móvil.
class CastTrack {
  final String id;
  final String label;
  final bool selected;
  const CastTrack({required this.id, required this.label, required this.selected});

  factory CastTrack.fromJson(Map<String, dynamic> j) => CastTrack(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        selected: j['sel'] == true,
      );
}

class CastSenderController extends ChangeNotifier {
  CastSenderController({
    PhoneSenderService Function()? senderFactory,
    CastTrustStore trustStore = const CastTrustStore(),
  })  : _senderFactory = senderFactory ?? PhoneSenderService.new,
        _trust = trustStore;

  final PhoneSenderService Function() _senderFactory;
  final CastTrustStore _trust;
  PhoneSenderService? _sender;

  // Streaming de un archivo LOCAL (descarga offline) del móvil a la TV por la
  // LAN. Cuando [_localUrl] != null, el LOAD envía esta URL (sin credenciales)
  // en vez de armar la URL Xtream desde la playlist activa.
  LocalFileServer? _fileServer;
  String? _localUrl;
  String? _localFilePath; // recordado para reintentar un cast de archivo local

  CastPhase _phase = CastPhase.idle;
  List<CastDevice> _devices = const [];
  CastDevice? _device;
  CastMedia? _media;
  String? _error;
  bool _wrongPin = false;
  String? _pin; // cacheado tras emparejar, para reconexión transparente
  bool _reconnecting = false;
  List<CastMedia>? _queue; // catálogo para el zapping (lo tiene el móvil)
  int _index = 0;
  List<CastTrack> _audioTracks = const [];
  List<CastTrack> _subtitleTracks = const [];

  List<CastTrack> get audioTracks => List.unmodifiable(_audioTracks);
  List<CastTrack> get subtitleTracks => List.unmodifiable(_subtitleTracks);

  /// El contenido casteado es en vivo (zap ± aplica).
  bool get isLive => _media?.contentType == 'live';

  /// Hay más de un canal en el catálogo para hacer zapping.
  bool get canZap => isLive && _queue != null && _queue!.length > 1;

  CastPhase get phase => _phase;
  List<CastDevice> get devices => List.unmodifiable(_devices);
  CastDevice? get device => _device;
  CastMedia? get media => _media;
  String? get error => _error;

  /// true tras un intento de PIN fallido (para que la UI marque el campo).
  bool get wrongPin => _wrongPin;

  bool get isCasting => _phase == CastPhase.casting;

  void _set(CastPhase p, {String? error}) {
    _phase = p;
    _error = error;
    notifyListeners();
  }

  /// Comienza a descubrir TVs. El contenido a castear se recuerda para enviarlo
  /// en cuanto el emparejamiento termine.
  Future<void> beginCast(CastMedia media,
      {List<CastMedia>? queue, int index = 0, String? localUrl}) async {
    // Un cast normal (sin localUrl) suelta cualquier archivo local previo para
    // que _sendLoad no reutilice una URL de archivo caduca.
    if (localUrl == null) {
      await _fileServer?.stop();
      _localFilePath = null;
    }
    _localUrl = localUrl;
    _media = media;
    _queue = queue;
    _index = index;
    _wrongPin = false;
    _set(CastPhase.discovering);
    try {
      final finder = _senderFactory();
      _devices = await finder.discover(timeout: const Duration(seconds: 4));
      await finder.close();
      if (_devices.isEmpty) {
        _set(CastPhase.error, error: 'no_devices');
        return;
      }
      // Con un solo dispositivo, conectar directo; con varios, que elija.
      if (_devices.length == 1) {
        await connectTo(_devices.first);
      } else {
        _set(CastPhase.devicesFound);
      }
    } catch (e) {
      _set(CastPhase.error, error: e.toString());
    }
  }

  /// Abre el canal con la TV elegida y pasa a pedir el PIN.
  Future<void> connectTo(CastDevice device) async {
    _device = device;
    _set(CastPhase.connecting);
    try {
      _sender = _senderFactory()..onDisconnected = _onDisconnected;
      _sender!.onTracks.listen(_onTracks);
      await _sender!.connect(device.host, device.port, secure: device.secure);
      // ¿TV de confianza (emparejada en los últimos 7 días)? Reanudar SIN PIN.
      final tvId = _sender!.tvId;
      if (tvId != null && tvId.isNotEmpty) {
        final token = await _trust.tokenFor(tvId);
        if (token != null && await _sender!.resume(token)) {
          _pin = token; // reconexión futura reautentica con el token
          await _startPlayback();
          return;
        }
      }
      _set(CastPhase.pairing);
    } catch (e) {
      _set(CastPhase.error, error: e.toString());
    }
  }

  /// Valida el PIN que el usuario leyó en la TV. Si es correcto, castea de una.
  Future<void> submitPin(String pin) async {
    if (_sender == null) return;
    _wrongPin = false;
    try {
      final ok = await _sender!.pair(pin);
      if (!ok) {
        _wrongPin = true;
        notifyListeners();
        return;
      }
      _pin = pin; // para reconexión transparente
      // Recordar la confianza 7 días: la TV emitió un token para no pedir PIN.
      final tvId = _sender!.tvId;
      final token = _sender!.issuedToken;
      if (tvId != null && tvId.isNotEmpty && token != null) {
        await _trust.save(tvId, token);
        _pin = token; // futuras reconexiones/sesiones reautentican con el token
      }
      await _startPlayback();
    } catch (e) {
      _set(CastPhase.error, error: e.toString());
    }
  }

  Future<void> _startPlayback() async {
    if (!await _sendLoad()) {
      _set(CastPhase.error, error: 'no_context');
      return;
    }
    _set(CastPhase.casting);
  }

  Future<bool> _sendLoad() async {
    final media = _media;
    if (_sender == null || media == null) return false;
    final local = _localUrl;
    final String url, user, pass;
    if (local != null) {
      // Archivo local servido por LAN: la URL ES el media, sin credenciales.
      url = local;
      user = '';
      pass = '';
    } else {
      final playlist = AppState.currentPlaylist;
      if (playlist == null) return false;
      url = playlist.url ?? '';
      user = playlist.username ?? '';
      pass = playlist.password ?? '';
    }
    await _sender!.sendLoad(
      channelId: media.channelId,
      contentType: media.contentType,
      url: url,
      username: user,
      password: pass,
      title: media.title,
      ext: media.ext,
    );
    return true;
  }

  /// Envía a la TV un archivo LOCAL ya descargado: lo sirve por HTTP en la LAN
  /// (con Range para permitir seek) y manda un LOAD con la URL local. El vídeo
  /// viaja móvil→TV por Wi-Fi, sin gastar Internet. Requiere estar en la misma
  /// red que la TV (si no hay IP LAN, aborta con error 'no_wifi').
  Future<void> castLocalFile({
    required String filePath,
    required String contentId,
    required String title,
    String ext = '',
  }) async {
    _localFilePath = filePath;
    final server = _fileServer ??= LocalFileServer();
    final String lanUrl;
    try {
      lanUrl = await server.serve(filePath);
    } catch (e) {
      _set(CastPhase.error, error: e.toString());
      return;
    }
    if (await server.lanIp() == null) {
      await server.stop();
      _set(CastPhase.error, error: 'no_wifi');
      return;
    }
    await beginCast(
      CastMedia(
        channelId: contentId,
        contentType: 'file',
        title: title,
        ext: ext,
      ),
      localUrl: lanUrl,
    );
    // Descubrimiento/conexión fallidos: soltar el servidor de archivos.
    if (_phase == CastPhase.error) {
      await _fileServer?.stop();
      _localUrl = null;
    }
  }

  /// Reintenta el último cast tras un error, eligiendo el camino correcto:
  /// re-sirve el archivo local si era un cast de archivo, o redescubre TVs si
  /// era un cast normal de la playlist.
  void retry() {
    final media = _media;
    if (media == null) return;
    final path = _localFilePath;
    if (media.contentType == 'file' && path != null) {
      castLocalFile(
        filePath: path,
        contentId: media.channelId,
        title: media.title,
        ext: media.ext,
      );
    } else {
      beginCast(media, queue: _queue, index: _index);
    }
  }

  /// El socket se cayó: si estábamos transmitiendo, reconecta y reanuda el
  /// control sin volver a pedir el PIN (lo tenemos cacheado).
  void _onDisconnected() {
    if (_phase == CastPhase.casting && !_reconnecting) _reconnect();
  }

  Future<void> _reconnect() async {
    final device = _device, pin = _pin, media = _media;
    final playlist = AppState.currentPlaylist;
    if (device == null || pin == null || media == null || playlist == null) return;
    _reconnecting = true;
    for (var attempt = 0; attempt < 5 && _phase == CastPhase.casting; attempt++) {
      await Future<void>.delayed(Duration(seconds: 1 << attempt)); // 1,2,4,8,16s
      try {
        _sender = _senderFactory()..onDisconnected = _onDisconnected;
        _sender!.onTracks.listen(_onTracks);
        await _sender!.connect(device.host, device.port, secure: device.secure);
        if (await _sender!.pair(pin)) {
          await _sendLoad();
          _reconnecting = false;
          return; // control recuperado
        }
      } catch (_) {/* reintentar con backoff */}
    }
    _reconnecting = false;
  }

  void playPause() => _sender?.sendCommand(CmdType.playPause);

  /// Zap: el móvil (que tiene el catálogo) reenvía un LOAD del canal
  /// siguiente/anterior; la TV cambia de canal sin round-trip de comando.
  Future<void> channelUp() => _zap(1);
  Future<void> channelDown() => _zap(-1);
  Future<void> _zap(int dir) async {
    final q = _queue;
    if (q == null || !isLive) return;
    final next = _index + dir;
    if (next < 0 || next >= q.length) return;
    _index = next;
    _media = q[next];
    _audioTracks = const [];
    _subtitleTracks = const [];
    notifyListeners();
    await _sendLoad();
  }

  /// Pide a la TV su lista de pistas actuales (audio/subtítulo).
  void requestTracks() => _sender?.sendCommand(CmdType.getTracks);

  void selectAudio(String id) =>
      _sender?.sendCommand(CmdType.selectAudio, {'id': id});
  void selectSubtitle(String id) =>
      _sender?.sendCommand(CmdType.selectSubtitle, {'id': id});

  void _onTracks(Map<String, dynamic> msg) {
    List<CastTrack> parse(String key) => ((msg[key] as List?) ?? const [])
        .map((e) => CastTrack.fromJson(e as Map<String, dynamic>))
        .toList();
    _audioTracks = parse('audio');
    _subtitleTracks = parse('sub');
    notifyListeners();
  }

  /// Termina el casting y vuelve a idle (la TV libera el stream).
  Future<void> stopCasting() async {
    _sender?.sendCommand(CmdType.stop);
    await _sender?.close();
    await _fileServer?.stop();
    _localUrl = null;
    _localFilePath = null;
    _sender = null;
    _device = null;
    _media = null;
    _devices = const [];
    _wrongPin = false;
    _pin = null;
    _reconnecting = false;
    _queue = null;
    _index = 0;
    _audioTracks = const [];
    _subtitleTracks = const [];
    _set(CastPhase.idle);
  }

  /// Cancela un flujo a medias (descubrimiento/pairing) sin dejar sockets abiertos.
  Future<void> cancel() => stopCasting();

  @override
  void dispose() {
    _sender?.close();
    _fileServer?.stop();
    super.dispose();
  }
}
