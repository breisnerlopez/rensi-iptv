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
  // móvil -> TV: reproducir contenido. Campos OPCIONALES del cuerpo del LOAD
  // (feature H — reproducción standalone de la TV): `standalone` (bool) y `pid`
  // (String = id de la playlist del móvil, opaco, NO derivado de las
  // credenciales). Cuando `standalone==true`, la TV —tras descifrar las
  // credenciales— las persiste cifradas indexadas por `pid`
  // (TvStandaloneCredsService) para poder seguir reproduciendo sin el móvil.
  // Compat. hacia atrás: ausentes → comportamiento de siempre (un receptor
  // viejo los ignora; un móvil viejo nunca los envía). Solo se envían para VOD/
  // series Xtream con consentimiento explícito; nunca en vivo/archivo/M3U.
  // Campo OPCIONAL adicional `sid` (String = seriesId): presente sólo en un
  // episodio de serie, para que la TV pueda resolver la lista COMPLETA de
  // episodios y AUTO-AVANZAR sola por la serie al reanudar en standalone.
  static const load = 'load';
  static const command = 'command'; // móvil -> TV: pausa/track/stop
  static const state = 'state'; // TV -> móvil: playing/pos
  static const tracks = 'tracks'; // TV -> móvil: pistas de audio/subtítulo
  static const ended = 'ended'; // TV -> móvil: reproducción detenida/cerrada en la TV
  static const completed = 'completed'; // TV -> móvil: el título terminó (fin de archivo) → el móvil puede auto-avanzar
  static const superseded = 'superseded'; // TV -> móvil: OTRO dispositivo tomó el control (cesión silenciosa; NO es caída ni fin)

  /// Feature H (fase 5) — sincronización BIDIRECCIONAL de "continuar viendo"
  /// entre móvil y TV, SOLO sobre el canal ya emparejado. El móvil envía sus
  /// deltas de la playlist activa tras emparejar/reconectar; la TV los MEZCLA en
  /// su playlist sintética `__cast__`, RESPONDE con sus propios deltas de
  /// `__cast__`, y el móvil los mezcla en su playlist real. Cuerpo:
  ///   { items: [ {cid, tmdb?, pos, dur, ct, ts} ], done?: bool }
  /// Solo-posición (no propaga borrados). Compat. hacia atrás: un extremo viejo
  /// que no lo entiende simplemente no responde (sin caída ni cuelgue). Ver
  /// [HistorySyncItem] / [historySyncShouldWrite].
  static const historySync = 'hist_sync';
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
  static const setVolume = 'set_volume'; // + campo 'v' (0-100)

  /// Feature H — el móvil pide a la TV que BORRE las credenciales standalone
  /// guardadas para un proveedor (+ campo 'pid'). Lo dispara el "olvidar
  /// credenciales" de Ajustes: al revocar (tvId, pid) el móvil marca un
  /// pending-wipe y lo envía la próxima vez que se conecta a esa TV, para que el
  /// borrado ocurra DE VERDAD en la TV (no solo el consentimiento del móvil).
  static const wipeStandalone = 'wipe_standalone';
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
/// El PÓSTER viaja igual que las fotos de reparto: NO una URL completa —que
/// dejaría al emisor apuntar la TV a un host arbitrario (SSRF/carga de host
/// arbitrario en un NetworkImage)— sino el FRAGMENTO `poster_path` CRUDO de TMDb
/// (p.ej. '/abc.jpg'). El receptor lo reconstruye contra el MISMO host fijo de
/// imágenes de TMDb (`image.tmdb.org`) que usan `profileUrl`/`posterUrl` en el
/// resto de la app (ver [posterUrl]). Nunca se transporta backdrop.
class CastMeta {
  // Tope duro de miembros que se materializan/serializan (defensa en profundidad
  // contra un peer que envíe un `cast` gigante para forzar memoria en la TV; el
  // rail ya muestra ≤20).
  static const int _maxCast = 30;
  // Tope de la sinopsis (unos pocos KB): una sinopsis TMDb real cabe de sobra.
  static const int _maxOverview = 4000;
  // Tope del fragmento de póster (un path TMDb real son ~32 chars).
  static const int _maxPosterPath = 256;

  final String overview;
  final List<CastMetaMember> cast;
  final String title; // título TMDb resuelto (puede diferir del del catálogo)
  final int? year;

  /// FRAGMENTO `poster_path` CRUDO de TMDb (p.ej. '/abc.jpg'), NO una URL. El
  /// receptor lo reconstruye contra el host fijo (ver [posterUrl]). Null si el
  /// título no tiene póster TMDb (contenido no enriquecido/archivo local) → el
  /// receptor mantiene su degradado (nunca se cae a una URL cruda del proveedor).
  final String? posterPath;

