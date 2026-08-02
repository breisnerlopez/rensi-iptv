// Controlador de casting del lado móvil (arquitectura D). Orquesta el ciclo
// completo que consume la UI: descubrir TVs → conectar → emparejar por PIN →
// enviar el canal (LOAD) → controlar (zap/pausa/stop). Envuelve
// PhoneSenderService y expone un estado observable (ChangeNotifier).
//
// Las credenciales del proveedor salen de la playlist activa (hidratada con
// secretos) y viajan cifradas por el canal de control; nunca a un backend.
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_navigator.dart';
import '../services/call_state_service.dart';
import '../services/hardware_volume_service.dart';
import '../models/content_type.dart';
import '../models/playlist_model.dart';
import '../models/watch_history.dart';
import '../repositories/user_preferences.dart';
import '../services/app_state.dart';
import '../services/event_bus.dart';
import '../services/cast/cast_protocol.dart';
import '../services/cast/cast_trust_store.dart';
import '../services/cast/local_file_server.dart';
import '../services/cast/phone_sender_service.dart';
import '../services/cast/standalone_consent_store.dart';
import '../services/watch_history_service.dart';

/// Datos para pedir consentimiento contextual de persistencia standalone
/// (feature H): la UI (cast_flow) los usa para armar el diálogo la primera vez
/// que se castea VOD/serie Xtream a una (TV, proveedor) con el permiso maestro
/// activo y sin consentimiento previo. Ver [CastSenderController.pendingStandaloneConsent].
class StandaloneConsentPrompt {
  final String tvId;
  final String providerId;
  final String deviceName;
  final String providerName;
  const StandaloneConsentPrompt({
    required this.tvId,
    required this.providerId,
    required this.deviceName,
    required this.providerName,
  });
}

