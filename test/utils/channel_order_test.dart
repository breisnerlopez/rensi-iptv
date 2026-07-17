import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/utils/channel_order.dart';

ContentItem chan(String id) => ContentItem(
      id,
      'Canal $id',
      '',
      ContentType.liveStream,
      liveStream: LiveStream(
        streamId: id,
        name: 'Canal $id',
        streamIcon: '',
        categoryId: 'c',
        epgChannelId: 'e',
        playlistId: 'p',
      ),
    );

void main() {
  // Set before building any ContentItem: its constructor calls buildMediaUrl,
  // which reads AppState.currentPlaylist!.
  AppState.currentPlaylist = Playlist(
    id: 'p',
    name: 'P',
    type: PlaylistType.xtream,
    url: 'http://x.tv:8080',
    username: 'u',
    password: 'w',
    createdAt: DateTime(2026, 1, 1),
  );

  final queue = [chan('10'), chan('11'), chan('12'), chan('13'), chan('14')];

  test('sin favoritos: orden intacto y queueIndex = posición', () {
    final r = orderFavoritesFirst(queue, {});
    expect(r.map((e) => e.item.id), ['10', '11', '12', '13', '14']);
    expect(r.map((e) => e.queueIndex), [0, 1, 2, 3, 4]);
    expect(r.every((e) => !e.isFavorite), isTrue);
  });

  test('favoritos primero, estable, con queueIndex REAL preservado', () {
    // Favoritos: 12 (idx2) y 14 (idx4).
    final r = orderFavoritesFirst(queue, {'12', '14'});
    // Favoritos primero en su orden original, luego el resto en su orden.
    expect(r.map((e) => e.item.id), ['12', '14', '10', '11', '13']);
    // El queueIndex debe seguir apuntando a la posición REAL en la cola, para
    // que un tap salte al canal correcto tras el reordenamiento.
    expect(r.map((e) => e.queueIndex), [2, 4, 0, 1, 3]);
    expect(r.where((e) => e.isFavorite).map((e) => e.item.id), ['12', '14']);
  });

  test('contrato del tap: el queueIndex de la fila tapeada apunta al canal correcto', () {
    final r = orderFavoritesFirst(queue, {'12', '14'});
    // El usuario ve los favoritos arriba y tapea la PRIMERA fila (display pos 0).
    // El onTap emite row.queueIndex; ese índice debe resolver al canal mostrado.
    final tappedRow = r[0]; // display: '12'
    expect(tappedRow.item.id, '12');
    expect(queue[tappedRow.queueIndex].id, tappedRow.item.id,
        reason: 'queue[queueIndex] debe ser exactamente el canal de la fila tapeada');
    // Segunda fila favorita.
    final tapped2 = r[1]; // '14'
    expect(queue[tapped2.queueIndex].id, '14');
    // Una fila no-favorita reordenada (display pos 2 = canal 10, queueIndex 0).
    final tapped3 = r[2];
    expect(queue[tapped3.queueIndex].id, tapped3.item.id);
  });

  test('recall de último canal: rastrea POR ID el canal que se deja, toggle', () {
    String? recall;
    // Viendo 'a'. Cambia a 'd': recall = 'a'.
    recall = recallIdAfterSwitch(recall, 'a', 'd');
    expect(recall, 'a');
    // 'd' → 'b': recall = 'd'.
    recall = recallIdAfterSwitch(recall, 'd', 'b');
    expect(recall, 'd');
    // Re-selecciona el mismo ('b' → 'b'): recall no cambia.
    recall = recallIdAfterSwitch(recall, 'b', 'b');
    expect(recall, 'd');
    // Tap en "último canal" ('b' → 'd'): recall = 'b' → toggle entre los dos.
    recall = recallIdAfterSwitch(recall, 'b', 'd');
    expect(recall, 'b');
  });

  test('recall por ID sobrevive un cambio de cola (categoría): resuelve por identidad', () {
    // El id se rastrea sin importar posiciones; el render lo resuelve contra la
    // cola vigente por identidad, así que un cambio de cola no puede apuntar al
    // canal equivocado (a diferencia de un índice crudo).
    String? recall = recallIdAfterSwitch(null, 'canal-A', 'canal-Z');
    expect(recall, 'canal-A');
    // colaB no contiene 'canal-A' → indexWhere devolvería -1 → la fila se oculta.
    final colaB = [chan('canal-X'), chan('canal-Y'), chan('canal-Z')];
    expect(colaB.indexWhere((c) => c.id == recall), -1);
    // colaB SÍ contiene 'canal-A' → resuelve a su posición real (no una cruzada).
    final colaC = [chan('canal-Q'), chan('canal-A')];
    expect(colaC.indexWhere((c) => c.id == recall), 1);
  });

  test('todos favoritos → orden intacto; ninguno → orden intacto', () {
    expect(
        orderFavoritesFirst(queue, {'10', '11', '12', '13', '14'})
            .map((e) => e.queueIndex),
        [0, 1, 2, 3, 4]);
    expect(orderFavoritesFirst(queue, {'999'}).map((e) => e.queueIndex),
        [0, 1, 2, 3, 4]);
  });
}
