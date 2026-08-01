// Controlador de casting del lado móvil (arquitectura D). Orquesta el ciclo
// completo que consume la UI: descubrir TVs → conectar → emparejar por PIN →
// enviar el canal (LOAD) → controlar (zap/pausa/stop). Envuelve
// PhoneSenderService y expone un estado observable (ChangeNotifier).
//
// Las credenciales del proveedor salen de la playlist activa (hidratada con
// secretos) y viajan cifradas por el canal de control; nunca a un backend.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/content_type.dart';
import '../models/watch_history.dart';
import '../services/app_state.dart';
import '../services/event_bus.dart';
import '../services/cast/cast_protocol.dart';
import '../services/cast/cast_trust_store.dart';
import '../services/cast/local_file_server.dart';
import '../services/cast/phone_sender_service.dart';
import '../services/watch_history_service.dart';

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
  final String contentType; // 'live' | 'vod' | 'series' | 'file'
  final String title;
  final String ext; // container_extension para VOD/series (vacío en vivo)

  // Contexto para reconstruir un WatchHistory en el móvil desde la posición que
  // reporta la TV (así el cast alimenta "continuar viendo"). Todos opcionales:
  // un cast de archivo local no tiene playlist (playlistId '').
  final String imagePath;
  final String playlistId;
  final String? seriesId;

  // streamId con el que ESCRIBIR el historial. DEBE coincidir con la clave que
  // usa el reproductor normal (Xtream: contentItem.id; M3U: m3uItem.id), NO con
  // channelId (que en M3U es la URL) — si no, se duplican filas de "continuar
  // viendo". Vacío → se cae a channelId.
  final String historyId;

  // Posición (ms) desde la que la TV debe REANUDAR al recibir este LOAD. Lleva la
  // última posición conocida del móvil (su "continuar viendo") para que castear
  // un título a medias NO empiece en 0 en la TV. 0 → sin resume (arranca desde el
  // principio, comportamiento de siempre). Compat. hacia atrás: un LOAD sin `pos`
  // se decodifica a 0. Para vivo se ignora (no es buscable).
  final int startPositionMs;

  // Metadatos TMDb OPCIONALES (sinopsis + reparto) que el móvil resolvió para
  // este contenido. Viajan con el LOAD para que el panel de pausa de la TV los
  // muestre sin que la TV necesite clave TMDb. Null → LOAD sin `meta` (idéntico
  // a antes). Para series todos los episodios de la cola comparten el mismo meta
  // (el de la SERIE), así el auto-avance sigue mostrando la ficha correcta.
  final CastMeta? meta;
  const CastMedia({
    required this.channelId,
    required this.contentType,
    required this.title,
    this.ext = '',
    this.imagePath = '',
    this.playlistId = '',
    this.seriesId,
    this.historyId = '',
    this.meta,
    this.startPositionMs = 0,
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
  // true tras que OTRO dispositivo tomara el control de la TV (mensaje
  // `superseded`): la sesión se cedió en silencio y NO debe reconectar. Se
  // rearma en cada beginCast (un cast nuevo puede volver a reconectar).
  bool _superseded = false;
  List<CastMedia>? _queue; // catálogo para el zapping (lo tiene el móvil)
  int _index = 0;
  List<CastTrack> _audioTracks = const [];
  List<CastTrack> _subtitleTracks = const [];

  // Historial desde la posición que reporta la TV (para "continuar viendo").
  // Se construye perezosamente al escribir: WatchHistoryService resuelve
  // AppDatabase de GetIt, que no existe en tests que solo montan el controlador.
  DateTime? _lastHistoryWrite; // throttle de escrituras a la BD (~10s)
  int _lastPos = 0; // última posición conocida (ms) reportada por la TV
  int _lastDur = 0; // última duración conocida (ms) reportada por la TV

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
    _superseded = false; // un cast nuevo puede volver a reconectar
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
      _sender = _senderFactory()
        ..onDisconnected = _onDisconnected
        ..onEnded = _onEnded
        ..onCompleted = _onCompleted
        ..onSuperseded = _onSuperseded;
      _sender!.onTracks.listen(_onTracks);
      _sender!.onState.listen(_onState);
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
      meta: media.meta,
      startPositionMs: await _resolveStartPosition(media),
    );
    return true;
  }

  /// Posición (ms) de resume a incluir en el LOAD. Prefiere la que trae el
  /// CastMedia (ya resuelta por el móvil); si es 0, la busca best-effort en el
  /// historial local ("continuar viendo") para que castear un título a medias
  /// arranque donde el usuario lo dejó, no en 0. Nunca lanza (sin BD → 0). No
  /// aplica a vivo (no buscable) ni a archivo local.
  Future<int> _resolveStartPosition(CastMedia media) async {
    if (media.startPositionMs > 0) return media.startPositionMs;
    if (media.contentType == 'live' || media.contentType == 'file') return 0;
    final playlistId = media.playlistId.isNotEmpty
        ? media.playlistId
        : (AppState.currentPlaylist?.id ?? '');
    final streamId =
        media.historyId.isNotEmpty ? media.historyId : media.channelId;
    if (playlistId.isEmpty || streamId.isEmpty) return 0;
    try {
      // Timeout: un read de BD colgado NUNCA debe bloquear el sendLoad (el LOAD
      // debe salir; sin posición se arranca desde el principio).
      final h = await WatchHistoryService()
          .getWatchHistory(playlistId, streamId)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      return h?.watchDuration?.inMilliseconds ?? 0;
    } catch (_) {
      return 0; // sin BD (p. ej. tests que solo montan el controlador) → 0
    }
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
    String imagePath = '',
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
        imagePath: imagePath,
      ),
      localUrl: lanUrl,
    );
    // Descubrimiento/conexión fallidos: soltar el servidor de archivos.
    if (_phase == CastPhase.error) {
      await _fileServer?.stop();
      _localUrl = null;
    }
  }

  /// Coexistencia móvil↔TV — política "el casting manda". Reemplaza EN CALIENTE
  /// lo que reproduce la TV por [media], reutilizando la sesión de casting YA
  /// abierta (sin redescubrir ni volver a emparejar). Lo usa el móvil cuando el
  /// usuario abre un título MIENTRAS castea: en vez de reproducirlo en el
  /// teléfono (doble reproducción + controles desincronizados), se reenvía a la
  /// TV como un re-LOAD sobre la sesión viva. No-op si no hay sesión activa.
  /// Devuelve true si el re-LOAD se envió; false si no había sesión utilizable
  /// (idle, o reconectándose con el socket muerto) o si el envío falló.
  Future<bool> castNext(CastMedia media,
      {List<CastMedia>? queue, int index = 0}) async {
    // No tocar durante _reconnect: `_phase` sigue `casting` pero `_sender`
    // apunta a un socket muerto en pleno backoff → un `_sendLoad` ahora
    // lanzaría. No-op seguro; el usuario reintenta cuando la sesión estabilice.
    if (_phase != CastPhase.casting || _sender == null || _reconnecting) {
      return false;
    }
    // Un re-LOAD de stream normal suelta cualquier archivo local previo: el
    // nuevo título arma su URL con las credenciales de la playlist activa, no
    // con una URL de archivo caduca (misma limpieza que hace beginCast).
    await _fileServer?.stop();
    _fileServer = null;
    _localUrl = null;
    _localFilePath = null;
    _media = media;
    _queue = queue;
    _index = index;
    _audioTracks = const [];
    _subtitleTracks = const [];
    // Cortar el arrastre de posición del título anterior (la TV arranca el nuevo
    // en 0); si no, un 'state' rezagado escribiría su posición sobre el entrante.
    _lastPos = 0;
    _lastDur = 0;
    _lastHistoryWrite = null;
    notifyListeners();
    try {
      await _sendLoad();
      return true;
    } catch (_) {
      // El socket se cayó justo al enviar: no romper la sesión. Si esto disparó
      // onDisconnected, _reconnect reenviará este `_media` (ya actualizado).
      return false;
    }
  }

  /// Igual que [castNext] pero para una descarga OFFLINE: sirve el archivo por
  /// la LAN (con Range para seek) y hace un re-LOAD con la URL local sobre la
  /// sesión de casting ya abierta (sin re-emparejar). No-op si no hay sesión o
  /// si el archivo no se puede servir / no hay IP LAN (deja la TV como estaba).
  /// Devuelve true si el re-LOAD del archivo se envió; false si no había sesión
  /// utilizable (idle/reconectando), no hay Wi-Fi, o el servido/envío falló.
  Future<bool> castNextLocalFile({
    required String filePath,
    required String contentId,
    required String title,
    String ext = '',
    String imagePath = '',
  }) async {
    // Mismo blindaje que castNext: no re-LOAD sobre un socket muerto en backoff.
    if (_phase != CastPhase.casting || _sender == null || _reconnecting) {
      return false;
    }
    final server = _fileServer ??= LocalFileServer();
    final String lanUrl;
    try {
      lanUrl = await server.serve(filePath);
    } catch (_) {
      return false; // no se pudo servir: no romper la sesión en curso
    }
    if (await server.lanIp() == null) return false; // sin Wi-Fi utilizable
    _localFilePath = filePath;
    _localUrl = lanUrl;
    _media = CastMedia(
      channelId: contentId,
      contentType: 'file',
      title: title,
      ext: ext,
      imagePath: imagePath,
    );
    _queue = null;
    _index = 0;
    _audioTracks = const [];
    _subtitleTracks = const [];
    _lastPos = 0;
    _lastDur = 0;
    _lastHistoryWrite = null;
    notifyListeners();
    try {
      await _sendLoad();
      return true;
    } catch (_) {
      return false;
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
        imagePath: media.imagePath,
      );
    } else {
      beginCast(media, queue: _queue, index: _index);
    }
  }

  /// El socket se cayó: si estábamos transmitiendo, reconecta y reanuda el
  /// control sin volver a pedir el PIN (lo tenemos cacheado).
  void _onDisconnected() {
    // Si nos cedieron el control (superseded), el cierre es esperado: NO pelear
    // por recuperar la TV (la controla ahora otro dispositivo).
    if (_superseded) return;
    if (_phase == CastPhase.casting && !_reconnecting) _reconnect();
  }

  /// OTRO dispositivo tomó el control de la TV. Cesión SILENCIOSA: ni error, ni
  /// reconexión, ni comando `stop` (eso mataría la reproducción del nuevo
  /// dueño). Solo soltamos nuestros recursos y vamos a idle; el mini-control y
  /// la UI de cast desaparecen solos al no estar ya en `casting`.
  void _onSuperseded() {
    if (_phase == CastPhase.idle) return;
    _superseded = true;
    // Bloquea SÍNCRONAMENTE que el cierre de socket que sigue dispare _reconnect
    // (mismo patrón que _onEnded; el teardown es async y aún no puso idle).
    _reconnecting = true;
    unawaited(_teardownSilently());
  }

  /// Teardown sin efectos hacia la TV (a diferencia de [stopCasting], NO envía
  /// `stop`): la TV ya la controla otro dispositivo.
  Future<void> _teardownSilently() async {
    final sender = _sender;
    _sender = null;
    _localUrl = null;
    _localFilePath = null;
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
    _lastHistoryWrite = null;
    _lastPos = 0;
    _lastDur = 0;
    _set(CastPhase.idle); // SIN error → la UI de cast/mini-control se retira sola
    await _fileServer?.stop();
    _fileServer = null;
    await sender?.close();
  }

  /// La TV avisó que dejó de reproducir (BACK en la TV, fin del contenido o
  /// stop en su lado): salir de "casting" hacia idle SIN reconectar.
  void _onEnded() {
    if (_phase == CastPhase.idle) return;
    // Bloquea SÍNCRONAMENTE que el cierre de socket que sigue dispare
    // _reconnect (stopCasting es async y aún no ha puesto phase=idle).
    _reconnecting = true;
    unawaited(stopCasting());
  }

  /// La TV avisó que el título TERMINÓ (fin de archivo, no un stop del usuario).
  /// Si estábamos casteando una SERIE y quedan episodios en la cola, avanzamos
  /// automáticamente reenviando un LOAD del siguiente (el móvil tiene el
  /// catálogo; la TV reemplaza la reproducción en el mismo sitio). Para VOD o
  /// para el último episodio no hacemos nada: la TV se queda en el fotograma
  /// final y el usuario sale con BACK (que dispara `ended` → idle).
  void _onCompleted() {
    if (_phase != CastPhase.casting) return;
    final q = _queue;
    final media = _media;
    if (media != null &&
        media.contentType == 'series' &&
        q != null &&
        _index + 1 < q.length) {
      _index++;
      _media = q[_index];
      _audioTracks = const [];
      _subtitleTracks = const [];
      // Historial: cortar el arrastre de posición del episodio anterior para no
      // escribir su posición sobre el nuevo (la TV arranca el siguiente en 0).
      _lastPos = 0;
      _lastDur = 0;
      _lastHistoryWrite = null;
      notifyListeners();
      unawaited(_sendLoad());
    }
  }

  Future<void> _reconnect() async {
    if (_superseded) return; // cedido a otro dispositivo: no reconectar
    final device = _device, pin = _pin, media = _media;
    final playlist = AppState.currentPlaylist;
    if (device == null || pin == null || media == null || playlist == null) return;
    _reconnecting = true;
    for (var attempt = 0; attempt < 5 && _phase == CastPhase.casting; attempt++) {
      await Future<void>.delayed(Duration(seconds: 1 << attempt)); // 1,2,4,8,16s
      try {
        _sender = _senderFactory()
          ..onDisconnected = _onDisconnected
          ..onEnded = _onEnded
          ..onCompleted = _onCompleted
          ..onSuperseded = _onSuperseded;
        _sender!.onTracks.listen(_onTracks);
        _sender!.onState.listen(_onState);
        await _sender!.connect(device.host, device.port, secure: device.secure);
        if (await _sender!.pair(pin)) {
          await _sendLoad();
          _reconnecting = false;
          return; // control recuperado
        }
      } catch (_) {/* reintentar con backoff */}
    }
    _reconnecting = false;
    // Agotados los reintentos sin recuperar el control: la TV se fue de verdad.
    // No dejar el móvil colgado en "casting" (mini-control fantasma / círculo de
    // carga infinito): terminar limpio.
    if (_phase == CastPhase.casting) await stopCasting();
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

  /// La TV reporta su posición de reproducción (MsgType.state). La usamos para
  /// escribir un WatchHistory en el móvil, de modo que lo casteado aparezca en
  /// "continuar viendo". Throttle a ~1 escritura cada 10s.
  void _onState(Map<String, dynamic> msg) {
    // Ignorar ticks rezagados de OTRO contenido: al auto-avanzar de episodio, un
    // 'state' final del episodio saliente (pos≈dur) podía llegar tras el swap de
    // _media y escribirse bajo el streamId del ENTRANTE (marcándolo ~100% visto).
    final id = msg['id'] as String?;
    if (id != null && _media != null && id != _media!.channelId) return;
    final pos = (msg['pos'] as num?)?.toInt() ?? 0;
    final dur = (msg['dur'] as num?)?.toInt() ?? 0;
    if (pos <= 0 || dur <= 0) return;
    _lastPos = pos;
    _lastDur = dur;
    final now = DateTime.now();
    final last = _lastHistoryWrite;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastHistoryWrite = now;
    _writeHistory(pos, dur);
  }

  /// Persiste un WatchHistory con la posición/duración conocidas del cast.
  /// Nunca deja que un fallo de BD rompa el casting.
  Future<void> _writeHistory(int posMs, int durMs) async {
    final media = _media;
    if (media == null) return;
    // Un archivo local no tiene ancla de catálogo (playlistId '') y su id puede
    // colisionar con la PK {playlist, streamId} del historial real de OTRO
    // contenido (insertOnConflictUpdate lo pisaría, degradando serie→vod). No
    // registramos historial para casts de archivo local.
    if (media.contentType == 'file') return;
    final contentType = switch (media.contentType) {
      'series' => ContentType.series,
      'vod' => ContentType.vod,
      _ => ContentType.liveStream,
    };
    final playlistId = media.playlistId.isNotEmpty
        ? media.playlistId
        : (AppState.currentPlaylist?.id ?? '');
    // streamId = la MISMA clave que usa el reproductor normal (evita duplicar
    // filas de "continuar viendo", sobre todo en M3U donde channelId es la URL).
    final streamId = media.historyId.isNotEmpty ? media.historyId : media.channelId;
    if (playlistId.isEmpty || streamId.isEmpty) return;
    try {
      final service = WatchHistoryService();
      // Avance-solo: la TV arranca en la posición de resume que le envió el móvil
      // en el LOAD (o 0 si no había), así que el reporte refleja el progreso real.
      // Si ya había una posición MAYOR para este título, NO la reducimos — casear
      // un título a medias no debe resetear su "continuar viendo".
      final existing = await service.getWatchHistory(playlistId, streamId);
      final existingMs = existing?.watchDuration?.inMilliseconds ?? 0;
      if (existingMs > posMs) return;
      await service.saveWatchHistory(
        WatchHistory(
          playlistId: playlistId,
          contentType: contentType,
          streamId: streamId,
          seriesId: media.seriesId,
          watchDuration: Duration(milliseconds: posMs),
          totalDuration: Duration(milliseconds: durMs),
          lastWatched: DateTime.now(),
          imagePath: media.imagePath,
          title: media.title,
        ),
      );
      // "Continuar viendo" del móvil se refresca con lo casteado a la TV.
      EventBus().emit('history_changed', null);
    } catch (_) {/* una escritura de historial nunca rompe el casting */}
  }

  /// Termina el casting y vuelve a idle (la TV libera el stream).
  Future<void> stopCasting() async {
    // Escritura final: si tenemos una última posición conocida, persistirla
    // (así un título casi terminado se registra con su progreso real).
    if (_lastPos > 0 && _lastDur > 0) {
      await _writeHistory(_lastPos, _lastDur);
    }
    final sender = _sender;
    sender?.sendCommand(CmdType.stop);
    // Pasar a idle YA: la UI (mini-control) refleja el stop al instante, sin
    // esperar al teardown del socket. El _sender se conserva en una local para
    // cerrarlo en segundo plano tras dejar salir el frame 'stop'.
    _sender = null;
    _localUrl = null;
    _localFilePath = null;
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
    _lastHistoryWrite = null;
    _lastPos = 0;
    _lastDur = 0;
    _set(CastPhase.idle);
    await _fileServer?.stop();
    // Teardown del socket en segundo plano: dar un instante a que el frame
    // 'stop' salga ANTES de cerrar (cerrar de inmediato podía descartarlo y
    // dejar la TV reproduciendo mientras el móvil ya está en idle).
    if (sender != null) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await sender.close();
    }
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
