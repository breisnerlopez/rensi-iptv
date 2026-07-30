// Sender de segunda pantalla que corre en el móvil (arquitectura D).
//
// Descubre la TV por mDNS (bonsoir), abre el WebSocket de control, se empareja
// por PIN y envía el LOAD (con credenciales cifradas) y comandos de control.
// El móvil NO reproduce: sólo controla.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:cryptography/cryptography.dart';

import 'cast_protocol.dart';

/// Un Android TV descubierto en la LAN.
class CastDevice {
  final String name;
  final String host;
  final int port;
  CastDevice({required this.name, required this.host, required this.port});
}

class PhoneSenderService {
  WebSocket? _ws;
  StreamSubscription? _sub;

  // Estado del reto de emparejamiento recibido de la TV.
  List<int>? _salt;
  List<int>? _nonce;
  SecretKey? _sessionKey;
  final _pairResult = Completer<bool>();
  final _challengeReady = Completer<void>();

  final _stateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onState => _stateController.stream;

  /// Descubre TVs anunciando [kCastServiceType] durante [timeout].
  Future<List<CastDevice>> discover(
      {Duration timeout = const Duration(seconds: 4)}) async {
    final discovery = BonsoirDiscovery(type: kCastServiceType);
    await discovery.ready;
    final found = <String, CastDevice>{};
    final sub = discovery.eventStream!.listen((event) async {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        await event.service!.resolve(discovery.serviceResolver);
      } else if (event.type ==
          BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final s = event.service!;
        final host = (s.toJson()['service.host'] ?? s.toJson()['host']) as String?;
        final port = s.port;
        if (host != null) {
          found[s.name] = CastDevice(name: s.name, host: host, port: port);
        }
      }
    });
    await discovery.start();
    await Future<void>.delayed(timeout);
    await sub.cancel();
    await discovery.stop();
    return found.values.toList();
  }

  /// Abre el WebSocket con la TV y espera el reto de emparejamiento.
  Future<void> connect(String host, int port) async {
    _ws = await WebSocket.connect('ws://$host:$port');
    _sub = _ws!.listen(_onMessage, onDone: () {
      if (!_pairResult.isCompleted) _pairResult.complete(false);
    });
    await _challengeReady.future
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw TimeoutException('sin reto de emparejamiento de la TV');
    });
  }

  /// Prueba el PIN. Devuelve true si la TV lo acepta.
  Future<bool> pair(String pin) async {
    if (_salt == null || _nonce == null) {
      throw StateError('connect() debe completarse antes de pair()');
    }
    _sessionKey = await CastCrypto.deriveSessionKey(pin, _salt!);
    final proof = await CastCrypto.proof(_sessionKey!, _nonce!);
    _ws!.add(encodeMsg(MsgType.pairProof, {'proof': proof}));
    return _pairResult.future.timeout(const Duration(seconds: 5));
  }

  /// Envía un LOAD: la TV reproducirá el contenido. Las credenciales viajan
  /// cifradas con la clave de sesión (AES-GCM).
  Future<void> sendLoad({
    required String channelId,
    String contentType = 'live',
    required String url,
    required String username,
    required String password,
    String title = '',
    String ext = '',
  }) async {
    if (_sessionKey == null) throw StateError('no emparejado');
    final creds = await CastCrypto.encryptJson(_sessionKey!, {
      'url': url,
      'user': username,
      'pass': password,
    });
    _ws!.add(encodeMsg(MsgType.load, {
      'id': channelId,
      'ct': contentType,
      'title': title,
      'ext': ext,
      'creds': creds,
    }));
  }

  void sendCommand(String cmd) {
    _ws?.add(encodeMsg(MsgType.command, {'c': cmd}));
  }

  void _onMessage(dynamic data) {
    final msg = decodeMsg(data as String);
    switch (msg['t']) {
      case MsgType.pairChallenge:
        _salt = base64.decode(msg['salt'] as String);
        _nonce = base64.decode(msg['nonce'] as String);
        if (!_challengeReady.isCompleted) _challengeReady.complete();
        break;
      case MsgType.pairResult:
        if (!_pairResult.isCompleted) _pairResult.complete(msg['ok'] == true);
        break;
      case MsgType.state:
        _stateController.add(msg);
        break;
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _ws?.close();
    await _stateController.close();
  }
}
