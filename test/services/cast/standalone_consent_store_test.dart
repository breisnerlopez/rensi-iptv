// Cobertura del store de consentimiento standalone (lado móvil, feature H).
// SharedPreferences en memoria (setMockInitialValues) — mismo patrón que otros
// tests del repo.
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/standalone_consent_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StandaloneConsentStore', () {
    test('isGranted is false before any grant', () async {
      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-1'), isFalse);
      expect(await StandaloneConsentStore.listGranted(), isEmpty);
    });

    test('grant then isGranted is true; listGranted reports the pair', () async {
      await StandaloneConsentStore.grant('tv-1', 'prov-1');
      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-1'), isTrue);

      final granted = await StandaloneConsentStore.listGranted();
      expect(granted, hasLength(1));
      expect(granted.single.tvId, 'tv-1');
      expect(granted.single.providerId, 'prov-1');
    });

    test('grant is idempotent: granting the same pair twice keeps one entry',
        () async {
      await StandaloneConsentStore.grant('tv-1', 'prov-1');
      await StandaloneConsentStore.grant('tv-1', 'prov-1');
      expect(await StandaloneConsentStore.listGranted(), hasLength(1));
    });

    test('grants are per (tvId, providerId): the same tv can grant two providers',
        () async {
      await StandaloneConsentStore.grant('tv-1', 'prov-1');
      await StandaloneConsentStore.grant('tv-1', 'prov-2');
      await StandaloneConsentStore.grant('tv-2', 'prov-1');

      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-1'), isTrue);
      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-2'), isTrue);
      expect(await StandaloneConsentStore.isGranted('tv-2', 'prov-1'), isTrue);
      // A pair that was never granted stays false.
      expect(await StandaloneConsentStore.isGranted('tv-2', 'prov-2'), isFalse);
      expect(await StandaloneConsentStore.listGranted(), hasLength(3));
    });

    test('revoke removes only the targeted pair', () async {
      await StandaloneConsentStore.grant('tv-1', 'prov-1');
      await StandaloneConsentStore.grant('tv-1', 'prov-2');

      await StandaloneConsentStore.revoke('tv-1', 'prov-1');

      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-1'), isFalse);
      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-2'), isTrue,
          reason: 'revoke must not touch the other pair');
      final granted = await StandaloneConsentStore.listGranted();
      expect(granted, hasLength(1));
      expect(granted.single.providerId, 'prov-2');
    });

    test('revoke of a non-granted pair is a no-op', () async {
      await StandaloneConsentStore.grant('tv-1', 'prov-1');
      await StandaloneConsentStore.revoke('tv-9', 'prov-9'); // never granted
      expect(await StandaloneConsentStore.listGranted(), hasLength(1));
      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-1'), isTrue);
    });
  });

  group('StandaloneConsentStore — cola de borrados pendientes (wipe real)', () {
    test('markPendingWipe/pendingWipesFor: encola por-TV y filtra por tvId',
        () async {
      await StandaloneConsentStore.markPendingWipe('tv-1', 'prov-1');
      await StandaloneConsentStore.markPendingWipe('tv-1', 'prov-2');
      await StandaloneConsentStore.markPendingWipe('tv-2', 'prov-1');

      expect(await StandaloneConsentStore.pendingWipesFor('tv-1'),
          containsAll(['prov-1', 'prov-2']));
      expect(await StandaloneConsentStore.pendingWipesFor('tv-2'), ['prov-1']);
      expect(await StandaloneConsentStore.pendingWipesFor('tv-9'), isEmpty);
    });

    test('markPendingWipe es idempotente', () async {
      await StandaloneConsentStore.markPendingWipe('tv-1', 'prov-1');
      await StandaloneConsentStore.markPendingWipe('tv-1', 'prov-1');
      expect(await StandaloneConsentStore.pendingWipesFor('tv-1'), ['prov-1']);
    });

    test('clearPendingWipe quita solo el par indicado', () async {
      await StandaloneConsentStore.markPendingWipe('tv-1', 'prov-1');
      await StandaloneConsentStore.markPendingWipe('tv-1', 'prov-2');

      await StandaloneConsentStore.clearPendingWipe('tv-1', 'prov-1');

      expect(await StandaloneConsentStore.pendingWipesFor('tv-1'), ['prov-2']);
    });

    test('la cola de pendientes es independiente de los consentimientos',
        () async {
      // Revocar + encolar un wipe no toca la lista de grants de OTROS pares.
      await StandaloneConsentStore.grant('tv-1', 'prov-9');
      await StandaloneConsentStore.markPendingWipe('tv-1', 'prov-1');
      expect(await StandaloneConsentStore.isGranted('tv-1', 'prov-9'), isTrue);
      expect(await StandaloneConsentStore.pendingWipesFor('tv-1'), ['prov-1']);
    });
  });
}
