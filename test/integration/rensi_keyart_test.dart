import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';

import 'harness.dart';

// Covers the CachedNetworkImage/memCacheWidth branch of RensiKeyArt (the poster
// decode-size cap). The other poster tests use imagePath:'' and only hit the
// gradient fallback, so this branch had zero coverage. Asserts it mounts without
// throwing at a normal slot size AND at a degenerate 0x0 layout (the memCacheWidth
// guard must not produce an invalid decode size).
void main() {
  setUpAll(loadFonts);
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  ContentItem withImage() {
    AppState.currentPlaylist = Playlist(
      id: 'pl',
      name: 'PL',
      type: PlaylistType.xtream,
      createdAt: DateTime(2026, 1, 1),
    );
    return ContentItem(
      'id1',
      'Peli',
      'https://example.test/poster.jpg', // non-empty → CachedNetworkImage branch
      ContentType.vod,
    );
  }

  Widget host(double w, double h, Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: w, height: h, child: child),
          ),
        ),
      );

  testWidgets('RensiKeyArt con imagen: monta CachedNetworkImage sin excepción',
      (tester) async {
    await tester.pumpWidget(host(190, 281, RensiKeyArt(item: withImage())));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'la rama de imagen (memCacheWidth) no debe lanzar');
    expect(find.byType(CachedNetworkImage), findsOneWidget,
        reason: 'con imagePath no vacío debe usar CachedNetworkImage, no el fallback');
  });

  testWidgets('RensiKeyArt en layout 0x0 degenerado no lanza (guard memCacheWidth)',
      (tester) async {
    await tester.pumpWidget(host(0, 0, RensiKeyArt(item: withImage())));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'ancho 0 debe caer en memCacheWidth:null, no en un tamaño inválido');
  });
}
