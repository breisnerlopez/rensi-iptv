# Backlog — ideas y mejoras pendientes

Ideas no comprometidas todavía; se priorizan aparte.

## Casting / segunda pantalla
- **Punto de envío desde el detalle/lista** (además del gate previo, ya hecho en
  v2.8.2): ofrecer "Enviar a la TV" también en la pantalla de detalle
  (película/serie) y en la lista de canales, para castear sin abrir el player.
- **Foreground service en el receptor Android TV**: mantener el receptor vivo con
  la app en segundo plano / cerrada, y traerla al frente al recibir un envío
  (comportamiento "tipo Cast Connect" sin depender de Google Play). Notificación
  persistente + auto-open al LOAD.

## Reproducción / conexiones lentas
- **Pre-buffer inteligente (mostrar carga + esperar/forzar):** pantalla que
  muestra velocidad de descarga, buffer acumulado y estado (cargando / listo /
  lento / sin datos), auto-inicia al haber colchón suficiente y permite forzar.
  Núcleo de decisión ya implementado y probado: `lib/utils/pre_buffer_monitor.dart`
  (heurística por fill-rate; "listo" = buffer ≥ meta). **Pendiente:** que libmpv
  PREFETCHE mientras retiene el video — abrir en pausa NO lee la red (verificado:
  `demuxer-cache-duration`/`cache-speed` quedan en 0). Solución: `cache-pause=yes`
  + `cache-pause-initial=yes` + `cache-pause-wait=<meta>` (fijados ANTES del open,
  cuidando la carrera con `_tuneForPerformance` que hoy pone `cache-pause=no`), y
  subir `demuxer-max-bytes` a un límite grande (idea del usuario) para más colchón.
  UI ya diseñada; para cast, la TV reporta las métricas por el canal de control.
  **Hallazgo (bloqueo actual):** el enfoque por `NativePlayer.setProperty`/`getProperty`
  en runtime NO funciona en este media_kit pineado — `demuxer-cache-duration`,
  `cache-speed` y `demuxer-cache-state` devuelven cadena VACÍA, y fijar
  `cache-pause-initial`/`cache-pause=yes` antes del open ROMPE la carga (el
  demuxer no arranca: `state.buffer`/`position` quedan en 0). Camino a explorar:
  pasar opciones mpv al CREAR el Player (`PlayerConfiguration`), u observar el
  buffer por la API nativa de media_kit (`player.stream.buffer`/`bufferingPercentage`)
  en vez de getProperty, o parchear media_kit. Nota de pruebas: el emulador de
  teléfono (phone_compact) no reproduce streams; validar en el emulador TV o en
  hardware real.
- **Descarga offline (VOD/series):** descargar el contenido completo al
  dispositivo para verlo sin conexión (gestor de descargas: almacenamiento,
  reanudar, gestión de espacio, UI). Feature separada del pre-buffer.

## Marca / identidad
- **Mascota de la app**: crear una mascota, estilo **pixel-art**, al estilo de
  Claude (Anthropic). Usable como banner de Android TV, icono de "esperando
  contenido" en la pantalla del receptor, estados vacíos y onboarding.

## Distribución
- Publicación en Google Play de la app (resolver mismatch de firma + política
  IPTV) — habilitaría además Cast Connect real. Ver `CASTING_ARCHITECTURE.md`.
