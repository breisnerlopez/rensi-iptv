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
  static const ended = 'ended'; // TV -> móvil: reproducción detenida/cerrada en la TV
  static const completed = 'completed'; // TV -> móvil: el título terminó (fin de archivo) → el móvil puede auto-avanzar
  static const superseded = 'superseded'; // TV -> móvil: OTRO dispositivo tomó el control (cesión silenciosa; NO es caída ni fin)
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

/// String tolerante: cualquier valor no-String del wire → ''. El `meta` viene de
/// un PEER emparejado; un tipo inesperado NUNCA debe lanzar (rompería el LOAD).
String _wireString(dynamic v) => v is String ? v : '';

/// Un miembro del reparto TMDb enviado con el LOAD (ver [CastMeta]). Lleva el
/// `profile_path` CRUDO de TMDb (no la URL completa) a propósito: el receptor lo
/// reconstruye a un `TmdbCredit` y reutiliza EXACTAMENTE el mismo `TmdbCastRail`
/// que las pantallas de detalle (que derivan la URL w185 del path). Enviar el
/// path evita acoplar el protocolo a un tamaño de imagen concreto y —a diferencia
/// de una URL completa— no permite al emisor apuntar a un host arbitrario.
class CastMetaMember {
  final String name;
  final String character; // '' si el rol es desconocido
  final String? profilePath; // path TMDb crudo, p.ej. '/abc.jpg'
  const CastMetaMember({
    required this.name,
    this.character = '',
    this.profilePath,
  });

  Map<String, dynamic> toJson() => {
        'n': name,
        if (character.isNotEmpty) 'c': character,
        if (profilePath != null && profilePath!.isNotEmpty) 'p': profilePath,
      };

  /// DEFENSIVO: tolera tipos inválidos del wire (todo cast con fallback), nunca
  /// lanza. Un `p` no-String → null.
  factory CastMetaMember.fromJson(Map<String, dynamic> j) => CastMetaMember(
        name: _wireString(j['n']),
        character: _wireString(j['c']),
        profilePath: j['p'] is String ? j['p'] as String : null,
      );
}

/// Metadatos TMDb OPCIONALES que el móvil resuelve y adjunta al LOAD para que el
/// panel de pausa de la TV (PauseInfoPanel) muestre sinopsis + reparto SIN que la
/// TV necesite su propia clave TMDb (la clave es por-usuario y vive solo en el
/// almacenamiento seguro del móvil). Todo es opcional: un LOAD sin `meta`
/// reproduce EXACTAMENTE igual que siempre (compat. hacia atrás — la TV puede
/// correr una build más vieja/nueva). Datos PÚBLICOS de TMDb, así que —a
/// diferencia de las credenciales— NO se cifran (el `title` ya viaja en claro en
/// el mismo envelope; sobre wss el canal ya va cifrado por TLS).
///
/// NO transporta poster/backdrop: el panel solo usa `overview` + `cast`, y una
/// URL de imagen controlable por el emisor sería un footgun (SSRF/carga de host
/// arbitrario el día que alguien la pintara en un NetworkImage). Las fotos de
/// reparto viajan como `profile_path` crudo, reconstruido contra un host fijo.
class CastMeta {
  // Tope duro de miembros que se materializan/serializan (defensa en profundidad
  // contra un peer que envíe un `cast` gigante para forzar memoria en la TV; el
  // rail ya muestra ≤20).
  static const int _maxCast = 30;
  // Tope de la sinopsis (unos pocos KB): una sinopsis TMDb real cabe de sobra.
  static const int _maxOverview = 4000;

  final String overview;
  final List<CastMetaMember> cast;
  final String title; // título TMDb resuelto (puede diferir del del catálogo)
  final int? year;

  const CastMeta({
    this.overview = '',
    this.cast = const [],
    this.title = '',
    this.year,
  });

  /// Sin nada que mostrar (ni sinopsis ni reparto): el emisor NO adjunta el meta
  /// y el receptor cae al comportamiento actual (TmdbEnrichment/solo-título).
  bool get isEmpty => overview.isEmpty && cast.isEmpty;

  Map<String, dynamic> toJson() => {
        if (overview.isNotEmpty) 'o': overview,
        if (cast.isNotEmpty)
          'cast': [for (final m in cast.take(_maxCast)) m.toJson()],
        if (title.isNotEmpty) 'title': title,
        if (year != null) 'year': year,
      };

  /// DEFENSIVO: todo cast del wire es tolerante (fallback), los miembros no-Map se
  /// SALTAN (no lanzan), el reparto se capa a [_maxCast] y la sinopsis a
  /// [_maxOverview]. Un `meta` malformado nunca debe abortar el LOAD.
  factory CastMeta.fromJson(Map<String, dynamic> j) {
    final rawCast = j['cast'];
    final members = <CastMetaMember>[];
    if (rawCast is List) {
      for (final e in rawCast) {
        if (e is Map) {
          members.add(CastMetaMember.fromJson(Map<String, dynamic>.from(e)));
        }
        if (members.length >= _maxCast) break;
      }
    }
    var overview = _wireString(j['o']);
    if (overview.length > _maxOverview) {
      overview = overview.substring(0, _maxOverview);
    }
    return CastMeta(
      overview: overview,
      cast: members,
      title: _wireString(j['title']),
      year: j['year'] is num ? (j['year'] as num).toInt() : null,
    );
  }
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
