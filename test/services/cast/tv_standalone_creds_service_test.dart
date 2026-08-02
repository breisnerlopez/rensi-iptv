// Cobertura del store cifrado de credenciales standalone de la TV (feature H).
// Usa el mock in-memory de FlutterSecureStorage (mismo patrón que
// playlist_secrets_service_test.dart). El foco: el invariante índice↔store —
// listProviderIds() nunca debe reportar un providerId que load() no pueda
// resolver (contrato atómico), incluida la corrección del bug de la "entrada
// fantasma" al guardar campos vacíos.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/tv_standalone_creds_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TvStandaloneCredsService', () {
    test('save/load round-trips the three fields', () async {
      await TvStandaloneCredsService.save(
        'prov-1',
        url: 'http://host:8080',
        user: 'u123',
        pass: 's3cr3t',
      );

      final creds = await TvStandaloneCredsService.load('prov-1');
      expect(creds, isNotNull);
      expect(creds!.url, 'http://host:8080');
      expect(creds.user, 'u123');
      expect(creds.pass, 's3cr3t');

      expect(await TvStandaloneCredsService.listProviderIds(), ['prov-1']);
    });

    test('load returns null for an unknown providerId', () async {
      expect(await TvStandaloneCredsService.load('nope'), isNull);
      expect(await TvStandaloneCredsService.listProviderIds(), isEmpty);
    });

    test('delete removes the creds AND the index entry', () async {
      await TvStandaloneCredsService.save('prov-1',
          url: 'http://h', user: 'u', pass: 'p');
      await TvStandaloneCredsService.save('prov-2',
          url: 'http://h2', user: 'u2', pass: 'p2');
      expect(await TvStandaloneCredsService.listProviderIds(),
          containsAll(['prov-1', 'prov-2']));

      await TvStandaloneCredsService.delete('prov-1');

      expect(await TvStandaloneCredsService.load('prov-1'), isNull);
      expect(await TvStandaloneCredsService.listProviderIds(), ['prov-2'],
          reason: 'delete drops prov-1 from the index, leaves prov-2');
      // prov-2 still fully resolvable.
      expect((await TvStandaloneCredsService.load('prov-2'))!.user, 'u2');
    });

    test('listProviderIds is deduped: re-saving the same id keeps one entry',
        () async {
      await TvStandaloneCredsService.save('prov-1',
          url: 'http://h', user: 'u', pass: 'p');
      await TvStandaloneCredsService.save('prov-1',
          url: 'http://h2', user: 'u2', pass: 'p2');
      expect(await TvStandaloneCredsService.listProviderIds(), ['prov-1']);
      expect((await TvStandaloneCredsService.load('prov-1'))!.url, 'http://h2',
          reason: 'a re-save overwrites the fields');
    });

    // ── The bug the gate flagged ────────────────────────────────────────────
    // A save with any empty field deletes that key, so load() (atomic) returns
    // null — the index MUST NOT keep the providerId, or listProviderIds() would
    // report a "phantom" id that load() cannot resolve.
    test('save with an all-empty payload leaves NO phantom index entry',
        () async {
      await TvStandaloneCredsService.save('ghost',
          url: '', user: '', pass: '');
      expect(await TvStandaloneCredsService.load('ghost'), isNull);
      expect(await TvStandaloneCredsService.listProviderIds(), isEmpty,
          reason: 'an all-empty save must not index a non-resolvable id');
    });

    test('re-saving an existing id with an empty field REMOVES it from the index',
        () async {
      // First a full, resolvable save → indexed.
      await TvStandaloneCredsService.save('prov-1',
          url: 'http://h', user: 'u', pass: 'p');
      expect(await TvStandaloneCredsService.listProviderIds(), ['prov-1']);

      // Now a partial save (pass empty) → pass key deleted, load() null.
      await TvStandaloneCredsService.save('prov-1',
          url: 'http://h', user: 'u', pass: '');

      expect(await TvStandaloneCredsService.load('prov-1'), isNull,
          reason: 'atomic load: a missing field yields null');
      expect(await TvStandaloneCredsService.listProviderIds(), isEmpty,
          reason: 'index stays consistent with the atomic load contract');
    });

    test('load is atomic: any single missing field yields null', () async {
      // url + user present, pass missing (via the partial-save path).
      await TvStandaloneCredsService.save('prov-1',
          url: 'http://h', user: 'u', pass: '');
      expect(await TvStandaloneCredsService.load('prov-1'), isNull);

      // pass present, url missing.
      await TvStandaloneCredsService.save('prov-2',
          url: '', user: 'u', pass: 'p');
      expect(await TvStandaloneCredsService.load('prov-2'), isNull);
    });
  });
}
