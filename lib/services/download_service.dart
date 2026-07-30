// Motor de descargas offline (VOD/series). Envuelve `background_downloader`
// (descargas en background con pausa/reanudar) y usa la tabla Drift
// `Downloads` como única fuente de verdad para la UI: `DownloadsScreen` y
// `DownloadButton` observan `watchAll()`/`watchOne()` en vez de hablar con el
// plugin directamente. Solo VOD/series — el llamador (pantallas de detalle)
// es responsable de no invocar `enqueue` para directo.
import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart';
import '../utils/download_policy.dart';

/// Subcarpeta (bajo `getApplicationSupportDirectory`) donde viven todos los
/// archivos descargados. Relativa a un `BaseDirectory.applicationSupport` de
/// background_downloader, para que el propio plugin resuelva la ruta igual
/// en cada plataforma.
const String _downloadsSubdir = 'downloads';

/// Grupo de tareas de background_downloader reservado para descargas offline,
/// para no interferir con otros usos futuros del plugin en la app.
const String _taskGroup = 'rensi_offline_downloads';

class DownloadService {
  DownloadService._internal();

  static final DownloadService instance = DownloadService._internal();

  /// Política de espacio/"visto" (tope de espacio + purga LRU). Expuesta para
  /// que la UI pueda mostrar el tope configurado.
  final DownloadPolicy policy = const DownloadPolicy();

  StreamSubscription<TaskUpdate>? _sub;
  bool _listening = false;

  /// Se suscribe a los updates de `background_downloader` (una sola vez). Es
  /// LAZY a propósito: renderizar `DownloadButton`/`DownloadsScreen` solo
  /// observa la tabla Drift (`watch*`) y NO debe tocar el plugin — hacerlo en
  /// el constructor colgaba `pumpAndSettle` en los widget tests. El listener
  /// arranca en la primera operación real (encolar/pausar/…) y la app lo
  /// activa al inicio (main.dart) para captar descargas de background.
  void ensureListening() {
    if (_listening) return;
    _listening = true;
    _sub = FileDownloader().updates.listen(_onUpdate, onError: (_) {});
  }

  AppDatabase get _db => GetIt.instance<AppDatabase>();

  // ---------------------------------------------------------------------
  // Lectura / observación
  // ---------------------------------------------------------------------

  /// Todas las descargas (cualquier estado), para `DownloadsScreen`.
  Stream<List<Download>> watchAll() => _db.select(_db.downloads).watch();

  /// La descarga de un contenido concreto, o `null` si nunca se encoló.
  /// Usado por `DownloadButton` para pintar su estado.
  Stream<Download?> watchOne(String contentId) {
    final q = _db.select(_db.downloads)
      ..where((d) => d.contentId.equals(contentId));
    return q.watchSingleOrNull();
  }

  Future<Download?> findByContentId(String contentId) {
    return (_db.select(_db.downloads)
          ..where((d) => d.contentId.equals(contentId)))
        .getSingleOrNull();
  }

  Future<Download?> _rowById(int id) =>
      (_db.select(_db.downloads)..where((d) => d.id.equals(id)))
          .getSingleOrNull();

  // ---------------------------------------------------------------------
  // Encolar
  // ---------------------------------------------------------------------

