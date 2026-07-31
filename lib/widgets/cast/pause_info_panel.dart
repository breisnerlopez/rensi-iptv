// Panel de información rico que aparece al PAUSAR en la TV (receptor de
// casting): TÍTULO + barra de progreso + sinopsis + reparto (actores). Reutiliza
// la infraestructura TMDb existente (TmdbEnrichment), que resuelve por título y
// degrada a nada si no hay clave o no hay coincidencia — así el panel siempre
// muestra al menos el título y NUNCA bloquea la reproducción.
//
// Pensado para 10 pies: todos los tamaños de fuente pasan por AppThemes.tenFoot.
import 'package:flutter/material.dart';

import '../../l10n/localization_extension.dart';
import '../../models/content_type.dart';
import '../../models/tmdb_search_result.dart';
import '../../utils/app_themes.dart';
import '../tmdb_enrichment.dart';
import '../tv/focus_highlight.dart';

class PauseInfoPanel extends StatelessWidget {
  const PauseInfoPanel({
    super.key,
    required this.title,
    required this.contentType,
    required this.position,
    required this.duration,
    this.hasNext = false,
    this.onNext,
    this.nextFocusNode,
  });

  final String title;
  final ContentType contentType;
  final Duration position;
  final Duration duration;

  /// Whether a next episode exists — controls whether the "Siguiente episodio"
  /// button is shown. Threaded from PlayerWidget's `_hasNextEpisode`.
  final bool hasNext;

  /// Invoked when the "Siguiente episodio" button is activated (touch or, on
  /// TV, the D-pad — see PlayerWidget._handleRemoteKey).
  final VoidCallback? onNext;

  /// Focus target for the "Siguiente episodio" button so the player can move
  /// the D-pad ring onto it with DOWN. Null → the button is touch-only.
  final FocusNode? nextFocusNode;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// D-pad-focusable "Siguiente episodio ›" button. Uses the same
  /// [FocusHighlight] language as the rest of the 10-foot UI: the [InkWell] is
  /// the real focus target (fed the shared [nextFocusNode]) and the wrapper
  /// paints the focus ring. It never autofocuses — the player hands the ring
  /// here on D-pad DOWN.
  Widget _buildNextButton(BuildContext context) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: nextFocusNode,
          onTap: onNext,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.skip_next, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                Text(
                  context.loc.next_episode,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: AppThemes.tenFoot(context, 16),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    color: Colors.white70, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
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
                if (hasNext && onNext != null) ...[
                  const SizedBox(height: 20),
                  _buildNextButton(context),
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