  const CastMeta({
    this.overview = '',
    this.cast = const [],
    this.title = '',
    this.year,
    this.posterPath,
  });

  /// Sin nada que mostrar (ni sinopsis ni reparto ni póster): el emisor NO
  /// adjunta el meta y el receptor cae al comportamiento actual
  /// (TmdbEnrichment/solo-título). Incluir el póster asegura que un título con
  /// solo carátula (sin sinopsis/reparto) igual la propague a la TV.
  bool get isEmpty =>
      overview.isEmpty && cast.isEmpty && (posterPath?.isEmpty ?? true);

  /// URL del póster reconstruida contra el host FIJO de imágenes de TMDb
  /// (`image.tmdb.org`) — MISMA disciplina y mismo host que `TmdbCredit.profileUrl`
  /// y `TmdbDetailResult.posterUrl` en la app. Como del emisor solo llega el
  /// FRAGMENTO (que se concatena DETRÁS de un path fijo `/t/p/w342`), el emisor no
  /// puede redirigir la carga a otro host. Null si no llegó fragmento.
  String? get posterUrl => (posterPath == null || posterPath!.isEmpty)
      ? null
      : 'https://image.tmdb.org/t/p/w342$posterPath';

  Map<String, dynamic> toJson() => {
        if (overview.isNotEmpty) 'o': overview,
        if (cast.isNotEmpty)
          'cast': [for (final m in cast.take(_maxCast)) m.toJson()],
        if (title.isNotEmpty) 'title': title,
        if (year != null) 'year': year,
        if (posterPath != null && posterPath!.isNotEmpty) 'poster': posterPath,
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
    // FRAGMENTO de póster: tolerante a tipos del wire, capado (un path TMDb real
    // son ~32 chars; el tope frena a un peer que mande una cadena gigante). Solo
    // es el fragmento; la URL se arma contra el host FIJO en [posterUrl].
    var poster = _wireString(j['poster']);
    if (poster.length > _maxPosterPath) {
      poster = poster.substring(0, _maxPosterPath);
    }
    return CastMeta(
      overview: overview,
      cast: members,
      title: _wireString(j['title']),
      year: j['year'] is num ? (j['year'] as num).toInt() : null,
      posterPath: poster.isEmpty ? null : poster,
    );
  }
}

/// Tope duro de items por sincronización de historial (feature H fase 5). Capa
/// tanto lo que se ENVÍA (los más recientes por `lastWatched`) como lo que se
/// PARSEA al recibir (defensa contra un peer que mande un lote gigante para
/// forzar memoria/ANR en una TV débil).
const int kHistorySyncMaxItems = 200;

/// Un item del wire de sincronización de historial (feature H fase 5). Forma
/// mínima a propósito ({cid, tmdb?, pos, dur, ct, ts}): cuanto menor el payload,
/// menor el riesgo de ANR/OOM en una TV débil al recibir el lote. NO lleva
/// título/carátula: el lado receptor conserva los de su fila existente y, para
/// una fila NUEVA (contenido que solo existía en el otro dispositivo), guarda la
/// posición aunque el título quede vacío (el objetivo es que el progreso llegue).
class HistorySyncItem {
  /// `cid` — id de stream (Xtream). Clave de unión primaria: es la MISMA en la
  /// fila real del móvil y en la fila `__cast__` de la TV.
  final String streamId;

  /// `tmdb` — id TMDb OPCIONAL. Reconciliación secundaria: cuando AMBOS lados lo
  /// tienen y DIFIEREN, se trata como contenido distinto (no se mezcla), aunque
  /// el `streamId` colisione entre proveedores. Null si no se conoce.
  final int? tmdbId;

  /// `pos` — posición vista (ms).
  final int posMs;

  /// `dur` — duración total (ms).
  final int durMs;

  /// `ct` — índice de [ContentType] (aislamiento: no se mezcla entre tipos).
  final int contentTypeIndex;

  /// `ts` — último visto (epoch ms). Desempata el merge (el más reciente gana).
  final int lastWatchedMs;

  const HistorySyncItem({
    required this.streamId,
    this.tmdbId,
    required this.posMs,
    required this.durMs,
    required this.contentTypeIndex,
    required this.lastWatchedMs,
  });

  Map<String, dynamic> toJson() => {
        'cid': streamId,
        if (tmdbId != null) 'tmdb': tmdbId,
        'pos': posMs,
        'dur': durMs,
        'ct': contentTypeIndex,
        'ts': lastWatchedMs,
      };

