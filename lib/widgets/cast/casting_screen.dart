// Pantalla que reemplaza al video en el móvil MIENTRAS se castea: el televisor
// reproduce y el teléfono es el control. Muestra el destino y los controles
// remotos (canal ±, play/pausa, detener). Reactiva al CastSenderController.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../l10n/localization_extension.dart';

const _accent = Color(0xFFD2603A);

class CastingScreen extends StatelessWidget {
  const CastingScreen({super.key, this.showChannelControls = true});

  /// El zapping ± solo tiene sentido en vivo.
  final bool showChannelControls;

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final c = context.watch<CastSenderController>();
    final device = c.device?.name ?? '';
    final title = c.media?.title ?? '';

    return Container(
      color: const Color(0xFF0B0B0D),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cast_connected, color: _accent, size: 64),
            const SizedBox(height: 20),
            Text(loc.cast_playing_on,
                style: const TextStyle(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 4),
            Text(device,
                style: const TextStyle(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(color: Colors.white70, fontSize: 17)),
            ],
            const SizedBox(height: 8),
            Text(loc.cast_remote_hint,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showChannelControls)
                  _roundBtn(Icons.skip_previous, c.channelDown),
                _roundBtn(Icons.play_arrow, c.playPause, big: true),
                if (showChannelControls)
                  _roundBtn(Icons.skip_next, c.channelUp),
              ],
            ),
            const SizedBox(height: 40),
            TextButton.icon(
              onPressed: () => c.stopCasting(),
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white70),
              label: Text(loc.cast_stop,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap, {bool big = false}) {
    final size = big ? 76.0 : 60.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: big ? _accent : const Color(0xFF1E1E24),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: big ? 40 : 30),
          ),
        ),
      ),
    );
  }
}
