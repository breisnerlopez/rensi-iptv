// Certificado self-signed para el canal wss:// del casting (SIN backend).
// La TV genera un par EC P-256 + un cert X.509 self-signed en runtime (una vez,
// persistido), sirve wss con él, y anuncia el SHA-256 de su cert (fingerprint).
// El móvil PINEA ese fingerprint (aprendido en el pairing y atado al PIN), así
// que no confía en ninguna CA del sistema: solo en ESA TV.
//
// EC P-256 (no RSA-2048) porque su generación es mucho más rápida en un TV de
// gama baja (PointyCastle es Dart puro, sin aceleración nativa).
import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

class CastTls {
  final String certPem;
  final String keyPem;
  final Uint8List certDer;
  CastTls({required this.certPem, required this.keyPem, required this.certDer});

  /// SHA-256 del DER del certificado — lo que se pinea.
  Uint8List get fingerprint => Uint8List.fromList(sha256.convert(certDer).bytes);

  /// Genera un par EC + cert self-signed nuevos. Operación costosa: hacerla una
  /// vez y persistir (ver [toStorage]/[fromStorage]).
  static CastTls generate() {
    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    const dn = {'CN': 'rensi-tv'};
    final csr = X509Utils.generateEccCsrPem(dn, priv, pub);
    final certPem = X509Utils.generateSelfSignedCertificate(
      priv,
      csr,
      3650, // ~10 años: el trust es por pinning, no por fecha
      issuer: dn,
      sans: ['rensi-tv'],
    );
    final keyPem = CryptoUtils.encodeEcPrivateKeyToPem(priv);
    return CastTls(certPem: certPem, keyPem: keyPem, certDer: pemToDer(certPem));
  }

  /// DER (bytes) del cuerpo base64 de un PEM de certificado.
  static Uint8List pemToDer(String pem) {
    final body = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s'), '');
    return base64.decode(body);
  }

  /// Serializa para persistir (secure storage): cert+key PEM.
  Map<String, String> toStorage() => {'cert': certPem, 'key': keyPem};

  static CastTls fromStorage(Map<String, String> m) => CastTls(
        certPem: m['cert']!,
        keyPem: m['key']!,
        certDer: pemToDer(m['cert']!),
      );
}
