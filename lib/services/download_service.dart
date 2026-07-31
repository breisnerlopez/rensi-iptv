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
import '../utils/build_media_url.dart' show kVodExtensionCandidates, swapUrlExtension;
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
  // Future COMPARTIDO de la config nativa (una sola ejecución). Se guarda el
  // future — no un bool — para que el primer enqueue pueda ESPERAR a que
  // trackTasks/resumeFromBackground terminen antes de encolar (si no, la
  // persistencia podría no aplicarse a la primera descarga).
  Future<void>? _configureFuture;

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
    // Fire-and-forget en el arranque: no debe bloquear a main.dart. El primer
    // enqueue SÍ espera este mismo future (ver enqueue) para no encolar antes
    // de que la persistencia esté activa.
    unawaited(_ensureConfigured());
  }

  /// Devuelve (y lanza una sola vez) el future de la config nativa.
  Future<void> _ensureConfigured() => _configureFuture ??= _configureOnce();

  /// Configura notificaciones (una sola vez) y activa la persistencia de
  /// `background_downloader` para que las descargas sobrevivan tanto a que
  /// la app pase a segundo plano como a que el proceso muera y la OS lo
  /// mate: la notificación 'running' con progressBar promueve la descarga a
  /// foreground service de Android; `trackTasks`+`resumeFromBackground`
  /// persisten el estado y lo recuperan al reabrir. Envuelto en try/catch:
  /// en tests (sin platform channel real) o en plataformas sin soporte esto
  /// no debe tumbar la app.
  Future<void> _configureOnce() async {
    try {
      FileDownloader().configureNotification(
        running:
            const TaskNotification('Descargando', '{filename}'),
        complete:
            const TaskNotification('Descarga completa', '{filename}'),
        error: const TaskNotification('Descarga fallida', '{filename}'),
        paused: const TaskNotification('Descarga en pausa', '{filename}'),
        progressBar: true,
      );
      await FileDownloader().trackTasks();
      await FileDownloader().resumeFromBackground();
    } catch (_) {
      // Best-effort: no hay red de seguridad mejor posible aquí — si esto
      // falla, las descargas siguen funcionando en primer plano (solo se
      // pierde la persistencia/foreground service).
    }
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
    // Esperar a que la config nativa (trackTasks/resumeFromBackground) termine
    // antes de encolar la PRIMERA descarga, para que la persistencia/foreground
    // service apliquen desde la primera tarea. Idempotente y ~instantáneo tras
    // la primera vez.
    await _ensureConfigured();

    // Best-effort: sin este permiso (Android 13+) la notificación 'running'
    // no se muestra y por tanto no hay foreground service — la descarga
    // igual se encola, solo con más riesgo de que la OS la mate en segundo
    // plano. Nunca debe impedir encolar.
    try {
      await FileDownloader().permissions.request(PermissionType.notifications);
    } catch (_) {}

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
            url: Value(url),
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

    await _startTaskForRow(rowId, contentId: contentId, url: url, ext: ext);
  }

  /// Construye y encola la DownloadTask de una fila (reusado por [enqueue] y por
  /// la auto-corrección de extensión). Marca la fila 'failed' si el plugin no
  /// acepta el encolado.
  Future<bool> _startTaskForRow(
    int rowId, {
    required String contentId,
    required String url,
    String? ext,
  }) async {
    // Nombre de archivo LEGIBLE a partir del título del contenido (p. ej.
    // "Rick and Morty S01E01.mkv") en vez del id de stream. La reproducción
    // resuelve por la columna `filePath`, no por el filename, así que esto es
    // puramente cosmético en disco. Si el título no está disponible, se cae al
    // comportamiento anterior (id saneado) para no producir nunca un nombre
    // vacío.
    final safeId = contentId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final row = await _rowById(rowId);
    final safeTitle = (row?.title ?? '')
        .replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Cap ~80 chars (recortando y re-trim por si el corte deja un espacio).
    final cappedTitle =
        safeTitle.length > 80 ? safeTitle.substring(0, 80).trim() : safeTitle;
    final baseName = cappedTitle.isEmpty ? safeId : cappedTitle;
    // Sufijo con el rowId SIEMPRE presente: dos contenidos distintos pueden
    // compartir título, y el filePath en disco debe ser único.
    final uniqueName = '$baseName ($rowId)';
    final filename =
        (ext != null && ext.isNotEmpty) ? '$uniqueName.$ext' : uniqueName;
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
      await _setStatus(rowId, 'failed', error: const Value('start_failed'));
    }
    return ok;
  }

  /// Auto-corrección de extensión: el panel Xtream puede servir una
  /// `container_extension` obsoleta — el contenido REPRODUCE (el player ya la
  /// auto-corrige) pero la descarga baja una página HTML de error. Al detectarla,
  /// reintenta la descarga con la SIGUIENTE extensión candidata
  /// ([kVodExtensionCandidates]) antes de rendirse. Acotado: avanza por la lista
  /// (mp4→mkv→avi) y devuelve false cuando se agota. Devuelve true si relanzó.
  Future<bool> _retryWithNextExtension(int rowId) async {
    final row = await _rowById(rowId);
    final baseUrl = row?.url;
    if (row == null || baseUrl == null || baseUrl.isEmpty) return false;
    final current = (row.ext ?? '').toLowerCase();
    final nextIdx = kVodExtensionCandidates.indexOf(current) + 1;
    if (nextIdx >= kVodExtensionCandidates.length) return false; // agotado
    final nextExt = kVodExtensionCandidates[nextIdx];
    final newUrl = swapUrlExtension(baseUrl, nextExt);
    await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId))).write(
      DownloadsCompanion(
        ext: Value(nextExt),
        url: Value(newUrl),
        status: const Value('queued'),
        filePath: const Value(null),
        bytesDownloaded: const Value(0),
        error: const Value(null),
      ),
    );
    await _startTaskForRow(rowId,
        contentId: row.contentId, url: newUrl, ext: nextExt);
    return true;
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

  /// Reintenta una descarga 'failed': borra la fila (y cualquier archivo
  /// parcial que hubiera quedado) y vuelve a encolar desde cero con los
  /// mismos datos originales, incluida la `url` guardada en la fila — el
  /// plugin no garantiza conservar el `DownloadTask` de una tarea que ya
  /// falló, así que no puede reutilizarse vía `taskForId`. No-op si la fila
  /// no existe o no tiene una `url` guardada (filas de antes de esta
  /// migración, que quedaron con `url` null).
  Future<void> retry(int id) async {
    final row = await _rowById(id);
    if (row == null) return;
    final url = row.url;
    if (url == null || url.isEmpty) {
      // Fila anterior a la migración (sin url persistida): no es reintentable.
      // Borrarla da feedback visible (desaparece) en vez de un no-op mudo; el
      // usuario la vuelve a descargar desde la ficha.
      await _deleteRow(id);
      return;
    }
    await _deleteRow(id);
    await enqueue(
      contentId: row.contentId,
      contentType: row.contentType,
      title: row.title,
      imagePath: row.imagePath,
      ext: row.ext,
      url: url,
      playlistId: row.playlistId,
    );
  }

  /// Marca una descarga 'complete' como 'failed' porque su archivo local ya
  /// no existe en disco (borrado fuera de la app, almacenamiento externo
  /// desmontado, etc.). Llamado por `DownloadsScreen` justo antes de
  /// reproducir, para no intentar abrir un archivo inexistente.
  Future<void> markMissing(int id) async {
    await (_db.update(_db.downloads)..where((d) => d.id.equals(id))).write(
      const DownloadsCompanion(
        status: Value('failed'),
        error: Value('file_missing'),
        filePath: Value(null),
      ),
    );
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
        error: Value(null),
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
          // Un reintento nativo (o resume()) volvió a progresar: cualquier
          // error previo mostrado en la UI ya no aplica.
          await _setStatus(rowId, 'downloading', error: const Value(null));
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
          await _setStatus(
            rowId,
            'failed',
            error: const Value('canceled_or_notfound'),
          );
          break;
        case TaskStatus.waitingToRetry:
          break;
      }
    }
  }

  Future<void> _setStatus(
    int rowId,
    String status, {
    Value<String?> error = const Value.absent(),
  }) async {
    await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId)))
        .write(DownloadsCompanion(status: Value(status), error: error));
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
    // Extensión obsoleta que da 404 (algunos paneles no devuelven la página
    // HTML sino un "no encontrado"): probar la siguiente extensión candidata,
    // como en _finalizeComplete. Solo 404 — no reintentar en throttle/auth/5xx.
    if (update.responseStatusCode == 404 &&
        await _retryWithNextExtension(rowId)) {
      return;
    }
    await _setStatus(rowId, 'failed', error: Value(_failureReason(update)));
  }

  /// Motivo legible de un `TaskStatus.failed`: prioriza la descripción de la
  /// excepción del plugin; si no hay, intenta con el código HTTP de
  /// respuesta; si tampoco hay código, un mensaje genérico.
  // El motivo se guarda como CÓDIGO estable (no texto), para que la UI lo
  // traduzca al idioma del usuario al mostrarlo. 'http:<code>' lleva el código
  // HTTP; el resto son claves fijas.
  String _failureReason(TaskStatusUpdate update) {
    final code = update.responseStatusCode;
    if (code != null && code > 0) return 'http:$code';
    return 'failed';
  }

  Future<void> _finalizeComplete(int rowId, TaskStatusUpdate update) async {
    final task = update.task;
    if (task is! DownloadTask) {
      await _setStatus(rowId, 'failed', error: const Value('failed'));
      return;
    }
    String path;
    try {
      path = await task.filePath();
    } catch (_) {
      await _setStatus(rowId, 'failed', error: const Value('failed'));
      return;
    }

    if (await _looksLikeHtmlError(path, update)) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      // El contenido puede reproducir pero descargar una página de error si el
      // panel sirve una extensión obsoleta: probar la siguiente candidata antes
      // de rendirse (mismo criterio que la auto-corrección del player).
      if (await _retryWithNextExtension(rowId)) return;
      await (_db.update(_db.downloads)..where((d) => d.id.equals(rowId)))
          .write(const DownloadsCompanion(
        status: Value('failed'),
        filePath: Value(null),
        error: Value('server_error_page'),
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
        error: const Value(null),
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
    _configureFuture = null;
  }
}
