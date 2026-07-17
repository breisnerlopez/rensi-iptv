import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

import 'harness.dart';

// Home rails only render the first 18 items. Before, the rest were silently
// unreachable; now a "Ver Todo" action opens the full category grid. Verified
// with a real tap on the button.
void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness(tv: false));
  tearDown(tearDownHarness);

  CategoryViewModel bigCat(int n) {
    AppState.currentPlaylist = Playlist(
      id: 'p1',
      name: 'P',
      type: PlaylistType.xtream,
      url: 'http://x.tv:8080',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2026, 1, 1),
    );
    return CategoryViewModel(
      category: Category(
        categoryId: 'c1',
        categoryName: 'Acción',
        parentId: 0,
        playlistId: 'p1',
        type: CategoryType.vod,
      ),
      contentItems: [
        for (var i = 0; i < n; i++)
          ContentItem('$i', 'Peli $i', '', ContentType.vod,
              containerExtension: 'mp4'),
      ],
    );
  }

  Widget host(CategoryViewModel cat, void Function(CategoryViewModel)? onSeeAll) {
    return MaterialApp(
      locale: const Locale('es'),
      theme: AppThemes.darkTheme, // provides the RensiColors theme extension
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RedesignHome(
        movieCategories: [cat],
        seriesCategories: const [],
        onOpen: (_) {},
        onPlay: (_) {},
        onSeeAll: onSeeAll,
      ),
    );
  }

  testWidgets('Con >18 ítems aparece "Ver Todo" y el tap invoca onSeeAll',
      (tester) async {
    CategoryViewModel? seen;
    await tester.pumpWidget(host(bigCat(25), (c) => seen = c));
    await tester.pump(const Duration(milliseconds: 300));

    final seeAll = find.text('Ver Todo');
    expect(seeAll, findsOneWidget,
        reason: 'una categoría con más de 18 ítems debe ofrecer "Ver Todo"');

    await tester.tap(seeAll, warnIfMissed: false);
    await tester.pump();
    expect(seen, isNotNull,
        reason: 'el tap real en "Ver Todo" debe invocar onSeeAll con la categoría');
    expect(seen!.category.categoryId, 'c1');
  });

  testWidgets('Con ≤18 ítems NO aparece "Ver Todo" (no hay nada oculto)',
      (tester) async {
    await tester.pumpWidget(host(bigCat(12), (_) {}));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ver Todo'), findsNothing,
        reason: 'sin ítems ocultos no debe ofrecerse "Ver Todo"');
  });

  testWidgets('Hero: botón "Comenzar a ver" (localizado) y el tap dispara onPlay',
      (tester) async {
    AppState.currentPlaylist = Playlist(
      id: 'p1',
      name: 'P',
      type: PlaylistType.xtream,
      url: 'http://x.tv:8080',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2026, 1, 1),
    );
    // A movie WITH an image → becomes the hero.
    final cat = CategoryViewModel(
      category: Category(
        categoryId: 'c1',
        categoryName: 'Acción',
        parentId: 0,
        playlistId: 'p1',
        type: CategoryType.vod,
      ),
      contentItems: [
        ContentItem('9', 'Peli Hero', 'http://img.example/x.jpg',
            ContentType.vod,
            containerExtension: 'mp4'),
      ],
    );
    ContentItem? played;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      theme: AppThemes.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RedesignHome(
        movieCategories: [cat],
        seriesCategories: const [],
        onOpen: (_) {},
        onPlay: (it) => played = it,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // Truthful, localized label (was hard-coded "Reproducir").
    expect(find.text('Comenzar a ver'), findsOneWidget,
        reason: 'el hero debe usar la etiqueta localizada start_watching');

    await tester.tap(find.text('Comenzar a ver'), warnIfMissed: false);
    await tester.pump();
    expect(played?.id, '9',
        reason: 'pulsar el botón del hero debe disparar onPlay con ese ítem');
  });
}