  /// Encola una nueva descarga offline. Aplica primero la purga por tope de
  /// espacio (`DownloadPolicy.idsToPurge`) sobre lo ya descargado, borrando
  /// archivo+fila de los sacrificados.
  Future<void> enqueue({
    required String contentId,
    required String contentType, // 'vod' | 'series'
    required String title,
    String imagePath = '',
    String? ext,
    required String url,
    required String playlistId,
  }) async {
    assert(contentType == 'vod' || contentType == 'series',
        'DownloadService.enqueue: solo vod|series, se recibió "$contentType"');
    ensureListening();

    // Best-effort: si ya hay una fila para este contenido en curso o
    // completa, no duplicar. Una fila 'failed' previa, en cambio, se limpia
    // aquí mismo para que reintentar (llamar enqueue otra vez) nunca deje
    // filas huérfanas repetidas en la pantalla de descargas.
    final existing = await findByContentId(contentId);
    if (existing != null) {
      if (existing.status == 'failed') {
        await _deleteRow(existing.id);
      } else {
        return;
      }
    }

    final incomingBytes = await _probeContentLength(url) ?? 0;
    await _purgeForIncoming(incomingBytes);

    final now = DateTime.now().millisecondsSinceEpoch;
    final rowId = await _db.into(_db.downloads).insert(
          DownloadsCompanion.insert(
            contentId: contentId,
            contentType: contentType,
            title: title,
            imagePath: Value(imagePath),
            ext: Value(ext),
            totalBytes: incomingBytes > 0
                ? Value(incomingBytes)
                : const Value.absent(),
            status: const Value('queued'),
            addedAt: now,
            playlistId: playlistId,
          ),
        );

    final supportDir = await getApplicationSupportDirectory();
    final downloadsDir = Directory(p.join(supportDir.path, _downloadsSubdir));
    try {
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
    } catch (_) {
      // El propio plugin también intenta crear el directorio destino; si esto
      // falla igualmente el enqueue de abajo fallará de forma visible.
    }

    final safeId = contentId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final filename =
        (ext != null && ext.isNotEmpty) ? '$safeId.$ext' : safeId;
    final taskId = 'dl_$rowId';

    final task = DownloadTask(
      taskId: taskId,
      url: url,
      filename: filename,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: _downloadsSubdir,
      group: _taskGroup,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
      metaData: rowId.toString(),
    );

    await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId))).write(
      DownloadsCompanion(taskId: Value(taskId)),
    );

    final ok = await FileDownloader().enqueue(task);
    if (!ok) {
      await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId)))
          .write(const DownloadsCompanion(status: Value('failed')));
    }
  }

  /// HEAD best-effort para conocer el tamaño antes de encolar (para la purga
  /// por tope de espacio). Si falla o no hay content-length, devuelve null —
  /// nunca bloquea el encolado por esto.
  Future<int?> _probeContentLength(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .headUrl(uri)
          .timeout(const Duration(seconds: 5));
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final len = response.contentLength;
      return len > 0 ? len : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _purgeForIncoming(int incomingBytes) async {
    final rows = await _db.select(_db.downloads).get();
    final entries = rows
        .where((d) => d.status == 'complete')
        .map((d) => DownloadEntry(
              id: d.id,
              bytes: d.totalBytes ?? d.bytesDownloaded,
              watched: d.watched,
              addedAt: d.addedAt,
            ))
        .toList();
    final purgeIds =
        policy.idsToPurge(entries, incomingBytes: incomingBytes);
    for (final id in purgeIds) {
      await _deleteRow(id);
    }
  }

  // ---------------------------------------------------------------------
  // Control: pausar / reanudar / cancelar / borrar
  // ---------------------------------------------------------------------

  Future<void> pause(int id) async {
    ensureListening();
    final row = await _rowById(id);
    final taskId = row?.taskId;
    if (taskId == null) return;
    final task = await _liveTask(taskId);
    if (task == null) return;
    await FileDownloader().pause(task);
  }

  Future<void> resume(int id) async {
    ensureListening();
    final row = await _rowById(id);
    final taskId = row?.taskId;
    if (taskId == null) return;
    final task = await _liveTask(taskId);
    if (task == null) return;

    // Si el propio plugin determina que este task ya no puede reanudarse
    // (p. ej. el servidor ignora Range y respondería 200 en vez de 206),
    // reiniciamos en limpio nosotros: borrar cualquier byte parcial y volver
    // a encolar el mismo task desde cero, en vez de arriesgar una
    // concatenación corrupta.
    final canResume = await FileDownloader().taskCanResume(task);
    if (!canResume) {
      await _restartClean(id, task);
      return;
    }
    await FileDownloader().resume(task);
  }

  Future<void> cancel(int id) async {
    ensureListening();
    final row = await _rowById(id);
    if (row == null) return;
    if (row.taskId != null) {
      await FileDownloader().cancelTaskWithId(row.taskId!);
    }
    await _deleteRow(id);
  }

  Future<void> delete(int id) async {
    ensureListening();
    final row = await _rowById(id);
    if (row == null) return;
    if (row.taskId != null && !_isFinalStatus(row.status)) {
      await FileDownloader().cancelTaskWithId(row.taskId!);
    }
    await _deleteRow(id);
  }

  bool _isFinalStatus(String status) =>
      status == 'complete' || status == 'failed';

  Future<DownloadTask?> _liveTask(String taskId) async {
    final t = await FileDownloader().taskForId(taskId);
    return t is DownloadTask ? t : null;
  }

  Future<void> _deleteRow(int id) async {
    final row = await _rowById(id);
    final path = row?.filePath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Best-effort: una fila huérfana sin archivo no es peor que lo que
        // había antes de intentar borrar.
      }
    }
    await (_db.delete(_db.downloads)..where((d) => d.id.equals(id))).go();
  }

  Future<void> _restartClean(int rowId, DownloadTask task) async {
    try {
      final path = await task.filePath();
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId))).write(
      const DownloadsCompanion(
        status: Value('queued'),
        bytesDownloaded: Value(0),
      ),
    );
    await FileDownloader().enqueue(task);
  }

  // ---------------------------------------------------------------------
  // Watched → borrado automático
  // ---------------------------------------------------------------------

  /// Marca como visto (y borra si la política lo indica) el contenido
  /// descargado cuya posición de reproducción alcanzó el umbral de
  /// `DownloadPolicy.isWatched`. No-op si no hay descarga completa para ese
  /// contentId.
  Future<void> markWatchedAndMaybeDelete(
    String contentId,
    Duration position,
    Duration total,
  ) async {
    final row = await findByContentId(contentId);
    if (row == null || row.status != 'complete') return;
    if (!policy.isWatched(position, total)) return;

    await (_db.update(_db.downloads)..where((d) => d.id.equals(row.id)))
        .write(const DownloadsCompanion(watched: Value(true)));

    if (policy.deleteWatched) {
      await _deleteRow(row.id);
    }
  }

  // ---------------------------------------------------------------------
  // Actualizaciones de background_downloader → fila Drift
  // ---------------------------------------------------------------------

  Future<void> _onUpdate(TaskUpdate update) async {
    final rowId = int.tryParse(update.task.metaData);
    if (rowId == null) return;

    if (update is TaskProgressUpdate) {
      if (update.progress < 0) return; // -1/-2/-3/-4/-5: lo maneja el status
      final expected =
          update.hasExpectedFileSize ? update.expectedFileSize : null;
      final bytes = expected != null
          ? (update.progress * expected).round()
          : null;
      await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId)))
          .write(
        DownloadsCompanion(
          status: const Value('downloading'),
          bytesDownloaded:
              bytes != null ? Value(bytes) : const Value.absent(),
          totalBytes:
              expected != null ? Value(expected) : const Value.absent(),
        ),
      );
      return;
    }

    if (update is TaskStatusUpdate) {
      switch (update.status) {
        case TaskStatus.enqueued:
        case TaskStatus.running:
          await _setStatus(rowId, 'downloading');
          break;
        case TaskStatus.paused:
          await _setStatus(rowId, 'paused');
          break;
        case TaskStatus.complete:
          await _finalizeComplete(rowId, update);
          break;
        case TaskStatus.failed:
          await _handleFailed(rowId, update);
          break;
        case TaskStatus.notFound:
        case TaskStatus.canceled:
          await _setStatus(rowId, 'failed');
          break;
        case TaskStatus.waitingToRetry:
          break;
      }
    }
  }

  Future<void> _setStatus(int rowId, String status) async {
    await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId)))
        .write(DownloadsCompanion(status: Value(status)));
  }

  Future<void> _handleFailed(int rowId, TaskStatusUpdate update) async {
    // El servidor ignoró la cabecera Range en un intento de reanudar (nos
    // devolvió 200 en vez de 206): cualquier byte parcial en disco es un
    // prefijo que corrompería la reproducción si lo dejamos. El propio
    // plugin ya intenta reiniciar solo en este caso; esto es una red de
    // seguridad para cuando ese intento nativo termina en 'failed' igual.
    if (update.responseStatusCode == 200) {
      final task = update.task;
      if (task is DownloadTask) {
        await _restartClean(rowId, task);
        return;
      }
    }
    await _setStatus(rowId, 'failed');
  }

  Future<void> _finalizeComplete(int rowId, TaskStatusUpdate update) async {
    final task = update.task;
    if (task is! DownloadTask) {
      await _setStatus(rowId, 'failed');
      return;
    }
    String path;
    try {
      path = await task.filePath();
    } catch (_) {
      await _setStatus(rowId, 'failed');
      return;
    }

    if (await _looksLikeHtmlError(path, update)) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId)))
          .write(const DownloadsCompanion(
        status: Value('failed'),
        filePath: Value(null),
      ));
      return;
    }

    int? size;
    try {
      final f = File(path);
      if (await f.exists()) size = await f.length();
    } catch (_) {}

    await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId))).write(
      DownloadsCompanion(
        status: const Value('complete'),
        filePath: Value(path),
        bytesDownloaded: Value(size ?? 0),
        totalBytes: size != null ? Value(size) : const Value.absent(),
      ),
    );
  }

  /// Heurística anti-página-de-error: si el `Content-Type` final es
  /// text/html, o si los primeros bytes del archivo son literalmente
  /// markup ('<...'), esto no es el vídeo/archivo esperado sino una página
  /// de error del panel (sesión caducada, id inválido, etc).
  Future<bool> _looksLikeHtmlError(
    String path,
    TaskStatusUpdate update,
  ) async {
    final mime = update.mimeType?.toLowerCase();
    if (mime != null && mime.contains('text/html')) return true;
    try {
      final f = File(path);
      if (!await f.exists()) return true;
      final raf = await f.open();
      List<int> head;
      try {
        head = await raf.read(32);
      } finally {
        await raf.close();
      }
      if (head.isEmpty) return true;
      final text = String.fromCharCodes(head).trimLeft().toLowerCase();
      return text.startsWith('<');
    } catch (_) {
      return false; // no penalizar una descarga buena por un fallo de IO
    }
  }

  /// Solo para tests / diagnósticos: libera el listener de updates.
  @visibleForTesting
  Future<void> disposeForTesting() async {
    await _sub?.cancel();
    _sub = null;
    _listening = false;
  }
}
