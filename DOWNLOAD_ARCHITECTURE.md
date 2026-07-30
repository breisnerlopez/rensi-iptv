# Descargas / Offline — Documento de Arquitectura

**Proyecto:** rensi_iptv (Flutter, v2.8.3)
**Objetivo:** poder **dejar contenido descargándose y verlo**, con manejo de espacio y **borrado al terminar de verlo**.
**Estado:** Etapa 1. **Pasó por gate adversarial (retador Opus + auditor Opus con verificación web de ToS y precios).** El gate cambió la recomendación: ver §6.

> **Conclusión de una línea:** construir **solo A (descarga en el dispositivo)**, reformulando su encuadre legal; **NO** construir el rehospedaje a nube de terceros (Google Drive/R2/Wasabi/B2/…) ni "privado" — viola el ToS al **almacenar** y arriesga baneo + hace al operador infractor directo. Si se quiere algo tipo servidor, **solo autohospedaje en hardware propio**. Y evaluar antes si con el **pre-buffer ya hecho + catch-up del proveedor** basta y no hay que descargar nada.

---

## 1. Anclas del estado actual (del código)

| Hecho | Implicación |
|---|---|
| VOD/series como archivo: `{url}/movie/{u}/{p}/{id}.{ext}` (`lib/utils/build_media_url.dart`) | Descargable por HTTP, **pero la extensión puede ser null/obsoleta** → el panel devuelve **HTML de error** (el código ya lo sortea con `kVodExtensionCandidates=['mp4','mkv','avi']` + `swapUrlExtension`). Un descargador debe reusar eso y **detectar que bajó una página de error**, no vídeo. |
| Contenedor mp4/mkv trae audio+subs **muxed** | Cierto **solo** para mp4/mkv. **Fuera de alcance:** proveedores HLS-only/`.m3u8`/`.ts` sin archivo directo, y DRM. |
| **Live** = stream continuo | No descargable; offline = solo VOD/series. |
| `max_connections` metadato sin lógica; `active_cons` **no fiable** en tiempo real (medido en CASTING §12) | Una descarga = 1 slot. El conteo propio **solo ve las conexiones de este dispositivo**, no otras sesiones de la cuenta → el uso real de slots es desconocido. |
| `watch_history_service` (`watchDuration`/`totalDuration`) | Base para "visto", **pero `totalDuration` puede ser poco fiable** en archivo parcial/remoto → no basta para un borrado destructivo. |
| **No hay backend propio** | Cualquier variante "servidor" es un componente nuevo. |
| media_kit reproduce archivos locales y URLs | Reproducir offline/servidor es trivial en el player. |

---

## 2. Camino A — Descarga en el dispositivo (RECOMENDADO, con matices)

### 2.1 Arquitectura
- Motor: `background_downloader` (Android/iOS, background, Range/reanudar, notificación). **Caveat iOS:** iOS limita/mata descargas largas en background → en iOS puede requerir mantener la app viva o trocear; no asumir paridad con Android.
- `DownloadService` + tabla Drift `Downloads` (id, contentId, tipo, ruta, bytes, total, estado, addedAt, watched). URL vía `buildMediaUrl`; guardar en dir de la app.
- UI: sección "Descargas" (progreso, pausa/cancelar), botón en detalle de peli/episodio, badge "offline". Reproducir = ruta local en el `PlayerWidget`.

### 2.2 Robustez (correcciones del gate)
- **Extensión null/obsoleta:** reusar `kVodExtensionCandidates`; tras descargar, **verificar que el archivo es media y no una página HTML de error** (magic bytes / content-type / probe), y reintentar con otra extensión.
- **Range:** algunos servidores Xtream **ignoran Range** → detectar (respuesta 200 en vez de 206) y, si no hay Range, **reanudar = reiniciar** o marcar "no reanudable", nunca concatenar bytes corruptos.
- **Reproducir a medio bajar:** solo permitir play offline con la descarga **completa y verificada** (evitar archivos truncados).
- **Tipos fuera de alcance:** declarar explícitamente que HLS-only/DRM no se descargan (mensaje claro al usuario).

