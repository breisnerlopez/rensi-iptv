// Valida el handshake wss COMPLETO extremo a extremo por loopback (sin fakes):
// la TV genera un cert, sirve wss con HttpServer.bindSecure, el móvil conecta
// por wss capturando y pineando el cert, y empareja con el proof atado al PIN y
// al fingerprint. Es la prueba headless del camino real de seguridad (el que
// los senders falsos de los otros tests no ejercitan).
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/cast_tls.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/services/cast/tv_receiver_service.dart';
import 'package:rensi_iptv/services/cast/tv_standalone_creds_service.dart';
import 'package:rensi_iptv/widgets/cast/tv_receiver_host.dart'
    show maybePersistStandaloneCreds, shouldWipeStandaloneOnBoot;

void main() {
  test('wss + cert-pinning + pairing atado al PIN, extremo a extremo', () async {
    final tls = CastTls.generate();
    final receiver =
        TvReceiverService(deviceName: 'TV', pin: '123456', tls: tls);
    final port = await receiver.start(advertise: false);

    // PIN correcto → empareja por wss con el cert pineado, y el LOAD con
    // credenciales llega descifrado.
    final sender = PhoneSenderService();
    await sender.connect('127.0.0.1', port, secure: true);
    expect(await sender.pair('123456'), isTrue,
        reason: 'pairing por wss con cert-pinning debe funcionar');

    final loadFut = receiver.onLoad.first;
    await sender.sendLoad(
        channelId: '6519',
        contentType: 'live',
        url: 'http://host:8080',
        username: 'u123',
        password: 's3cr3t',
        title: 'Canal');
    final req = await loadFut.timeout(const Duration(seconds: 3));
    expect(req.username, 'u123');
    expect(req.password, 's3cr3t'); // credenciales descifradas intactas
    expect(req.meta, isNull, reason: 'un LOAD sin meta llega con meta null');
    await sender.close();

    // Un 2º LOAD que SÍ lleva meta TMDb: llega decodificado extremo a extremo
    // por el camino real del receptor (mismo socket wss ya emparejado).
    final sender2 = PhoneSenderService();
    await sender2.connect('127.0.0.1', port, secure: true);
    expect(await sender2.pair('123456'), isTrue);
    final loadFut2 = receiver.onLoad.first;
    await sender2.sendLoad(
      channelId: '7001',
      contentType: 'vod',
      url: 'http://host:8080',
      username: 'u123',
      password: 's3cr3t',
      title: 'Marea negra',
      ext: 'mp4',
      meta: const CastMeta(
        overview: 'Sinopsis',
        cast: [
          CastMetaMember(
              name: 'Mark Wahlberg',
              character: 'Mike Williams',
              profilePath: '/mw.jpg'),
        ],
        title: 'Marea negra',
        year: 2016,
      ),
    );
    final req2 = await loadFut2.timeout(const Duration(seconds: 3));
    expect(req2.meta, isNotNull, reason: 'el meta viaja con el LOAD');
    expect(req2.meta!.overview, 'Sinopsis');
    expect(req2.meta!.cast.single.name, 'Mark Wahlberg');
    expect(req2.meta!.cast.single.profilePath, '/mw.jpg');
    expect(req2.meta!.year, 2016);
    // Fix #1: un LOAD sin `pos` llega con startPositionMs 0 (compat. hacia atrás).
    expect(req.startPositionMs, 0, reason: 'LOAD sin pos → resume 0');
    await sender2.close();

    // Fix #1: un 3er LOAD que SÍ lleva posición de resume la round-trip-ea
    // extremo a extremo por el camino real (wss ya emparejado).
    final sender3 = PhoneSenderService();
    await sender3.connect('127.0.0.1', port, secure: true);
    expect(await sender3.pair('123456'), isTrue);
    final loadFut3 = receiver.onLoad.first;
    await sender3.sendLoad(
      channelId: '7002',
      contentType: 'vod',
      url: 'http://host:8080',
      username: 'u123',
      password: 's3cr3t',
      title: 'A medias',
      ext: 'mp4',
      startPositionMs: 630000, // ~10.5 min
    );
    final req3 = await loadFut3.timeout(const Duration(seconds: 3));
    expect(req3.startPositionMs, 630000,
        reason: 'la posición de resume llega intacta a la TV');
    await sender3.close();

    // PIN incorrecto → rechazado también sobre wss.
    final bad = PhoneSenderService();
    await bad.connect('127.0.0.1', port, secure: true);
    expect(await bad.pair('000000'), isFalse);
    await bad.close();

    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('confianza: tras emparejar con PIN, un 2º móvil reanuda SIN PIN', () async {
    final tls = CastTls.generate();
    final tokens = <String>[]; // crece vía onIssueToken (dispositivos de confianza)
    final receiver = TvReceiverService(
      deviceName: 'TV',
      pin: '123456',
      tls: tls,
      tvId: 'tv-1',
      knownTokens: tokens,
      onIssueToken: tokens.add,
    );
    final port = await receiver.start(advertise: false);

    // 1ª vez: PIN → la TV emite un token de confianza.
    final first = PhoneSenderService();
    await first.connect('127.0.0.1', port, secure: true);
    expect(await first.pair('123456'), isTrue);
    expect(first.issuedToken, isNotNull);
    expect(first.tvId, 'tv-1');
    expect(tokens, contains(first.issuedToken));
    await first.close();

    // 2ª vez (otro socket): reanuda con el token, SIN PIN.
    final again = PhoneSenderService();
    await again.connect('127.0.0.1', port, secure: true);
    expect(await again.resume(first.issuedToken!), isTrue,
        reason: 'un token de confianza vigente empareja sin PIN');
    await again.close();

    // Un token desconocido NO reanuda.
    final bad = PhoneSenderService();
    await bad.connect('127.0.0.1', port, secure: true);
    expect(await bad.resume('token-invalido'), isFalse);
    await bad.close();

    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'regresión trust: un token emitido en ESTE arranque se honra sin PIN aunque '
      'knownTokens y la persistencia sean listas DISTINTAS (cableado de producción)',
      () async {
    final tls = CastTls.generate();
    // Reproduce el cableado real de tv_receiver_host: `knownTokens` es la lista
    // FIJA cargada al arrancar (vacía la primera vez), y `onIssueToken` persiste
    // en OTRA lista/almacenamiento. Con el bug, el token recién emitido nunca
    // entraba en la lista que el servicio consulta → se re-pedía el PIN.
    final loadedAtBoot = <String>[]; // lo que se pasó como knownTokens
    final persisted = <String>[]; // adonde va el token emitido (otra lista)
    final receiver = TvReceiverService(
      deviceName: 'TV',
      pin: '123456',
      tls: tls,
      tvId: 'tv-1',
      knownTokens: loadedAtBoot,
      onIssueToken: persisted.add,
    );
    final port = await receiver.start(advertise: false);

    // 1ª vez: PIN → emite token. La lista knownTokens NO se toca.
    final first = PhoneSenderService();
    await first.connect('127.0.0.1', port, secure: true);
    expect(await first.pair('123456'), isTrue);
    final token = first.issuedToken!;
    await first.close();
    expect(loadedAtBoot, isEmpty, reason: 'knownTokens quedó intacta');
    expect(persisted, contains(token));

    // Reconexión en el MISMO arranque de la TV: debe reanudar SIN PIN.
    final again = PhoneSenderService();
    await again.connect('127.0.0.1', port, secure: true);
    expect(await again.resume(token), isTrue,
        reason: 'el token emitido en este arranque debe honrarse sin PIN');
    await again.close();

    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'multi-dispositivo: un 2º LOAD toma el control (last-load-wins) y la TV '
      'avisa `superseded` al 1º ANTES de cerrarlo', () async {
    final tls = CastTls.generate();
    final receiver = TvReceiverService(deviceName: 'TV', pin: '123456', tls: tls);
    final port = await receiver.start(advertise: false);

    // 1er móvil: empareja y hace LOAD → pasa a ser el controlador.
    final first = PhoneSenderService();
    var firstSuperseded = false;
    var firstDisconnected = false;
    first.onSuperseded = () => firstSuperseded = true;
    first.onDisconnected = () => firstDisconnected = true;
    await first.connect('127.0.0.1', port, secure: true);
    expect(await first.pair('123456'), isTrue);
    await first.sendLoad(
        channelId: 'a',
        contentType: 'live',
        url: 'http://h',
        username: 'u',
        password: 'p');
    await receiver.onLoad.first.timeout(const Duration(seconds: 3));

    // 2º móvil: empareja y hace LOAD → arrebata el control.
    final second = PhoneSenderService();
    await second.connect('127.0.0.1', port, secure: true);
    expect(await second.pair('123456'), isTrue);
    await second.sendLoad(
        channelId: 'b',
        contentType: 'live',
        url: 'http://h',
        username: 'u',
        password: 'p');
    await receiver.onLoad.first.timeout(const Duration(seconds: 3));

    // El 1º recibe `superseded` (cesión), NO una caída: llega ANTES del cierre.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(firstSuperseded, isTrue, reason: 'el 1er dispositivo fue cedido');
    expect(firstDisconnected, isFalse,
        reason: 'superseded llega antes del close → no se ve como caída');

    await first.close();
    await second.close();
    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  // ── Feature H — LOAD standalone extremo a extremo + persistencia en la TV ──
  // Por loopback ws:// (SIN TLS): lo que se prueba aquí es el wire de
  // standalone/pid + el descifrado de credenciales (AES-GCM bajo la clave de
  // sesión, independiente de TLS) + la persistencia/borrado en la TV. El
  // handshake wss ya está cubierto por el 1er test; usar ws:// evita su
  // flakiness ocasional de TLS por loopback y aísla lo que aquí importa.
  test('LOAD standalone: `standalone`+`pid` viajan por el wire y la TV persiste '
      'las credenciales descifradas; un LOAD normal NO persiste nada', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final receiver = TvReceiverService(deviceName: 'TV', pin: '123456');
    final port = await receiver.start(advertise: false);

    final sender = PhoneSenderService();
    await sender.connect('127.0.0.1', port, secure: false);
    expect(await sender.pair('123456'), isTrue);

    // (1) LOAD standalone de VOD Xtream.
    final loadFut = receiver.onLoad.first;
    await sender.sendLoad(
      channelId: '7001',
      contentType: 'vod',
      url: 'http://host:8080',
      username: 'u123',
      password: 's3cr3t',
      title: 'Peli',
      ext: 'mp4',
      standalone: true,
      pid: 'prov-1',
    );
    final req = await loadFut.timeout(const Duration(seconds: 3));
    expect(req.standalone, isTrue, reason: '`standalone` round-trip por el wire');
    expect(req.providerId, 'prov-1', reason: '`pid` round-trip por el wire');
    expect(req.username, 'u123'); // credenciales descifradas intactas
    expect(req.password, 's3cr3t');

    // La TV persiste (mismo glue que tv_receiver_host._play).
    await maybePersistStandaloneCreds(req);
    final saved = await TvStandaloneCredsService.load('prov-1');
    expect(saved, isNotNull, reason: 'la TV guardó las credenciales standalone');
    expect(saved!.url, 'http://host:8080');
    expect(saved.user, 'u123');
    expect(saved.pass, 's3cr3t');

    // (2) LOAD NORMAL (sin standalone) → decodifica a false y NO persiste nada.
    final loadFut2 = receiver.onLoad.first;
    await sender.sendLoad(
      channelId: '9',
      contentType: 'vod',
      url: 'http://host:8080',
      username: 'u123',
      password: 's3cr3t',
      title: 'Otra',
      ext: 'mp4',
    );
    final req2 = await loadFut2.timeout(const Duration(seconds: 3));
    expect(req2.standalone, isFalse,
        reason: 'compat. hacia atrás: sin `standalone` en el wire → false');
    expect(req2.providerId, '');
    await maybePersistStandaloneCreds(req2);
    expect(await TvStandaloneCredsService.listProviderIds(), ['prov-1'],
        reason: 'un LOAD normal no deja credenciales en la TV');

    // (3) Wipe por-proveedor: el móvil manda CmdType.wipeStandalone con el pid;
    // llega por el canal de control y la TV borra esas credenciales (creds +
    // índice) — el mismo efecto que aplica tv_receiver_host._handleCommand.
    final cmdFut = receiver.onCommand.first;
    sender.sendCommand(CmdType.wipeStandalone, {'pid': 'prov-1'});
    final cmd = await cmdFut.timeout(const Duration(seconds: 3));
    expect(cmd['c'], CmdType.wipeStandalone);
    expect(cmd['pid'], 'prov-1');
    await TvStandaloneCredsService.delete(cmd['pid'] as String);
    expect(await TvStandaloneCredsService.load('prov-1'), isNull,
        reason: 'el wipe borró las credenciales standalone en la TV');
    expect(await TvStandaloneCredsService.listProviderIds(), isEmpty);

    await sender.close();
    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  // ── Feature H (fase 5) — sync de historial bidireccional por el wire ────────
  // Solo se ejercita el CANAL (envío móvil→TV, entrega a onHistorySync, y la
  // RESPUESTA TV→móvil por sendMessage llegando a onHistorySync del móvil). La
  // mezcla en BD la cubren los tests de WatchHistoryService (sin montar widgets).
  test('historySync: el móvil envía sus deltas, la TV los recibe (solo tras '
      'emparejar) y RESPONDE con los suyos; el móvil los recibe', () async {
    final receiver = TvReceiverService(deviceName: 'TV', pin: '123456');
    final port = await receiver.start(advertise: false);

    final sender = PhoneSenderService();
    // Recogemos lo que le llegue de vuelta al móvil (la respuesta de la TV).
    final phoneGot = <List<HistorySyncItem>>[];
    sender.onHistorySync.listen(phoneGot.add);
    await sender.connect('127.0.0.1', port, secure: false);
    expect(await sender.pair('123456'), isTrue);

    // El móvil envía sus deltas; la TV los surface en onHistorySync. El evento
    // lleva el socket origen + su deviceId (aquí vacío: no hubo LOAD) + los items.
    final tvGotFut = receiver.onHistorySync.first;
    sender.sendHistorySync(const [
      HistorySyncItem(
        streamId: '7001',
        posMs: 60000,
        durMs: 600000,
        contentTypeIndex: 1,
        lastWatchedMs: 1000,
      ),
    ]);
    final (tvSocket, tvDeviceId, tvItems) =
        await tvGotFut.timeout(const Duration(seconds: 3));
    expect(tvItems.single.streamId, '7001');
    expect(tvItems.single.posMs, 60000);
    expect(tvDeviceId, '', reason: 'sin LOAD previo → partición `__cast__` plana');

    // La TV RESPONDE con los suyos por el SOCKET ORIGEN (mismo glue que el host:
    // sendMessageTo). Debe llegar al onHistorySync del móvil.
    receiver.sendMessageTo(
        tvSocket,
        MsgType.historySync,
        encodeHistorySyncBody(const [
          HistorySyncItem(
            streamId: 'tv-9',
            posMs: 120000,
            durMs: 900000,
            contentTypeIndex: 2,
            lastWatchedMs: 2000,
          ),
        ]));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(phoneGot.single.single.streamId, 'tv-9');
    expect(phoneGot.single.single.contentTypeIndex, 2);

    await sender.close();
    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('historySync: un envío ANTES de emparejar se ignora (no llega a la TV)',
      () async {
    final receiver = TvReceiverService(deviceName: 'TV', pin: '123456');
    final port = await receiver.start(advertise: false);

    final sender = PhoneSenderService();
    await sender.connect('127.0.0.1', port, secure: false);
    // SIN emparejar: enviar historySync no debe emitirse en onHistorySync.
    var tvGotSomething = false;
    final sub = receiver.onHistorySync.listen((_) => tvGotSomething = true);
    sender.sendHistorySync(const [
      HistorySyncItem(
        streamId: 'x',
        posMs: 1,
        durMs: 2,
        contentTypeIndex: 1,
        lastWatchedMs: 1,
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(tvGotSomething, isFalse,
        reason: 'solo se procesa sobre el canal emparejado');

    await sub.cancel();
    await sender.close();
    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  // ── Feature H — guarda del auto-wipe al arrancar (no borrar en falso-vacío) ─
  test('shouldWipeStandaloneOnBoot: solo borra con vacío GENUINO, nunca en un '
      'fallo de lectura de tokens', () {
    // Vacío genuino (lectura OK, cero tokens de confianza) → borra.
    expect(
        shouldWipeStandaloneOnBoot(tokensLoadedOk: true, tokensEmpty: true),
        isTrue);
    // Lectura OK con tokens → NO borra (hay dispositivos de confianza).
    expect(
        shouldWipeStandaloneOnBoot(tokensLoadedOk: true, tokensEmpty: false),
        isFalse);
    // Fallo de lectura (falso-vacío por el catch): NUNCA borra, aunque parezca
    // vacío. Esta es la regresión que el gate marcó como bloqueante.
    expect(
        shouldWipeStandaloneOnBoot(tokensLoadedOk: false, tokensEmpty: true),
        isFalse);
    expect(
        shouldWipeStandaloneOnBoot(tokensLoadedOk: false, tokensEmpty: false),
        isFalse);
  });

  // ── Feature H (fase 5) — carrera: reply de historySync atado al socket ORIGEN ─
  // Reproduce la fuga cruzada que este rework debía cerrar: un móvil A manda un
  // historySync cuyo merge es LENTO; mientras está en vuelo, un móvil B hace un
  // LOAD (toma de control → reasigna el socket "activo" a B). La respuesta de A
  // NO debe salir por el socket de B. Se simula el host con el MISMO glue de
  // producción (`_onHistorySync` → `sendMessageTo(socketOrigen, …)`), con el
  // merge gateado por un Completer para hacerlo determinista (sin depender de
  // latencias reales de BD).
  test(
      'race (fase 5): la respuesta a un historySync lento se ata al socket ORIGEN; '
      'un LOAD de OTRO móvil en pleno merge NO se la roba (per-socket, no spoofeable)',
      () async {
    final receiver = TvReceiverService(deviceName: 'TV', pin: '123456');
    final port = await receiver.start(advertise: false);

    // Host-sim: al recibir un lote, MEZCLA (lento, gateado) y RESPONDE al socket
    // ORIGEN en la partición de SU deviceId — igual que _onHistorySync real.
    final mergeGate = Completer<void>();
    final hostSub = receiver.onHistorySync.listen((event) async {
      final (socket, deviceId, _) = event;
      await mergeGate.future; // merge en vuelo hasta que el test lo suelte
      receiver.sendMessageTo(
          socket,
          MsgType.historySync,
          encodeHistorySyncBody([
            HistorySyncItem(
              streamId: 'reply-$deviceId',
              posMs: 1,
              durMs: 2,
              contentTypeIndex: 1,
              lastWatchedMs: 1,
            ),
          ]));
    });

    // Móvil A: empareja, LOAD con SU deviceId (fija la partición del socket) y
    // manda su historySync → arranca el merge lento.
    final a = PhoneSenderService();
    final aGot = <List<HistorySyncItem>>[];
    a.onHistorySync.listen(aGot.add);
    await a.connect('127.0.0.1', port, secure: false);
    expect(await a.pair('123456'), isTrue);
    await a.sendLoad(
        channelId: 'a',
        contentType: 'live',
        url: 'http://h',
        username: 'u',
        password: 'p',
        deviceId: 'devA');
    await receiver.onLoad.first.timeout(const Duration(seconds: 3));
    a.sendHistorySync(const [
      HistorySyncItem(
        streamId: 'a1',
        posMs: 1000,
        durMs: 10000,
        contentTypeIndex: 1,
        lastWatchedMs: 1,
      ),
    ]);
    // Deja que el evento de A llegue al host-sim y quede esperando el gate.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Móvil B: empareja y hace un LOAD → TOMA el control (reasigna el "activo").
    final b = PhoneSenderService();
    final bGot = <List<HistorySyncItem>>[];
    b.onHistorySync.listen(bGot.add);
    await b.connect('127.0.0.1', port, secure: false);
    expect(await b.pair('123456'), isTrue);
    await b.sendLoad(
        channelId: 'b',
        contentType: 'live',
        url: 'http://h',
        username: 'u',
        password: 'p',
        deviceId: 'devB');
    await receiver.onLoad.first.timeout(const Duration(seconds: 3));

    // Con el "socket activo" ya apuntando a B, SUELTA el merge de A: la respuesta
    // debe volver por el socket de A (aún abierto), NUNCA por el de B.
    mergeGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(bGot, isEmpty,
        reason: 'la respuesta de A jamás debe llegar al socket de B (fuga cruzada)');
    expect(aGot, isNotEmpty,
        reason: 'A sigue conectado → recibe su propia respuesta');
    expect(aGot.single.single.streamId, 'reply-devA',
        reason: 'la respuesta va scopeada a la partición de A (deviceId del LOAD de A)');

    await hostSub.cancel();
    await a.close();
    await b.close();
    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  // Caso socket-cerrado: si A se desconecta antes de que termine su merge, la
  // respuesta apunta a un socket muerto → no-op silencioso (nunca cae en otro
  // socket, nunca revienta).
  test(
      'race (fase 5): si el socket ORIGEN ya se cerró al terminar el merge, la '
      'respuesta no va a NADIE (no-op) y no revienta; otro móvil no la recibe',
      () async {
    final receiver = TvReceiverService(deviceName: 'TV', pin: '123456');
    final port = await receiver.start(advertise: false);

    final mergeGate = Completer<void>();
    Object? hostError;
    final hostSub = receiver.onHistorySync.listen((event) async {
      final (socket, deviceId, _) = event;
      await mergeGate.future;
      try {
        receiver.sendMessageTo(
            socket,
            MsgType.historySync,
            encodeHistorySyncBody([
              HistorySyncItem(
                streamId: 'reply-$deviceId',
                posMs: 1,
                durMs: 2,
                contentTypeIndex: 1,
                lastWatchedMs: 1,
              ),
            ]));
      } catch (e) {
        hostError = e; // no debería ocurrir: sendMessageTo no propaga
      }
    });

    // Móvil A: empareja, LOAD(devA), historySync → arranca el merge (gateado).
    final a = PhoneSenderService();
    await a.connect('127.0.0.1', port, secure: false);
    expect(await a.pair('123456'), isTrue);
    await a.sendLoad(
        channelId: 'a',
        contentType: 'live',
        url: 'http://h',
        username: 'u',
        password: 'p',
        deviceId: 'devA');
    await receiver.onLoad.first.timeout(const Duration(seconds: 3));
    a.sendHistorySync(const [
      HistorySyncItem(
        streamId: 'a1',
        posMs: 1000,
        durMs: 10000,
        contentTypeIndex: 1,
        lastWatchedMs: 1,
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Otro móvil B, conectado y a la escucha (jamás debe recibir la respuesta de A).
    final b = PhoneSenderService();
    final bGot = <List<HistorySyncItem>>[];
    b.onHistorySync.listen(bGot.add);
    await b.connect('127.0.0.1', port, secure: false);
    expect(await b.pair('123456'), isTrue);

    // A se DESCONECTA antes de que termine el merge (cierra su socket).
    await a.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Suelta el merge: la respuesta apunta a un socket cerrado → no-op.
    mergeGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(hostError, isNull,
        reason: 'sendMessageTo a un socket cerrado no propaga (best-effort)');
    expect(bGot, isEmpty,
        reason: 'A se fue → la respuesta no cae en el socket de B');

    await hostSub.cancel();
    await b.close();
    await receiver.stop();
    receiver.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
