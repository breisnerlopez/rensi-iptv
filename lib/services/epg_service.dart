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
  /// Returns null when the request failed, an empty list when the panel has no
  /// listing for the channel. The distinction is the whole point: see
  /// [_failureBackoff].
  final Future<List<EpgEntry>?> Function(String streamId) _fetch;
  final Duration _ttl;

  /// How long to wait before asking again after a FAILED request.
  ///
  /// Short, because a failure is usually transient, but not zero: without it a
  /// panel that is refusing requests gets hammered by every row that scrolls
  /// past. Success — including a legitimately empty schedule — uses the full
  /// [_ttl] instead. Treating "no guide" as "ask again" is what produced 245
  /// requests for one pass over a 300-channel playlist, and Xtream panels ban
  /// for that.
  static const Duration _failureBackoff = Duration(minutes: 2);

  /// Bounded, and ordered by insertion so the oldest entry is the first key.
  /// A 5000-channel playlist scrolled end to end would otherwise leave 5000
  /// entries — each with up to four base64-decoded descriptions — resident for
  /// the life of the process.
  static const int _maxEntries = 300;

  final Map<String, List<EpgEntry>> _cache = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, DateTime> _failedAt = {};
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
    final now = DateTime.now();
    final cached = _cache[streamId];
    final at = _fetchedAt[streamId];
    if (cached != null && at != null && now.difference(at) < _ttl) {
      return Future.value(cached);
    }

    final failed = _failedAt[streamId];
    if (failed != null && now.difference(failed) < _failureBackoff) {
      return Future.value(const []);
    }

    // Share the request rather than issuing one per caller: a rail and a grid
    // showing the same channel would otherwise both hit the panel.
    final existing = _inFlight[streamId];
    if (existing != null) return existing;

    final future = _fetch(streamId).then((entries) {
      if (entries == null) {
        // Failure: back off briefly rather than remembering a wrong answer.
        _failedAt[streamId] = DateTime.now();
        return const <EpgEntry>[];
      }
      // A real answer, empty or not. Remembering the empty one is what stops a
      // channel with no guide from re-asking on every rebuild.
      _failedAt.remove(streamId);
      _remember(streamId, entries);
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


  /// Drops everything, including requests already in flight — otherwise a
  /// response that was on its way would repopulate a cache we just cleared.
  void invalidate() {
    _cache.clear();
    _fetchedAt.clear();
    _failedAt.clear();
    _inFlight.clear();
  }
}