### 2.3 Espacio y borrado (política acordada, endurecida)
- **Borrar al ver:** **opt-in explícito** (no por defecto silencioso) y **con papelera reversible** (o confirmación) — el borrado es destructivo y `totalDuration` no es 100% fiable. Marcar "visto" a ~95% pero **no destruir sin validar** la duración.
- **Tope de espacio** configurable. Realista: una peli HD son **4-8 GB** (15-40 GB en 4K) → 10 GB ≈ **1-2 películas**; presentar el tope con ese contexto y purga LRU de lo no-visto + aviso.

### 2.4 Límites / sesiones simultáneas
- Máx. 1 descarga activa; encolar. No iniciar si al reproducir en vivo se llegaría al tope. **Limitación honesta:** el conteo propio no ve otras sesiones/dispositivos de la cuenta; el proveedor puede **truncar/throttlear/banear silenciosamente** en vez de dar un error limpio → tratar respuestas anómalas (truncamiento, 4xx/5xx, corte) como fallo y no reintentar en bucle.

### 2.5 Legal (reformulado por el gate)
**A NO es "lícito" per se.** La defensa de copia privada/time-shift **asume fuente lícita**; si el proveedor Xtream no tiene licencia, descargar es **reproducción de una copia infractora**, se borre o no. La ventaja real de A es que es **menos expuesto** que B: efímero, sin violar ToS de terceros, sin exponer una cuenta a terminación, sin convertir a nadie en distribuidor/operador. Encuadre correcto: **A = menor exposición, no legalidad**.

### 2.6 Esfuerzo / riesgos
- Esfuerzo: **medio** (~2–3 semanas con la robustez del §2.2). Costo: **$0**. Riesgo técnico: medio (gotchas §2.2). Riesgo legal: el inherente a la fuente (§2.5).

---

## 3. Camino B — Servidor → nube de terceros (**BLOQUEADO por el gate**)

**FALLO del auditor: BLOQUEADO.** Verificado contra ToS reales (2026-07-30):
- **Wasabi** y **Backblaze B2** prohíben literalmente el **"storage/storing"** de contenido con copyright sin derechos (no solo compartir); **Google Workspace/One** escanea y limita incluso privados; **Cloudflare R2** exige garantía de no-infracción. Todos contemplan **terminación de cuenta**. → **La infracción/incumplimiento ocurre al ALMACENAR/SUBIR, antes de compartir.** Las "salvaguardas" del plan original (URL firmada, no compartir) mitigan el eje equivocado.
- En B, el **operador del servidor** fija/sube/sirve las copias = **infractor directo** (salto de riesgo cualitativo sobre A), y expone una cuenta identificable a un tercero que escanea y termina.
- **Incoherencia de fondo:** si el uso es efímero (ver-y-borrar), **no hace falta rehospedar** — un servidor puede **proxy-stream directo** del IPTV sin subir nada. El rehospedaje a nube solo aporta para una **biblioteca persistente**, que es justo el caso de **máximo costo de retención Y máxima exposición**. B se justifica solo donde más daña.

**Única vía de "B" aceptable-con-condiciones:** **autohospedaje en hardware propio del usuario** (NAS/mini-PC/VPS de disco propio), sin object-storage de terceros, sin URLs compartidas, un solo dueño. Aun así subsiste el riesgo de reproducción-desde-fuente-infractora. **No** se construye rehospedaje a Google Drive/R2/Wasabi/B2/Storj.

