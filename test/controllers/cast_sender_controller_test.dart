// Tests de la máquina de estados del casting (lado móvil), con un sender falso
// inyectado — sin sockets ni red. Cubre el flujo feliz y los caminos de error.
import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/services/call_state_service.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/services/cast/standalone_consent_store.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

class _FakeSender extends PhoneSenderService {
  _FakeSender({
    this.devices = const [],
    this.correctPin = '123456',
    this.failConnect = false,
    String? tvId,
  }) {
    // tvId es un campo mutable heredado de PhoneSenderService (la TV real lo
    // envía en el reto de emparejamiento). El fake lo fija directamente para los
    // tests de standalone, que gatean la persistencia por (tvId, providerId).
    this.tvId = tvId;
  }
  final List<CastDevice> devices;
  final String correctPin;
  final bool failConnect;
  final List<Map<String, String>> loads = [];
  final List<CastMeta?> loadMetas = [];
  final List<int> loadStartPositions = [];
  final List<bool> loadStandalone = [];
  final List<String> loadPids = [];
  final List<String> loadDeviceIds = []; // `did` enviado en cada LOAD
  final List<String?> loadSeriesIds = []; // `sid` enviado en cada LOAD
  final List<String> commands = [];
  final List<int> seekMs = []; // ms de CmdType.seek enviados (scrub móvil→TV)
  final List<String> wipedPids = []; // pids de CmdType.wipeStandalone enviados
  final List<List<HistorySyncItem>> sentHistory = []; // sendHistorySync enviados
  bool closed = false;
  int connectCalls = 0; // veces que se abrió el canal (detecta una reconexión)

  @override
  Future<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async =>
      devices;
  @override
  Future<void> connect(String host, int port, {bool secure = false}) async {
    connectCalls++;
    if (failConnect) throw Exception('connect failed');
  }
  @override
  Future<bool> pair(String pin) async => pin == correctPin;
  @override
  Future<void> sendLoad({
    required String channelId,
    String contentType = 'live',
    required String url,
    required String username,
    required String password,
    String title = '',
    String ext = '',
    CastMeta? meta,
    int startPositionMs = 0,
    bool standalone = false,
    String pid = '',
    String deviceId = '',
    String? seriesId,
  }) async {
    loads.add({'id': channelId, 'url': url, 'user': username, 'pass': password});
    loadMetas.add(meta);
    loadStartPositions.add(startPositionMs);
    loadStandalone.add(standalone);
    loadPids.add(pid);
    loadDeviceIds.add(deviceId);
    loadSeriesIds.add(seriesId);
  }
  @override
  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) {
    commands.add(cmd);
    if (cmd == CmdType.wipeStandalone && extra['pid'] is String) {
      wipedPids.add(extra['pid'] as String);
    }
    if (cmd == CmdType.seek && extra['ms'] is int) {
      seekMs.add(extra['ms'] as int);
    }
  }

  // Canal de pistas que la TV reporta (MsgType.tracks). El controlador se
  // suscribe a este stream; el test empuja pistas con [emitTracks].
  final _tracks = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get onTracks => _tracks.stream;
  void emitTracks(Map<String, dynamic> m) {
    if (!_tracks.isClosed) _tracks.add(m);
  }

  // Canal de estado que la TV reporta (MsgType.state, incluye pos/dur/vol). El
  // controlador se suscribe a este stream; el test empuja estados con
  // [emitState] para probar el eco de volumen (_onState) sin sockets reales.
  final _states = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get onState => _states.stream;
  void emitState(Map<String, dynamic> m) {
    if (!_states.isClosed) _states.add(m);
  }

  // Feature H (fase 5) — canal de sync de historial. El controlador envía sus
  // deltas con sendHistorySync y se suscribe a onHistorySync para la RESPUESTA
  // de la TV; el test empuja respuestas con [emitHistorySync].
  final _history = StreamController<List<HistorySyncItem>>.broadcast();
  @override
  Stream<List<HistorySyncItem>> get onHistorySync => _history.stream;
  @override
  void sendHistorySync(List<HistorySyncItem> items, {bool done = true}) {
    sentHistory.add(items);
  }
  void emitHistorySync(List<HistorySyncItem> m) {
    if (!_history.isClosed) _history.add(m);
  }

  // NB: do NOT close _tracks here. beginCast()'s discovery step calls close() on
  // the SAME fake instance (senderFactory returns one shared fake), so closing
  // the stream would kill the tracks channel the controller later subscribes to.
  @override
  Future<void> close() async => closed = true;
}

/// Fake del bridge de estado de llamada: sin canal nativo. Emite estados por un
/// StreamController controlable y devuelve un permiso configurable, para probar
/// la vigilancia de llamadas (pausa/reanuda el cast) de forma determinista.
class _FakeCallState extends CallStateService {
  _FakeCallState({this.granted = true});
  final bool granted;
  final _controller = StreamController<String>.broadcast();
  int permissionRequests = 0;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Stream<String> callStates() => _controller.stream;

  void emit(String s) {
    if (!_controller.isClosed) _controller.add(s);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oneTv = CastDevice(name: 'Sala', host: '192.168.1.9', port: 55000);
  const media = CastMedia(channelId: '6519', contentType: 'live', title: 'Canal 6519');

  setUp(() {
    // Feature H (fase 5) — deviceId estable del móvil (SharedPreferences). Sin
    // esto getCastDeviceId caería a '' por MissingPluginException (best-effort
    // en el controlador); con el mock, el LOAD lleva un `did` real y verificable.
    SharedPreferences.setMockInitialValues({});
    AppState.currentPlaylist = Playlist(
      id: 'p',
      name: 'P',
      type: PlaylistType.xtream,
      createdAt: DateTime(2026, 1, 1),
      url: 'http://host:8080',
      username: 'u123',
      password: 's3cr3t',
    );
  });

  CastSenderController make(_FakeSender fake) =>
      CastSenderController(senderFactory: () => fake);

  test('flujo feliz: un TV → conecta → PIN correcto → casting con credenciales', () async {
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);

    await c.beginCast(media);
    // Un solo dispositivo → conecta directo y pasa a pairing.
    expect(c.phase, CastPhase.pairing);
    expect(c.device, oneTv);

    await c.submitPin('123456');
    expect(c.phase, CastPhase.casting);
    expect(c.isCasting, isTrue);
    // El LOAD llevó las credenciales de la playlist activa.
    expect(fake.loads.single, {
      'id': '6519',
      'url': 'http://host:8080',
      'user': 'u123',
      'pass': 's3cr3t',
    });
  });

  test('feature H — el LOAD lleva un deviceId ESTABLE (mismo entre casts)',
      () async {
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    expect(fake.loadDeviceIds.single, isNotEmpty,
        reason: 'el LOAD debe particionar por dispositivo (did no vacío)');
    final first = fake.loadDeviceIds.single;

    // Un segundo cast (misma app/prefs) reutiliza EXACTAMENTE el mismo id: es la
    // clave de partición del historial en la TV, no puede cambiar por sesión.
    final fake2 = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c2 = make(fake2);
    await c2.beginCast(media);
    await c2.submitPin('123456');
    expect(fake2.loadDeviceIds.single, first);
  });

  test('PIN incorrecto marca wrongPin y NO castea', () async {
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('000000');
    expect(c.wrongPin, isTrue);
    expect(c.phase, CastPhase.pairing);
    expect(fake.loads, isEmpty);
    // Reintento con el correcto sí castea.
    await c.submitPin('123456');
    expect(c.phase, CastPhase.casting);
    expect(c.wrongPin, isFalse);
  });

