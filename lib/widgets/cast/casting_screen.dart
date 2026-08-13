// Controles completos del casting (se abre desde el mini-control global): destino,
// play/pausa, zap ± (solo en vivo y si hay catálogo), selección de pista de audio
// y de subtítulos (poblada con las pistas reales que reporta la TV), y detener.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../l10n/localization_extension.dart';

const _accent = Color(0xFFD2603A);

class CastingScreen extends StatelessWidget {
  const CastingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final c = context.watch<CastSenderController>();
    final device = c.device?.name ?? '';
    final title = c.media?.title ?? '';

    return Container(
      color: const Color(0xFF0B0B0D),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.cast_connected, color: _accent, size: 56),
              const SizedBox(height: 16),
              Text(loc.cast_playing_on,
                  style: const TextStyle(color: Colors.white54, fontSize: 15)),
              const SizedBox(height: 4),
              Text(device,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 17)),
              ],
              const SizedBox(height: 6),
              Text(loc.cast_remote_hint,
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (c.canZap) _roundBtn(Icons.skip_previous, c.channelDown),
                  _roundBtn(Icons.play_arrow, c.playPause, big: true),
                  if (c.canZap) _roundBtn(Icons.skip_next, c.channelUp),
                  // Serie: saltar manualmente al siguiente episodio en la TV
                  // (canZap es solo-vivo y canCastNextEpisode solo-serie: nunca
                  // aparecen a la vez).
                  if (c.canCastNextEpisode)
                    _roundBtn(Icons.skip_next, c.castNextEpisode),
                ],
              ),
              // Scrub de posición (seek móvil→TV): solo VOD/serie. En vivo se
              // oculta por completo (además del guard del listener del player).
              if (!c.isLive) ...[
                const SizedBox(height: 20),
                _scrubRow(context, c),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Icon(_volumeIcon(c.volume), color: Colors.white70, size: 22),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _accent,
                          thumbColor: _accent,
                          inactiveTrackColor: const Color(0xFF1E1E24),
                          overlayColor: _accent.withValues(alpha: 0.2),
                        ),
                        child: Slider(
                          value: c.volume / 100,
                          onChanged: (v) => c.setVolume(v * 100),
                          // Silencia el eco de la TV mientras dura el gesto (evita
                          // que un eco en tránsito haga saltar el slider bajo el
                          // dedo) y manda el valor final YA al soltar.
                          onChangeStart: (_) => c.beginVolumeDrag(),
                          onChangeEnd: (v) => c.endVolumeDrag(v * 100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pillBtn(Icons.audiotrack, 'Audio',
                      () => _openTracks(context, c, audio: true)),
                  const SizedBox(width: 12),
                  _pillBtn(Icons.subtitles, 'Subtítulos',
                      () => _openTracks(context, c, audio: false)),
                ],
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: c.stopCasting,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.white70),
                label: Text(loc.cast_stop,
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _openTracks(BuildContext context, CastSenderController c,
      {required bool audio}) {
    c.requestTracks(); // pide a la TV sus pistas actuales
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF15151A),
      builder: (_) => ChangeNotifierProvider<CastSenderController>.value(
        value: c,
        child: Consumer<CastSenderController>(
          builder: (context, c, _) {
            final tracks = audio ? c.audioTracks : c.subtitleTracks;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(audio ? 'Audio' : 'Subtítulos',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (!audio)
                    ListTile(
                      leading: const Icon(Icons.subtitles_off, color: Colors.white54),
                      title: const Text('Desactivados',
                          style: TextStyle(color: Colors.white)),
                      onTap: () {
                        c.selectSubtitle('');
                        Navigator.pop(context);
                      },
                    ),
                  if (tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: _accent),
                    ),
                  for (final t in tracks)
                    ListTile(
                      leading: Icon(t.selected ? Icons.check : Icons.circle_outlined,
                          color: t.selected ? _accent : Colors.white38),
                      title: Text(t.label, style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        audio ? c.selectAudio(t.id) : c.selectSubtitle(t.id);
                        Navigator.pop(context);
                      },
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _volumeIcon(double v) {
    if (v <= 0) return Icons.volume_off;
    if (v < 50) return Icons.volume_down;
    return Icons.volume_up;
  }

  /// Slider de scrub de posición para VOD/serie casteado. Se alimenta de la
  /// posición/duración que la TV reporta ([castPositionMs]/[castDurationMs]).
  /// Mientras no haya duración conocida (aún no llegó el primer `state`, throttle
  /// ~5s), se muestra DESHABILITADO (onChanged null) para no permitir un salto a
  /// ciegas ni dividir por cero — nunca crashea.
  Widget _scrubRow(BuildContext context, CastSenderController c) {
    final durMs = c.castDurationMs;
    final posMs = c.castPositionMs;
    final enabled = c.canScrub; // !isLive && durMs > 0
    final value = enabled ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accent,
              thumbColor: _accent,
              inactiveTrackColor: const Color(0xFF1E1E24),
              overlayColor: _accent.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              // Deshabilitado hasta conocer la duración: sin ella no hay a dónde
              // saltar. Al arrastrar, actualización local optimista (el thumb sigue
              // al dedo) y al soltar se manda el seek a la TV (como el volumen).
              onChanged: enabled
                  ? (v) => c.updateSeekDrag(
                      Duration(milliseconds: (v * durMs).round()))
                  : null,
              onChangeStart: enabled ? (_) => c.beginSeekDrag() : null,
              onChangeEnd: enabled
                  ? (v) =>
                      c.endSeekDrag(Duration(milliseconds: (v * durMs).round()))
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmtDuration(posMs),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                Text(enabled ? _fmtDuration(durMs) : '--:--',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// H:MM:SS (o M:SS bajo una hora) desde milisegundos, para las etiquetas del
  /// slider de scrub. Valores no positivos → '0:00'.
  String _fmtDuration(int ms) {
    if (ms <= 0) return '0:00';
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap, {bool big = false}) {
    final size = big ? 72.0 : 56.0;
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
            child: Icon(icon, color: Colors.white, size: big ? 38 : 28),
          ),
        ),
      ),
    );
  }

  Widget _pillBtn(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFF1E1E24),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }
}
