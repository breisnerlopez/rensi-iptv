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
}
