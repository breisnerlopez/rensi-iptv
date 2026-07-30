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

class CastSenderController extends ChangeNotifier {
  CastSenderController({PhoneSenderService Function()? senderFactory})
      : _senderFactory = senderFactory ?? PhoneSenderService.new;

  final PhoneSenderService Function() _senderFactory;
  PhoneSenderService? _sender;

  CastPhase _phase = CastPhase.idle;
  List<CastDevice> _devices = const [];
  CastDevice? _device;
  CastMedia? _media;
  String? _error;
  bool _wrongPin = false;
  String? _pin; // cacheado tras emparejar, para reconexión transparente
  bool _reconnecting = false;

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
  Future<void> beginCast(CastMedia media) async {
    _media = media;
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
      await _sender!.connect(device.host, device.port);
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
      await _startPlayback();
    } catch (e) {
      _set(CastPhase.error, error: e.toString());
    }
  }

  Future<void> _startPlayback() async {
    final playlist = AppState.currentPlaylist;
    final media = _media;
    if (_sender == null || playlist == null || media == null) {
      _set(CastPhase.error, error: 'no_context');
      return;
    }
    await _sender!.sendLoad(
      channelId: media.channelId,
      contentType: media.contentType,
      url: playlist.url ?? '',
      username: playlist.username ?? '',
      password: playlist.password ?? '',
      title: media.title,
      ext: media.ext,
    );
    _set(CastPhase.casting);
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
        await _sender!.connect(device.host, device.port);
        if (await _sender!.pair(pin)) {
          await _sender!.sendLoad(
            channelId: media.channelId,
            contentType: media.contentType,
            url: playlist.url ?? '',
            username: playlist.username ?? '',
            password: playlist.password ?? '',
            title: media.title,
            ext: media.ext,
          );
          _reconnecting = false;
          return; // control recuperado
        }
      } catch (_) {/* reintentar con backoff */}
    }
    _reconnecting = false;
  }

  void channelUp() => _sender?.sendCommand(CmdType.channelUp);
  void channelDown() => _sender?.sendCommand(CmdType.channelDown);
  void playPause() => _sender?.sendCommand(CmdType.playPause);

  /// Termina el casting y vuelve a idle (la TV libera el stream).
  Future<void> stopCasting() async {
    _sender?.sendCommand(CmdType.stop);
    await _sender?.close();
    _sender = null;
    _device = null;
    _media = null;
    _devices = const [];
    _wrongPin = false;
    _pin = null;
    _reconnecting = false;
    _set(CastPhase.idle);
  }

  /// Cancela un flujo a medias (descubrimiento/pairing) sin dejar sockets abiertos.
  Future<void> cancel() => stopCasting();

  @override
  void dispose() {
    _sender?.close();
    super.dispose();
  }
}
