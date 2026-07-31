// Panel de información rico que aparece al PAUSAR en la TV (receptor de
// casting): TÍTULO + barra de progreso + sinopsis + reparto (actores). Reutiliza
// la infraestructura TMDb existente (TmdbEnrichment), que resuelve por título y
// degrada a nada si no hay clave o no hay coincidencia — así el panel siempre
// muestra al menos el título y NUNCA bloquea la reproducción.
//
// Pensado para 10 pies: todos los tamaños de fuente pasan por AppThemes.tenFoot.
import 'package:flutter/material.dart';

import '../../models/content_type.dart';
import '../../models/tmdb_search_result.dart';
import '../../utils/app_themes.dart';
import '../tmdb_enrichment.dart';

class PauseInfoPanel extends StatelessWidget {
  const PauseInfoPanel({
    super.key,
    required this.title,
    required this.contentType,
    required this.position,
    required this.duration,
  });

  final String title;
  final ContentType contentType;
  final Duration position;
  final Duration duration;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hasDur = duration.inMilliseconds > 0;
    final progress = hasDur
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    // Series → búsqueda de TV; el resto (VOD) → película. El vivo no llega aquí
    // (el llamador lo excluye: no hay título fiable que buscar en TMDb).
    final mediaType =
        contentType == ContentType.series ? TmdbMediaType.tv : TmdbMediaType.movie;

    return Positioned.fill(
      child: DecoratedBox(
        // Scrim degradado: oscurece lo justo para leer, dejando ver el fotograma.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [Color(0xF2000000), Color(0x99000000), Color(0x33000000)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 40, 48, 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Insignia de "En pausa".
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pause_circle_filled,
                        color: Color(0xFFD2603A), size: 26),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: AppThemes.tenFoot(context, AppThemes.h2Size),
                      ),
                    ),
                  ],
                ),
                if (hasDur) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(_fmt(position),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: AppThemes.tenFoot(context, 13))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: Colors.white24,
                            valueColor:
                                const AlwaysStoppedAnimation(Color(0xFFD2603A)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_fmt(duration),
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: AppThemes.tenFoot(context, 13))),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                // Enriquecimiento TMDb: sinopsis + reparto. Se auto-oculta
                // (SizedBox.shrink) si no hay clave TMDb o no hay coincidencia,
                // dejando el panel con solo el título/progreso. Nunca bloquea.
                Flexible(
                  child: SingleChildScrollView(
                    child: TmdbEnrichment(
                      title: title,
                      mediaType: mediaType,
                      locale: Localizations.localeOf(context),
                      existingOverview: '',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
