import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/utils/genre_utils.dart';

// Semantics the Browse full-catalogue filter and CategoryDetail rely on after
// unifying on genre_utils: exact-token (never substring) and accent-safe.
ContentItem _movie(String id, String? genre) => ContentItem(
      id,
      'Movie $id',
      '',
      ContentType.vod,
      vodStream: VodStream(
        streamId: id,
        name: 'Movie $id',
        streamIcon: '',
        categoryId: '1',
        rating: '0',
        rating5based: 0,
        containerExtension: 'mp4',
        createdAt: null,
        genre: genre,
      ),
    );

ContentItem _series(String id, String? genre) => ContentItem(
      id,
      'Series $id',
      '',
      ContentType.series,
      seriesStream: SeriesStream(
        playlistId: 'p',
        seriesId: id,
        name: 'Series $id',
        genre: genre,
      ),
    );

void main() {
  test('enumerateGenres covers movies AND series, sorted, deduped', () {
    final items = [
      _movie('1', 'Terror'),
      _movie('2', 'Comedia, Terror'),
      _series('3', 'Terror / Suspense'),
      _movie('4', 'Melodrama'),
      _movie('5', 'Acción'),
    ];
    final genres = enumerateGenres(items);
    expect(genres, ['Acción', 'Comedia', 'Melodrama', 'Suspense', 'Terror']);
  });

  test('Terror selects all horror movies + series (exact token)', () {
    final items = [
      _movie('1', 'Terror'),
      _movie('2', 'Comedia, Terror'),
      _series('3', 'Terror / Suspense'),
      _movie('4', 'Comedia'),
    ];
    final matched =
        items.where((it) => itemHasGenre(it, 'Terror')).map((e) => e.id).toList();
    expect(matched, ['1', '2', '3']);
  });

  test('Drama does NOT catch Melodrama (no substring bleed)', () {
    final items = [_movie('1', 'Drama'), _movie('2', 'Melodrama')];
    final matched =
        items.where((it) => itemHasGenre(it, 'Drama')).map((e) => e.id).toList();
    expect(matched, ['1']);
  });

  test('accented genre "Acción" matches case-insensitively', () {
    final items = [_movie('1', 'Acción'), _movie('2', 'accion sin tilde')];
    expect(itemHasGenre(items[0], 'acción'), isTrue);
    expect(itemHasGenre(items[0], 'Acción'), isTrue);
    // Different bytes (no accent) must not match the accented chip.
    expect(itemHasGenre(items[1], 'Acción'), isFalse);
  });

  test('empty catalogue enumerates no genres (row degradation trigger)', () {
    expect(enumerateGenres([_movie('1', null), _movie('2', '')]), isEmpty);
  });

  test('ampersand genres stay whole ("Action & Adventure" is ONE genre)', () {
    final items = [
      _series('1', 'Action & Adventure'),
      _series('2', 'Sci-Fi & Fantasy, Drama'),
    ];
    expect(enumerateGenres(items),
        ['Action & Adventure', 'Drama', 'Sci-Fi & Fantasy']);
    expect(itemHasGenre(items[0], 'Action & Adventure'), isTrue);
    expect(itemHasGenre(items[0], 'Action'), isFalse);
    expect(itemHasGenre(items[1], 'Sci-Fi & Fantasy'), isTrue);
  });
}
