// Mini-control global de casting (modelo YouTube/Netflix): una barra persistente
// que se muestra en CUALQUIER pantalla mientras se transmite a la TV, para que el
// usuario siga navegando/buscando contenido. Al tocarla se expande a los controles
// completos (canal ±, audio, subtítulos, detener). Se monta app-wide en el
// `builder` de MaterialApp; se auto-oculta cuando no hay casting.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../l10n/localization_extension.dart';
import '../../redesign/rensi_widgets.dart';
import '../../services/app_navigator.dart';
import '../../utils/app_themes.dart';
import 'casting_screen.dart';

class CastMiniController extends StatelessWidget {
  const CastMiniController({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CastSenderController>();
    if (!c.isCasting) return const SizedBox.shrink();
    final loc = context.loc;
    final device = c.device?.name ?? '';
    final title = c.media?.title ?? '';
    final r = rensi(context);
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          // Levantar el mini-control POR ENCIMA de la barra de navegación
          // inferior para no tapar los iconos de explorar/inferiores mientras
          // se navega durante el casting.
          padding: const EdgeInsets.fromLTRB(
              8, 0, 8, 8 + kBottomNavigationBarHeight),
          child: Material(
            color: r.surface2,
            elevation: 10,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openControls(context, c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.cast_connected, color: r.accent, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${loc.cast_playing_on} $device'.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.text2, fontSize: AppThemes.labelSize),
                          ),
                          if (title.isNotEmpty)
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: AppThemes.bodySmallSize,
                                  fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    // No `tooltip:` on these buttons: the mini-controller is
                    // mounted in MaterialApp.builder as a SIBLING of the
                    // Navigator, so it has no Overlay ancestor. A Tooltip asserts
                    // ("No Overlay widget found") at build time; the failing
                    // IconButton is then replaced by the (unbounded) error widget,
                    // which blows the Row out by ~1940px ("RIGHT OVERFLOWED"). A
                    // Semantics label keeps the a11y affordance without an Overlay.
                    Semantics(
                      label: 'Play/Pause',
                      button: true,
                      child: IconButton(
                        icon: Icon(
                          c.isTvPlaying ? Icons.pause : Icons.play_arrow,
                          color: scheme.onSurface,
                        ),
                        onPressed: c.playPause,
                      ),
                    ),
                    Semantics(
                      label: loc.cast_stop,
                      button: true,
                      child: IconButton(
                        icon: Icon(Icons.stop, color: r.text2),
                        onPressed: c.stopCasting,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openControls(BuildContext context, CastSenderController controller) =>
      openCastControls(context, controller);
}

/// Abre el panel de controles de la TV (destino, play/pausa, volumen, pistas,
/// detener) como hoja modal sobre el navegador raíz. Reutilizado por el
/// mini-control y por el handoff del reproductor: al enviar un título a la TV,
/// tras cerrar el player se muestran estos controles para tenerlos a mano.
void openCastControls(BuildContext context, CastSenderController controller) {
  showModalBottomSheet<void>(
    context: appNavigatorKey.currentContext ?? context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<CastSenderController>.value(
      value: controller,
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: const CastingScreen(),
        ),
      ),
    ),
  );
}
