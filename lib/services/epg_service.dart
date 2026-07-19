import 'package:rensi_iptv/models/epg_entry.dart';

/// Fetches and caches "what is on now" per channel.
///
/// `get_short_epg` is a per-stream call, so the shape of this service is
/// dictated by cost: a 5000-channel playlist would be 5000 requests if the UI
/// asked naively. Rows therefore ask only for the channel they are about to
/// paint, results are cached, and in-flight requests are shared so a list that
/// scrolls back and forth does not re-ask for the same channel.
class EpgService {
  EpgService(this._fetch, {Duration? ttl})
      : _ttl = ttl ?? const Duration(minutes: 30);

  /// Just the lookup, not the whole repository. Depending on IptvRepository
  /// dragged a database and platform plugins into every test of this service —
  /// which is the coupling telling you the dependency was too wide.
  final Future<List<EpgEntry>> Function(String streamId) _fetch;
  final Duration _ttl;

  /// Bounded, and ordered by insertion so the oldest entry is the first key.
  /// A 5000-channel playlist scrolled end to end would otherwise leave 5000
  /// entries — each with up to four base64-decoded descriptions — resident for
  /// the life of the process.
  static const int _maxEntries = 300;

  final Map<String, List<EpgEntry>> _cache = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, Future<List<EpgEntry>>> _inFlight = {};

  void _remember(String streamId, List<EpgEntry> entries) {
    _cache.remove(streamId);
    _cache[streamId] = entries;
    _fetchedAt[streamId] = DateTime.now();
    while (_cache.length > _maxEntries) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _fetchedAt.remove(oldest);
    }
  }

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

    final future = _fetch(streamId).then((entries) {
      // Only remember a real answer. Caching an empty list would make a
      // two-second network blip hide the schedule for the next 30 minutes,
      // because "no data" and "the request failed" look identical here.
      if (entries.isNotEmpty) _remember(streamId, entries);
      return entries;
      // Braces, not an arrow: `Map.remove` returns the value it removed — here
      // the very future being built — and `whenComplete` awaits a returned
      // Future. The arrow form made the future wait for itself, and every call
      // hung forever.
    }).whenComplete(() {
      _inFlight.remove(streamId);
    });

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

  /// Drops everything, including requests already in flight — otherwise a
  /// response that was on its way would repopulate a cache we just cleared.
  void invalidate() {
    _cache.clear();
    _fetchedAt.clear();
    _inFlight.clear();
  }
}
