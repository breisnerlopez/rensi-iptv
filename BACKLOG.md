# Backlog — ideas y mejoras pendientes

Ideas no comprometidas todavía; se priorizan aparte.

## Casting / segunda pantalla
- **Punto de envío ANTES de abrir el reproductor** (evitar gastar datos): ofrecer
  "Enviar a la TV" desde la pantalla de detalle (película/serie) y desde la lista
  de canales en vivo, para castear sin cargar el stream en el móvil. Ver la
  discusión de UX en la conversación (el botón dentro del player obliga a cargar
  el contenido antes de poder enviarlo).
- **Recordatorio "abre la app IPTV en tu TV"** al iniciar un envío (la app debe
  estar abierta en el televisor para recibir).
- **Foreground service en el receptor Android TV**: mantener el receptor vivo con
  la app en segundo plano / cerrada, y traerla al frente al recibir un envío
  (comportamiento "tipo Cast Connect" sin depender de Google Play). Notificación
  persistente + auto-open al LOAD.

## Marca / identidad
- **Mascota de la app**: crear una mascota, estilo **pixel-art**, al estilo de
  Claude (Anthropic). Usable como banner de Android TV, icono de "esperando
  contenido" en la pantalla del receptor, estados vacíos y onboarding.

## Distribución
- Publicación en Google Play de la app (resolver mismatch de firma + política
  IPTV) — habilitaría además Cast Connect real. Ver `CASTING_ARCHITECTURE.md`.