  test('varios TVs → estado devicesFound para que el usuario elija', () async {
    final fake = _FakeSender(devices: [
      oneTv,
      CastDevice(name: 'Cuarto', host: '192.168.1.10', port: 55001),
    ]);
    final c = make(fake);
    await c.beginCast(media);
    expect(c.phase, CastPhase.devicesFound);
    expect(c.devices.length, 2);
  });

  test('sin TVs → error no_devices', () async {
    final c = make(_FakeSender(devices: const []));
    await c.beginCast(media);
    expect(c.phase, CastPhase.error);
    expect(c.error, 'no_devices');
  });

  test('fallo de conexión → error', () async {
    final fake = _FakeSender(devices: [oneTv], failConnect: true);
    final c = make(fake);
    await c.beginCast(media);
    expect(c.phase, CastPhase.error);
  });

  test('stopCasting cierra el socket y vuelve a idle', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    await c.stopCasting();
    expect(c.phase, CastPhase.idle);
    expect(fake.closed, isTrue);
    expect(fake.commands, contains('stop'));
  });

  test('reconexión: al caerse el socket reconecta SIN re-LOAD destructivo; un '
      'state de la TV confirma la sesión viva (reenganche silencioso)', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);
    expect(fake.loads.length, 1);

    // Simular caída del socket estando en casting.
    fake.onDisconnected?.call();
    // Esperar el primer backoff (1s) + la reconexión.
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(c.isCasting, isTrue, reason: 'sigue en casting tras reconectar');
    expect(fake.loads.length, 1,
        reason: 'reenganche silencioso: NO re-LOAD que reinicie la TV desde una '
            'posición vieja (la TV siguió reproduciendo)');

    // La TV eco un `state` (sigue reproduciendo) → confirma la sesión viva; el
    // fallback de recuperación queda cancelado y NUNCA re-LOADea.
    fake.emitState({'id': media.channelId, 'pos': 30000, 'dur': 600000});
    await Future<void>.delayed(const Duration(seconds: 8));
    expect(fake.loads.length, 1,
        reason: 'sesión confirmada viva: sigue sin re-LOAD tras la ventana');

    await c.stopCasting();
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('reconexión: si la TV NO eco ningún state (se reinició/paró), recupera '
      'con un re-LOAD en la ÚLTIMA posición viva, no desde el principio', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    const vod = CastMedia(
      channelId: '7001',
      contentType: 'vod',
      title: 'Peli',
      ext: 'mp4',
      playlistId: 'p',
      historyId: '7001',
    );
    await c.beginCast(vod);
    await c.submitPin('123456');
    // La TV reportó progreso (minuto 0:30) antes de la caída.
    fake.emitState({'id': '7001', 'pos': 30000, 'dur': 600000});
    await Future<void>.delayed(Duration.zero);
    final before = fake.loads.length;

    fake.onDisconnected?.call();
    // Reconecta (~1s) pero la TV NO eco state → pasada la ventana de resync (7s)
    // se recupera con un re-LOAD.
    await Future<void>.delayed(const Duration(seconds: 9));

    expect(fake.loads.length, before + 1, reason: 'recuperó con un re-LOAD');
    expect(fake.loadStartPositions.last, 30000,
        reason: 're-LOAD en la última posición viva de la TV, no en 0');

    await c.stopCasting();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('play/pausa se envía como comando; zap sin catálogo es no-op', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    c.playPause();
    await c.channelUp(); // sin queue → no hace nada
    expect(fake.commands, ['play_pause']);
  });

  test('zap: con catálogo, channelUp/Down reenvían el LOAD del canal vecino',
      () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    final q = const [
      CastMedia(channelId: '1', contentType: 'live', title: 'C1'),
      CastMedia(channelId: '2', contentType: 'live', title: 'C2'),
    ];
    await c.beginCast(q[0], queue: q, index: 0);
    await c.submitPin('123456');
    expect(fake.loads.last['id'], '1');
    await c.channelUp();
    expect(fake.loads.last['id'], '2'); // reenvió el LOAD del siguiente
    await c.channelDown();
    expect(fake.loads.last['id'], '1');
    await c.channelDown(); // ya en el primero → no-op
    expect(fake.loads.length, 3);
  });

  test('selección de audio/subtítulo se envía con su id', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    c.selectAudio('a2');
    c.selectSubtitle('');
    expect(fake.commands, ['sel_audio', 'sel_sub']);
  });

  test('serie: al completar un episodio auto-avanza al siguiente y reenvía LOAD',
      () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    final eps = const [
      CastMedia(channelId: 'e1', contentType: 'series', title: 'Ep 1'),
      CastMedia(channelId: 'e2', contentType: 'series', title: 'Ep 2'),
    ];
    await c.beginCast(eps[0], queue: eps, index: 0);
    await c.submitPin('123456');
    expect(c.media?.channelId, 'e1');
    final before = fake.loads.length;

    // La TV avisa fin de episodio (MsgType.completed) → auto-avance.
    fake.onCompleted?.call();
    await Future<void>.delayed(Duration.zero);
    expect(c.media?.channelId, 'e2');
    expect(fake.loads.last['id'], 'e2');
    expect(fake.loads.length, before + 1);

    // Completar el ÚLTIMO episodio no avanza (no hay siguiente).
    fake.onCompleted?.call();
    await Future<void>.delayed(Duration.zero);
    expect(c.media?.channelId, 'e2');
    expect(fake.loads.length, before + 1);
  });

  test('castNextEpisode: salto MANUAL al siguiente episodio de una serie '
      '(reenvía el LOAD, sin esperar los créditos)', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    final eps = const [
      CastMedia(channelId: 'e1', contentType: 'series', title: 'Ep 1'),
      CastMedia(channelId: 'e2', contentType: 'series', title: 'Ep 2'),
      CastMedia(channelId: 'e3', contentType: 'series', title: 'Ep 3'),
    ];
    await c.beginCast(eps[0], queue: eps, index: 0);
    await c.submitPin('123456');
    expect(c.canCastNextEpisode, isTrue, reason: 'hay episodios por delante');
    final before = fake.loads.length;

    await c.castNextEpisode();
    expect(c.media?.channelId, 'e2');
    expect(fake.loads.last['id'], 'e2');
    expect(fake.loads.length, before + 1);

    await c.castNextEpisode();
    expect(c.media?.channelId, 'e3');
    expect(c.canCastNextEpisode, isFalse,
        reason: 'último episodio: no hay siguiente');

    // En el último no hace nada (no hay siguiente).
    final atLast = fake.loads.length;
    await c.castNextEpisode();
    expect(c.media?.channelId, 'e3');
    expect(fake.loads.length, atLast);
  });

  // Respaldo de auto-avance por STREAM resuelto desde la BD, para cuando la cola
  // en memoria NO ofrece un siguiente episodio (cola null porque se casteó sin
  // cola, reconexión que la perdió, temporada parcial o índice desviado). Este es
  // el caso que rompía "la serie no continúa en la TV" pese a que el `completed`
  // llegaba bien (verificado en 2 emuladores: la cadena TV→móvil funciona; lo
  // frágil era depender solo de la cola). El respaldo resuelve el siguiente por
  // (temporada, episodio) del episodio actual.
  group('auto-avance por STREAM desde la BD (respaldo sin cola)', () {
    late AppDatabase db;
    setUp(() async {
      await getIt.reset();
      db = createTestDatabase();
      getIt.registerSingleton<AppDatabase>(db);
      // Serie 'S1': 2 temporadas × 2 episodios. Se insertan DESORDENADOS a
      // propósito (ids no contiguos, temporada/episodio barajados) para probar
      // que el respaldo se apoya en el ORDER BY (temporada, episodio) de la BD.
      Future<void> ep(String id, int s, int n) =>
          db.insertEpisode(EpisodesCompanion.insert(
            seriesId: 'S1',
            episodeId: id,
            episodeNum: n,
            title: 'S${s}E$n',
            season: s,
            playlistId: 'p',
          ));
      await ep('e12', 1, 2);
      await ep('e21', 2, 1);
      await ep('e11', 1, 1);
      await ep('e22', 2, 2);
    });
    tearDown(() async {
      await getIt.reset();
      await db.close();
    });

    CastMedia streamedEp(String id) => CastMedia(
          channelId: id,
          contentType: 'series',
          title: 'ep $id',
          ext: 'mkv',
          playlistId: 'p',
          historyId: id,
        );

    test('cola null: al completar, resuelve el SIGUIENTE episodio desde la BD',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      // beginCast SIN cola (queue null) — el escenario que dejaba la serie sin
      // auto-avanzar en la TV.
      await c.beginCast(streamedEp('e11'), queue: null, index: 0);
      await c.submitPin('123456');
      final before = fake.loads.length;
      fake.onCompleted?.call();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.media?.channelId, 'e12', reason: 'S1E1 → S1E2 vía BD');
      expect(fake.loads.last['id'], 'e12');
      expect(fake.loads.length, before + 1);
    });

    test('cruza el fin de temporada: S1E2 → S2E1 (vía BD)', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(streamedEp('e12'), queue: null, index: 0);
      await c.submitPin('123456');
      fake.onCompleted?.call();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.media?.channelId, 'e21',
          reason: 'último de la temporada 1 → primero de la 2');
      expect(fake.loads.last['id'], 'e21');
    });

    test('tras avanzar por BD, la cola queda REPARADA (próximo salto sin BD)',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(streamedEp('e11'), queue: null, index: 0);
      await c.submitPin('123456');
      fake.onCompleted?.call(); // e11 → e12 (por BD, reconstruye la cola)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.media?.channelId, 'e12');
      fake.onCompleted?.call(); // e12 → e21 (ya por la cola reparada)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.media?.channelId, 'e21',
          reason: 'la cola reconstruida cubre el resto de la serie');
    });

    test('último episodio de la serie: NO avanza (la TV se queda en el fin)',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(streamedEp('e22'), queue: null, index: 0);
      await c.submitPin('123456');
      final before = fake.loads.length;
      fake.onCompleted?.call();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.media?.channelId, 'e22');
      expect(fake.loads.length, before, reason: 'sin siguiente → sin LOAD');
    });

    test('VOD por stream NO usa el respaldo de BD (no auto-avanza)', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      // Mismo id que un episodio, pero contentType 'vod' → jamás debe avanzar.
      await c.beginCast(
          const CastMedia(
              channelId: 'e11', contentType: 'vod', title: 'peli', playlistId: 'p'),
          queue: null);
      await c.submitPin('123456');
      final before = fake.loads.length;
      fake.onCompleted?.call();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fake.loads.length, before,
          reason: 'VOD no auto-avanza aunque existan episodios homónimos');
    });
  });

  test('castNextEpisode: NO aplica a VOD ni a vivo (solo series)', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    final q = const [
      CastMedia(channelId: 'v1', contentType: 'vod', title: 'Peli 1'),
      CastMedia(channelId: 'v2', contentType: 'vod', title: 'Peli 2'),
    ];
    await c.beginCast(q[0], queue: q, index: 0);
    await c.submitPin('123456');
    expect(c.canCastNextEpisode, isFalse, reason: 'VOD no es serie');
    final before = fake.loads.length;
    await c.castNextEpisode();
    expect(c.media?.channelId, 'v1'); // no avanzó
    expect(fake.loads.length, before);
  });

  test('castNextEpisode: no-op SEGURO mientras se reconecta (socket en backoff)',
      () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    final eps = const [
      CastMedia(channelId: 'e1', contentType: 'series', title: 'Ep 1'),
      CastMedia(channelId: 'e2', contentType: 'series', title: 'Ep 2'),
    ];
    await c.beginCast(eps[0], queue: eps, index: 0);
    await c.submitPin('123456');
    final before = fake.loads.length;

    fake.onDisconnected?.call(); // arranca _reconnect → _reconnecting=true
    expect(c.canCastNextEpisode, isFalse,
        reason: 'no ofrecer el salto sobre un socket muerto');
    await c.castNextEpisode();
    expect(fake.loads.length, before, reason: 'sin re-LOAD durante el backoff');
    expect(c.media?.channelId, 'e1', reason: 'el media no cambió');

    await c.stopCasting();
  });

  test('castNextEpisode: no-op si no se está casteando', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    expect(c.canCastNextEpisode, isFalse);
    await c.castNextEpisode();
    expect(fake.loads, isEmpty);
    expect(c.phase, CastPhase.idle);
  });

  test('castNext: mientras castea, re-LOAD de un nuevo título sin re-emparejar',
      () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    await c.beginCast(media); // 'live' 6519
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);
    final before = fake.loads.length;

    // El usuario abre OTRO título en el móvil mientras castea: se reenvía a la
    // TV (política "casting manda"), NO se reproduce local.
    const next =
        CastMedia(channelId: '7001', contentType: 'vod', title: 'Peli', ext: 'mp4');
    await c.castNext(next);

    expect(c.isCasting, isTrue, reason: 'sigue la MISMA sesión (sin re-pairing)');
    expect(c.media?.channelId, '7001');
    expect(fake.loads.length, before + 1, reason: 're-LOAD del nuevo título');
    expect(fake.loads.last['id'], '7001');
    // Las credenciales siguen saliendo de la playlist activa.
    expect(fake.loads.last['user'], 'u123');
  });

  test('el meta TMDb del CastMedia se reenvía con el LOAD', () async {
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);
    const withMeta = CastMedia(
      channelId: '7001',
      contentType: 'vod',
      title: 'Peli',
      meta: CastMeta(overview: 'Sinopsis', title: 'Peli'),
    );
    await c.beginCast(withMeta);
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);
    expect(fake.loadMetas.single?.overview, 'Sinopsis');

    // Un CastMedia sin meta → LOAD sin meta (compat. hacia atrás).
    await c.castNext(const CastMedia(
        channelId: '8', contentType: 'vod', title: 'Otra'));
    expect(fake.loadMetas.last, isNull);
  });

  test('Fix #1: la posición de resume del CastMedia viaja con el LOAD', () async {
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);
    // Un VOD casteado a medias (p. ej. minuto ~10 = 600000ms).
    const resumed = CastMedia(
      channelId: '7001',
      contentType: 'vod',
      title: 'Peli',
      ext: 'mp4',
      startPositionMs: 600000,
    );
    await c.beginCast(resumed);
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);
    expect(fake.loadStartPositions.single, 600000,
        reason: 'la TV debe reanudar donde el móvil lo dejó, no en 0');
  });

  test('Fix #1: un CastMedia de vivo NO lleva posición (no es buscable)',
      () async {
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);
    await c.beginCast(media); // 'live'
    await c.submitPin('123456');
    expect(fake.loadStartPositions.single, 0);
  });

  test('Fix #1: sin startPositionMs, siembra la posición desde el historial '
      'local ("continuar viendo")', () async {
    await getIt.reset();
    final db = createTestDatabase();
    getIt.registerSingleton<AppDatabase>(db);
    addTearDown(() async {
      await getIt.reset();
      await db.close();
    });
    // Título visto hasta el minuto 12 en el móvil.
    await WatchHistoryService().saveWatchHistory(WatchHistory(
      playlistId: 'p',
      contentType: ContentType.vod,
      streamId: '7001',
      watchDuration: const Duration(minutes: 12),
      totalDuration: const Duration(minutes: 100),
      lastWatched: DateTime(2026),
      title: 'Peli',
    ));
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);
    // CastMedia SIN startPositionMs → debe caer al historial local.
    const m = CastMedia(
      channelId: '7001',
      contentType: 'vod',
      title: 'Peli',
      ext: 'mp4',
      playlistId: 'p',
      historyId: '7001',
    );
    await c.beginCast(m);
    await c.submitPin('123456');
    expect(fake.loadStartPositions.single,
        const Duration(minutes: 12).inMilliseconds,
        reason: 'la posición del LOAD se sembró desde el historial local');
  });

  test('Fix #7 (cast): las pistas que reporta la TV pueblan audio/subtitleTracks',
      () async {
    final fake = _FakeSender(devices: [oneTv], correctPin: '123456');
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    expect(c.audioTracks, isEmpty, reason: 'aún sin pistas reportadas');

    // La TV responde a getTracks con sus pistas reales (MsgType.tracks).
    fake.emitTracks({
      'audio': [
        {'id': 'a1', 'label': 'Español', 'sel': true},
        {'id': 'a2', 'label': 'English', 'sel': false},
      ],
      'sub': [
        {'id': 's1', 'label': 'Español', 'sel': false},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    expect(c.audioTracks.map((t) => t.label), ['Español', 'English'],
        reason: 'el panel de cast lee las pistas REALES de la TV, no el player '
            'local (vacío al castear)');
    expect(c.audioTracks.first.selected, isTrue);
    expect(c.subtitleTracks.single.label, 'Español');
  });

  test('castNext: no-op si no se está casteando', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    final sent = await c.castNext(
        const CastMedia(channelId: 'x', contentType: 'vod', title: 'X'));
    expect(sent, isFalse);
    expect(fake.loads, isEmpty);
    expect(c.phase, CastPhase.idle);
  });

  test('castNext: no-op SEGURO mientras se reconecta (socket muerto en backoff)',
      () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);
    final before = fake.loads.length;

    // Caída del socket → arranca _reconnect y queda _reconnecting=true (backoff).
    fake.onDisconnected?.call();

    // Un recast AHORA no debe tocar el socket muerto: no-op, devuelve false.
    final sent = await c.castNext(
        const CastMedia(channelId: '9', contentType: 'vod', title: 'X'));
    expect(sent, isFalse);
    expect(fake.loads.length, before, reason: 'sin re-LOAD sobre socket en backoff');
    expect(c.media?.channelId, media.channelId, reason: 'el media no cambió');

    await c.stopCasting(); // corta el bucle de reconexión pendiente
  });

  test('superseded: OTRO dispositivo toma el control → idle silencioso, sin '
      'error y sin reconectar', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    await c.beginCast(media);
    await c.submitPin('123456');
    expect(c.isCasting, isTrue);
    final loadsAtTakeover = fake.loads.length;

    // La TV avisa que otro móvil tomó el control.
    fake.onSuperseded?.call();
    await Future<void>.delayed(Duration.zero); // dejar correr el teardown async

    expect(c.phase, CastPhase.idle);
    expect(c.error, isNull, reason: 'cesión SILENCIOSA: sin fase de error');
    expect(c.media, isNull);
    expect(fake.commands, isNot(contains('stop')),
        reason: 'NO enviar stop: la TV la controla ahora el nuevo dispositivo');

    // El cierre de socket que llega justo después NO debe reconectar.
    fake.onDisconnected?.call();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.phase, CastPhase.idle, reason: 'no pelea por recuperar la TV');
    expect(fake.loads.length, loadsAtTakeover,
        reason: 'no reenvió LOAD (no reconectó)');
  });

  test('completar NO auto-avanza para VOD (solo series)', () async {
    final fake = _FakeSender(devices: [oneTv]);
    final c = make(fake);
    final q = const [
      CastMedia(channelId: 'v1', contentType: 'vod', title: 'Peli 1'),
      CastMedia(channelId: 'v2', contentType: 'vod', title: 'Peli 2'),
    ];
    await c.beginCast(q[0], queue: q, index: 0);
    await c.submitPin('123456');
    final before = fake.loads.length;
    fake.onCompleted?.call();
    await Future<void>.delayed(Duration.zero);
    expect(c.media?.channelId, 'v1'); // no avanzó
    expect(fake.loads.length, before);
  });

  group('volumen (control remoto de TV desde el sheet de casting)', () {
    test('setVolume: clamp 0-100, actualización optimista inmediata + notifica',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      var notifications = 0;
      c.addListener(() => notifications++);

      c.setVolume(150); // por encima del máximo
      expect(c.volume, 100, reason: 'clamp superior');
      expect(notifications, greaterThan(0),
          reason: 'el slider se mueve fluido sin esperar la red (optimista)');

      c.setVolume(-10); // por debajo del mínimo
      expect(c.volume, 0, reason: 'clamp inferior');
    });

    test('setVolume: el envío del comando se DEBOUNCE (no un comando por tick)',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      fake.commands.clear();

      // Simula un arrastre: varios ticks seguidos, cada uno dentro de la
      // ventana de debounce del anterior.
      for (var i = 0; i < 5; i++) {
        c.setVolume(50.0 + i);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(fake.commands.where((x) => x == CmdType.setVolume), isEmpty,
          reason: 'aún dentro de la ventana de debounce: nada enviado todavía');

      // Pasada la ventana de debounce sin más ticks, se manda UN solo comando
      // con el último valor (coalescido).
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fake.commands.where((x) => x == CmdType.setVolume).length, 1,
          reason: 'los ticks del arrastre se coalescen en un único envío');
    });

    test('endVolumeDrag: manda el valor final DE INMEDIATO, sin esperar el debounce',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      fake.commands.clear();

      c.beginVolumeDrag();
      c.setVolume(30);
      c.endVolumeDrag(77);
      // Sin esperar ningún delay: el comando ya salió.
      expect(fake.commands, [CmdType.setVolume]);
      expect(c.volume, 77);
    });

    test('nudgeVolume: +5/-5, envío INMEDIATO (sin debounce) y clamp superior',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      fake.commands.clear();

      // Un botón físico de volumen baja: -5 desde 100 (default) → 95, y el
      // comando sale YA (sin esperar los ~180ms del debounce).
      c.nudgeVolume(-5);
      expect(c.volume, 95, reason: 'delta -5 aplicado');
      expect(fake.commands, [CmdType.setVolume],
          reason: 'cada pulsación aterriza de inmediato, sin coalescer');

      // +5 → 100.
      c.nudgeVolume(5);
      expect(c.volume, 100, reason: 'delta +5 aplicado');

      // Clamp superior: otro +5 no pasa de 100.
      c.nudgeVolume(5);
      expect(c.volume, 100, reason: 'clamp superior en 100');
    });

    test('nudgeVolume: clamp inferior en 0', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      c.setVolume(3); // optimista inmediato
      c.nudgeVolume(-5); // 3 - 5 → 0 (clamp)
      expect(c.volume, 0, reason: 'clamp inferior en 0');
    });

    test('_onState: aplica el eco de vol cuando NO se arrastra', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');

      fake.emitState({'id': media.channelId, 'vol': 42});
      await Future<void>.delayed(Duration.zero);
      expect(c.volume, 42);
    });

    test('_onState: IGNORA el eco de vol MIENTRAS el usuario arrastra (evita '
        'el jitter del slider)', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');

      c.beginVolumeDrag();
      c.setVolume(80); // valor optimista bajo el dedo
      // Un eco REZAGADO de un valor anterior llega mid-arrastre.
      fake.emitState({'id': media.channelId, 'vol': 10});
      await Future<void>.delayed(Duration.zero);
      expect(c.volume, 80,
          reason: 'el eco NO debe pelear con el dedo del usuario');

      // Al soltar, el próximo eco vuelve a sincronizar con normalidad.
      c.endVolumeDrag(80);
      fake.emitState({'id': media.channelId, 'vol': 65});
      await Future<void>.delayed(Duration.zero);
      expect(c.volume, 65,
          reason: 'tras soltar, el eco vuelve a aplicar con normalidad');
    });
  });

  // ── Scrub de posición (seek móvil→TV) para VOD/serie en streaming ─────────
  // NOTA (cobertura del guard de vivo): el guard "excluir vivo" y el clamp+cap
  // 1s-antes-de-EOF viven en el LISTENER 'cast_seek' del PlayerWidget (lado
  // receptor), no en el controlador. Ejercerlos exigiría montar el PlayerWidget
  // con un Player nativo MOCKEADO para observar la llamada interna `_player.seek`
  // (o su ausencia) — media_kit expone `Player` como clase concreta, así que no
  // hay infra para interceptar `seek()` sin un display/emulador. El guard es un
  // early-return trivial de una línea y su riesgo real (el error
  // "--force-seekable=yes" en vivo) ya quedó validado en el rig. Aquí se cubre
  // exhaustivamente el lado controlador: envío del comando, drag helpers, freno
  // del eco durante el arrastre, canScrub y el guard de reconexión.
  group('scrub de posición (seek móvil→TV)', () {
    const vod = CastMedia(
      channelId: '7001',
      contentType: 'vod',
      title: 'Peli',
      ext: 'mp4',
      playlistId: 'p',
      historyId: '7001',
    );

    Future<CastSenderController> castVod(_FakeSender fake) async {
      final c = make(fake);
      await c.beginCast(vod);
      await c.submitPin('123456');
      return c;
    }

    test('seekTo: envía CmdType.seek con el ms correcto', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = await castVod(fake);
      c.seekTo(const Duration(minutes: 3)); // 180000 ms
      expect(fake.commands, contains(CmdType.seek));
      expect(fake.seekMs, [180000]);
    });

    test('seekTo: no-op SEGURO mientras se reconecta (socket en backoff)',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = await castVod(fake);
      fake.commands.clear();
      fake.seekMs.clear();

      fake.onDisconnected?.call(); // arranca _reconnect → _reconnecting=true
      c.seekTo(const Duration(minutes: 5));
      expect(fake.seekMs, isEmpty,
          reason: 'no mandar el seek contra un socket muerto en backoff');
      expect(fake.commands.where((x) => x == CmdType.seek), isEmpty);

      await c.stopCasting();
    });

    test('updateSeekDrag: fija la posición ÓPTIMISTA (el thumb sigue al dedo)',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = await castVod(fake);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.beginSeekDrag();
      c.updateSeekDrag(const Duration(seconds: 90));
      expect(c.castPositionMs, 90000, reason: 'posición local optimista');
      expect(notifications, greaterThan(0), reason: 'notifica para redibujar');
      // Aún NO se manda el comando: el seek sale al soltar.
      expect(fake.seekMs, isEmpty);
    });

    test('_onState: IGNORA el eco de posición MIENTRAS se arrastra (evita el '
        'jitter del thumb), pero SÍ toma la duración', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = await castVod(fake);

      c.beginSeekDrag();
      c.updateSeekDrag(const Duration(seconds: 90)); // 90000 bajo el dedo
      // Un eco REZAGADO de la TV llega mid-arrastre con una posición vieja.
      fake.emitState({'id': vod.channelId, 'pos': 5000, 'dur': 600000});
      await Future<void>.delayed(Duration.zero);
      expect(c.castPositionMs, 90000,
          reason: 'el eco de posición NO debe pelear con el dedo');
      expect(c.castDurationMs, 600000,
          reason: 'la duración sí se toma siempre (habilita el slider)');
    });

    test('endSeekDrag: fija la posición, MANDA el seek y reactiva el eco',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = await castVod(fake);

      c.beginSeekDrag();
      c.updateSeekDrag(const Duration(seconds: 90));
      c.endSeekDrag(const Duration(seconds: 90));
      expect(c.castPositionMs, 90000);
      expect(fake.seekMs, [90000], reason: 'al soltar sale el seek a la TV');

      // Tras soltar, el próximo eco vuelve a aplicar con normalidad.
      fake.emitState({'id': vod.channelId, 'pos': 95000, 'dur': 600000});
      await Future<void>.delayed(Duration.zero);
      expect(c.castPositionMs, 95000,
          reason: 'tras soltar, el eco de posición vuelve a sincronizar');
    });

    test('canScrub: false en vivo, false sin duración, true en VOD con duración',
        () async {
      // Vivo: nunca scrub (un seek en vivo lanza --force-seekable=yes).
      final fakeLive = _FakeSender(devices: [oneTv]);
      final cLive = make(fakeLive);
      await cLive.beginCast(media); // media global es 'live'
      await cLive.submitPin('123456');
      expect(cLive.canScrub, isFalse, reason: 'vivo: sin scrub');

      // VOD sin duración conocida aún (ningún state con dur>0): deshabilitado.
      final fake = _FakeSender(devices: [oneTv]);
      final c = await castVod(fake);
      expect(c.castDurationMs, 0);
      expect(c.canScrub, isFalse,
          reason: 'sin duración no hay a dónde saltar (slider deshabilitado)');

      // Llega el primer state con duración → habilitado.
      fake.emitState({'id': vod.channelId, 'pos': 1000, 'dur': 600000});
      await Future<void>.delayed(Duration.zero);
      expect(c.canScrub, isTrue, reason: 'VOD con duración conocida: scrub OK');
    });
  });

  // ── Feature H — gating del flag de persistencia standalone ────────────────
  // El flag `standalone`+`pid` solo debe viajar en el LOAD cuando se cumplen
  // TODAS: permiso maestro ON ∧ consentimiento (tvId, pid) ∧ VOD/serie Xtream.
  // El consentimiento gatea SOLO la persistencia; el casting nunca se bloquea.
  group('standalone (feature H): gating del flag de persistencia', () {
    const tvId = 'tv-42';
    const vod = CastMedia(
      channelId: '7001',
      contentType: 'vod',
      title: 'Peli',
      ext: 'mp4',
      playlistId: 'p', // == AppState.currentPlaylist.id del setUp
      historyId: '7001',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<CastSenderController> castVod(_FakeSender fake,
        {CastMedia m = vod}) async {
      final c = make(fake);
      await c.beginCast(m);
      await c.submitPin('123456');
      return c;
    }

    test('envía standalone+pid con permiso maestro ON + consentimiento + VOD '
        'Xtream', () async {
      await UserPreferences.setTvStandaloneAllowed(true);
      await StandaloneConsentStore.grant(tvId, 'p');
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      final c = await castVod(fake);
      expect(c.isCasting, isTrue);
      expect(fake.loadStandalone.last, isTrue);
      expect(fake.loadPids.last, 'p');
    });

    test('NO envía standalone con el permiso maestro OFF (aunque haya '
        'consentimiento)', () async {
      // Permiso maestro no seteado → default OFF.
      await StandaloneConsentStore.grant(tvId, 'p');
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      final c = await castVod(fake);
      expect(c.isCasting, isTrue, reason: 'el casting NO se bloquea');
      expect(fake.loadStandalone.last, isFalse);
      expect(fake.loadPids.last, '');
    });

    test('NO envía standalone sin consentimiento (aunque el permiso esté ON)',
        () async {
      await UserPreferences.setTvStandaloneAllowed(true);
      // Sin grant para (tvId, 'p').
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      await castVod(fake);
      expect(fake.loadStandalone.last, isFalse);
      expect(fake.loadPids.last, '');
    });

    test('NUNCA envía standalone para vivo, aun con permiso + consentimiento',
        () async {
      await UserPreferences.setTvStandaloneAllowed(true);
      await StandaloneConsentStore.grant(tvId, 'p');
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      // media global es 'live'.
      final c = await castVod(fake, m: media);
      expect(c.isCasting, isTrue);
      expect(fake.loadStandalone.last, isFalse,
          reason: 'standalone es solo VOD/serie, nunca vivo');
    });

    test('NO envía standalone para M3U (Xtream-only)', () async {
      await UserPreferences.setTvStandaloneAllowed(true);
      await StandaloneConsentStore.grant(tvId, 'pm3u');
      AppState.currentPlaylist = Playlist(
        id: 'pm3u',
        name: 'Lista M3U',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026, 1, 1),
        url: 'http://host/list.m3u',
      );
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      await castVod(fake,
          m: const CastMedia(
              channelId: '7001',
              contentType: 'vod',
              title: 'Peli',
              ext: 'mp4',
              playlistId: 'pm3u'));
      expect(fake.loadStandalone.last, isFalse,
          reason: 'el rebuild bare-URL de M3U está fuera de alcance');
    });

    test('NO envía standalone sin tvId conocido (no emparejado)', () async {
      await UserPreferences.setTvStandaloneAllowed(true);
      await StandaloneConsentStore.grant('', 'p');
      // Fake SIN tvId (default null) → no hay ancla de consentimiento por-TV.
      final fake = _FakeSender(devices: [oneTv]);
      await castVod(fake);
      expect(fake.loadStandalone.last, isFalse);
    });

    test('pendingStandaloneConsent: pide consentimiento la 1ª vez y, al '
        'otorgarlo, reenvía el LOAD con standalone', () async {
      await UserPreferences.setTvStandaloneAllowed(true);
      // Aún SIN consentimiento.
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      final c = await castVod(fake);
      expect(fake.loadStandalone.last, isFalse,
          reason: 'el 1er LOAD sale sin standalone (aún no hay consentimiento)');

      final prompt = await c.pendingStandaloneConsent();
      expect(prompt, isNotNull, reason: 'amerita preguntar');
      expect(prompt!.tvId, tvId);
      expect(prompt.providerId, 'p');
      expect(prompt.providerName, 'P'); // nombre de la playlist del setUp

      final before = fake.loads.length;
      await c.grantStandaloneConsent(prompt.tvId, prompt.providerId);
      expect(await StandaloneConsentStore.isGranted(tvId, 'p'), isTrue);
      expect(fake.loads.length, before + 1,
          reason: 'al otorgar, reenvía el LOAD para persistir ya esta sesión');
      expect(fake.loadStandalone.last, isTrue);
      expect(fake.loadPids.last, 'p');

      // Ya otorgado → ya no vuelve a preguntar.
      expect(await c.pendingStandaloneConsent(), isNull);
    });

    test('pendingStandaloneConsent: null cuando el permiso maestro está OFF',
        () async {
      await StandaloneConsentStore.grant(tvId, 'p'); // consentimiento sí…
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      final c = await castVod(fake);
      // …pero permiso maestro OFF → nada que preguntar (ni persistir).
      expect(await c.pendingStandaloneConsent(), isNull);
    });

    test('NO envía standalone si el playlistId del CastMedia DIVERGE de la '
        'playlist activa (pid y creds deben ser de la MISMA playlist)', () async {
      await UserPreferences.setTvStandaloneAllowed(true);
      // Consentimiento para el id de la playlist activa ('p')…
      await StandaloneConsentStore.grant(tvId, 'p');
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      // …pero el CastMedia dice pertenecer a OTRA playlist ('otra'). Las creds
      // del LOAD salen de currentPlaylist ('p') → persistirlas bajo 'otra' (o
      // enviar el pid de 'p' con las creds de 'p' pero el consentimiento de otra)
      // corrompería el replay: se rechaza.
      await castVod(fake,
          m: const CastMedia(
              channelId: '7001',
              contentType: 'vod',
              title: 'Peli',
              ext: 'mp4',
              playlistId: 'otra'));
      expect(fake.loadStandalone.last, isFalse);
      expect(fake.loadPids.last, '');
    });

    test('revoke → pending-wipe → al emparejar de nuevo con esa TV el móvil '
        'envía CmdType.wipeStandalone y lo desencola', () async {
      // El usuario había consentido y ahora "olvida" las creds (flujo de
      // Ajustes: revoke + markPendingWipe), estando desconectado de la TV.
      await StandaloneConsentStore.grant(tvId, 'p');
      await StandaloneConsentStore.revoke(tvId, 'p');
      await StandaloneConsentStore.markPendingWipe(tvId, 'p');
      expect(await StandaloneConsentStore.pendingWipesFor(tvId), ['p']);

      // La próxima vez que el móvil se empareja/castea a esa TV, descarga el
      // wipe pendiente por el canal de control.
      final fake = _FakeSender(devices: [oneTv], tvId: tvId);
      final c = make(fake);
      await c.beginCast(vod);
      await c.submitPin('123456');
      await Future<void>.delayed(Duration.zero); // deja correr el flush async

      expect(fake.wipedPids, contains('p'),
          reason: 'se envió CmdType.wipeStandalone con el pid pendiente');
      expect(await StandaloneConsentStore.pendingWipesFor(tvId), isEmpty,
          reason: 'el pendiente se limpia tras enviarse');
    });
  });

  // ── Feature H (fase 5) — sync bidireccional de historial (hooks del móvil) ──
  group('historySync (feature H fase 5)', () {
    late AppDatabase db;
    setUp(() async {
      await getIt.reset();
      db = createTestDatabase();
      getIt.registerSingleton<AppDatabase>(db);
    });
    tearDown(() async {
      await getIt.reset();
      await db.close();
    });

    Future<void> seedContinueWatching() =>
        WatchHistoryService().saveWatchHistory(WatchHistory(
          playlistId: 'p',
          contentType: ContentType.vod,
          streamId: '7001',
          watchDuration: const Duration(minutes: 5),
          totalDuration: const Duration(minutes: 100),
          lastWatched: DateTime(2026),
          title: 'Peli',
        ));

    test('al emparejar, el móvil ENVÍA sus deltas de la playlist activa una vez',
        () async {
      await seedContinueWatching();
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      // _syncHistory es unawaited (lee BD): dejarlo asentar.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fake.sentHistory.length, 1, reason: 'un solo envío por conexión');
      expect(fake.sentHistory.single.single.streamId, '7001');
      expect(fake.sentHistory.single.single.posMs,
          const Duration(minutes: 5).inMilliseconds);
      await c.stopCasting();
    });

    test('al reconectar, el móvil vuelve a ENVIAR sus deltas (otra vez)',
        () async {
      await seedContinueWatching();
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fake.sentHistory.length, 1);

      // Caída del socket → reconecta (~1s) y vuelve a sincronizar.
      fake.onDisconnected?.call();
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(fake.sentHistory.length, 2,
          reason: 'reengancharse dispara otro sync');
      await c.stopCasting();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('la RESPUESTA de la TV se MEZCLA en la playlist activa del móvil',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');

      // La TV responde con un título visto en la TV (standalone): 20 min de 100.
      fake.emitHistorySync(const [
        HistorySyncItem(
          streamId: 'tv-42',
          posMs: 1200000, // 20 min
          durMs: 6000000, // 100 min
          contentTypeIndex: 1, // vod
          lastWatchedMs: 4000,
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final row = await WatchHistoryService().getWatchHistory('p', 'tv-42');
      expect(row, isNotNull,
          reason: 'el progreso de la TV llegó al "continuar viendo" del móvil');
      expect(row!.watchDuration, const Duration(minutes: 20));
      // El controlador NO responde a la respuesta (evita el ping-pong): no hay
      // un segundo envío disparado por consumir la réplica.
      expect(fake.sentHistory.length, lessThanOrEqualTo(1));
      await c.stopCasting();
    });
  });

  // ── Pausa-al-recibir-llamada mientras se castea ───────────────────────────
  group('pausa por llamada (solo cast)', () {
    test('pauseForCall pausa SOLO si está reproduciendo; es idempotente ante un '
        'segundo evento (ringing→offhook no re-togglea)', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      fake.commands.clear();

      // Tras castear, la TV está reproduciendo → pausa con un play_pause.
      c.pauseForCall();
      expect(fake.commands, [CmdType.playPause]);
      // Un segundo evento (p. ej. offhook tras ringing) NO vuelve a togglear.
      c.pauseForCall();
      expect(fake.commands.length, 1, reason: 'ya pausado: no re-toggle');
    });

    test('resumeAfterCall reanuda SOLO si fuimos nosotros quienes pausamos',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      fake.commands.clear();

      // Sin una pausa-por-llamada previa, resume es no-op.
      c.resumeAfterCall();
      expect(fake.commands, isEmpty);

      // Pausamos por llamada y luego reanudamos: un toggle cada uno.
      c.pauseForCall();
      c.resumeAfterCall();
      expect(fake.commands, [CmdType.playPause, CmdType.playPause]);
      // Un segundo resume ya no hace nada (no estamos en pausa-por-llamada).
      c.resumeAfterCall();
      expect(fake.commands.length, 2);
    });

    test('si el usuario ya pausó a mano, una llamada NO re-togglea (no arranca '
        'una TV pausada) y al colgar tampoco la reanuda', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      fake.commands.clear();

      // Usuario pausa a mano (toggle → estado intencionado = pausado).
      c.playPause();
      expect(fake.commands, [CmdType.playPause]);
      // Llega una llamada: como NO está reproduciendo, no togglea.
      c.pauseForCall();
      expect(fake.commands.length, 1, reason: 'no togglear una TV ya pausada');
      // Y al colgar no reanuda (no fuimos nosotros quienes pausamos).
      c.resumeAfterCall();
      expect(fake.commands.length, 1);
    });

    test('paused-for-call → el usuario togglea A MANO → al colgar '
        'resumeAfterCall NO manda un toggle extra (el usuario tomó el control)',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      fake.commands.clear();

      // La TV pausa por una llamada entrante.
      c.pauseForCall();
      expect(fake.commands, [CmdType.playPause]);

      // Mientras sigue "pausada por llamada", el usuario decide a mano
      // reanudar (o pausar) desde el control remoto: esto debe relinquir el
      // flag _pausedForCall, tomando el control manual del estado de play.
      c.playPause();
      expect(fake.commands, [CmdType.playPause, CmdType.playPause]);

      // La llamada termina: como el usuario ya tomó el control manual,
      // resumeAfterCall debe ser un no-op (NO un tercer toggle que revertiría
      // la acción manual del usuario).
      c.resumeAfterCall();
      expect(fake.commands.length, 2,
          reason: 'resumeAfterCall es no-op: nos relinquimos el control al '
              'usuario togglear a mano durante la pausa-por-llamada');
    });

    test('glue: con el toggle ON y permiso concedido, ringing pausa e idle '
        'reanuda vía el stream de estado de llamada', () async {
      await UserPreferences.setPauseCastOnCall(true);
      final fake = _FakeSender(devices: [oneTv]);
      final callFake = _FakeCallState(granted: true);
      final c =
          CastSenderController(senderFactory: () => fake, callState: callFake);
      await c.beginCast(media);
      await c.submitPin('123456');
      expect(c.isCasting, isTrue);
      // _maybeStartCallWatch es unawaited (lee prefs + pide permiso): asentar.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(callFake.permissionRequests, 1,
          reason: 'se pide el permiso una vez por sesión de casting');
      fake.commands.clear();

      callFake.emit('ringing');
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, [CmdType.playPause], reason: 'pausa al sonar');

      callFake.emit('idle');
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, [CmdType.playPause, CmdType.playPause],
          reason: 'reanuda al colgar');

      await c.stopCasting();
    });

    test('glue: con el toggle OFF no se pide permiso ni se vigilan llamadas',
        () async {
      await UserPreferences.setPauseCastOnCall(false);
      final fake = _FakeSender(devices: [oneTv]);
      final callFake = _FakeCallState(granted: true);
      final c =
          CastSenderController(senderFactory: () => fake, callState: callFake);
      await c.beginCast(media);
      await c.submitPin('123456');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(callFake.permissionRequests, 0, reason: 'toggle OFF: no se pide');
      fake.commands.clear();

      callFake.emit('ringing');
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, isEmpty, reason: 'no se vigilan llamadas');

      await c.stopCasting();
    });

    test('glue: permiso DENEGADO → no se suscribe (una llamada no pausa)',
        () async {
      await UserPreferences.setPauseCastOnCall(true);
      final fake = _FakeSender(devices: [oneTv]);
      final callFake = _FakeCallState(granted: false);
      final c =
          CastSenderController(senderFactory: () => fake, callState: callFake);
      await c.beginCast(media);
      await c.submitPin('123456');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(callFake.permissionRequests, 1);
      fake.commands.clear();

      callFake.emit('ringing');
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, isEmpty,
          reason: 'sin permiso: la función es un no-op silencioso');

      await c.stopCasting();
    });

    test('al parar el casting se libera la vigilancia (idle posterior no '
        'reanuda una TV que ya no controlamos)', () async {
      await UserPreferences.setPauseCastOnCall(true);
      final fake = _FakeSender(devices: [oneTv]);
      final callFake = _FakeCallState(granted: true);
      final c =
          CastSenderController(senderFactory: () => fake, callState: callFake);
      await c.beginCast(media);
      await c.submitPin('123456');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      callFake.emit('ringing');
      await Future<void>.delayed(Duration.zero);
      await c.stopCasting();
      fake.commands.clear();

      // Tras stopCasting, la suscripción se canceló: un idle rezagado no toca
      // nada (el sender ya es null y _pausedForCall se limpió).
      callFake.emit('idle');
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, isEmpty);
    });
  });

  // ── Revalidación de liveness al volver del fondo (BUG 2: el socket muere en
  //    silencio mientras el móvil está backgroundeado; al reanudar hay que
  //    detectarlo y reconectar, no mandar `stop`/comandos a un socket muerto) ──
  group('foreground liveness', () {
    test(
        'resume con socket MUERTO (la TV no responde a la sonda) → getTracks + '
        'reconexión forzada NO destructiva', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      expect(c.isCasting, isTrue);
      final before = fake.loads.length; // 1
      final connectsBefore = fake.connectCalls; // 1 (conexión inicial)
      expect(fake.commands, isNot(contains(CmdType.getTracks)));

      // Vuelve a primer plano SIN haber oído a la TV hace poco → sondea.
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero); // deja salir la sonda
      expect(fake.commands, contains(CmdType.getTracks),
          reason: 'sondea la sesión con getTracks al reanudar');

      // La TV NO responde: pasado el timeout de sonda (9s) + el 1er backoff (1s)
      // se fuerza la reconexión, y la sesión se re-engancha SIN re-LOAD.
      await Future<void>.delayed(const Duration(seconds: 11));
      expect(c.isCasting, isTrue, reason: 'sigue casteando tras reconectar');
      expect(fake.connectCalls, greaterThan(connectsBefore),
          reason: 'se forzó una reconexión (se reabrió el canal)');
      expect(fake.loads.length, before,
          reason: 'reenganche silencioso: sin re-LOAD que reinicie la TV');

      // Un `state` confirma la sesión viva y cancela el fallback de resync.
      fake.emitState({'id': media.channelId, 'pos': 30000, 'dur': 600000});
      await c.stopCasting();
    }, timeout: const Timeout(Duration(seconds: 25)));

    test('resume con socket VIVO (la TV responde a la sonda) → NO reconecta',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      final before = fake.loads.length;
      final connectsBefore = fake.connectCalls;

      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, contains(CmdType.getTracks));

      // La TV responde a la sonda (cualquier mensaje entrante prueba liveness):
      // se cancela el timeout, así que NO se fuerza reconexión.
      fake.emitTracks({'audio': const [], 'sub': const []});
      await Future<void>.delayed(const Duration(seconds: 10)); // > timeout de sonda

      expect(fake.connectCalls, connectsBefore,
          reason: 'socket vivo: no se fuerza reconexión');
      expect(c.isCasting, isTrue);
      expect(fake.loads.length, before, reason: 'sin re-LOAD');
      await c.stopCasting();
    }, timeout: const Timeout(Duration(seconds: 18)));

    test('resume con respuesta de LATENCIA MEDIA (4s < 9s) → NO stale, sin '
        'reconexión (margen del timeout)', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      final connectsBefore = fake.connectCalls;

      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, contains(CmdType.getTracks));

      // Un Android TV despertando de standby responde con retraso: a los 4s
      // (dentro del timeout de 9s) contesta → la sesión NO es stale.
      await Future<void>.delayed(const Duration(seconds: 4));
      fake.emitTracks({'audio': const [], 'sub': const []});
      // Deja pasar el resto de la ventana de sonda: no debe reconectar.
      await Future<void>.delayed(const Duration(seconds: 6)); // total 10s > 9s
      expect(fake.connectCalls, connectsBefore,
          reason: 'respuesta a 4s (< 9s) → socket vivo, sin falso-positivo');
      expect(c.isCasting, isTrue);
      await c.stopCasting();
    }, timeout: const Timeout(Duration(seconds: 18)));

    test('carrera: el pingInterval reconecta ANTES de que venza la sonda → la '
        'sonda obsoleta (token viejo) NO fuerza una 2ª reconexión fantasma',
        () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');
      final connectsAfterCast = fake.connectCalls; // 1

      // Resume arma la sonda de liveness (sin inbound reciente).
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, contains(CmdType.getTracks));

      // En paralelo, el pingInterval detecta la caída → onDisconnected →
      // _reconnect, que COMPLETA (~1s backoff) mucho antes de que venza la sonda
      // (9s): la reconexión exitosa bumpea el token de sesión.
      fake.onDisconnected?.call();
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(fake.connectCalls, connectsAfterCast + 1,
          reason: 'una sola reconexión (la del ping)');
      expect(c.isCasting, isTrue);
      // Confirma la sesión viva (cancela el fallback de resync del reconnect).
      fake.emitState({'id': media.channelId, 'pos': 1000, 'dur': 600000});

      // Deja VENCER la sonda vieja (9s): con el token ya bumpeado NO debe cerrar
      // el socket recién reconectado ni forzar una reconexión fantasma.
      await Future<void>.delayed(const Duration(seconds: 9));
      expect(fake.connectCalls, connectsAfterCast + 1,
          reason: 'la sonda obsoleta no fuerza una reconexión fantasma');
      expect(c.isCasting, isTrue);
      await c.stopCasting();
    }, timeout: const Timeout(Duration(seconds: 25)));

    test('carrera: stop + nuevo cast dentro de la ventana de sonda → la sonda de '
        'la sesión vieja NO toca la nueva', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');

      // Arma la sonda de la sesión A.
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, contains(CmdType.getTracks));

      // Detén A y arranca un cast NUEVO (sesión B) DENTRO de la ventana (9s).
      await c.stopCasting();
      fake.commands.clear();
      await c.beginCast(media);
      await c.submitPin('123456');
      expect(c.isCasting, isTrue);
      final connectsB = fake.connectCalls;

      // Deja vencer la sonda de la sesión A: no debe reconectar/matar la sesión B.
      await Future<void>.delayed(const Duration(seconds: 10));
      expect(c.isCasting, isTrue, reason: 'la sesión B sigue sana');
      expect(fake.connectCalls, connectsB,
          reason: 'la sonda de A no fuerza una reconexión en B');
      await c.stopCasting();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('resume con la TV oída hace POCO → NO sondea (socket ya vivo)', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      await c.beginCast(media);
      await c.submitPin('123456');

      // Un `state` reciente prueba que el socket está vivo.
      fake.emitState({'id': media.channelId, 'pos': 1000, 'dur': 600000});
      await Future<void>.delayed(Duration.zero);
      fake.commands.clear();

      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, isNot(contains(CmdType.getTracks)),
          reason: 'oímos a la TV hace <6s → no hace falta sondear');
      await c.stopCasting();
    });

    test('resume sin casting en curso → no-op (no sonda)', () async {
      final fake = _FakeSender(devices: [oneTv]);
      final c = make(fake);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(fake.commands, isNot(contains(CmdType.getTracks)));
      expect(c.phase, CastPhase.idle);
    });
  });
}
