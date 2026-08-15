import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/parental_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ParentalService.instance.relock();
  });

  group('ParentalService', () {
    test('no PIN initially; hasPin false', () async {
      // Fresh mock storage → nothing set.
      expect(await ParentalService.instance.hasPin(), isFalse);
    });

    test('setPin then verify: correct PIN unlocks, wrong PIN does not',
        () async {
      final svc = ParentalService.instance;
      await svc.setPin('1234');
      expect(await svc.hasPin(), isTrue);
      // setPin unlocks the session for the parent.
      expect(svc.isUnlocked, isTrue);

      svc.relock();
      expect(svc.isUnlocked, isFalse);
      expect(await svc.verifyPin('0000'), isFalse,
          reason: 'wrong PIN must not verify');
      expect(svc.isUnlocked, isFalse);
      expect(await svc.verifyPin('1234'), isTrue,
          reason: 'correct PIN verifies');
      expect(svc.isUnlocked, isTrue, reason: 'a correct PIN unlocks the session');
    });

    test('PIN is not stored in clear (hash+salt only)', () async {
      // The stored value is `salt:hash` base64 — never the raw PIN. Verify by
      // reading the raw storage back and asserting the PIN string is absent.
      const storage = FlutterSecureStorage();
      await ParentalService.instance.setPin('4321');
      final raw = await storage.read(key: 'parental.pin');
      expect(raw, isNotNull);
      expect(raw!.contains('4321'), isFalse,
          reason: 'the raw PIN must never appear in storage');
      expect(raw.split(':').length, 2, reason: 'stored as salt:hash');
    });

    test('same PIN yields DIFFERENT stored hashes (random per-PIN salt)',
        () async {
      const storage = FlutterSecureStorage();
      final svc = ParentalService.instance;
      await svc.setPin('1111');
      final first = await storage.read(key: 'parental.pin');
      await svc.setPin('1111');
      final second = await storage.read(key: 'parental.pin');
      expect(first, isNot(equals(second)),
          reason: 'a fresh random salt makes identical PINs hash differently');
    });

    test('clearPin removes the PIN and re-locks', () async {
      final svc = ParentalService.instance;
      await svc.setPin('9999');
      await svc.clearPin();
      expect(await svc.hasPin(), isFalse);
      expect(svc.isUnlocked, isFalse);
    });
  });
}
