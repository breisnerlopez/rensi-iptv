// Protocolo del canal de control de "segunda pantalla" (arquitectura D).
//
// El móvil (sender) y el Android TV (receiver) hablan por un WebSocket LAN.
// Emparejamiento sin backend ni PAKE (no disponible cross-platform en Dart):
//   1. La TV muestra un PIN de 6 dígitos y envía {salt, nonce}.
//   2. Ambos derivan una clave de sesión = HKDF-SHA256(PIN, salt).
//   3. El móvil prueba conocimiento del PIN con HMAC-SHA256(clave, nonce)
//      (challenge-response: el PIN nunca viaja).
//   4. Las credenciales Xtream del LOAD viajan cifradas con AES-GCM bajo la
//      clave de sesión (nunca en claro por la LAN) — mitiga R3.
//
// Nota de seguridad: un PIN corto tiene baja entropía; esto NO es resistente a
// diccionario offline como un PAKE. Mitigar con PIN de vida corta y pocos
// intentos (ver TvReceiverService).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Nombre del servicio mDNS/DNS-SD que anuncia la TV.
const String kCastServiceType = '_rensi-cast._tcp';

/// Tipos de mensaje del envelope JSON `{ "t": <tipo>, ... }`.
class MsgType {
  static const pairChallenge = 'pair_challenge'; // TV -> móvil: {salt, nonce}
  static const pairProof = 'pair_proof'; // móvil -> TV: {proof}
  static const pairResult = 'pair_result'; // TV -> móvil: {ok}
  static const load = 'load'; // móvil -> TV: reproducir contenido
  static const command = 'command'; // móvil -> TV: pausa/track/stop
  static const state = 'state'; // TV -> móvil: playing/pos
  static const tracks = 'tracks'; // TV -> móvil: pistas de audio/subtítulo
  static const error = 'error';
}

/// Comandos de control remoto (payload de MsgType.command → campo `c`).
/// El zapping NO va por aquí: lo resuelve el móvil reenviando un LOAD (tiene el
/// catálogo). Estos comandos actúan sobre la reproducción ya en curso en la TV.
class CmdType {
  static const playPause = 'play_pause';
  static const stop = 'stop';
  static const getTracks = 'get_tracks'; // pide a la TV sus pistas actuales
  static const selectAudio = 'sel_audio'; // + campo 'id'
  static const selectSubtitle = 'sel_sub'; // + campo 'id' ('' = off)
}

String encodeMsg(String type, Map<String, dynamic> body) =>
    jsonEncode({'t': type, ...body});

Map<String, dynamic> decodeMsg(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

/// Cripto de emparejamiento y cifrado de credenciales. Envuelve el paquete
/// `cryptography` para que sender y receiver compartan exactamente el mismo
/// esquema (evita desajustes sutiles).
class CastCrypto {
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _hmac = Hmac.sha256();
  static final _aes = AesGcm.with256bits();
  static const _info = 'rensi-cast-v1';

  /// Clave de sesión de 32 bytes derivada del PIN + salt (idéntica en ambos
  /// extremos si el PIN coincide).
  static Future<SecretKey> deriveSessionKey(String pin, List<int> salt) {
    return _hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
      info: utf8.encode(_info),
    );
  }

  /// Prueba de conocimiento del PIN: HMAC(clave, nonce || certfp). Base64.
  ///
  /// Atar el fingerprint del cert TLS de la TV (`certfp`) al HMAC del PIN da
  /// autenticación mutua del canal: un MITM que presente otro cert no puede
  /// forjar una prueba válida sin el PIN. En ws:// plano `certfp` es vacío y se
  /// reduce a HMAC(clave, nonce).
  static Future<String> proof(SecretKey key, List<int> nonce,
      [List<int> certfp = const []]) async {
    final mac = await _hmac.calculateMac([...nonce, ...certfp], secretKey: key);
    return base64.encode(mac.bytes);
  }

  /// Verificación en tiempo constante de la prueba recibida (atada a `certfp`).
  static Future<bool> verifyProof(SecretKey key, List<int> nonce, String proofB64,
      [List<int> certfp = const []]) async {
    final expected = await proof(key, nonce, certfp);
    return _constantTimeEquals(expected, proofB64);
  }

  /// Comparación de bytes en tiempo constante (para pinning de fingerprint).
  static bool bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Cifra un JSON (p.ej. credenciales) con AES-GCM. Devuelve {n, ct} base64
  /// (la MAC va concatenada en el SecretBox).
  static Future<Map<String, String>> encryptJson(
      SecretKey key, Map<String, dynamic> data) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
    );
    return {
      'n': base64.encode(box.nonce),
      'ct': base64.encode(box.cipherText),
      'm': base64.encode(box.mac.bytes),
    };
  }

  /// Descifra lo producido por [encryptJson]. Lanza si la MAC no valida
  /// (integridad/autenticidad).
  static Future<Map<String, dynamic>> decryptJson(
      SecretKey key, Map<String, dynamic> enc) async {
    final box = SecretBox(
      base64.decode(enc['ct'] as String),
      nonce: base64.decode(enc['n'] as String),
      mac: Mac(base64.decode(enc['m'] as String)),
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  static bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a), bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < ab.length; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }
}

/// Bytes aleatorios criptográficos (salt/nonce de emparejamiento).
Uint8List randomBytes(int n) {
  final r = SecretKeyData.random(length: n);
  return Uint8List.fromList(r.bytes);
}
