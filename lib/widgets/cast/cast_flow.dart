// UI del flujo de casting (lado móvil): botón "Enviar a la TV" y el modal que
// guía descubrir → elegir TV → emparejar por PIN → (error/reintentar). Cuando
// el emparejamiento termina, el modal se cierra y el player muestra la pantalla
// de control (casting_screen.dart). Todo reactivo al CastSenderController.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/localization_extension.dart';

const _accent = Color(0xFFD2603A);

/// Botón de casting para la barra del reproductor. Cambia de icono según si ya
/// se está transmitiendo.
class CastButton extends StatelessWidget {
  const CastButton({
    super.key,
    required this.media,
    this.queue,
    this.index = 0,
    this.color = Colors.white,
  });

  /// Qué contenido castear al pulsar (canal/película/episodio actual).
  final CastMedia media;

  /// Catálogo para el zapping (canales de la categoría, episodios…). Opcional.
  final List<CastMedia>? queue;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final casting = context.select<CastSenderController, bool>((c) => c.isCasting);
    return IconButton(
      tooltip: context.loc.cast_to_tv,
      icon: Icon(casting ? Icons.cast_connected : Icons.cast, color: color),
      onPressed: () => startCastFlow(context, media, queue: queue, index: index),
    );
  }
}

/// Inicia el descubrimiento y abre el modal guiado. No hace nada si ya se está
/// transmitiendo (en ese caso el control vive en el player).
Future<void> startCastFlow(BuildContext context, CastMedia media,
    {List<CastMedia>? queue, int index = 0}) async {
  final controller = context.read<CastSenderController>();
  if (controller.isCasting) return;
  controller.beginCast(media, queue: queue, index: index);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF15151A),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChangeNotifierProvider<CastSenderController>.value(
      value: controller,
      child: const _CastSheet(),
    ),
  );
  // Si el usuario cerró el modal a media sesión (sin llegar a casting), limpiar.
  if (!controller.isCasting && controller.phase != CastPhase.idle) {
    controller.cancel();
  }
}

class _CastSheet extends StatefulWidget {
  const _CastSheet();
  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  final _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Consumer<CastSenderController>(
      builder: (context, c, _) {
        // En cuanto empieza a transmitir, cerrar el modal (el control pasa al player).
        if (c.isCasting) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
        }
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ..._bodyFor(context, c, loc),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _bodyFor(BuildContext context, CastSenderController c, AppLocalizations loc) {
    switch (c.phase) {
      case CastPhase.discovering:
        return [_status(loc.cast_searching, spinner: true)];
      case CastPhase.connecting:
        return [_status(loc.cast_connecting, spinner: true)];
      case CastPhase.devicesFound:
        return [
          _title(loc.cast_choose_device),
          const SizedBox(height: 8),
          for (final d in c.devices)
            ListTile(
              leading: const Icon(Icons.tv, color: _accent),
              title: Text(d.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(d.host,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () => c.connectTo(d),
            ),
        ];
      case CastPhase.pairing:
        return _pairingBody(context, c, loc);
      case CastPhase.error:
        return [
          _status(
              c.error == 'no_devices' ? loc.cast_no_devices : loc.cast_error,
              icon: Icons.tv_off),
          const SizedBox(height: 16),
          _primaryButton(loc.cast_retry, () {
            if (c.media != null) c.beginCast(c.media!);
          }),
        ];
      case CastPhase.idle:
      case CastPhase.casting:
        return [_status(loc.cast_connecting, spinner: true)];
    }
  }

  List<Widget> _pairingBody(BuildContext context, CastSenderController c, AppLocalizations loc) {
    return [
      _title(c.device?.name ?? loc.cast_to_tv),
      const SizedBox(height: 8),
      Text(loc.cast_enter_pin,
          style: const TextStyle(color: Colors.white70, fontSize: 15)),
      const SizedBox(height: 16),
      TextField(
        controller: _pinCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofocus: true,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 30, letterSpacing: 10, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: '',
          errorText: c.wrongPin ? loc.cast_wrong_pin : null,
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _accent, width: 2),
          ),
        ),
        onSubmitted: (v) => c.submitPin(v.trim()),
      ),
      const SizedBox(height: 16),
      _primaryButton(loc.cast_pair, () => c.submitPin(_pinCtrl.text.trim())),
    ];
  }

  Widget _title(String t) => Text(t,
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold));

  Widget _status(String text, {bool spinner = false, IconData? icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            if (spinner)
              const CircularProgressIndicator(color: _accent)
            else if (icon != null)
              Icon(icon, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
      );

  Widget _primaryButton(String label, VoidCallback onTap) => SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}
