import 'package:rensi_iptv/models/playlist_content_model.dart';

/// A channel-list row: the item to display plus its index in the REAL playback
/// queue (so a tap jumps to the right channel even when the list is reordered).
class OrderedChannel {
  final ContentItem item;
  final int queueIndex;
  final bool isFavorite;
  const OrderedChannel(this.item, this.queueIndex, this.isFavorite);
}

/// The channel ID to keep as "last channel" recall after switching from channel
/// [oldId] to [newId]. Tracked by IDENTITY (not a raw queue index) so it stays
/// correct across queue changes (e.g. switching category rebuilds the queue) —
/// the recall row resolves the ID against the current queue at render time and
/// simply hides if that channel is no longer present. Switching to a genuinely
/// different channel makes the one we're leaving the recall target; re-selecting
/// the same channel keeps the existing recall. Pure + unit-testable.
String? recallIdAfterSwitch(String? currentRecallId, String oldId, String newId) {
  return newId != oldId ? oldId : currentRecallId;
}

/// Orders the player's channel list favourites-first while preserving each
/// item's original (queue) order within its group — a stable partition. The
/// returned rows carry the ORIGINAL queue index so selection still maps back to
/// the correct playlist entry. Pure + deterministic so it can be unit-tested
/// without the player engine.
List<OrderedChannel> orderFavoritesFirst(
  List<ContentItem> queue,
  Set<String> favoriteIds,
) {
  final favorites = <OrderedChannel>[];
  final rest = <OrderedChannel>[];
  for (var i = 0; i < queue.length; i++) {
    final item = queue[i];
    final fav = favoriteIds.contains(item.id.toString());
    (fav ? favorites : rest).add(OrderedChannel(item, i, fav));
  }
  return [...favorites, ...rest];
}
