// Botón de descarga offline para una ficha de VOD o de un episodio de serie.
// Se coloca en las pantallas de detalle. Pinta: icono de descargar (nada
// encolado), progreso mientras descarga/pausa, o "disponible offline" cuando
// ya está completa.
//
// Refleja el estado con una consulta PUNTUAL (findByContentId) que se refresca
// en cada acción del propio botón, NO con un `watch()` Drift vivo: una consulta
// Drift perpetuamente abierta sobre NativeDatabase cuelga `boundary.toImage`
// bajo `runAsync` en los widget tests de captura. La progresión en vivo
// (barra que avanza sola) vive en DownloadsScreen, que no se captura.
import 'package:flutter/material.dart';

import '../l10n/localization_extension.dart';
import '../database/database.dart';
import '../models/content_type.dart';
import '../models/playlist_content_model.dart';
import '../services/app_state.dart';
import '../services/download_service.dart';

class DownloadButton extends StatefulWidget {
  const DownloadButton({super.key, required this.item});

  final ContentItem item;

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  Future<Download?>? _future;

  ContentItem get item => widget.item;

  bool get _supported =>
      item.contentType == ContentType.vod ||
      item.contentType == ContentType.series;

  @override
  void initState() {
    super.initState();
    if (_supported) _refresh();
  }

  @override
  void didUpdateWidget(DownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != item.id) _refresh();
  }

  void _refresh() {
    if (!_supported) return;
    setState(() {
      _future = DownloadService.instance.findByContentId(item.id);
    });
  }

  Future<void> _enqueue() async {
    final playlistId = AppState.currentPlaylist?.id ?? '';
    final contentType = item.contentType == ContentType.series ? 'series' : 'vod';
    await DownloadService.instance.enqueue(
      contentId: item.id,
      contentType: contentType,
      title: item.name,
      imagePath: item.imagePath,
      ext: item.containerExtension,
      url: item.url,
      playlistId: playlistId,
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();

    return FutureBuilder<Download?>(
      future: _future,
      builder: (context, snapshot) {
        final row = snapshot.data;
        if (row == null) {
          return IconButton(
            tooltip: context.loc.download_for_offline,
            icon: const Icon(Icons.download_outlined),
            onPressed: _enqueue,
          );
        }
        switch (row.status) {
          case 'complete':
            return IconButton(
              tooltip: context.loc.download_available_offline,
              icon: const Icon(Icons.download_done, color: Colors.green),
              onPressed: null,
            );
          case 'failed':
            return IconButton(
              tooltip: context.loc.download_failed_retry,
              icon: const Icon(Icons.error_outline, color: Colors.redAccent),
              onPressed: () async {
                await DownloadService.instance.delete(row.id);
                await _enqueue();
              },
            );
          case 'paused':
            return IconButton(
              tooltip: context.loc.download_resume,
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () async {
                await DownloadService.instance.resume(row.id);
                if (mounted) _refresh();
              },
            );
          case 'queued':
          case 'downloading':
          default:
            final total = row.totalBytes;
            final progress = (total != null && total > 0)
                ? row.bytesDownloaded / total
                : null;
            return IconButton(
              tooltip: context.loc.download_pause,
              icon: SizedBox(
                width: 24,
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2,
                    ),
                    const Icon(Icons.pause, size: 14),
                  ],
                ),
              ),
              onPressed: () async {
                await DownloadService.instance.pause(row.id);
                if (mounted) _refresh();
              },
            );
        }
      },
    );
  }
}
