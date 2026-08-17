// Foreground service del EMISOR de casting (móvil = control de la TV).
//
// PROBLEMA que resuelve: al castear, el video corre en la TV pero la conexión
// de CONTROL (wss) vive en el proceso de la app. Al cambiar de app o apagar la
// pantalla, Android congela/mata el proceso → se cae el control → el ciclo de
// reconexión puede reiniciar la TV. Un foreground service mantiene VIVO el
// proceso (+ WakeLock/WifiLock → CPU y wifi vivos con la pantalla apagada), y de
// paso muestra la notificación persistente con controles que pidió el usuario.
//
// Tipo de FGS: `dataSync` (declarado en AndroidManifest). NO se usa
// `mediaPlayback` (exige una MediaSession reproduciendo local, que aquí no hay)
// ni `connectedDevice` (exige una asociación de companion device BT/USB); ambos
// podrían impedir arrancar el servicio en Android 14/15. `dataSync` arranca sin
// esos requisitos; su cap de 6h/sesión es de sobra para castear y se resetea al
// traer la app al frente.
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point del ISOLATE del FGS (top-level + vm:entry-point). Se limita a
/// reenviar al isolate principal (donde vive el CastSenderController) los taps de
/// los botones de la notificación; toda la lógica de cast está en el principal.
@pragma('vm:entry-point')
void castForegroundTaskEntry() {
  FlutterForegroundTask.setTaskHandler(_CastTaskHandler());
}

class _CastTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
  @override
  void onNotificationButtonPressed(String id) =>
      FlutterForegroundTask.sendDataToMain(id);
  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

/// IDs de las acciones de la notificación (compartidos con el bridge).
class CastFgAction {
  static const playPause = 'playpause';
  static const stop = 'stop';
}

class CastForegroundService {
  CastForegroundService._();

  static bool _inited = false;

  /// Handler de los botones de la notificación ('playpause'|'stop') → lo cablea
  /// el bridge para rutearlos al CastSenderController.
  static void Function(String id)? onAction;

  /// Init idempotente (llamar una vez al arranque, en main).
  static void init() {
    if (_inited) return;
    _inited = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is String) onAction?.call(data);
    });
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rensi_cast',
        channelName: 'Casting',
        channelDescription: 'Se muestra mientras envías contenido a la TV',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // Alcance elegido por el usuario: mantener vivo aun con pantalla apagada.
        allowWakeLock: true, // CPU vivo (evita que Doze congele los timers)
        allowWifiLock: true, // wifi vivo → la conexión LAN no se corta
        autoRunOnBoot: false,
        allowAutoRestart: false,
        // NOTA (verificado en el nativo del plugin): el "matar el FGS al quitar
        // la app de recientes" —para no dejar WakeLock/WifiLock zombis— se hace
        // SOLO por el atributo `android:stopWithTask="true"` del manifest. La
        // opción Dart homónima NO se usa a propósito: instala TrackVisibilityUtils,
        // que apaga el FGS en CADA background/pantalla-apagada → anularía el
        // keep-alive que es justo el propósito de esta feature.
      ),
    );
  }

  static List<NotificationButton> _buttons(
          bool playing, String playLabel, String pauseLabel, String stopLabel) =>
      [
        NotificationButton(
            id: CastFgAction.playPause, text: playing ? pauseLabel : playLabel),
        NotificationButton(id: CastFgAction.stop, text: stopLabel),
      ];

  /// Arranca (o actualiza si ya corre) el FGS con el estado de cast actual.
  /// Best-effort: cualquier fallo del plugin no debe romper el casting.
  static Future<void> startOrUpdate({
    required String title,
    required String text,
    required bool playing,
    required String playLabel,
    required String pauseLabel,
    required String stopLabel,
  }) async {
    init();
    try {
      final buttons = _buttons(playing, playLabel, pauseLabel, stopLabel);
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
          notificationButtons: buttons,
        );
        return;
      }
      // Permiso de notificación (Android 13+). Si se niega, el FGS igual mantiene
      // vivo el proceso — solo que sin la notificación visible.
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      // Nota: el plugin NO lanza en fallo de arranque; devuelve un
      // ServiceRequestResult. Se loguea para diagnóstico (best-effort: un fallo
      // de arranque NO debe romper el casting, solo se pierde el keep-alive).
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        notificationButtons: buttons,
        callback: castForegroundTaskEntry,
      );
      if (result is ServiceRequestFailure && kDebugMode) {
        debugPrint('CastForegroundService.startService falló: ${result.error}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CastForegroundService.startOrUpdate: $e');
    }
  }

  /// Retira el FGS + la notificación (y suelta WakeLock/WifiLock). Idempotente.
  static Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CastForegroundService.stop: $e');
    }
  }
}
