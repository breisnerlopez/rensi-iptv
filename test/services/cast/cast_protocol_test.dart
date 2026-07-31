// Tests del núcleo de seguridad del canal de control (emparejamiento + cifrado).
// Deterministas y headless: son la red de seguridad de la parte más delicada
// (credenciales por la LAN). Ver lib/services/cast/cast_protocol.dart.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/tv_receiver_service.dart';

void main() {
  group('CastLoadRequest.mediaUrl — construye la URL Xtream por tipo', () {
    CastLoadRequest req(String ct, {String ext = ''}) => CastLoadRequest(
        channelId: '9', contentType: ct, url: 'http://h:8080',
        username: 'u', password: 'p', title: 't', ext: ext);

    test('live: sin segmento de tipo ni extensión', () {
      expect(req('live').mediaUrl, 'http://h:8080/u/p/9');
    });
    test('vod: /movie/…/id.ext', () {
      expect(req('vod', ext: 'mp4').mediaUrl, 'http://h:8080/movie/u/p/9.mp4');
    });
    test('series: /series/…/id.ext', () {
      expect(req('series', ext: 'mkv').mediaUrl, 'http://h:8080/series/u/p/9.mkv');
    });
    test('vod sin extensión: sin sufijo', () {
      expect(req('vod').mediaUrl, 'http://h:8080/movie/u/p/9');
    });
    test('file: URL LAN cruda del archivo local, sin credenciales ni sufijo', () {
      // Un archivo local servido por el móvil ya viene como URL completa
      // (http://<ip>:<port>/f); el receptor la reproduce tal cual.
      final r = CastLoadRequest(
          channelId: 'x',
          contentType: 'file',
          url: 'http://192.168.1.23:41231/f',
          username: '',
          password: '',
          title: 'peli',
          ext: 'mp4');
      expect(r.mediaUrl, 'http://192.168.1.23:41231/f');
    });
  });

  group('CastCrypto — emparejamiento por PIN', () {
    test('el mismo PIN + salt derivan la misma clave en ambos extremos', () async {
      final salt = randomBytes(16);
      final a = await CastCrypto.deriveSessionKey('123456', salt);
      final b = await CastCrypto.deriveSessionKey('123456', salt);
      expect(await a.extractBytes(), await b.extractBytes());
    });

    test('PIN distinto → clave distinta', () async {
      final salt = randomBytes(16);
      final a = await CastCrypto.deriveSessionKey('123456', salt);
      final b = await CastCrypto.deriveSessionKey('654321', salt);
      expect(await a.extractBytes(), isNot(await b.extractBytes()));
    });

    test('salt distinto → clave distinta (mismo PIN)', () async {
      final a = await CastCrypto.deriveSessionKey('123456', randomBytes(16));
      final b = await CastCrypto.deriveSessionKey('123456', randomBytes(16));
      expect(await a.extractBytes(), isNot(await b.extractBytes()));
    });

    test('la prueba HMAC del PIN correcto verifica', () async {
      final salt = randomBytes(16);
      final nonce = randomBytes(16);
      final key = await CastCrypto.deriveSessionKey('123456', salt);
      final proof = await CastCrypto.proof(key, nonce);
      expect(await CastCrypto.verifyProof(key, nonce, proof), isTrue);
    });

    test('la prueba de un PIN incorrecto NO verifica', () async {
      final salt = randomBytes(16);
      final nonce = randomBytes(16);
      final tvKey = await CastCrypto.deriveSessionKey('123456', salt);
      final attackerKey = await CastCrypto.deriveSessionKey('000000', salt);
      final badProof = await CastCrypto.proof(attackerKey, nonce);
      expect(await CastCrypto.verifyProof(tvKey, nonce, badProof), isFalse);
    });

    test('la prueba no verifica con otro nonce (anti-replay del reto)', () async {
      final salt = randomBytes(16);
      final key = await CastCrypto.deriveSessionKey('123456', salt);
      final proof = await CastCrypto.proof(key, randomBytes(16));
      expect(await CastCrypto.verifyProof(key, randomBytes(16), proof), isFalse);
    });
  });

  group('CastCrypto — atadura del cert al PIN (wss / anti-MITM)', () {
    test('el proof cambia si cambia el certfp', () async {
      final salt = randomBytes(16);
      final nonce = randomBytes(16);
      final key = await CastCrypto.deriveSessionKey('123456', salt);
      final p1 = await CastCrypto.proof(key, nonce, [1, 2, 3]);
      final p2 = await CastCrypto.proof(key, nonce, [9, 9, 9]);
      expect(p1, isNot(p2));
    });

    test('un proof atado a un certfp NO verifica contra otro cert (MITM)', () async {
      final salt = randomBytes(16);
      final nonce = randomBytes(16);
      final key = await CastCrypto.deriveSessionKey('123456', salt);
      final proof = await CastCrypto.proof(key, nonce, [1, 2, 3, 4]);
      expect(await CastCrypto.verifyProof(key, nonce, proof, [5, 6, 7, 8]), isFalse);
      expect(await CastCrypto.verifyProof(key, nonce, proof, [1, 2, 3, 4]), isTrue);
    });

    test('bytesEqual compara en tiempo constante', () {
      expect(CastCrypto.bytesEqual([1, 2, 3], [1, 2, 3]), isTrue);
      expect(CastCrypto.bytesEqual([1, 2, 3], [1, 2, 4]), isFalse);
      expect(CastCrypto.bytesEqual([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('CastCrypto — credenciales cifradas (AES-GCM)', () {
    test('round-trip: descifra exactamente lo cifrado', () async {
      final key = await CastCrypto.deriveSessionKey('123456', randomBytes(16));
      final creds = {'url': 'http://host:8080', 'user': 'u123', 'pass': 's3cr3t'};
      final enc = await CastCrypto.encryptJson(key, creds);
      expect(await CastCrypto.decryptJson(key, enc), creds);
    });

    test('las credenciales NO viajan en claro (ni user ni pass en el payload)', () async {
      final key = await CastCrypto.deriveSessionKey('123456', randomBytes(16));
      final enc = await CastCrypto.encryptJson(
          key, {'url': 'http://h', 'user': 'BREISNER', 'pass': 'p4ssw0rd'});
      final wire = jsonEncode(enc);
      expect(wire, isNot(contains('BREISNER')));
      expect(wire, isNot(contains('p4ssw0rd')));
    });

    test('una clave equivocada NO puede descifrar', () async {
      final k1 = await CastCrypto.deriveSessionKey('123456', randomBytes(16));
      final k2 = await CastCrypto.deriveSessionKey('999999', randomBytes(16));
      final enc = await CastCrypto.encryptJson(k1, {'x': 'y'});
      expect(() => CastCrypto.decryptJson(k2, enc), throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('ciphertext manipulado → falla la MAC (integridad)', () async {
      final key = await CastCrypto.deriveSessionKey('123456', randomBytes(16));
      final enc = await CastCrypto.encryptJson(key, {'pass': 'abc'});
      final raw = base64.decode(enc['ct']!);
      raw[0] ^= 0xFF; // manipular un byte
      final tampered = {...enc, 'ct': base64.encode(raw)};
      expect(() => CastCrypto.decryptJson(key, tampered), throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('cada cifrado usa un nonce distinto (no reutiliza)', () async {
      final key = await CastCrypto.deriveSessionKey('123456', randomBytes(16));
      final a = await CastCrypto.encryptJson(key, {'x': '1'});
      final b = await CastCrypto.encryptJson(key, {'x': '1'});
      expect(a['n'], isNot(b['n']));
    });
  });

  group('protocolo — envelope', () {
    test('encode/decode preserva tipo y cuerpo', () {
      final raw = encodeMsg(MsgType.load, {'id': '6519', 'ct': 'live'});
      final msg = decodeMsg(raw);
      expect(msg['t'], MsgType.load);
      expect(msg['id'], '6519');
      expect(msg['ct'], 'live');
    });

    test('randomBytes devuelve la longitud pedida y varía', () {
      expect(randomBytes(16).length, 16);
      expect(randomBytes(16), isNot(randomBytes(16)));
    });
  });

  group('CastMeta — metadatos TMDb opcionales del LOAD', () {
    final meta = const CastMeta(
      overview: 'Un desastre en una plataforma petrolífera.',
      cast: [
        CastMetaMember(
            name: 'Mark Wahlberg',
            character: 'Mike Williams',
            profilePath: '/mw.jpg'),
        CastMetaMember(name: 'Kurt Russell'), // sin personaje ni foto
      ],
      title: 'Marea negra',
      year: 2016,
    );

    test('round-trip: toJson→fromJson conserva todos los campos', () {
      final r = CastMeta.fromJson(meta.toJson());
      expect(r.overview, meta.overview);
      expect(r.title, meta.title);
      expect(r.year, 2016);
      expect(r.cast.length, 2);
      expect(r.cast[0].name, 'Mark Wahlberg');
      expect(r.cast[0].character, 'Mike Williams');
      expect(r.cast[0].profilePath, '/mw.jpg');
      // El 2º miembro no tenía personaje ni foto → campos vacíos/null, no crash.
      expect(r.cast[1].name, 'Kurt Russell');
      expect(r.cast[1].character, '');
      expect(r.cast[1].profilePath, isNull);
    });

    test('NO transporta poster/backdrop (footgun de URL de host arbitrario)', () {
      // Ni el emisor los puebla ni el wire debe llevarlos.
      expect(meta.toJson().containsKey('poster'), isFalse);
      expect(meta.toJson().containsKey('backdrop'), isFalse);
    });

    test('DEFENSIVO: un meta de tipos INVÁLIDOS no lanza y da valores benignos',
        () {
      // Exactamente lo que el receptor haría con el meta de un LOAD malformado
      // (peer malicioso / version-skew). Antes esto lanzaba y ABORTABA el LOAD.
      late CastMeta r;
      expect(
        () => r = CastMeta.fromJson({
          'o': 123, // no-String
          'title': ['x'], // no-String
          'year': 'abc', // no-num
          'cast': [
            null, // no-Map → se salta
            42, // no-Map → se salta
            {'n': 999, 'c': true, 'p': 7}, // campos de tipos inválidos
            {'n': 'Válido'},
          ],
        }),
        returnsNormally,
      );
      expect(r.overview, '');
      expect(r.title, '');
      expect(r.year, isNull);
      // Los dos no-Map se saltaron; los dos Map se conservaron (nombre tolerante).
      expect(r.cast.length, 2);
      expect(r.cast[0].name, ''); // 'n' era num → ''
      expect(r.cast[0].profilePath, isNull); // 'p' era num → null
      expect(r.cast[1].name, 'Válido');
    });

    test('DEFENSIVO: capa el reparto y la sinopsis (memoria en la TV)', () {
      final huge = CastMeta.fromJson({
        'o': 'x' * 10000,
        'cast': [for (var i = 0; i < 200; i++) {'n': 'A$i'}],
      });
      expect(huge.cast.length, lessThanOrEqualTo(30));
      expect(huge.overview.length, lessThanOrEqualTo(4000));
    });

    test('un LOAD con meta INVÁLIDO se decodifica sin lanzar (no aborta el LOAD)',
        () {
      // Simula el paso de parseo del receptor sobre un envelope malformado.
      final raw = encodeMsg(MsgType.load, {
        'id': '9',
        'ct': 'vod',
        'meta': {'o': 123, 'cast': [null], 'year': 'abc'},
      });
      final msg = decodeMsg(raw);
      expect(() => CastMeta.fromJson(msg['meta'] as Map<String, dynamic>),
          returnsNormally);
    });

    test('isEmpty: sin sinopsis ni reparto', () {
      expect(const CastMeta().isEmpty, isTrue);
      expect(const CastMeta(overview: 'x').isEmpty, isFalse);
      expect(
          const CastMeta(cast: [CastMetaMember(name: 'A')]).isEmpty, isFalse);
    });

    test('un LOAD que lleva meta round-trips por el envelope del protocolo', () {
      // Exactamente lo que arma phone_sender_service.sendLoad al adjuntar meta.
      final raw = encodeMsg(MsgType.load, {
        'id': '7001',
        'ct': 'vod',
        'title': 'Marea negra',
        'ext': 'mp4',
        'meta': meta.toJson(),
      });
      final msg = decodeMsg(raw);
      expect(msg['t'], MsgType.load);
      final decoded = CastMeta.fromJson(msg['meta'] as Map<String, dynamic>);
      expect(decoded.title, 'Marea negra');
      expect(decoded.cast.first.name, 'Mark Wahlberg');
    });

    test('compat. hacia atrás: un LOAD SIN meta decodifica sin `meta` (null)', () {
      final raw = encodeMsg(MsgType.load, {'id': '9', 'ct': 'live'});
      final msg = decodeMsg(raw);
      expect(msg.containsKey('meta'), isFalse,
          reason: 'una build vieja no incluye meta → el receptor lo trata null');
    });
  });
}
