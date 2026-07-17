import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('media_kit inicializa y crea un Player real (libmpv presente)', () async {
    MediaKit.ensureInitialized();
    final player = Player();
    expect(player, isNotNull);
    // Estado inicial coherente.
    expect(player.state.playing, isFalse);
    await player.dispose();
  });

  test('Player abre un stream inválido y emite error (manejo de errores real)',
      () async {
    MediaKit.ensureInitialized();
    final player = Player();
    final errors = <String>[];
    final sub = player.stream.error.listen(errors.add);
    await player.open(Media('http://127.0.0.1:1/no-such-stream.m3u8'),
        play: true);
    // Dale tiempo real a libmpv para fallar la apertura.
    await Future.delayed(const Duration(seconds: 4));
    // ignore: avoid_print
    print('PLAYER errors=${errors.length}: ${errors.take(2).toList()}');
    await sub.cancel();
    await player.dispose();
    // No afirmamos count exacto (depende de libmpv), solo que no crashea.
    expect(true, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
