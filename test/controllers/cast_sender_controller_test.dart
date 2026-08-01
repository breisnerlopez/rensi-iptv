// Tests de la máquina de estados del casting (lado móvil), con un sender falso
// inyectado — sin sockets ni red. Cubre el flujo feliz y los caminos de error.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/watch_history_service.dart';

import '../helpers/test_database.dart';

class _FakeSender extends PhoneSenderService {
  _FakeSender({
    this.devices = const [],
    this.correctPin = '123456',
    this.failConnect = false,
  });
  final List<CastDevice> devices;
  final String correctPin;
  final bool failConnect;
  final List<Map<String, String>> loads = [];
  final List<CastMeta?> loadMetas = [];
  final List<int> loadStartPositions = [];
  final List<String> commands = [];
  bool closed = false;

  @override
  Future<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async =>
      devices;
  @override
  Future<void> connect(String host, int port, {bool secure = false}) async {
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
  }) async {
    loads.add({'id': channelId, 'url': url, 'user': username, 'pass': password});
    loadMetas.add(meta);
    loadStartPositions.add(startPositionMs);
  }
  @override
  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) =>
      commands.add(cmd);

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

  // NB: do NOT close _tracks here. beginCast()'s discovery step calls close() on
  // the SAME fake instance (senderFactory returns one shared fake), so closing
  // the stream would kill the tracks channel the controller later subscribes to.
  @override
  Future<void> close() async => closed = true;
}

void main() {
  final oneTv = CastDevice(name: 'Sala', host: '192.168.1.9', port: 55000);
  const media = CastMedia(channelId: '6519', contentType: 'live', title: 'Canal 6519');

  setUp(() {
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

  test('reconexión: al caerse el socket mientras castea, reconecta y reenvía el LOAD',
      () async {
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
    expect(fake.loads.length, 2, reason: 'reenvió el LOAD tras reconectar');
  }, timeout: const Timeout(Duration(seconds: 10)));

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
}
