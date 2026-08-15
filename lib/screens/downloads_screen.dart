// Pantalla de gestión de descargas offline (VOD/series): progreso, acciones
// (pausar/reanudar/cancelar/borrar) y reproducción local al tocar una
// descarga completa. Integración pendiente de quien cablea la ruta (ver
// reporte del encargo): esta pantalla es autocontenida y no depende de
// argumentos de navegación.
//
// Sin claves de i18n todavía (ver reporte): los textos son literales.
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/localization_extension.dart';
import '../database/database.dart';
import '../models/content_type.dart';
import '../models/m3u_item.dart';
import '../models/playlist_content_model.dart';
import '../models/playlist_model.dart';
import '../services/app_state.dart';
import '../services/download_service.dart';
import '../widgets/cast/cast_flow.dart';
import '../widgets/player_widget.dart';

const _offlinePlaylistId = '__offline__';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.downloads_title)),
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
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              DownloadService.instance.retry(download.id);
            },
            child: Text(dialogContext.loc.download_retry),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
