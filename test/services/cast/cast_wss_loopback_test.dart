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
}
