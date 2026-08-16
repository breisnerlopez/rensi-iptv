// Pantalla de gestión de descargas offline (VOD/series): progreso, acciones
// (pausar/reanudar/cancelar/borrar) y reproducción local al tocar una
// descarga completa. Integración pendiente de quien cablea la ruta (ver
// reporte del encargo): esta pantalla es autocontenida y no depende de
// argumentos de navegación.
//
// Sin claves de i18n todavía (ver reporte): los textos son literales.
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/localization_extension.dart';
import '../database/database.dart';
import '../models/content_type.dart';
import '../models/m3u_item.dart';
import '../models/playlist_content_model.dart';
import '../models/playlist_model.dart';
import '../models/tmdb_search_result.dart';
import '../services/app_state.dart';
import '../services/download_service.dart';
import '../services/tmdb_service.dart';
import '../utils/imported_filename.dart';
import '../utils/responsive_helper.dart';
import '../widgets/cast/cast_flow.dart';
import '../widgets/player_widget.dart';
import 'file_browser_screen.dart';

const _offlinePlaylistId = '__offline__';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.downloads_title),
        actions: [
          IconButton(
            tooltip: context.loc.import_file,
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => importLocalVideo(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Download>>(
        stream: DownloadService.instance.watchAll(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <Download>[];
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (rows.isEmpty) {
            return Center(
              child: Text(context.loc.downloads_empty),
            );
          }
          // Más recientes primero.
          final sorted = [...rows]
            ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
          final usedBytes = rows.fold<int>(
            0,
            (sum, d) => sum + (d.bytesDownloaded),
          );
          return Column(
            children: [
              _UsageHeader(
                usedBytes: usedBytes,
                capBytes: DownloadService.instance.policy.capBytes,
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _DownloadTile(download: sorted[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UsageHeader extends StatelessWidget {
  const _UsageHeader({required this.usedBytes, required this.capBytes});

  final int usedBytes;
  final int capBytes;

  @override
  Widget build(BuildContext context) {
    final ratio = capBytes > 0 ? (usedBytes / capBytes).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.loc.downloads_storage_used}: '
            '${_formatBytes(usedBytes)} / ${_formatBytes(capBytes)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.download});

  final Download download;

  double? get _progress {
    final total = download.totalBytes;
    if (total == null || total <= 0) return null;
    return (download.bytesDownloaded / total).clamp(0.0, 1.0);
  }

  String _statusLabel(BuildContext context) {
    switch (download.status) {
      case 'queued':
        return context.loc.download_status_queued;
      case 'downloading':
        return context.loc.download_status_downloading;
      case 'paused':
        return context.loc.download_status_paused;
      case 'complete':
        return context.loc.download_status_complete;
      case 'failed':
        return context.loc.download_status_failed;
      default:
        return download.status;
    }
  }

  Future<void> _play(BuildContext context) async {
    final path = download.filePath;
    if (path == null) return;

    // El archivo pudo borrarse fuera de la app (limpieza manual, tarjeta SD
    // desmontada, etc.): si ya no está, no intentamos reproducirlo — se
    // marca la fila como fallida (con motivo) para que quede claro y sea
    // reintentable desde el propio diálogo de fallo.
    if (!await File(path).exists()) {
      await DownloadService.instance.markMissing(download.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.download_err_file_missing),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final contentType =
        download.contentType == 'series' ? ContentType.series : ContentType.vod;

    // Mismo patrón que TvReceiverHost: para que ContentItem resuelva su url al
    // archivo local (y no a la URL Xtream) hace falta una playlist "m3u" activa
    // mientras se construye el ContentItem; se restaura la anterior al volver.
    final saved = AppState.currentPlaylist;
    AppState.currentPlaylist = Playlist(
      id: _offlinePlaylistId,
      name: 'Offline',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
    final item = ContentItem(
      download.contentId,
      download.title,
      download.imagePath,
      contentType,
      m3uItem: M3uItem(
        id: download.contentId,
        playlistId: _offlinePlaylistId,
        url: path,
        contentType: contentType,
        name: download.title,
      ),
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: PlayerWidget(contentItem: item, queue: [item]),
        ),
      ),
    );
    AppState.currentPlaylist = saved;
  }

  /// Diálogo mostrado al tocar una fila 'failed': motivo completo del fallo
  /// y acción para reintentar (borra la fila y vuelve a encolar).
  /// Traduce el CÓDIGO de error guardado en la BD al idioma del usuario.
  /// 'http:<code>' antepone el código HTTP; el resto son claves fijas.
  String _localizedError(BuildContext context, String code) {
    final loc = context.loc;
    if (code.startsWith('http:')) {
      final c = code.substring(5);
      return c.isNotEmpty ? '${loc.download_err_http} $c' : loc.download_err_http;
    }
    switch (code) {
      case 'start_failed':
        return loc.download_err_start_failed;
      case 'file_missing':
        return loc.download_err_file_missing;
      case 'canceled_or_notfound':
        return loc.download_err_canceled;
      case 'server_error_page':
        return loc.download_err_server_page;
      case 'failed':
      default:
        return loc.download_err_generic;
    }
  }

  Future<void> _showFailedDialog(BuildContext context) async {
    final code = download.error;
    final reason =
        code == null ? _statusLabel(context) : _localizedError(context, code);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          download.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.loc.close),
          ),
          // Import: no hay re-descarga posible; el botón borra la fila (honesto)
          // en vez de "reintentar" (que borraría en silencio).
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (download.imported) {
                DownloadService.instance.delete(download.id);
              } else {
                DownloadService.instance.retry(download.id);
              }
            },
            child: Text(download.imported
                ? dialogContext.loc.download_delete
                : dialogContext.loc.download_retry),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = download.status == 'complete';
    final isFailed = download.status == 'failed';
    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 56,
        child: download.imagePath.isEmpty
            ? const ColoredBox(
                color: Colors.black26,
                child: Icon(Icons.movie_outlined),
              )
            : CachedNetworkImage(
                imageUrl: download.imagePath,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: Colors.black26,
                  child: Icon(Icons.movie_outlined),
                ),
              ),
      ),
      title: Text(download.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_statusLabel(context)}'
            '${_progress != null ? ' • ${(_progress! * 100).round()}%' : ''}'
            ' • ${_formatBytes(download.bytesDownloaded)}'
            '${download.totalBytes != null ? ' / ${_formatBytes(download.totalBytes!)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (download.status == 'downloading' || download.status == 'paused')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: _progress),
            ),
          if (isFailed && (download.error ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _localizedError(context, download.error!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._actionsFor(context),
        ],
      ),
      onTap: isComplete
          ? () => _play(context)
          : (isFailed ? () => _showFailedDialog(context) : null),
    );
  }

  List<Widget> _actionsFor(BuildContext context) {
    switch (download.status) {
      case 'downloading':
      case 'queued':
        return [
          IconButton(
            tooltip: context.loc.download_pause,
            icon: const Icon(Icons.pause),
            onPressed: () => DownloadService.instance.pause(download.id),
          ),
          IconButton(
            tooltip: context.loc.download_cancel,
            icon: const Icon(Icons.close),
            onPressed: () => DownloadService.instance.cancel(download.id),
          ),
        ];
      case 'paused':
        return [
          IconButton(
            tooltip: context.loc.download_resume,
            icon: const Icon(Icons.play_arrow),
            onPressed: () => DownloadService.instance.resume(download.id),
          ),
          IconButton(
            tooltip: context.loc.download_cancel,
            icon: const Icon(Icons.close),
            onPressed: () => DownloadService.instance.cancel(download.id),
          ),
        ];
      case 'failed':
        return [
          // Un import no es re-descargable (no tiene URL de origen); "reintentar"
          // solo borraría la fila en silencio, así que se omite para imports.
          if (!download.imported)
            IconButton(
              tooltip: context.loc.download_retry,
              icon: const Icon(Icons.refresh),
              onPressed: () => DownloadService.instance.retry(download.id),
            ),
          IconButton(
            tooltip: context.loc.download_delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => DownloadService.instance.delete(download.id),
          ),
        ];
      case 'complete':
      default:
        return [
          if (download.filePath != null)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 4),
              child: Icon(Icons.play_arrow),
            ),
          if (download.filePath != null)
            IconButton(
              tooltip: context.loc.download_send_to_tv,
              icon: const Icon(Icons.cast),
              onPressed: () async {
                // Serie descargada: arma la cola de episodios hermanos
                // descargados para que la TV auto-avance. Película o episodio
                // suelto → cola null (cast único, sin cambios).
                final (queue, index) =
                    await buildDownloadedSeriesQueue(download);
                if (!context.mounted) return;
                startLocalFileCastFlow(
                  context,
                  filePath: download.filePath!,
                  contentId: download.contentId,
                  title: download.title,
                  ext: download.ext ?? '',
                  queue: queue,
                  index: index,
                );
              },
            ),
          IconButton(
            tooltip: context.loc.download_delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => DownloadService.instance.delete(download.id),
          ),
        ];
    }
  }
}

/// Extensiones de video aceptadas al importar (para el navegador in-app de la
/// TV; en móvil file_picker filtra por FileType.video).
const List<String> _importVideoExtensions = [
  'mp4', 'mkv', 'avi', 'mov', 'webm', 'm4v', 'ts', 'flv', 'wmv', 'mpg', 'mpeg',
  '3gp',
];

// Debounce: un import en vuelo bloquea otro (doble-tap del botón o mientras se
// copia) → evita abrir dos selectores y duplicar el archivo en disco.
bool _importInFlight = false;

/// Flujo de import de un video local: elegir → traer a la biblioteca → aparece
/// en Descargas → enriquecer con TMDb (best-effort). Botón "Importar".
Future<void> importLocalVideo(BuildContext context) async {
  if (_importInFlight) return;
  _importInFlight = true;
  try {
    final picked = await _pickVideoSource(context);
    if (picked == null || !context.mounted) return;

    // Móvil → `movePath` (file_picker ya cacheó el archivo; MOVERLO es
    // instantáneo, no hace falta barra). TV → `source` (copia del original, con
    // barra de progreso).
    final isCopy = picked.source != null;
    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context, rootNavigator: true);
    if (isCopy) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ImportProgressDialog(name: picked.name, progress: progress),
      );
    }

    Download? row;
    Object? error;
    try {
      row = await DownloadService.instance.importLocalFile(
        source: picked.source,
        movePath: picked.movePath,
        fileName: picked.name,
        sizeBytes: picked.size,
        onProgress: (copied, total) {
          progress.value = (total != null && total > 0)
              ? (copied / total).clamp(0.0, 1.0)
              : null;
        },
      );
    } catch (e) {
      error = e;
    }

    if (isCopy && navigator.mounted) navigator.pop(); // cerrar el progreso
    progress.dispose();

    if (!context.mounted) return;
    if (error != null || row == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.loc.import_failed)));
      return;
    }
    // Best-effort, NO bloquea: la fila ya aparece con el nombre del archivo.
    unawaited(_enrichImportWithTmdb(row, picked.name));
  } finally {
    _importInFlight = false;
  }
}

