// Controles completos del casting (se abre desde el mini-control global): destino,
// play/pausa, zap ± (solo en vivo y si hay catálogo), selección de pista de audio
// y de subtítulos (poblada con las pistas reales que reporta la TV), y detener.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../l10n/localization_extension.dart';
import '../../redesign/rensi_widgets.dart';
import '../../utils/app_themes.dart';

class CastingScreen extends StatelessWidget {
  const CastingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final c = context.watch<CastSenderController>();
    final device = c.device?.name ?? '';
    final title = c.media?.title ?? '';
    final r = rensi(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.cast_connected, color: r.accent, size: 56),
              const SizedBox(height: 16),
              Text(loc.cast_playing_on,
                  style: TextStyle(color: r.text2, fontSize: AppThemes.bodySmallSize)),
              const SizedBox(height: 4),
              Text(device,
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: AppThemes.h3Size,
                      fontWeight: FontWeight.bold)),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: r.text2, fontSize: AppThemes.bodySize)),
              ],
              const SizedBox(height: 6),
              Text(loc.cast_remote_hint,
                  style: TextStyle(color: r.text3, fontSize: AppThemes.labelSize)),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (c.canZap) _roundBtn(context, Icons.skip_previous, c.channelDown),
                  _roundBtn(context, c.isTvPlaying ? Icons.pause : Icons.play_arrow,
                      c.playPause,
                      big: true),
                  if (c.canZap) _roundBtn(context, Icons.skip_next, c.channelUp),
                  // Serie: saltar manualmente al siguiente episodio en la TV
                  // (canZap es solo-vivo y canCastNextEpisode solo-serie: nunca
                  // aparecen a la vez).
                  if (c.canCastNextEpisode)
                    _roundBtn(context, Icons.skip_next, c.castNextEpisode),
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
                    Icon(_volumeIcon(c.volume), color: r.text2, size: 22),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: r.accent,
                          thumbColor: r.accent,
                          inactiveTrackColor: r.surface3,
                          overlayColor: r.accent.withValues(alpha: 0.2),
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
                  _pillBtn(context, Icons.audiotrack, loc.cast_audio,
                      () => _openTracks(context, c, audio: true)),
                  const SizedBox(width: 12),
                  _pillBtn(context, Icons.subtitles, loc.cast_subtitles,
                      () => _openTracks(context, c, audio: false)),
                ],
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: c.stopCasting,
                icon: Icon(Icons.stop_circle_outlined, color: r.text2),
                label: Text(loc.cast_stop,
                    style: TextStyle(color: r.text2, fontSize: AppThemes.bodySmallSize)),
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
      backgroundColor: rensi(context).surface2,
      builder: (_) => ChangeNotifierProvider<CastSenderController>.value(
        value: c,
        child: TrackSheetBody(audio: audio),
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
              activeTrackColor: rensi(context).accent,
              thumbColor: rensi(context).accent,
              inactiveTrackColor: rensi(context).surface3,
              overlayColor: rensi(context).accent.withValues(alpha: 0.2),
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
                    style: TextStyle(
                        color: rensi(context).text2, fontSize: AppThemes.labelSize)),
                Text(enabled ? _fmtDuration(durMs) : '--:--',
                    style: TextStyle(
                        color: rensi(context).text2, fontSize: AppThemes.labelSize)),
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

  Widget _roundBtn(BuildContext context, IconData icon, VoidCallback onTap,
      {bool big = false}) {
    final r = rensi(context);
    final size = big ? 72.0 : 56.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: big ? r.accent : r.surface3,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon,
                color: big ? r.onAccent : Theme.of(context).colorScheme.onSurface,
                size: big ? 38 : 28),
          ),
        ),
      ),
    );
  }

  Widget _pillBtn(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: rensi(context).surface3,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }
}

/// Cuerpo del selector de pistas (audio/subtítulos). FIX-3: si la TV no responde
/// a `getTracks` (socket muerto en reconexión, o contenido sin pistas), el
/// spinner NO gira para siempre — tras un timeout muestra un estado vacío honesto
/// ("sin pistas") en vez de una rueda eterna.
class TrackSheetBody extends StatefulWidget {
  const TrackSheetBody({required this.audio});
  final bool audio;

  @override
  State<TrackSheetBody> createState() => TrackSheetBodyState();
}

class TrackSheetBodyState extends State<TrackSheetBody> {
  Timer? _timeout;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;
    final r = rensi(context);
    return Consumer<CastSenderController>(
      builder: (context, c, _) {
        final tracks = audio ? c.audioTracks : c.subtitleTracks;
        // Pistas llegaron → cancelar el timeout (por si un rebuild posterior).
        if (tracks.isNotEmpty && !_timedOut) _timeout?.cancel();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    audio ? context.loc.cast_audio : context.loc.cast_subtitles,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: AppThemes.bodySize,
                        fontWeight: FontWeight.bold)),
              ),
              if (!audio)
                ListTile(
                  leading: Icon(Icons.subtitles_off, color: r.text2),
                  title: Text(context.loc.cast_subtitles_off,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface)),
                  onTap: () {
                    c.selectSubtitle('');
                    Navigator.pop(context);
                  },
                ),
              if (tracks.isEmpty && !_timedOut)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: r.accent),
                ),
              if (tracks.isEmpty && _timedOut)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20),
                  child: Text(context.loc.no_tracks_available,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: r.text3)),
                ),
              for (final t in tracks)
                ListTile(
                  leading: Icon(
                      t.selected ? Icons.check : Icons.circle_outlined,
                      color: t.selected ? r.accent : r.text3),
                  title: Text(t.label,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface)),
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
    );
  }
}
