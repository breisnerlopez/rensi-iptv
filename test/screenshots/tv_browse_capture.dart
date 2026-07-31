import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/services/app_state.dart';

import '../integration/harness.dart';

// Renders the Explorar (browse) grid on a TV viewport to verify 10-foot scale +
// the unified white focus (was: tiny cramped tiles + amber glow).
void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness()); // tv = true
  tearDown(tearDownHarness);

  CategoryViewModel cat(String id, String name, int n) => CategoryViewModel(
        category: Category(
            categoryId: id,
            categoryName: name,
            parentId: 0,
            playlistId: 'p1',
            type: CategoryType.vod),
        contentItems: [
          for (var i = 0; i < n; i++)
            ContentItem('$id-$i', '$name $i', '', ContentType.vod,
                containerExtension: 'mp4'),
        ],
      );

  testWidgets('TV: Explorar — escala 10-foot + foco blanco', (tester) async {
    AppState.currentPlaylist = Playlist(
        id: 'p1',
        name: 'P',
        type: PlaylistType.xtream,
        url: 'http://x.tv:8080',
        username: 'u',
        password: 'p',
        createdAt: DateTime(2026, 1, 1));
    final cats = [
      cat('c1', 'Acción', 24),
      cat('c2', 'Drama', 24),
      cat('c3', 'Comedia', 24),
    ];
    await pumpScreen(
      tester,
      BrowseRedesign(
        movieCategories: cats,
        seriesCategories: const [],
        onOpen: (_) async {},
      ),
    );
    await settle(tester);
    // Move focus onto the first grid poster so the white ring shows.
    await down(tester);
    await down(tester);
    await settle(tester);
    await shot(tester, 'tv_browse_1.png');
    expect(find.byType(BrowseRedesign), findsOneWidget);
  });
}
