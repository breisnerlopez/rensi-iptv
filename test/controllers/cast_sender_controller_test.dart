// Tests de la máquina de estados del casting (lado móvil), con un sender falso
// inyectado — sin sockets ni red. Cubre el flujo feliz y los caminos de error.
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/controllers/cast_sender_controller.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';

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
  }) async {
    loads.add({'id': channelId, 'url': url, 'user': username, 'pass': password});
  }
  @override
  void sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) =>
      commands.add(cmd);
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
}
