// Puente entre el CastSenderController y el foreground service del casting.
// Se monta app-wide (junto al CastMiniController, bajo el provider). Escucha el
// controller: al entrar en casting arranca/actualiza el FGS (que mantiene vivo
// el proceso en segundo plano); al salir lo retira. Cubre TODAS las salidas
// (idle/stop/superseded/error/reconnect-agotado) porque el controller pasa
// siempre por el único embudo `_set()` que notifica. Rutea los botones de la
// notificación (play/pausa, detener) de vuelta al controller.
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../l10n/localization_extension.dart';
import '../../services/cast/cast_foreground_service.dart';

class CastForegroundBridge extends StatefulWidget {
  const CastForegroundBridge({super.key});

  @override
  State<CastForegroundBridge> createState() => _CastForegroundBridgeState();
}

class _CastForegroundBridgeState extends State<CastForegroundBridge> {
  CastSenderController? _controller;
  String? _lastKey; // dedup: no llamar al plugin en cada notifyListeners

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<CastSenderController>();
    if (!identical(c, _controller)) {
      _controller?.removeListener(_sync);
      _controller = c..addListener(_sync);
      // Botones de la notificación → controller (mismos métodos que el
      // mini-control; `playPause` ya se blinda solo durante la reconexión).
      CastForegroundService.onAction = (id) {
        final ctrl = _controller;
        if (ctrl == null) return;
        if (id == CastFgAction.playPause) {
          ctrl.playPause();
        } else if (id == CastFgAction.stop) {
          ctrl.stopCasting();
        }
      };
      _sync();
    }
  }

  void _sync() {
    final c = _controller;
    if (c == null || !mounted) return;
    if (!c.isCasting) {
      if (_lastKey != null) {
        _lastKey = null;
        CastForegroundService.stop();
      }
      return;
    }
    final title = c.media?.title ?? '';
    final device = c.device?.name ?? '';
    final playing = c.isTvPlaying;
    // Solo tocar el plugin cuando cambia algo que afecta la notificación.
    final key = '$playing|$title|$device';
    if (key == _lastKey) return;
    _lastKey = key;
    final loc = context.loc;
    CastForegroundService.startOrUpdate(
      title: title.isEmpty ? loc.cast_active : title,
      text: '${loc.cast_playing_on} $device'.trim(),
      playing: playing,
      playLabel: loc.play,
      pauseLabel: loc.pause,
      stopLabel: loc.cast_stop,
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_sync);
    CastForegroundService.onAction = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
