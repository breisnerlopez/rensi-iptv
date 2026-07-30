// Valida que la generación de cert self-signed funciona en este proyecto y que
// el par cert+key sirve para SecurityContext (lo que usará HttpServer.bindSecure
// para servir wss). Es la validación headless del camino de wss/cert-pinning.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/cast_tls.dart';

void main() {
  test('genera un cert self-signed con fingerprint pineable y round-trip', () {
    final tls = CastTls.generate();
    expect(tls.certPem, contains('BEGIN CERTIFICATE'));
    expect(tls.keyPem, contains('PRIVATE KEY'));
    expect(tls.certDer, isNotEmpty);
    expect(tls.fingerprint.length, 32); // SHA-256

    // Persistencia round-trip: mismo fingerprint tras restaurar.
    final restored = CastTls.fromStorage(tls.toStorage());
    expect(restored.fingerprint, tls.fingerprint);
  });

  test('el cert+key sirven para SecurityContext (HttpServer.bindSecure)', () {
    final tls = CastTls.generate();
    final ctx = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(tls.certPem.codeUnits)
      ..usePrivateKeyBytes(tls.keyPem.codeUnits);
    expect(ctx, isNotNull);
  });
}
