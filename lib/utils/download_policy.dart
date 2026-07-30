// Política de descargas offline: qué se considera "visto" (para borrar al ver)
// y qué purgar para respetar el tope de espacio. Pura y testeable; el
// DownloadService la usa para decidir. Ver DOWNLOAD_ARCHITECTURE.md §2.3.
class DownloadEntry {
  final int id;
  final int bytes;
  final bool watched;
  final int addedAt; // epoch ms; más antiguo = candidato a purga
  const DownloadEntry({
    required this.id,
    required this.bytes,
    required this.watched,
    required this.addedAt,
  });
}

class DownloadPolicy {
  const DownloadPolicy({
    this.capBytes = 10 * 1024 * 1024 * 1024, // 10 GB por defecto
    this.deleteWatched = true, // borrar-al-ver (opt-in; ver §2.3)
    this.watchedThreshold = 0.95,
  });

  final int capBytes;
  final bool deleteWatched;
  final double watchedThreshold;

  /// "Visto" cuando la posición alcanza el umbral del total. Conservador: si no
  /// hay duración fiable, NO se marca visto (no destruir sobre señal dudosa).
  bool isWatched(Duration? position, Duration? total) {
    if (total == null || total.inMilliseconds <= 0 || position == null) {
      return false;
    }
    return position.inMilliseconds >= total.inMilliseconds * watchedThreshold;
  }

  /// Ids a purgar para que el total (+ lo que entra) no supere el tope.
  /// Orden de sacrificio: primero los VISTOS (más antiguos), luego los
  /// no-vistos más antiguos (LRU). Devuelve vacío si ya cabe.
  List<int> idsToPurge(List<DownloadEntry> current, {int incomingBytes = 0}) {
    var total =
        current.fold<int>(0, (s, e) => s + e.bytes) + incomingBytes;
    if (total <= capBytes) return const [];
    final order = [...current]..sort((a, b) {
      if (a.watched != b.watched) return a.watched ? -1 : 1; // vistos primero
      return a.addedAt.compareTo(b.addedAt); // más antiguo primero
    });
    final purge = <int>[];
    for (final e in order) {
      if (total <= capBytes) break;
      purge.add(e.id);
      total -= e.bytes;
    }
    return purge;
  }
}
