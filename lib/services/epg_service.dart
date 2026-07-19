import 'package:rensi_iptv/models/epg_entry.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';

/// Fetches and caches "what is on now" per channel.
///
/// `get_short_epg` is a per-stream call, so the shape of this service is
/// dictated by cost: a 5000-channel playlist would be 5000 requests if the UI
/// asked naively. Rows therefore ask only for the channel they are about to
/// paint, results are cached, and in-flight requests are shared so a list that
/// scrolls back and forth does not re-ask for the same channel.
class EpgService {
  EpgService(this._repository, {Duration? ttl})
      : _ttl = ttl ?? const Duration(minutes: 30);

  final IptvRepository _repository;
  final Duration _ttl;

  final Map<String, List<EpgEntry>> _cache = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, Future<List<EpgEntry>>> _inFlight = {};

  /// Entries for [streamId], from cache when fresh.
  Future<List<EpgEntry>> entriesFor(String streamId) {
    final cached = _cache[streamId];
    final at = _fetchedAt[streamId];
    if (cached != null && at != null && DateTime.now().difference(at) < _ttl) {
      return Future.value(cached);
    }

    // Share the request rather than issuing one per caller: a rail and a grid
    // showing the same channel would otherwise both hit the panel.
    final existing = _inFlight[streamId];
    if (existing != null) return existing;

    final future = _repository.getShortEpg(streamId).then((entries) {
      _cache[streamId] = entries;
      _fetchedAt[streamId] = DateTime.now();
      return entries;
    }).whenComplete(() => _inFlight.remove(streamId));

    _inFlight[streamId] = future;
    return future;
  }

  /// The programme airing at [now], or null when the panel returned nothing
  /// usable. Returning null rather than the first entry matters: showing a
  /// finished programme as "now" is worse than showing no programme at all.
  Future<EpgEntry?> nowPlaying(String streamId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final entries = await entriesFor(streamId);
    for (final e in entries) {
      if (e.isLiveAt(at)) return e;
    }
    return null;
  }

  /// What follows the programme airing at [now].
  Future<EpgEntry?> upNext(String streamId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final entries = await entriesFor(streamId);
    for (final e in entries) {
      if (e.start.isAfter(at)) return e;
    }
    return null;
  }

  void invalidate() {
    _cache.clear();
    _fetchedAt.clear();
  }
}
