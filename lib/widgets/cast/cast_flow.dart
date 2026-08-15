// UI del flujo de casting (lado móvil): botón "Enviar a la TV" y el modal que
// guía descubrir → elegir TV → emparejar por PIN → (error/reintentar). Cuando
// el emparejamiento termina, el modal se cierra y el player muestra la pantalla
// de control (casting_screen.dart). Todo reactivo al CastSenderController.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cast_sender_controller.dart';
import '../../database/database.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/localization_extension.dart';
import '../../redesign/rensi_widgets.dart';
import '../../services/download_service.dart';
import '../../utils/app_themes.dart';

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
    backgroundColor: rensi(context).surface2,
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
  // Feature H — consentimiento contextual de persistencia standalone. Solo se
  // pregunta cuando el permiso maestro está activo y es la PRIMERA vez que se
  // castea VOD/serie Xtream a esta (TV, proveedor) sin consentimiento previo
  // (lo decide el controlador). NO bloquea el casting: ya está en curso; el
  // consentimiento solo habilita que la TV guarde las credenciales.
  if (context.mounted && controller.isCasting) {
    await _maybePromptStandaloneConsent(context, controller);
  }
}

/// Muestra, si procede, el diálogo de consentimiento para que la TV guarde las
/// credenciales del proveedor (reproducción standalone). Divulga honestamente el
/// riesgo residual (extracción en una TV con root/comprometida; el emparejamiento
/// por PIN no resiste a un atacante que capture el emparejamiento). Al aceptar,
/// registra el consentimiento (StandaloneConsentStore) vía el controlador, que
/// además reenvía el LOAD para persistir ya en esta sesión.
Future<void> _maybePromptStandaloneConsent(
    BuildContext context, CastSenderController controller) async {
  final prompt = await controller.pendingStandaloneConsent();
  if (prompt == null || !context.mounted) return;
  final loc = context.loc;
  final device =
      prompt.deviceName.isNotEmpty ? prompt.deviceName : loc.cast_to_tv;
  final provider = prompt.providerName.isNotEmpty ? prompt.providerName : '—';
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(loc.tv_standalone_consent_title(device)),
      content: Text(loc.tv_standalone_consent_body(provider)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: Text(loc.tv_standalone_consent_decline),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: rensi(context).accent),
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: Text(loc.tv_standalone_consent_accept),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await controller.grantStandaloneConsent(prompt.tvId, prompt.providerId);
  }
}

/// Inicia el envío a la TV de un archivo LOCAL ya descargado (streaming por la
/// LAN, sin gastar Internet). Reusa el mismo modal guiado que [startCastFlow].
Future<void> startLocalFileCastFlow(
  BuildContext context, {
  required String filePath,
  required String contentId,
  required String title,
  String ext = '',
  List<CastMedia>? queue,
  int index = 0,
}) async {
  final controller = context.read<CastSenderController>();
  if (controller.isCasting) return;
  controller.castLocalFile(
    filePath: filePath,
    contentId: contentId,
    title: title,
    ext: ext,
    queue: queue,
    index: index,
  );
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: rensi(context).surface2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChangeNotifierProvider<CastSenderController>.value(
      value: controller,
      child: const _CastSheet(),
    ),
  );
  if (!controller.isCasting && controller.phase != CastPhase.idle) {
    controller.cancel();
  }
}

/// Arma la cola de casting para una descarga [tapped]: los episodios DESCARGADOS
/// hermanos (misma serie) en orden temporada/episodio, cada uno como `CastMedia`
/// de archivo con su `localFilePath` y `isDownloadedSeries: true`, para que la TV
/// auto-avance al terminar cada uno. Devuelve `(queue, index)` donde `index`
/// apunta al episodio tocado. Para una película, o una serie con un solo
/// episodio descargado, devuelve `(null, 0)` → cast de archivo único que se
/// detiene al final (comportamiento sin cambios). Compartido por la pantalla de
/// descargas y la coexistencia móvil↔TV del reproductor.
Future<(List<CastMedia>?, int)> buildDownloadedSeriesQueue(
  Download tapped,
) async {
  final siblings =
      await DownloadService.instance.siblingDownloadedEpisodes(tapped);
  if (siblings.length < 2) return (null, 0);
  final queue = [
    for (final d in siblings)
      CastMedia(
        channelId: d.contentId,
        contentType: 'file',
        title: d.title,
        ext: d.ext ?? '',
        imagePath: d.imagePath,
        localFilePath: d.filePath,
        isDownloadedSeries: true,
      ),
  ];
  var index = siblings.indexWhere((d) => d.id == tapped.id);
  if (index < 0) index = 0;
  return (queue, index);
}

class _CastSheet extends StatefulWidget {
  const _CastSheet();
  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  final _pinCtrl = TextEditingController();
  bool _popScheduled = false; // el auto-cierre se programa UNA sola vez

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
        // En cuanto empieza a transmitir, cerrar el modal (el control pasa al
        // player). Una sola vez: el builder del Consumer se re-ejecuta en cada
        // notifyListeners (p. ej. al llegar las pistas) y sin este guard se
        // programaría otro pop dentro de la animación de salida → se cerraría
        // también la pantalla del reproductor (over-pop).
        if (c.isCasting && !_popScheduled) {
          _popScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.canPop(context)) Navigator.pop(context);
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
                    // Tokenized: white24 was invisible on the light-theme sheet
                    // surface (surface2 is a light beige in light mode).
                    color: rensi(context).hairline2,
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
              leading: Icon(Icons.tv, color: rensi(context).accent),
              title: Text(d.name,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              subtitle: Text(d.host,
                  style: TextStyle(color: rensi(context).text3, fontSize: AppThemes.labelSize)),
              onTap: () => c.connectTo(d),
            ),
        ];
      case CastPhase.pairing:
        return _pairingBody(context, c, loc);
      case CastPhase.error:
        final msg = switch (c.error) {
          'no_devices' => loc.cast_no_devices,
          // Archivo local sin Wi‑Fi: la TV no puede alcanzar la URL de la LAN.
          'no_wifi' => loc.cast_need_wifi,
          _ => loc.cast_error,
        };
        return [
          _status(msg, icon: Icons.tv_off),
          const SizedBox(height: 16),
          _primaryButton(loc.cast_retry, c.retry),
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
          style: TextStyle(color: rensi(context).text2, fontSize: AppThemes.bodySmallSize)),
      const SizedBox(height: 16),
      TextField(
        controller: _pinCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofocus: true,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: AppThemes.h2Size,
            letterSpacing: 10,
            fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: '',
          errorText: c.wrongPin ? loc.cast_wrong_pin : null,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: rensi(context).hairline2),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: rensi(context).accent, width: 2),
          ),
        ),
        onSubmitted: (v) => c.submitPin(v.trim()),
      ),
      const SizedBox(height: 16),
      _primaryButton(loc.cast_pair, () => c.submitPin(_pinCtrl.text.trim())),
    ];
  }

  Widget _title(String t) => Text(t,
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: AppThemes.h3Size,
          fontWeight: FontWeight.bold));

  Widget _status(String text, {bool spinner = false, IconData? icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            if (spinner)
              CircularProgressIndicator(color: rensi(context).accent)
            else if (icon != null)
              Icon(icon, color: rensi(context).text3, size: 48),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: rensi(context).text2, fontSize: AppThemes.bodySmallSize)),
          ],
        ),
      );

  Widget _primaryButton(String label, VoidCallback onTap) => SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: rensi(context).accent),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}
