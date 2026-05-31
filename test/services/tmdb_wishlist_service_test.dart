import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/services/tmdb_wishlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TmdbWishlistService', () {
    test('toggle adds and removes wishlist items', () async {
      const item = TmdbSearchResult(
        id: 1,
        mediaType: TmdbMediaType.movie,
        title: 'Dune',
        voteAverage: 8,
      );

      expect(await TmdbWishlistService.toggle(item), isTrue);
      expect(await TmdbWishlistService.contains(item), isTrue);
      expect(await TmdbWishlistService.getItems(), hasLength(1));

      expect(await TmdbWishlistService.toggle(item), isFalse);
      expect(await TmdbWishlistService.contains(item), isFalse);
      expect(await TmdbWishlistService.getItems(), isEmpty);
    });

    test('getKeys returns id|mediaType identifiers for O(1) lookups',
        () async {
      const movie = TmdbSearchResult(
        id: 42,
        mediaType: TmdbMediaType.movie,
        title: 'A',
        voteAverage: 7,
      );
      const tv = TmdbSearchResult(
        id: 42, // same id, different mediaType
        mediaType: TmdbMediaType.tv,
        title: 'B',
        voteAverage: 7,
      );
      await TmdbWishlistService.toggle(movie);
      await TmdbWishlistService.toggle(tv);

      final keys = await TmdbWishlistService.getKeys();
      expect(keys.contains('42|movie'), isTrue);
      expect(keys.contains('42|tv'), isTrue);
      expect(keys.length, 2);
    });

    test('remove deletes by id+mediaType', () async {
      const movie = TmdbSearchResult(
        id: 7,
        mediaType: TmdbMediaType.movie,
        title: 'M',
        voteAverage: 5,
      );
      const tv = TmdbSearchResult(
        id: 7,
        mediaType: TmdbMediaType.tv,
        title: 'T',
        voteAverage: 5,
      );
      await TmdbWishlistService.toggle(movie);
      await TmdbWishlistService.toggle(tv);
      await TmdbWishlistService.remove(movie);
      expect(await TmdbWishlistService.contains(movie), isFalse);
      expect(await TmdbWishlistService.contains(tv), isTrue);
    });
  });
}
