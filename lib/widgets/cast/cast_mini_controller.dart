// Mini-control global de casting (modelo YouTube/Netflix): una barra persistente
// que se muestra en CUALQUIER pantalla mientras se transmite a la TV, para que el
// usuario siga navegando/buscando contenido. Al tocarla se expande a los controles
// completos (canal ±, audio, subtítulos, detener). Se monta app-wide en el
// `builder` de MaterialApp; se auto-oculta cuando no hay casting.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../l10n/localization_extension.dart';
import '../../services/app_navigator.dart';
import 'casting_screen.dart';

const _accent = Color(0xFFD2603A);

class CastMiniController extends StatelessWidget {
  const CastMiniController({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CastSenderController>();
    if (!c.isCasting) return const SizedBox.shrink();
    final loc = context.loc;
    final device = c.device?.name ?? '';
    final title = c.media?.title ?? '';

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Material(
            color: const Color(0xFF1A1A20),
            elevation: 10,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openControls(context, c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.cast_connected, color: _accent, size: 26),
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
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          if (title.isNotEmpty)
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      tooltip: 'Play/Pause',
                      onPressed: c.playPause,
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop, color: Colors.white70),
                      tooltip: loc.cast_stop,
                      onPressed: c.stopCasting,
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

  void _openControls(BuildContext context, CastSenderController controller) {
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
}