/// Elige un video. Móvil: file_picker cachea el archivo → devolvemos `movePath`
/// (esa cache, para MOVERLA a la biblioteca; NO usamos `withReadStream`, que en
/// file_picker 8.x lanza si el `path` viene nulo). Muestra un overlay
/// "Importando…" mientras file_picker copia (paso opaco y lento en archivos
/// grandes → sin esto la app se ve congelada). TV: navegador in-app → `source`
/// (copia del original, sin moverlo).
Future<
    ({
      Stream<List<int>>? source,
      String? movePath,
      String name,
      int? size
    })?> _pickVideoSource(BuildContext context) async {
  if (ResponsiveHelper.isDesktopOrTV(context)) {
    final file = await Navigator.of(context).push<File?>(
      MaterialPageRoute(
        builder: (_) => FileBrowserScreen(
          title: context.loc.import_file,
          extensions: _importVideoExtensions,
        ),
      ),
    );
    if (file == null) return null;
    final size = await file.length();
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path;
    return (source: file.openRead(), movePath: null, name: name, size: size);
  }

  final nav = Navigator.of(context, rootNavigator: true);
  var busyShown = false;
  void showBusy() {
    if (busyShown || !context.mounted) return;
    busyShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ImportBusyDialog(),
    );
  }

  void hideBusy() {
    if (busyShown && nav.mounted) {
      nav.pop();
      busyShown = false;
    }
  }

  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      // file_picker copia el content:// a su cache DENTRO de este await (lento y
      // opaco en archivos grandes); el callback nos deja mostrar "Importando…".
      onFileLoading: (status) =>
          status == FilePickerStatus.picking ? showBusy() : hideBusy(),
    );
  } catch (e) {
    hideBusy();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.loc.import_failed)));
    }
    return null;
  }
  hideBusy(); // seguridad si el 'done' no llegó
  if (result == null || result.files.isEmpty) return null; // cancelado
  final f = result.files.single;

  final path = f.path;
  if (path != null && path.isNotEmpty) {
    // file_picker ya cacheó el archivo aquí → MOVER esa copia a la biblioteca.
    return (source: null, movePath: path, name: f.name, size: f.size);
  }
  // Sin ruta (algún provider cloud sin archivo local): no se pudo leer → avisar.
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.loc.import_failed)));
  }
  return null;
}