  /// DEFENSIVO: todo campo es tolerante a tipos del wire (un peer emparejado
  /// puede correr otra build). Un `cid` no-String → ''; num inválidos → 0. El
  /// llamador (parseHistorySyncItems) descarta los items sin `cid` o sin pos/dur.
  factory HistorySyncItem.fromJson(Map<String, dynamic> j) => HistorySyncItem(
        streamId: j['cid'] is String ? j['cid'] as String : '',
        tmdbId: j['tmdb'] is num ? (j['tmdb'] as num).toInt() : null,
        posMs: (j['pos'] as num?)?.toInt() ?? 0,
        durMs: (j['dur'] as num?)?.toInt() ?? 0,
        contentTypeIndex: (j['ct'] as num?)?.toInt() ?? -1,
        lastWatchedMs: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// Recorta [items] a los [kHistorySyncMaxItems] MÁS RECIENTES por `lastWatched`
/// (descendente). Se aplica tanto al enviar como al recibir.
List<HistorySyncItem> capHistorySync(List<HistorySyncItem> items) {
  if (items.length <= kHistorySyncMaxItems) {
    final sorted = [...items]
      ..sort((a, b) => b.lastWatchedMs.compareTo(a.lastWatchedMs));
    return sorted;
  }
  final sorted = [...items]
    ..sort((a, b) => b.lastWatchedMs.compareTo(a.lastWatchedMs));
  return sorted.sublist(0, kHistorySyncMaxItems);
}

/// REGLA DE MERGE (IDÉNTICA EN AMBOS LADOS — móvil y TV). Decide si [incoming]
/// debe ESCRIBIRSE sobre [existing] (la fila local con el MISMO `streamId`).
///
/// POSICIÓN-PRIMARIA (drift-immune): gana SIEMPRE la posición MÁS LEJANA; el
/// `ts` solo desempata una posición EXACTAMENTE igual. Es deliberado y NO es
/// idéntico a comparar por `ts`: los Android-TV suelen no tener RTC con batería
/// y arrancan con el reloj en época/1970 o desincronizado, así que un `ts` de la
/// TV puede ser arbitrariamente viejo o futuro; usarlo como criterio primario
/// dejaría que un reloj atrasado descarte un avance REAL. Al priorizar la
/// posición, "el progreso siempre se sincroniza" (el intent del usuario) y se
/// alinea con la misma guarda pos-only del `_writeHistory` del cast. Reglas:
///   - Sin fila existente → sí (fila nueva).
///   - Aislamiento por tipo: distinto `ct` → no (no degradar serie↔vod↔vivo).
///   - Cross-check TMDb: si AMBOS tienen `tmdb` y DIFIEREN → no (colisión de
///     streamId entre proveedores; contenido distinto).
///   - Posición entrante MENOR que la existente → no (NUNCA reduce el progreso).
///   - Posición entrante MAYOR → sí (la más lejana gana, sin mirar `ts`).
///   - Posición EXACTAMENTE igual → desempata el `ts` más reciente.
bool historySyncShouldWrite(HistorySyncItem incoming, HistorySyncItem? existing) {
  if (existing == null) return true;
  if (incoming.contentTypeIndex != existing.contentTypeIndex) return false;
  final a = incoming.tmdbId, b = existing.tmdbId;
  if (a != null && b != null && a != b) return false;
  if (incoming.posMs < existing.posMs) return false; // nunca reduce
  if (incoming.posMs > existing.posMs) return true; // la más lejana gana
  return incoming.lastWatchedMs > existing.lastWatchedMs; // empate exacto → ts
}

/// Serializa el cuerpo de un mensaje [MsgType.historySync].
Map<String, dynamic> encodeHistorySyncBody(List<HistorySyncItem> items,
        {bool? done}) =>
    {
      'items': [for (final it in capHistorySync(items)) it.toJson()],
      if (done != null) 'done': done,
    };

/// Parsea (DEFENSIVO) los items de un cuerpo [MsgType.historySync]. Tolera un
/// `items` ausente/de tipo inesperado (→ vacío), entradas no-Map (se saltan) y
/// capa a [kHistorySyncMaxItems] (un lote gigante NO debe tumbar una TV débil).
List<HistorySyncItem> parseHistorySyncItems(Map<String, dynamic> body) {
  final raw = body['items'];
  if (raw is! List) return const [];
  final out = <HistorySyncItem>[];
  // Dos topes independientes: por lo ACEPTADO (`out.length`) y por lo ESCANEADO
  // (`scanned`). Solo el primero no basta: una lista gigante de basura no-Map
  // nunca incrementa `out.length`, así que se iteraría entera (ANR en una TV
  // débil). Acotar por el índice CRUDO frena ese lote adversarial aunque no
  // acepte ni un item.
  var scanned = 0;
  for (final e in raw) {
    if (++scanned > kHistorySyncMaxItems * 2) break;
    if (e is Map) {
      out.add(HistorySyncItem.fromJson(Map<String, dynamic>.from(e)));
    }
    // Tope de materialización: no construir más de lo que vamos a conservar.
    if (out.length >= kHistorySyncMaxItems * 2) break;
  }
  return capHistorySync(out);
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
