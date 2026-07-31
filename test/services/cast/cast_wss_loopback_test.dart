// Valida el handshake wss COMPLETO extremo a extremo por loopback (sin fakes):
// la TV genera un cert, sirve wss con HttpServer.bindSecure, el móvil conecta
// por wss capturando y pineando el cert, y empareja con el proof atado al PIN y
// al fingerprint. Es la prueba headless del camino real de seguridad (el que
// los senders falsos de los otros tests no ejercitan).
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/cast_tls.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/services/cast/tv_receiver_service.dart';

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
    await sender.close();

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
}