/// Id de la playlist sintética del casting en la TV (feature H). Debe coincidir
/// con `_castPlaylistId` de tv_receiver_host.dart. El móvil NUNCA la usa como
/// playlist activa; se comprueba solo para excluirla del sync de historial.
const String _kCastPlaylistId = '__cast__';

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

  // Ruta LOCAL del archivo descargado que respalda este item (null salvo cast
  // de descarga offline). La usa el auto-avance de una SERIE descargada: al
  // terminar un episodio, el móvil re-sirve por LAN el archivo del SIGUIENTE
  // (cada uno con su propia URL) antes del LOAD. En un cast normal (stream) es
  // null y no aplica.
  final String? localFilePath;

  // true SOLO para episodios de una serie DESCARGADA encolados para auto-avanzar.
  // El LOAD sigue viajando con contentType 'file' (la TV lo reproduce como VOD
  // local, igual que un cast de archivo suelto); este flag es lo que permite
  // que `_onCompleted` avance al siguiente episodio descargado sin confundir el
  // caso de stream (contentType 'series') ni el de una PELÍCULA descargada
  // (queue null → no avanza). Un archivo suelto lo deja en false.
  final bool isDownloadedSeries;
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
    this.localFilePath,
    this.isDownloadedSeries = false,
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
    HardwareVolumeService? hwVolume,
    CallStateService? callState,
  })  : _senderFactory = senderFactory ?? PhoneSenderService.new,
        _trust = trustStore,
        _hwVolume = hwVolume ?? HardwareVolumeService.instance,
        _callState = callState ?? const CallStateService() {
    // Route hardware VOLUME_UP/DOWN presses (forwarded by the native layer only
    // while casting) to [nudgeVolume]. The service's channel calls are try/caught
    // no-ops without a native peer, so this stays inert in `flutter test`.
    _hwVolume.onStep = nudgeVolume;
  }

  final PhoneSenderService Function() _senderFactory;
  final CastTrustStore _trust;
  final HardwareVolumeService _hwVolume;
  final CallStateService _callState;
  PhoneSenderService? _sender;

  // Pausa-al-recibir-llamada mientras se castea. Solo se activa cuando el
  // casting empieza Y el toggle (UserPreferences.getPauseCastOnCall) está ON; se
  // pide el permiso READ_PHONE_STATE como mucho UNA vez por sesión de casting.
  // [_callSub] es la suscripción al stream de estado de llamada (null = inactivo,
  // suscribir registra el listener nativo; cancelar lo libera). [_pausedForCall]
  // recuerda que fuimos NOSOTROS quienes pausamos por una llamada (para reanudar
  // solo en ese caso). [_tvPlaying] es el estado de reproducción INTENCIONADO de
  // la TV (playPause es un toggle: sin rastrearlo, una llamada podría dar el
  // toggle equivocado). [_callWatchRequested] evita re-pedir el permiso.
  StreamSubscription<String>? _callSub;
  bool _pausedForCall = false;
  bool _callWatchRequested = false;
  bool _tvPlaying = false;

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

  // Reattach tras una caída de socket (típicamente al backgroundear el móvil):
  // la TV NO deja de reproducir cuando el socket del móvil se cae (su ruta de
  // player sigue abierta). Reenviar un LOAD al reconectar REINICIABA la TV desde
  // una posición vieja y borraba el progreso hecho mientras el móvil no estaba
  // (además de perder el `completed`/`state`/volumen durante el backoff). Ahora
  // el reconnect solo restablece el canal de control y espera a que un `state`
  // de la TV confirme que la sesión sigue viva; solo si NINGUNO llega en esta
  // ventana se recupera con un re-LOAD en la última posición viva (cubre una TV
  // que sí se reinició/paró). Ver [_reconnect]/[_armResyncFallback]/[_onState].
  bool _awaitingResync = false;
  Timer? _resyncTimer;
  // > que el throttle de `state` de la TV (~5s), para que incluso una TV en una
  // build vieja (que no eco un `state` inmediato al reconectar) confirme con su
  // tick periódico ANTES de que el fallback dispare un re-LOAD innecesario.
  static const _resyncTimeout = Duration(seconds: 7);

  // Volumen de reproducción en la TV (escala 0-100, igual que UserPreferences/
  // media_kit). Optimista: se actualiza local al mover el slider y se
  // corrige con lo que la TV reporta de vuelta en MsgType.state (`vol`).
  double _volume = 100;
  double get volume => _volume;
  // true MIENTRAS el usuario arrastra el slider del sheet de casting. Mientras
  // dura, [_onState] IGNORA el eco `vol` de la TV: sin esto, un eco en tránsito
  // de un tick anterior al arrastre llega A MITAD del gesto y hace SALTAR el
  // slider bajo el dedo (el eco “pelea” con la posición que el usuario está
  // arrastrando). Al soltar (endVolumeDrag) se apaga y el próximo eco vuelve a
  // sincronizar con lo que la TV realmente aplicó.
  bool _draggingVolume = false;
  // Debounce del comando `set_volume`: onChanged del Slider dispara por FRAME
  // durante el arrastre; sin esto se mandarían decenas de comandos por gesto.
  // El valor optimista/notifyListeners SÍ es inmediato (el slider se ve fluido);
  // solo el envío por la red se coalesce a como mucho 1 cada ~180ms.
  Timer? _volumeDebounce;
  static const _volumeDebounceDelay = Duration(milliseconds: 180);

  List<CastTrack> get audioTracks => List.unmodifiable(_audioTracks);
  List<CastTrack> get subtitleTracks => List.unmodifiable(_subtitleTracks);

  /// El contenido casteado es en vivo (zap ± aplica).
  bool get isLive => _media?.contentType == 'live';

  /// Hay más de un canal en el catálogo para hacer zapping.
  bool get canZap => isLive && _queue != null && _queue!.length > 1;

  /// El contenido casteado es una serie (por stream o descargada) — el mismo
  /// criterio que usa el auto-avance [_onCompleted] para decidir si saltar al
  /// siguiente episodio.
  bool get _isSeriesCast {
    final m = _media;
    return m != null && (m.contentType == 'series' || m.isDownloadedSeries);
  }

  /// Hay un episodio siguiente al que saltar MANUALMENTE mientras se castea una
  /// serie (el "Siguiente episodio" al estilo Netflix, pero enviado a la TV).
  /// Mismo criterio de "hay siguiente" que el auto-avance, más el blindaje de no
  /// tocar la sesión durante la reconexión (socket muerto en backoff).
  bool get canCastNextEpisode =>
      _phase == CastPhase.casting &&
      !_reconnecting &&
      _isSeriesCast &&
      _queue != null &&
      _index >= 0 &&
      _index + 1 < _queue!.length;

  CastPhase get phase => _phase;
  List<CastDevice> get devices => List.unmodifiable(_devices);
  CastDevice? get device => _device;
  CastMedia? get media => _media;
  String? get error => _error;

  /// true tras un intento de PIN fallido (para que la UI marque el campo).
  bool get wrongPin => _wrongPin;

  bool get isCasting => _phase == CastPhase.casting;

  void _set(CastPhase p, {String? error}) {
    final wasCasting = _phase == CastPhase.casting;
    _phase = p;
    _error = error;
    // Tell the native layer to intercept (or release) the phone's hardware
    // volume keys exactly when casting starts/stops. Best-effort no-op off-device.
    final nowCasting = p == CastPhase.casting;
    if (nowCasting != wasCasting) {
      _hwVolume.setCastingActive(nowCasting);
      if (nowCasting) {
        // La TV arranca reproduciendo tras el LOAD; empieza a vigilar llamadas.
        _tvPlaying = true;
        unawaited(_maybeStartCallWatch());
      } else {
        _stopCallWatch();
      }
    }
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
    _cancelResync(); // un cast nuevo no debe arrastrar un reenganche pendiente
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
      _sender!.onHistorySync.listen(_onHistorySync);
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
    // Feature H — emparejados con esta TV: descargar cualquier borrado de
    // credenciales pendiente (revocado mientras estábamos desconectados) ANTES
    // del LOAD. Best-effort y no bloqueante: nunca debe impedir castear.
    unawaited(_flushPendingStandaloneWipes());
    if (!await _sendLoad()) {
      _set(CastPhase.error, error: 'no_context');
      return;
    }
    _set(CastPhase.casting);
    // Feature H (fase 5) — tras emparejar/reanudar, sincronizar "continuar
    // viendo" con la TV (una sola vez por conexión). Best-effort y no bloqueante.
    unawaited(_syncHistory());
  }

  /// [resumeOverrideMs] fuerza la posición de resume del LOAD (gana sobre el
  /// CastMedia y el historial). Lo usa la recuperación del reconnect para
  /// reanudar EXACTAMENTE donde la TV estaba (su última posición viva), en vez
  /// de una posición vieja del CastMedia. 0/null → resolución normal.
  Future<bool> _sendLoad({int? resumeOverrideMs}) async {
    final media = _media;
    if (_sender == null || media == null) return false;
    // Cualquier LOAD intencionado (inicial, zap, castNext, auto-avance o la
    // propia recuperación) ESTABLECE la reproducción → desarma cualquier
    // reenganche pendiente para que su fallback no dispare un re-LOAD duplicado
    // más tarde sobre un contenido que ya cambió.
    _cancelResync();
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
    // Feature H — ¿debe este LOAD pedir a la TV que persista las credenciales
    // para reproducción standalone? Solo si (permiso maestro) ∧ (consentimiento
    // por-(TV,proveedor)) ∧ (VOD/serie Xtream, nunca vivo/archivo/M3U). Devuelve
    // el `pid` a enviar, o null si no aplica.
    final standalonePid = await _resolveStandalonePid(media, isLocal: local != null);
    // Feature H (fase 5) — id ESTABLE de este móvil, para que la TV particione su
    // historial de casting por-dispositivo (`__cast__:<deviceId>`) y sincronice
    // el progreso SOLO a este móvil. Best-effort: sin SharedPreferences (tests) o
    // ante cualquier fallo → '' (la TV cae al `__cast__` plano; nunca rompe el LOAD).
    String deviceId = '';
    try {
      deviceId = await UserPreferences.getCastDeviceId();
    } catch (_) {/* sin prefs → sin partición (compat. hacia atrás) */}
    await _sender!.sendLoad(
      channelId: media.channelId,
      contentType: media.contentType,
      url: url,
      username: user,
      password: pass,
      title: media.title,
      ext: media.ext,
      meta: media.meta,
      startPositionMs:
          await _resolveStartPosition(media, override: resumeOverrideMs),
      standalone: standalonePid != null,
      pid: standalonePid ?? '',
      deviceId: deviceId,
    );
    return true;
  }

  /// ÚNICA fuente de verdad de la elegibilidad standalone, para que
  /// [_resolveStandalonePid] (envío del flag) y [pendingStandaloneConsent]
  /// (diálogo) NO puedan divergir. Devuelve (tvId, pid, providerName) cuando el
  /// contexto habilita persistencia standalone, o null si no aplica. Condiciones:
  ///   - NO es un cast de archivo local ([isLocal] false) — sin credenciales.
  ///   - El contenido es VOD o serie (nunca vivo ni archivo).
  ///   - Hay un tvId conocido (emparejado) para el consentimiento por-TV.
  ///   - La playlist activa es Xtream (el rebuild bare-M3U está fuera de alcance).
  ///   - El `pid` (id de playlist) y las credenciales que viajan en el LOAD son
  ///     de la MISMA playlist: el LOAD manda SIEMPRE las creds de
  ///     `currentPlaylist` (ver [_sendLoad]), así que el `pid` DEBE ser
  ///     `currentPlaylist.id`. Si el CastMedia trae un `playlistId` DISTINTO
  ///     (coexistencia/multi-playlist), se rechaza: persistir las creds de una
  ///     playlist bajo el id de OTRA corrompería el replay standalone.
  ///   - El permiso MAESTRO está activo (UserPreferences.getTvStandaloneAllowed).
  /// NO comprueba el consentimiento por-(tvId,pid): eso lo decide cada llamador
  /// (enviar exige granted; el diálogo exige NO-granted).
  Future<({String tvId, String pid, String providerName})?>
      _standaloneEligibility(CastMedia media, {required bool isLocal}) async {
    if (isLocal) return null;
    final ct = media.contentType;
    if (ct != 'vod' && ct != 'series') return null;
    final tvId = _sender?.tvId;
    if (tvId == null || tvId.isEmpty) return null;
    final playlist = AppState.currentPlaylist;
    if (playlist == null || playlist.type != PlaylistType.xtream) return null;
    // El pid ancla las credenciales de currentPlaylist (las que se envían):
    // debe ser su id, y no puede diverger del playlistId del CastMedia.
    final pid = playlist.id;
    if (pid.isEmpty) return null;
    if (media.playlistId.isNotEmpty && media.playlistId != pid) return null;
    if (!await UserPreferences.getTvStandaloneAllowed()) return null;
    return (tvId: tvId, pid: pid, providerName: playlist.name);
  }

  /// El `pid` a enviar en el LOAD para pedir persistencia standalone, o null si
  /// NO debe persistirse. Elegible ([_standaloneEligibility]) Y con
  /// consentimiento explícito para (tvId, pid).
  Future<String?> _resolveStandalonePid(CastMedia media,
      {required bool isLocal}) async {
    final e = await _standaloneEligibility(media, isLocal: isLocal);
    if (e == null) return null;
    if (!await StandaloneConsentStore.isGranted(e.tvId, e.pid)) return null;
    return e.pid;
  }

  /// Si la sesión actual AMERITA pedir consentimiento contextual de persistencia
  /// standalone (feature H): la UI lo consulta tras empezar a castear para
  /// mostrar el diálogo la PRIMERA vez que se castea VOD/serie Xtream a una
  /// (TV, proveedor) con el permiso maestro activo y SIN consentimiento previo.
  /// Devuelve null si no aplica (no bloquea nada; el casting ya está en curso).
  Future<StandaloneConsentPrompt?> pendingStandaloneConsent() async {
    if (_phase != CastPhase.casting) return null;
    final media = _media;
    if (media == null) return null;
    final e = await _standaloneEligibility(media, isLocal: _localUrl != null);
    if (e == null) return null;
    if (await StandaloneConsentStore.isGranted(e.tvId, e.pid)) return null;
    return StandaloneConsentPrompt(
      tvId: e.tvId,
      providerId: e.pid,
      deviceName: _device?.name ?? '',
      providerName: e.providerName,
    );
  }

  /// Feature H — al reengancharse a una TV, ENVÍA los borrados pendientes (el
  /// usuario revocó el consentimiento estando desconectado): por cada `pid`
  /// pendiente para este tvId manda CmdType.wipeStandalone y lo desencola. Así
  /// "Olvidar credenciales en esta TV" borra DE VERDAD las creds en la TV la
  /// próxima vez que el móvil la ve (no solo el consentimiento del móvil).
  /// Best-effort: no bloquea el casting; el auto-wipe al desemparejar es el
  /// respaldo último si el comando no llega.
  Future<void> _flushPendingStandaloneWipes() async {
    final sender = _sender;
    final tvId = sender?.tvId;
    if (sender == null || tvId == null || tvId.isEmpty) return;
    final pids = await StandaloneConsentStore.pendingWipesFor(tvId);
    for (final pid in pids) {
      sender.sendCommand(CmdType.wipeStandalone, {'pid': pid});
      await StandaloneConsentStore.clearPendingWipe(tvId, pid);
    }
  }

  /// El usuario ACEPTÓ el diálogo de consentimiento: registra el permiso para
  /// (tvId, providerId) y, si seguimos casteando ese contenido, reenvía el LOAD
  /// (en la última posición viva) para que la TV persista las credenciales YA en
  /// esta sesión (no solo en el próximo LOAD). Un breve re-arranque en la TV es
  /// el precio de opt-in inmediato; el casting no se interrumpe.
  Future<void> grantStandaloneConsent(String tvId, String providerId) async {
    await StandaloneConsentStore.grant(tvId, providerId);
    if (_phase == CastPhase.casting && _sender != null && !_reconnecting) {
      try {
        await _sendLoad(resumeOverrideMs: _lastPos > 0 ? _lastPos : null);
      } catch (_) {/* el socket cayó al reenviar: _reconnect reenviará _media */}
    }
  }

  /// Posición (ms) de resume a incluir en el LOAD. Prefiere la que trae el
  /// CastMedia (ya resuelta por el móvil); si es 0, la busca best-effort en el
  /// historial local ("continuar viendo") para que castear un título a medias
  /// arranque donde el usuario lo dejó, no en 0. Nunca lanza (sin BD → 0). No
  /// aplica a vivo (no buscable) ni a archivo local.
  Future<int> _resolveStartPosition(CastMedia media, {int? override}) async {
    // La posición viva que reporta la TV (recuperación del reconnect) manda
    // sobre todo lo demás: es dónde está la reproducción AHORA MISMO.
    if (override != null && override > 0) return override;
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
  ///
  /// [queue]/[index] OPCIONALES: para una SERIE descargada, el llamador arma la
  /// cola ordenada de episodios descargados hermanos (cada `CastMedia` con su
  /// `localFilePath` y `isDownloadedSeries: true`) para que la TV auto-avance al
  /// terminar cada episodio (mismo mecanismo que el stream, pero re-sirviendo el
  /// archivo local siguiente). Para una película descargada se omiten (cast
  /// único que se detiene al final, como siempre).
  Future<void> castLocalFile({
    required String filePath,
    required String contentId,
    required String title,
    String ext = '',
    String imagePath = '',
    List<CastMedia>? queue,
    int index = 0,
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
    // El item "actual" es el de la cola en [index] (ya trae localFilePath y el
    // tag de serie descargada); sin cola, se arma uno suelto como hasta ahora.
    final media = (queue != null && index >= 0 && index < queue.length)
        ? queue[index]
        : CastMedia(
            channelId: contentId,
            contentType: 'file',
            title: title,
            ext: ext,
            imagePath: imagePath,
          );
    await beginCast(
      media,
      queue: queue,
      index: index,
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
  ///
  /// [queue]/[index] OPCIONALES, con el mismo significado que en [castLocalFile]:
  /// una serie descargada abierta MIENTRAS se castea también auto-avanza.
  Future<bool> castNextLocalFile({
    required String filePath,
    required String contentId,
    required String title,
    String ext = '',
    String imagePath = '',
    List<CastMedia>? queue,
    int index = 0,
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
    _media = (queue != null && index >= 0 && index < queue.length)
        ? queue[index]
        : CastMedia(
            channelId: contentId,
            contentType: 'file',
            title: title,
            ext: ext,
            imagePath: imagePath,
          );
    // Solo se conserva cola si hay más de un episodio (auto-avance); una cola de
    // un solo item equivale a no tener cola (cast único que se detiene al final).
    _queue = (queue != null && queue.length > 1) ? queue : null;
    _index = _queue != null ? index : 0;
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
        // Preserva el auto-avance de una serie descargada al reintentar: la cola
        // (episodios hermanos) y el índice actual se re-envían tal cual.
        queue: _queue,
        index: _index,
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
    _cancelResync();
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
    if (media == null || q == null || _index + 1 >= q.length) return;
    // Avanza en dos casos: una serie por STREAM (contentType 'series') o una
    // serie DESCARGADA (contentType 'file' + isDownloadedSeries). NO avanza en
    // VOD por stream ni en una película descargada (esos llegan con queue null o
    // contentType 'vod'/'file' sin el tag → guarda arriba o este check).
    final isSeries = media.contentType == 'series' || media.isDownloadedSeries;
    if (!isSeries) return;
    final nextIndex = _index + 1;
    final next = q[nextIndex];
    if (next.isDownloadedSeries && next.localFilePath != null) {
      // Serie descargada: el siguiente episodio es un ARCHIVO local que hay que
      // re-servir por la LAN (con su propia URL). Servimos ANTES de comprometer
      // el avance, para no dejar el estado a medias si el re-servido falla.
      unawaited(_advanceLocalSeries(nextIndex, next));
    } else {
      // Serie por stream: la TV re-arma la URL con las credenciales de la
      // playlist; basta comprometer el avance y reenviar el LOAD.
      _commitAdvance(nextIndex, next);
      unawaited(_sendLoad());
    }
  }

  /// Comete el avance al episodio [next] (índice [i] en la cola): actualiza
  /// `_media`/`_index`, limpia las pistas y corta el arrastre de posición del
  /// episodio anterior (la TV arranca el siguiente en 0). Solo debe llamarse
  /// cuando el siguiente episodio está listo para reproducirse, para no dejar el
  /// mini-control mostrando un episodio que la TV no llegó a cargar.
  void _commitAdvance(int i, CastMedia next) {
    _index = i;
    _media = next;
    _audioTracks = const [];
    _subtitleTracks = const [];
    _lastPos = 0;
    _lastDur = 0;
    _lastHistoryWrite = null;
    notifyListeners();
  }

  /// Re-sirve por la LAN el archivo local del siguiente episodio descargado
  /// (cada uno en su propio puerto/URL) y, SOLO si el re-servido tuvo éxito,
  /// comete el avance y envía un LOAD sobre la sesión viva. Si el archivo no se
  /// puede servir (borrado / IO) o no hay Wi‑Fi, NO avanza: `_media`/`_index`
  /// siguen en el episodio anterior y la TV queda en su último fotograma, igual
  /// que al llegar al final de la cola (BACK sale). Así no queda un estado a
  /// medias (mini-control adelantado con la TV congelada).
  Future<void> _advanceLocalSeries(int i, CastMedia next) async {
    final server = _fileServer ??= LocalFileServer();
    final String lanUrl;
    try {
      lanUrl = await server.serve(next.localFilePath!);
    } catch (_) {
      return;
    }
    if (await server.lanIp() == null) return;
    _localFilePath = next.localFilePath;
    _localUrl = lanUrl;
    _commitAdvance(i, next);
    try {
      await _sendLoad();
    } catch (_) {
      // El socket cayó justo al enviar: _reconnect reenviará este `_media` ya
      // actualizado (su localFilePath quedó servido arriba).
    }
  }

  Future<void> _reconnect() async {
    if (_superseded) return; // cedido a otro dispositivo: no reconectar
    final device = _device, pin = _pin, media = _media;
    final playlist = AppState.currentPlaylist;
    if (device == null || pin == null || media == null || playlist == null) return;
    _reconnecting = true;
    // La TV siguió reproduciendo mientras el socket estuvo caído: cualquier
    // `state` que llegue tras reengancharnos lo confirma y cancela la
    // recuperación por re-LOAD. Se arma ANTES de conectar para no perder un
    // `state` que la TV eco de inmediato al reconectar (evita la carrera).
    _awaitingResync = true;
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
        _sender!.onHistorySync.listen(_onHistorySync);
        await _sender!.connect(device.host, device.port, secure: device.secure);
        if (await _sender!.pair(pin)) {
          _reconnecting = false;
          // Se detuvo el casting mientras reconectábamos (stop/superseded en
          // pleno backoff): no re-enganchar ni armar el fallback.
          if (_phase != CastPhase.casting) {
            _cancelResync();
            return;
          }
          // Canal de control recuperado. NO reenviar LOAD a ciegas: eso reinicia
          // la TV desde una posición vieja y borra el progreso que hizo mientras
          // no estábamos. En su lugar, reenganche SILENCIOSO: la TV sigue
          // reproduciendo y su `state` periódico resincroniza posición/volumen.
          // Solo si NINGÚN `state` confirma la sesión viva dentro de la ventana
          // se recupera con un re-LOAD en la última posición viva (cubre una TV
          // que sí se reinició/paró de verdad).
          _armResyncFallback();
          // Feature H (fase 5) — reengancharse es otra oportunidad de reconciliar
          // "continuar viendo" con la TV (una sola vez por reconexión).
          unawaited(_syncHistory());
          return;
        }
      } catch (_) {/* reintentar con backoff */}
    }
    _reconnecting = false;
    _cancelResync();
    // Agotados los reintentos sin recuperar el control: la TV se fue de verdad.
    // No dejar el móvil colgado en "casting" (mini-control fantasma / círculo de
    // carga infinito): terminar limpio.
    if (_phase == CastPhase.casting) await stopCasting();
  }

  /// Arma el fallback de recuperación tras un reenganche: si en [_resyncTimeout]
  /// la TV no ha ecoado ningún `state` (señal de que YA no reproduce nuestro
  /// contenido — se reinició o paró), se re-LOADea en la última posición viva
  /// conocida. Si llega un `state` antes, [_onState] cancela esto y el
  /// reenganche queda silencioso (sin reiniciar la reproducción).
  void _armResyncFallback() {
    _resyncTimer?.cancel();
    _resyncTimer = Timer(_resyncTimeout, () {
      if (!_awaitingResync || _phase != CastPhase.casting) return;
      _awaitingResync = false;
      unawaited(_sendLoad(resumeOverrideMs: _lastPos));
    });
  }

  /// Desarma el reenganche pendiente (sesión confirmada viva, o terminada).
  void _cancelResync() {
    _awaitingResync = false;
    _resyncTimer?.cancel();
    _resyncTimer = null;
  }

  void playPause() {
    if (_sender == null) return;
    _sender!.sendCommand(CmdType.playPause);
    // Rastrear el estado INTENCIONADO de la TV: playPause es un toggle, así que
    // pauseForCall/resumeAfterCall necesitan saber si estaba reproduciendo para
    // no dar el toggle equivocado. Un `state` posterior lo corrige si drifta.
    _tvPlaying = !_tvPlaying;
    // Si el usuario togglea a mano MIENTRAS estamos pausados-por-llamada, su
    // acción manual toma el control: soltamos el flag para que, al colgar,
    // resumeAfterCall() NO dispare un toggle automático que revierta lo que el
    // usuario acaba de decidir (sería un toggle "fantasma" no pedido por nadie).
    _pausedForCall = false;
  }

  // ── Pausa-al-recibir-llamada (solo mientras se castea) ────────────────────

  /// Arranca la vigilancia de llamadas si el toggle está ON y se concede el
  /// permiso. Idempotente (no re-suscribe si ya está activa) y best-effort: sin
  /// permiso o sin peer nativo (tests/desktop) es un no-op silencioso, y el
  /// permiso se pide como mucho una vez por sesión de casting.
  Future<void> _maybeStartCallWatch() async {
    if (_callSub != null || _callWatchRequested) return;
    bool enabled;
    try {
      enabled = await UserPreferences.getPauseCastOnCall();
    } catch (_) {
      enabled = false; // sin prefs (tests) → no vigilar
    }
    if (!enabled || _phase != CastPhase.casting) return;
    _callWatchRequested = true; // pedir el permiso como mucho una vez por sesión
    final granted = await _callState.ensurePermission();
    // El casting pudo terminar mientras se resolvía el permiso, o el permiso fue
    // denegado: no suscribir (ni reintentar/molestar más en esta sesión).
    if (!granted || _phase != CastPhase.casting || _callSub != null) return;
    _callSub = _callState.callStates().listen(_onCallState);
  }

  void _onCallState(String state) {
    switch (state) {
      case 'ringing':
      case 'offhook':
        pauseForCall();
      case 'idle':
        resumeAfterCall();
    }
  }

  /// Libera la vigilancia de llamadas (fin de casting / dispose). Idempotente.
  void _stopCallWatch() {
    _callSub?.cancel();
    _callSub = null;
    _callWatchRequested = false;
    _pausedForCall = false;
  }

  /// Pausa la TV por una llamada entrante, SOLO si está reproduciendo (evita un
  /// toggle equivocado). Idempotente: un segundo evento (ringing→offhook) no
  /// vuelve a togglear. Recuerda que fuimos nosotros para reanudar luego.
  void pauseForCall() {
    if (_phase != CastPhase.casting || _sender == null) return;
    if (_pausedForCall || !_tvPlaying) return;
    _sender!.sendCommand(CmdType.playPause);
    _tvPlaying = false;
    _pausedForCall = true;
  }

  /// Reanuda la TV al terminar la llamada, SOLO si fuimos nosotros quienes
  /// pausamos (si el usuario ya la había pausado a mano, no la reanudamos).
  void resumeAfterCall() {
    if (!_pausedForCall) return;
    _pausedForCall = false;
    if (_phase != CastPhase.casting || _sender == null) return;
    _sender!.sendCommand(CmdType.playPause);
    _tvPlaying = true;
  }

  /// Zap: el móvil (que tiene el catálogo) reenvía un LOAD del canal
  /// siguiente/anterior; la TV cambia de canal sin round-trip de comando.
  Future<void> channelUp() => _zap(1);
  Future<void> channelDown() => _zap(-1);
  Future<void> _zap(int dir) async {
    final q = _queue;
    if (q == null || !isLive) return;
    // No zapear durante la reconexión: `_phase` sigue `casting` pero `_sender`
    // apunta a un socket muerto en pleno backoff → un `_sendLoad` ahora lanzaría
    // (mismo hazard que endurecimos en `castNext`). No-op seguro; el usuario
    // reintenta cuando la sesión estabilice.
    if (_phase != CastPhase.casting || _sender == null || _reconnecting) return;
    final next = _index + dir;
    if (next < 0 || next >= q.length) return;
    _index = next;
    _media = q[next];
    _audioTracks = const [];
    _subtitleTracks = const [];
    notifyListeners();
    try {
      await _sendLoad();
    } catch (_) {
      // El socket cayó justo al enviar: la reconexión reenviará `_media` ya fijado.
    }
  }

  /// Salta MANUALMENTE al siguiente episodio en la TV durante el casting de una
  /// serie (el usuario pulsa "Siguiente episodio" en el móvil, sin esperar a los
  /// créditos). Reutiliza EXACTAMENTE el mismo camino que el auto-avance de fin
  /// de archivo [_onCompleted]: re-servido por LAN para una serie DESCARGADA,
  /// re-LOAD directo para una serie por STREAM. No-op seguro si no hay siguiente,
  /// no se está casteando, o la sesión se está reconectando (socket en backoff).
  Future<void> castNextEpisode() async {
    if (_phase != CastPhase.casting || _sender == null || _reconnecting) return;
    final q = _queue;
    final media = _media;
    if (media == null || q == null || _index + 1 >= q.length) return;
    final isSeries = media.contentType == 'series' || media.isDownloadedSeries;
    if (!isSeries) return;
    final nextIndex = _index + 1;
    final next = q[nextIndex];
    if (next.isDownloadedSeries && next.localFilePath != null) {
      // Serie descargada: el siguiente episodio es un ARCHIVO local; se re-sirve
      // por la LAN antes de comprometer el avance (igual que el auto-avance).
      await _advanceLocalSeries(nextIndex, next);
    } else {
      // Serie por stream: comprometer el avance y reenviar el LOAD.
      _commitAdvance(nextIndex, next);
      try {
        await _sendLoad();
      } catch (_) {
        // El socket cayó justo al enviar: _reconnect reenviará este `_media` ya
        // actualizado (mismo comportamiento que el zap/auto-avance).
      }
    }
  }

  /// Pide a la TV su lista de pistas actuales (audio/subtítulo).
  void requestTracks() => _sender?.sendCommand(CmdType.getTracks);

  void selectAudio(String id) =>
      _sender?.sendCommand(CmdType.selectAudio, {'id': id});
  void selectSubtitle(String id) =>
      _sender?.sendCommand(CmdType.selectSubtitle, {'id': id});

  /// Fija el volumen de reproducción en la TV (0-100). Actualización local
  /// optimista (el slider reacciona sin esperar la vuelta) inmediata; el
  /// COMANDO a la TV se debounce (ver [_volumeDebounce]) para no inundar la
  /// red durante un arrastre continuo. La TV eco su volumen real en cada
  /// `state` (ver [_onState]).
  void setVolume(double v) {
    _volume = v.clamp(0, 100);
    notifyListeners();
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(_volumeDebounceDelay, () {
      _sender?.sendCommand(CmdType.setVolume, {'v': _volume.round()});
    });
  }

  /// El usuario EMPIEZA a arrastrar el slider de volumen: silencia el eco de
  /// la TV hasta soltar (ver el doc de [_draggingVolume]).
  void beginVolumeDrag() => _draggingVolume = true;

  /// El usuario SUELTA el slider en [v] (0-100): fija el volumen final YA
  /// (cancela cualquier debounce pendiente y manda el comando de inmediato,
  /// sin esperar los ~180ms) y reactiva el eco de la TV.
  void endVolumeDrag(double v) {
    _draggingVolume = false;
    _volume = v.clamp(0, 100);
    notifyListeners();
    _volumeDebounce?.cancel();
    _sender?.sendCommand(CmdType.setVolume, {'v': _volume.round()});
  }

  /// Nudges the TV's cast volume by [delta] (a hardware VOLUME_UP/DOWN press
  /// while casting maps to +5 / -5). Unlike [setVolume], this sends the command
  /// IMMEDIATELY (cancels the debounce) so each physical press lands crisply,
  /// and pops a brief on-screen indicator of the new TV volume so the user gets
  /// feedback even when the cast control sheet isn't open.
  void nudgeVolume(int delta) {
    _volume = (_volume + delta).clamp(0, 100);
    notifyListeners();
    _volumeDebounce?.cancel();
    _sender?.sendCommand(CmdType.setVolume, {'v': _volume.round()});
    _showVolumeToast(_volume.round());
  }

  // Transient "Volumen TV  N%" indicator shown on a hardware volume nudge.
  // Mounted into the root navigator's Overlay (via appNavigatorKey), so it works
  // even when no cast sheet is open. Single instance: a new nudge refreshes the
  // existing entry instead of stacking. Auto-dismisses after [_toastDuration].
  OverlayEntry? _volumeToast;
  Timer? _volumeToastTimer;
  final ValueNotifier<int> _volumeToastValue = ValueNotifier<int>(0);
  static const _toastDuration = Duration(milliseconds: 1100);

  void _showVolumeToast(int volume) {
    // No navigator (unit tests / not yet mounted) → skip silently.
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _volumeToastValue.value = volume;
    if (_volumeToast == null) {
      _volumeToast = OverlayEntry(
        builder: (context) => _VolumeToast(value: _volumeToastValue),
      );
      overlay.insert(_volumeToast!);
    }
    _volumeToastTimer?.cancel();
    _volumeToastTimer = Timer(_toastDuration, _removeVolumeToast);
  }

  void _removeVolumeToast() {
    _volumeToastTimer?.cancel();
    _volumeToastTimer = null;
    _volumeToast?.remove();
    _volumeToast = null;
  }

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
    // Reenganche confirmado: un `state` de la TV para el contenido actual prueba
    // que la sesión sobrevivió a la caída de socket y la TV SIGUE reproduciéndolo
    // → cancelar la recuperación por re-LOAD (ver [_reconnect]). Debe correr para
    // CUALQUIER `state` (incluso pos<=0), por eso va antes del guard de pos/dur.
    if (_awaitingResync) _cancelResync();
    // Eco de volumen: la TV manda su volumen real en cada `state`. Campo
    // OPCIONAL (compat. hacia atrás con una TV vieja que no lo envía aún):
    // solo se actualiza si viene y difiere, para no notificar de más. Mientras
    // el usuario ARRASTRA el slider, el eco se IGNORA por completo (ni
    // _volume= ni notifyListeners): un eco en tránsito de un valor anterior no
    // debe pelear con el dedo del usuario. Al soltar, endVolumeDrag ya fijó el
    // valor final y el próximo eco vuelve a sincronizar con normalidad.
    if (!_draggingVolume) {
      final vol = (msg['vol'] as num?)?.toDouble();
      if (vol != null && vol != _volume) {
        _volume = vol.clamp(0, 100);
        notifyListeners();
      }
    }
    final pos = (msg['pos'] as num?)?.toInt() ?? 0;
    final dur = (msg['dur'] as num?)?.toInt() ?? 0;
    if (pos <= 0 || dur <= 0) return;
    // Un `state` con posición real es prueba de que la TV está reproduciendo:
    // corrige el estado intencionado por si driftó (salvo que lo tengamos pausado
    // por una llamada, para que un eco rezagado no dispare un resume espurio).
    if (!_pausedForCall) _tvPlaying = true;
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

  /// El id de la playlist REAL activa del móvil para el sync de historial, o ''
  /// si no hay una utilizable. Nunca la sintética `__cast__` (esa es de la TV).
  String get _activeSyncPlaylistId {
    final id = AppState.currentPlaylist?.id ?? '';
    // Nunca la sintética `__cast__` ni sus particiones `__cast__:<deviceId>`
    // (esas son de la TV): el móvil sincroniza SIEMPRE su playlist REAL activa.
    return (id.isEmpty || id.startsWith(_kCastPlaylistId)) ? '' : id;
  }

  /// Feature H (fase 5) — envía a la TV los deltas de "continuar viendo" de la
  /// playlist activa (una vez por conexión/reconexión). La TV los mezcla en
  /// `__cast__` y responde con los suyos (ver [_onHistorySync]). Best-effort:
  /// un fallo de BD o de red NUNCA debe romper el casting.
  Future<void> _syncHistory() async {
    final sender = _sender;
    final playlistId = _activeSyncPlaylistId;
    if (sender == null || playlistId.isEmpty) return;
    try {
      final items = await WatchHistoryService()
          .historySyncDeltas(playlistId)
          .timeout(const Duration(seconds: 4), onTimeout: () => const []);
      sender.sendHistorySync(items);
    } catch (_) {/* sin BD (tests) o socket caído: no romper el casting */}
  }

  /// Feature H (fase 5) — la TV respondió con sus deltas de `__cast__`. Los
  /// mezclamos en la playlist REAL activa del móvil (misma regla que la TV, por
  /// `streamId`) para que el progreso hecho en la TV (incl. standalone) aparezca
  /// en "continuar viendo" del teléfono. NO respondemos (evita el ping-pong).
  Future<void> _onHistorySync(List<HistorySyncItem> items) async {
    if (items.isEmpty) return;
    final playlistId = _activeSyncPlaylistId;
    if (playlistId.isEmpty) return;
    try {
      final n = await WatchHistoryService().mergeHistorySync(playlistId, items);
      if (n > 0) EventBus().emit('history_changed', null);
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
    _cancelResync();
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
    _volumeDebounce?.cancel();
    _resyncTimer?.cancel();
    _callSub?.cancel();
    _removeVolumeToast();
    _volumeToastValue.dispose();
    // Release the hardware-key hook if we owned it (avoid a dangling closure to
    // a disposed controller). Only clear if it still points at us. Also drop the
    // native casting flag as defense-in-depth so volume keys can never stay
    // hijacked if this controller is torn down mid-cast (the singleton normally
    // only dies with the process, but don't rely on that).
    if (_hwVolume.onStep == nudgeVolume) _hwVolume.onStep = null;
    _hwVolume.setCastingActive(false);
    _sender?.close();
    _fileServer?.stop();
    super.dispose();
  }
}

/// The small centered pill that shows the TV's new volume on a hardware nudge.
/// Rebuilds only when [value] changes (a rapid press just refreshes the number).
class _VolumeToast extends StatelessWidget {
  const _VolumeToast({required this.value});

  final ValueNotifier<int> value;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volume_up, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  ValueListenableBuilder<int>(
                    valueListenable: value,
                    builder: (context, v, _) {
                      // Este OverlayEntry vive bajo el Overlay raíz de la
                      // MaterialApp, así que AppLocalizations.of(context)
                      // normalmente resuelve. Por si acaso (contexto huérfano,
                      // localización aún no lista, etc.) se cae al literal en
                      // español SIN lanzar: el toast de volumen nunca debe
                      // crashear la app.
                      String text;
                      try {
                        text = AppLocalizations.of(context)
                                ?.cast_tv_volume(v) ??
                            'Volumen TV  $v%';
                      } catch (_) {
                        text = 'Volumen TV  $v%';
                      }
                      return Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
