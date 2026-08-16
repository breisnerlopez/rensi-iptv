import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/imported_filename.dart';

void main() {
  group('parseImportedFilename', () {
    test('película con año y tags de release', () {
      final r = parseImportedFilename('Collateral.2004.1080p.BluRay.x264.mkv');
      expect(r.title, 'Collateral');
      expect(r.year, 2004);
      expect(r.isEpisode, isFalse);
    });

    test('episodio SxxExx → isEpisode, título antes del marcador', () {
      final r = parseImportedFilename('Show.Name.S01E02.720p.WEB-DL.mkv');
      expect(r.title, 'Show Name');
      expect(r.isEpisode, isTrue);
    });

    test('episodio formato 1x05', () {
      final r = parseImportedFilename('Rick and Morty 1x05.mkv');
      expect(r.title, 'Rick and Morty');
      expect(r.isEpisode, isTrue);
    });

    test('año entre paréntesis', () {
      final r = parseImportedFilename('The Matrix (1999).mp4');
      expect(r.title, 'The Matrix');
      expect(r.year, 1999);
      expect(r.isEpisode, isFalse);
    });

    test('nombre suelto sin metadata → nombre normalizado', () {
      final r = parseImportedFilename('some_random_video.mp4');
      expect(r.title, 'some random video');
      expect(r.year, isNull);
      expect(r.isEpisode, isFalse);
    });

    test('sin extensión', () {
      final r = parseImportedFilename('Just A Title');
      expect(r.title, 'Just A Title');
      expect(r.isEpisode, isFalse);
    });

    test('solo tags tras el título no dejan el título vacío', () {
      final r = parseImportedFilename('Interstellar 2160p HDR x265.mkv');
      expect(r.title, 'Interstellar');
    });
  });
}
