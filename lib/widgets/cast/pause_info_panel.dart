// Panel de información rico que aparece al PAUSAR en la TV (receptor de
// casting): TÍTULO + barra de progreso + sinopsis + reparto (actores). Reutiliza
// la infraestructura TMDb existente (TmdbEnrichment), que resuelve por título y
// degrada a nada si no hay clave o no hay coincidencia — así el panel siempre
// muestra al menos el título y NUNCA bloquea la reproducción.
//
// Pensado para 10 pies: todos los tamaños de fuente pasan por AppThemes.tenFoot.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/localization_extension.dart';
import '../../models/content_type.dart';
import '../../models/tmdb_search_result.dart';
import '../../services/cast/cast_protocol.dart';
import '../../utils/app_themes.dart';
import '../tmdb_cast_rail.dart';
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
    this.sentMeta,
  });

  final String title;
  final ContentType contentType;
  final Duration position;
  final Duration duration;

  /// Metadatos TMDb (sinopsis + reparto) que el MÓVIL resolvió y envió con el
  /// LOAD de casting. Cuando llega (y no está vacío) el panel muestra ESTOS datos
  /// —la TV no tiene clave TMDb— en vez de llamar a [TmdbEnrichment]. Null (cast
  /// desde una build vieja, reproducción local en la TV, o sin coincidencia) →
  /// se cae al comportamiento actual: TmdbEnrichment/solo-título.
  final CastMeta? sentMeta;

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
                // Sinopsis + reparto. Preferimos los metadatos que el MÓVIL
                // resolvió y ENVIÓ con el LOAD ([sentMeta]) — la TV no tiene
                // clave TMDb, así que llamar a TmdbEnrichment aquí no traería
                // reparto. Si no llegó meta (build vieja / reproducción local /
                // sin coincidencia) caemos a TmdbEnrichment (que a su vez degrada
                // a solo-título). Ninguna de las dos ramas bloquea nunca.
                Flexible(
                  child: SingleChildScrollView(
                    child: (sentMeta != null && !sentMeta!.isEmpty)
                        ? _SentMetaSection(meta: sentMeta!)
                        : TmdbEnrichment(
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

/// Sinopsis + reparto a partir de los metadatos TMDb que el móvil ENVIÓ con el
/// LOAD. Reutiliza el mismo [TmdbCastRail] que las pantallas de detalle (la
/// lista enviada se reconstruye a [TmdbCredit] desde el `profile_path` crudo). No
/// llama a TMDb: pinta lo recibido. Todos los tamaños pasan por AppThemes.tenFoot
/// (UI de 10 pies). Se auto-oculta si no hay nada que mostrar.
class _SentMetaSection extends StatelessWidget {
  const _SentMetaSection({required this.meta});

  final CastMeta meta;

  @override
  Widget build(BuildContext context) {
    final overview = meta.overview.trim();
    // Capado a 20 (lo que el rail muestra): un peer con un `cast` gigante no debe
    // materializar una lista enorme en memoria en la TV.
    final members = meta.cast.where((m) => m.name.isNotEmpty).take(20).toList();
    final cast = <TmdbCredit>[
      for (var i = 0; i < members.length; i++)
        TmdbCredit(
          id: i,
          name: members[i].name,
          character:
              members[i].character.isEmpty ? null : members[i].character,
          profilePath: members[i].profilePath,
        )
    ];
    // URL del póster reconstruida por CastMeta contra el host FIJO de TMDb
    // (image.tmdb.org) a partir del fragmento enviado por el móvil — nunca una URL
    // controlada por el emisor. Null (contenido no-TMDb / archivo local) → sin
    // póster (el guard de abajo lo omite y el panel queda como antes).
    final posterUrl = meta.posterUrl;
    final showOverview = overview.isNotEmpty;
    if (!showOverview && cast.isEmpty && posterUrl == null) {
      return const SizedBox.shrink();
    }

    final overviewColumn = <Widget>[
      if (showOverview) ...[
        Text(
          context.loc.description,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white70,
            fontSize: AppThemes.tenFoot(context, AppThemes.bodySmallSize),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          overview,
          style: TextStyle(
            color: Colors.white,
            height: 1.5,
            fontSize: AppThemes.tenFoot(context, AppThemes.bodySize),
          ),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (posterUrl != null || showOverview) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (posterUrl != null) _CastPoster(url: posterUrl),
                if (posterUrl != null && showOverview)
                  const SizedBox(width: 20),
                if (showOverview)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: overviewColumn,
                    ),
                  ),
              ],
            ),
            if (cast.isNotEmpty) const SizedBox(height: 24),
          ],
          if (cast.isNotEmpty) ...[
            Text(
              context.loc.cast,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white70,
                fontSize: AppThemes.tenFoot(context, AppThemes.bodySmallSize),
              ),
            ),
            const SizedBox(height: 12),
            // Mismo rail que las pantallas de detalle; blanco explícito para el
            // fondo oscuro del scrim. Sin onActorTap → avatares inertes/no
            // enfocables (nada roba el foco al reproductor en pausa).
            TmdbCastRail(
              cast: cast,
              nameColor: Colors.white,
              characterColor: Colors.white54,
            ),
          ],
        ],
      ),
    );
  }
}

/// Póster 2:3 acotado para el panel de pausa. [url] YA viene reconstruida contra
/// el host FIJO de TMDb (ver [CastMeta.posterUrl]); este widget solo la pinta. En
/// carga/fallo muestra un marcador del MISMO tamaño para que el layout no salte.
class _CastPoster extends StatelessWidget {
  const _CastPoster({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    const width = 120.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: width * 3 / 2,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => _fallback(),
          errorWidget: (_, __, ___) => _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: const Color(0x22FFFFFF),
        child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 40),
      );
}
