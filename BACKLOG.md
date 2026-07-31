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

## Casting / TV — feedback en dispositivo real (2026-07-31)
Reportado probando en la caja de TV + móvil reales (el casting NO es reproducible en emulador).

- **[EN CURSO] Primer intento de reproducción en la TV se cuelga** en "Preparando…"
  (visto hasta 36s) SIN lanzar error; el botón **Reintentar** (que llama a
  `_reopenCurrent`, saltándose toda la preparación de `_initializePlayer`) **casi
  siempre funciona a la 2ª**. → La preparación previa (config subtítulos / background /
  historial / cola de audio) tiene un `await` que cuelga solo la 1ª vez en esa caja.
  Fix: timeout por cada await de la preparación para que ninguno bloquee el arranque.
- **Al reproducir y dar ATRÁS vuelve al contador "Preparando…"** — como si la ventana
  de preparación quedara detrás del reproductor (fuga de estado/overlay). Investigar.
- **No hay info de lo que se reproduce en la TV**: al pulsar OK / pausar / dar play
  debería salir la **barra de reproducción** + **título** (ahora no se ve nada).
- **Info rica al pausar/reproducir**: mostrar **título + sinopsis + reparto (actores)
  + info relevante** de la película (reutilizar el detalle TMDb).
- **El contenido casteado NO aparece en el histórico** de la pantalla principal de la
  TV (`TvReceiverHome`). Revisar bajo qué playlistId/streamId guarda la TV su historial.
- **Mostrar la versión de la app en la TV** (`TvReceiverHome`).
- **Búsqueda (móvil): "Reproducir desde" no reproduce** — cuando el contenido está en
  más de una lista, el detalle de búsqueda muestra las listas (incluso "LopezCueto3"
  DUPLICADA) pero al seleccionar una **no pasa nada** (no reproduce ni navega).

## Búsqueda / historial / series / navegación — feedback (2026-07-31, cont.)
- **Búsqueda por primera palabra falla**: "Rick" NO encuentra "Rick y Morty", pero
  "morty" SÍ. La coincidencia por el primer token del título multi-palabra falla.
  Revisar el matching (¿prefijo/token/orden?).
- **Historial en AMBOS dispositivos**: el contenido enviado a la TV debe aparecer en
  el histórico de reproducción de la TV Y del móvil (reiterado; ver también v2.10.0
  cast→continuar-viendo — el usuario no lo ve).
- **Series por cast — continuación de episodios (DECISIÓN DE DISEÑO)**: al castear una
  serie, ¿el siguiente episodio se envía automático o manual? Evaluar la mejor UX
  factible (autoplay del siguiente en la TV vs control manual desde el móvil).
- **"Ver todo" / cuadrícula (DECISIÓN DE DISEÑO, pide especialista UX)**: el carrusel
  horizontal sirve, pero con muchos ítems preferir una **cuadrícula completa** vía
  "Ver todos" (o una flechita a la derecha), INCLUYENDO las reproducciones recientes.
  Evaluar con especialista en experiencia/diseño.
