import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/redesign/live_redesign.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';

import 'harness.dart';

// Real-device (German + Arabic) review caught it: Browse's type chips ('Todo',
// 'Películas', 'Series') and both Browse's and Live's "all" chip ('Todos') were
// hard-coded Spanish, so every non-Spanish user saw Spanish filter labels while
// the rest of the screen was in their language. The titles already localized
// (context.loc), which is why it slipped — only the chips were literals.
void main() {
  setUp(() => setUpHarness(tv: false));
  tearDown(tearDownHarness);

  testWidgets('Browse type + genre chips localize (de)', (tester) async {
    await pumpScreen(
      tester,
      BrowseRedesign(
        movieCategories: const [],
        seriesCategories: const [],
        onOpen: (_) async {},
      ),
      size: const Size(960, 540),
      locale: const Locale('de'),
    );
    await settle(tester);

    expect(find.text('Entdecken'), findsWidgets, reason: 'title in German');
    expect(find.text('Filme'), findsWidgets, reason: 'movies type chip in German');
    expect(find.text('Serien'), findsWidgets, reason: 'series type chip in German');
    // No leftover hard-coded Spanish.
    expect(find.text('Películas'), findsNothing);
    expect(find.text('Series'), findsNothing);
    expect(find.text('Todo'), findsNothing);
    expect(find.text('Todos'), findsNothing);
  });

  testWidgets('Live category chips localize the "all" chip (de)',
      (tester) async {
    await pumpScreen(
      tester,
      LiveRedesign(
        liveCategories: [
          CategoryViewModel(
            category: Category(
              categoryId: 'c1',
              categoryName: 'Sport',
              parentId: 0,
              playlistId: 'p1',
              type: CategoryType.live,
            ),
            contentItems: const [],
          ),
        ],
        onPlay: (_) {},
      ),
      size: const Size(960, 540),
      locale: const Locale('de'),
    );
    await settle(tester);

    // The "all" chip is localized; a real category name (data) stays as-is.
    expect(find.text('Alle'), findsWidgets, reason: '"all" chip in German');
    expect(find.text('Todos'), findsNothing, reason: 'no hard-coded Spanish "all"');
    expect(find.text('Sport'), findsWidgets, reason: 'real category name kept');
  });
}