/// Overlay indeterminado mientras file_picker copia el archivo elegido a su
/// cache (paso que no reporta progreso). Evita que la app se vea congelada.
class _ImportBusyDialog extends StatelessWidget {
  const _ImportBusyDialog();
  @override
  Widget build(BuildContext context) {
    // PopScope(canPop:false): el back no debe cerrar este overlay (si no, el pop
    // programático de cierre caería sobre DownloadsScreen y echaría al usuario).
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(context.loc.importing)),
          ],
        ),
      ),
    );
  }
}

/// Empareja el import con TMDb (best-effort): parsea el nombre, busca como serie
/// o película según el patrón de episodio, y si hay match actualiza
/// título+póster. Silencioso ante sin-clave/sin-red/sin-match (queda el nombre).
Future<void> _enrichImportWithTmdb(Download row, String fileName) async {
  try {
    final info = parseImportedFilename(fileName);
    final results = await TmdbService().searchTitle(
      info.title,
      year: info.year,
      mediaType: info.isEpisode ? TmdbMediaType.tv : TmdbMediaType.movie,
    );
    if (results.isEmpty) return;
    final best = results.first;
    if (best.title.isEmpty) return;
    await DownloadService.instance.updateImportMetadata(
      row.id,
      title: best.title,
      imagePath: best.posterUrl,
    );
  } catch (_) {
    // sin clave / sin red / sin match → se conserva el nombre del archivo.
  }
}

class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog({required this.name, required this.progress});
  final String name;
  final ValueNotifier<double?> progress;

  @override
  Widget build(BuildContext context) {
    // PopScope(canPop:false): el botón/mando ATRÁS no debe cerrar este diálogo
    // (si no, el pop de cierre programático caería sobre DownloadsScreen y
    // echaría al usuario). Solo se cierra por código al terminar el import.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(context.loc.importing),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: value),
                  if (value != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${(value * 100).round()}%',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