### 3.1 Costos (corregidos + datados, 2026-07-30) — para contexto
| Proveedor | Real (2026-07-30) | Caveat para "ver y borrar" |
|---|---|---|
| Cloudflare R2 | $15/TB-mo, **egress $0**, ops despreciables para video | Mejor para efímero (sin retención mínima; storage prorrateado). |
| Backblaze B2 | $6/TB-mo, egress libre vía Cloudflare | Bien; sin mínimos. |
| **Wasabi** | $6.99/TB-mo | ❌ **Trampa:** retención mínima **90 días/objeto** + mínimo **1 TB/mes** → pagas 90 días por una peli borrada en horas. |
| **Storj** | **$6–15/TB-mo** + **egress $7/TB** (nuevo pricing nov-2025; ya NO $4/TB) | Egress por cada visionado; peor para reproducir. |
| Google One 2TB | $9.99/mes | ToS prohíbe rehospedar copyright → baneo. |
| **NAS/hardware propio** | ~$0/mes recurrente | La única vía "B" no bloqueada (autohospedaje). |
Fuentes: páginas de precios oficiales R2/Wasabi/B2/Storj/Google + AUP de Wasabi/B2/Google (consultado 2026-07-30). "Mucho espacio en nube muy barato para video" **no es realista** en nube de terceros para este patrón; y encima está bloqueado por ToS.

---

## 4. Alternativa: NO descargar (evaluar primero)
El gate exige considerar la opción más simple:
- **Pre-buffer ya implementado (v2.8.3):** para "dejar y ver sin cortes", el pre-buffer + un colchón mayor puede bastar sin archivos ni gestión de espacio.
- **Catch-up / timeshift del proveedor:** muchos paneles Xtream exponen archivo/catch-up nativo (`/timeshift/...`) → ver contenido pasado sin descargar nada. **Verificar si el proveedor lo ofrece** antes de construir descargas.
- Si lo que se busca es **offline real (sin internet)**, entonces sí hace falta A.

---

## 5. Recomendación
1. **Verificar primero** si el pre-buffer + catch-up del proveedor cubren la necesidad (§4). Si sí → no construir descargas.
2. Si se necesita **offline real** → construir **A** con la robustez del §2.2–2.4 y el borrado **opt-in/reversible** del §2.3, y el encuadre legal honesto del §2.5.
3. **NO construir** el rehospedaje a nube de terceros (§3, bloqueado). Si el usuario insiste en "servidor", **solo autohospedaje en su propio hardware**, documentando el riesgo residual.

---

## 6. Registro del gate adversarial
- **Retador (Opus):** RECHAZADO. Fallos: URL VOD no es archivo fiable (extensión null → HTML de error; HLS/DRM fuera); "personal/privado = zona gris" es racionalización con contradicción interna; costos sin fuente/fecha + choque Wasabi/rotación; borrar-al-ver destructivo sobre señal no validada; conteo de slots no cubre multi-dispositivo; A sobrevendido; faltan alternativas (no-descargar/catch-up).
- **Auditor (Opus, verificado web):** **B BLOQUEADO** — Wasabi/B2/Google/R2 prohíben **almacenar** copyright (no solo compartir) con terminación de cuenta; copia-privada asume fuente lícita; B hace al operador infractor directo. Costos corregidos: **Storj ya no $4/TB (es $6-15 + egress $7)**; **Wasabi trampa por retención 90 días**; R2/B2 mejores para efímero; para efímero **no se necesita nube** (proxy directo). A = **menos expuesto, no lícito**.
- **Integración (principal):** este documento descarta el rehospedaje a nube de terceros, reformula el encuadre legal de A, endurece borrado/robustez/costos, y añade la alternativa "no descargar".

## 7. Decisiones abiertas
1. ¿Tu proveedor ofrece **catch-up/timeshift**? (Lo verifico rápido contra tu panel — puede evitar construir descargas.)
2. ¿El objetivo es **offline real sin internet** (→ A) o solo "dejar y ver fluido" (→ quizá basta el pre-buffer)?
3. Si algún día "servidor": ¿tienes **hardware propio** (NAS/mini-PC) para autohospedaje? (Única vía no bloqueada.)
