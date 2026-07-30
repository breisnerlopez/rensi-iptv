# Casting a Android TV / Google TV — Documento de Arquitectura

**Proyecto:** rensi_iptv (Flutter, v2.7.0)
**Objetivo:** el móvil actúa como **control remoto**; el televisor reproduce el contenido IPTV **directamente desde el servidor**. Sin mirroring de pantalla, sin retransmitir el video desde el móvil.
**Estado del documento:** Etapa 1 — arquitectura y recomendación. **Pasó por gate adversarial (retador Opus + auditor Opus).** Veredicto: NO comprometer la arquitectura completa hoy; ejecutar una fase de spikes de de-risking y cerrar el gate de Play primero. Ver §11 (registro del gate) y §9 (decisiones pendientes). El PoC (entregable 5) se especifica en §8.

---

## 1. Contexto y estado actual (anclado en el código)

Lo que hoy existe y condiciona el diseño:

| Área | Estado actual | Ref. |
|---|---|---|
| Motor de reproducción | `media_kit` (libmpv por debajo). Afinado para TV boxes Amlogic (`vo: mediacodec_embed`, `hwdec: mediacodec`). Buffer 64 MiB. | `lib/widgets/player_widget.dart:160,477` |
| Autenticación Xtream | Solo **user + password**. NO hay token/JWT/sesión. Auth = user+pass en cada request. | `lib/models/api_configuration_model.dart:1` |
| Almacenamiento de secretos | `flutter_secure_storage` cifrado; la DB guarda la playlist **sin** secretos. | `lib/services/playlist_secrets_service.dart:6` |
| **URLs de stream** | user y password van **en el path** de cada URL. Live: `{url}/{user}/{pass}/{id}` (sin extensión). VOD: `{url}/movie/{user}/{pass}/{id}.{ext}`. Series: `{url}/series/{user}/{pass}/{id}.{ext}`. | `lib/utils/build_media_url.dart:6` |
| Fuga de credenciales ya asumida | Existe `credential_scrubber.dart` para enmascarar user/pass en logs/UI. `main.dart:45` ya anota el riesgo "cast screen". | `lib/utils/credential_scrubber.dart` |
| Subtítulos / audio | Provienen de las pistas **embebidas** que expone libmpv; **no** de la API Xtream. Preferencia de idioma persistida. | `player_widget.dart:694,711` |
| Resiliencia | Backoff exponencial (5 reintentos), watchdog de stall en live (15 s → reopen), auto-heal de extensión VOD (`mp4/mkv/avi`), reconexión por conectividad. **Todo en el cliente libmpv.** | `player_error_handler.dart`, `player_widget.dart:790,396` |
| Zapping | Reabre el stream completo (sin precarga), con debounce de 350 ms. | `player_widget.dart:864,1130` |
| Multi-proveedor | Sí. Playlist activa en `AppState.currentPlaylist`. | `lib/services/app_state.dart:7` |
| Límite de conexiones | `maxConnections`/`activeCons`/`allowedOutputFormats` (`["m3u8","ts","rtmp"]`) se guardan como **metadato informativo**; NO se aplica ninguna lógica. | `lib/database/database.dart:86-92` |
| Código de casting existente | **Ninguno.** Sin Cast SDK, DLNA, UPnP, discovery ni "enviar a TV". | (grep vacío) |
| **Distribución (contexto de negocio)** | La app **NO está en Google Play** por mismatch de firma + fricción de política IPTV. | `memory: play-store-status` |

**Cinco consecuencias de diseño que arrastramos:**

1. **La autenticación Xtream es intrínsecamente "user/pass en la URL".** No hay tokens nativos que emita el panel. Cualquier "token temporal" tendrá que fabricarlo **nuestra** infraestructura, no el proveedor.
2. **Toda la robustez de reproducción vive en libmpv en el cliente.** Un receptor externo (Web Receiver de Cast) **no hereda nada** de eso: habría que reescribir backoff, stall-watchdog, ext-heal, zapping en JS.
3. **libmpv reproduce lo que Cast nativo NO:** MPEG-TS crudo continuo, MPEG-2 video, AC-3/E-AC-3 audio — todos comunes en IPTV.
4. **La app ya es Flutter + media_kit corriendo en Android y afinada para TV.** Reutilizar ese player en el receptor de la TV es la palanca más grande del proyecto — **e es independiente del mecanismo de transporte** (Cast o propio).
5. **El casting a TV con Cast Connect reintroduce la dependencia de Google Play**, que es un bloqueo abierto del proyecto. Esto condiciona la elección de arquitectura más que cualquier detalle técnico de Cast.

---

## 2. Realidades de Google Cast + IPTV (lo que restringe las opciones)

Verificado contra docs oficiales de Google Cast (2025-2026):

- **El App ID del receiver es público.** No protege nada por sí mismo; viaja en el sender. Trátalo como público.
- **El Web Receiver (CAF) reproduce solo HLS, DASH y Smooth Streaming** (Shaka/MSE por debajo). **No reproduce un `.ts` continuo crudo** ni descarga progresiva fuera de esos tres frameworks. TS solo se reproduce **dentro de** HLS segmentado.
- **Codecs de Cast (por HW):** H.264, HEVC, VP9, AV1; audio AAC/Opus/FLAC/MP3. **MPEG-2 video y AC-3/E-AC-3/MP2 audio NO están soportados** por el receptor Cast estándar — y son frecuentes en canales IPTV/DVB.
- **CORS + HTTPS obligatorios** para un Custom Web Receiver. Muchos servidores Xtream no envían CORS.
- **Inyección de auth:** solo el receiver puede añadir headers HTTP. El sender NO puede forzar headers arbitrarios.
- **Cast Connect** lanza tu **app Android TV nativa** como receptor. **Verificado (auditor):** para lanzar esa app en dispositivos de usuario final **debe estar PUBLICADA en Google Play**; una app **sideloadeada NO se lanza** por Cast Connect (error `APP_NOT_INSTALLED_BY_WHITELISTED_INSTALLER`) y cae al Web Receiver. El sideload solo funciona en **test devices registrados** por serial en la Cast Console. → **Cast Connect = dependencia dura de Play.**
- **CredentialsData** (Cast Connect) viaja por el canal Cast sobre **TLS + device authentication** (sólido en tránsito), pero **no es E2E criptográfico de aplicación**: el SDK del dispositivo lo descifra y lo entrega a la app TV. Si `LaunchRequestChecker` rechaza, cae al Web Receiver.
- **Flutter sender:** no hay plugin oficial de Google. El más maduro es **`flutter_chrome_cast`** (iOS+Android). Para `CredentialsData`/Cast Connect completo probablemente haya que escribir platform channels sobre los SDK nativos.
- **media_kit/libmpv como player del receptor:** viable — Cast Connect exige un `MediaSession`, pero se puede **alimentar manualmente** desde cualquier player (ExoPlayer solo lo automatiza vía `MediaSessionConnector`). No hay implementación pública conocida de libmpv+Cast Connect → es un **spike genuino**, no un imposible.
- **Discovery moderno de Chromecast/Google TV = mDNS/DNS-SD** (no DIAL, que es legacy). Relevante para la 4ª arquitectura (§3, opción D).
- **Costo de registro Cast:** cuota única de **$5**.

**El punto duro para IPTV:** el endpoint live típico de Xtream es un **MPEG-TS continuo** con codecs que Cast nativo no reproduce. Esto **descarta de facto** las rutas que dependen del player de Cast (Default y Web Receiver) para live. Solo un player propio en la TV (libmpv/ExoPlayer+FFmpeg) lo resuelve — **da igual si el transporte es Cast Connect o propio.**

---

## 3. Entregable 2 — Comparativa técnica (cuatro alternativas)

> El gate añadió la opción **D**, omitida en la primera versión: como **ambas apps son nuestras**, no es obligatorio usar el bridge de Cast Connect para pasar contenido+credenciales entre nuestro móvil y nuestra TV.

| Criterio | **A) Default Media Receiver** | **B) Custom Web Receiver (CAF)** | **C) Cast Connect + app ATV propia** | **D) App ATV propia + control LAN propio (mDNS/DNS-SD + websocket), SIN Cast Connect** |
|---|---|---|---|---|
| Quién reproduce | Player de Cast (Google) | Shaka/MSE en tu web hospedada | **Tu app nativa en la TV** | **Tu app nativa en la TV** |
| MPEG-TS crudo (live Xtream) | ❌ | ❌ | ✅ (libmpv/media_kit) | ✅ (libmpv/media_kit) |
| Codecs IPTV (MPEG-2, AC-3…) | ❌ | ❌ | ✅ (según HW) | ✅ (según HW) |
| Inyección de headers/token auth | ❌ | ✅ | ✅ | ✅ |
| Reutiliza la resiliencia libmpv actual | ❌ | ❌ (reescribir en JS) | ✅ | ✅ |
| Subtítulos/multi-audio embebidos | Limitado | ⚠️ solo declarados | ✅ | ✅ |
| **Botón "Cast" estándar del SO / interop con otros senders** | ✅ | ✅ | ✅ | ❌ (control propio; solo entre nuestras apps) |
| **Distribución de la app TV sin Google Play** | — | — (deploy web) | ❌ **Requiere publicar en Play** (sideload NO habilita Cast Connect) | ✅ **Sideload funciona** (esquiva el gate de Play) |
| CORS / HTTPS requeridos | — | ✅ ambos | ❌ | ❌ |
| Hosting/backend propio | No | ✅ (receiver + probable proxy) | ⚠️ opcional | ⚠️ opcional |
| App(s) a mantener | 1 | 2 | 2 (+ fallback web) | 2 |
| Registro/publicación externa | App ID | App ID + web | **App ID + package ATV + publicación Play** | Solo distribución de la app (sideload/store) |
| Assistant / voz | Sí | Sí | Parcial | ❌ |
| Esfuerzo relativo | Trivial | Medio | **Alto** | **Alto** (sin el gate de Play) |
| Sirve para IPTV real, calidad comercial | ❌ | ⚠️ solo si el proveedor da HLS Cast-friendly | ✅ **si se logra publicar en Play** | ✅ **hoy, sin depender de Play** |

**Lectura tras el gate:**
- **A** descartado (no inyecta auth, no reproduce IPTV real).
- **B** frágil para IPTV (depende de HLS Cast-friendly + proxy para creds/CORS + reescribir la resiliencia). Útil solo como *fallback* reducido para VOD H.264/AAC.
- **C** y **D** son las dos reales, y **comparten el mismo activo caro**: la app ATV Flutter con media_kit. **La única diferencia es el transporte de descubrimiento/control** (Cast Connect vs propio) — y esa diferencia decide la dependencia de Play:
  - **C** da el botón Cast estándar e interop, pero **exige publicar la app ATV en Play** (bloqueo abierto del proyecto).
  - **D** entrega el objetivo funcional (móvil controla, TV reproduce directo) **hoy, vía sideload**, a costa de perder el botón Cast estándar y la interop con senders de terceros.

---

## 4. Manejo de cada requisito solicitado

### 4.1 Autenticación segura (no exponer user/pass)

Realidad: Xtream autentica por user/pass en el path; **no emite tokens**. Estrategias:

- **(MVP) Credenciales por el canal de control local** — `CredentialsData` (C) o mensaje cifrado por websocket LAN (D). La app TV construye la URL igual que el móvil hoy; las credenciales **no se hospedan** en ningún backend.
- **(Recomendado a término) Token temporal + URL firmada por backend propio.** Oculta las credenciales incluso de la app TV; habilita el Web Receiver como fallback. Coste: infra + operación.
- **(Máximo) Proxy propio de streaming** entre la TV y Xtream: traduce token→credenciales, añade CORS y puede re-empaquetar TS→HLS. Resuelve auth+CORS+formato, pero es un componente con costo de ancho de banda y un punto único de fallo.

> **Análisis de seguridad honesto (corregido tras el gate — la afirmación previa "no empeora el modelo actual" NO es defendible):**
> El **transporte** es comparable o mejor (TLS + device-auth en Cast; TLS en un websocket propio) al modelo actual (user/pass in-path). **Pero el modelo cambia de "1 dispositivo controlado (móvil, secure storage)" a "2 dispositivos, uno a menudo compartido/comunal" (dongle Chromecast/Google TV).** Deltas de riesgo nuevos, no presentes hoy:
> - Credenciales residentes (en memoria, y potencialmente **persistidas** por la app TV para resume/reconexión) en un segundo dispositivo.
> - **Superficie de logs no verificada:** el `credential_scrubber` actual solo cubre logs propios del móvil, no el SDK de Cast ni libmpv en la TV. **Requiere spike de logcat** y **portar el scrubber al lado ATV** antes de manejar credenciales reales.
> - Ruta de fallback (Web Receiver) con manejo de credenciales distinto y sin analizar.
>
> Conclusión: "riesgo de transporte comparable **+ nueva superficie de dispositivo/logs**". La mitigación robusta a término es token/proxy para que la app TV nunca vea user/pass reales.

### 4.2 No consumir dos conexiones simultáneas (límite de streams)

El riesgo real no es el solape de cliente, sino que **muchos paneles Xtream NO liberan el slot al instante** al desconectar el móvil: dependen de timeouts de segmento/keepalive que pueden tardar **decenas de segundos**. Si la TV abre antes de que el panel libere el slot del móvil, `max_connections=1` rechaza.

Estrategia corregida:

1. **Handshake estricto de traspaso:** el móvil hace `stop`/dispose de su player **y espera confirmación de liberación** antes de que la TV abra. **No** hay "solape aceptable de 1-2 s" — con `max_connections=1` el solape es precisamente lo que rompe.
2. Como el panel puede tardar en liberar, la app TV debe **reintentar el `open` con backoff** ante el rechazo por límite (mensaje del panel), no fallar duro.
3. **F0 (auditoría de proveedor) debe medir la LATENCIA DE LIBERACIÓN de slot**, no solo el valor de `max_connections`. Esa latencia decide si el traspaso es viable o si hace falta que el proveedor suba a `max_connections≥2` o un proxy que multiplexe.
4. Superficializar `maxConnections`/`activeCons` (ya en DB, `database.dart:86`) para avisar al usuario si el proveedor está saturado.

### 4.3 Live, películas y series

- **Live:** `streamType = LIVE`, sin resume, loop-reopen — igual que hoy. Zapping por el canal de control (§4.5).
- **Películas (VOD):** BUFFERED con **resume**; sincronizar `watchDuration` (`watch_history_service.dart`) entre TV y móvil por el canal de control.
- **Series:** cola de episodios enviada al receptor; autoavance, resume por episodio (replica `episode_screen.dart`).

### 4.4 Subtítulos, pistas de audio, reconexiones

- **Con app TV = media_kit (C o D):** se **reutiliza** enumeración de pistas embebidas por libmpv, match de idioma tolerante (`_langSynonyms`), subtítulos externos por URL, backoff, stall-watchdog, ext-heal, reconexión. La UI de selección se opera desde el móvil por el canal de control.
- **Con Web Receiver (B):** hay que **reimplementar** todo en JS y depender de tracks declarados en el HLS/DASH; los subtítulos embebidos de un TS no serán accesibles.

### 4.5 Cambios rápidos de canal (zapping)

- El móvil envía "canal +/-" o número por el **canal de mensajes de baja latencia** (mensaje custom de Cast en C; websocket en D). No reabre la sesión.
- La app TV ejecuta el mismo `_changeChannel` con debounce de hoy (`player_widget.dart:1130`). La latencia = reabrir la URL en libmpv (igual que en el móvil).
- Con Web Receiver, cada cambio es un **LOAD nuevo** de Shaka → más lento, sin la lógica anti-storm existente.

---

## 5. Entregable 3 — Recomendación (corregida tras el gate)

### La recomendación NO es "comprometerse con C hoy". Es:

**(1) Construir primero el activo compartido: la app Android TV en el mismo Flutter + media_kit, con el transporte de control tras una abstracción.** Ese activo (player + leanback UI + navegación D-pad + glue de MediaSession + manejo de comandos remotos) es **idéntico para C y para D**. No hay que decidir el transporte para empezar a construir lo caro y reutilizable.

**(2) Elegir el transporte (C vs D) según el resultado del gate de Google Play**, que es la variable decisiva:

- **Si se consigue publicar la app ATV en Google Play** (resolver firma + superar política IPTV) → **C (Cast Connect)**: da el botón Cast estándar del ecosistema e interop con otros senders (experiencia "tipo YouTube").
- **Si Play sigue bloqueado o es incierto** → **D (control LAN propio, mDNS/DNS-SD + websocket)**: entrega el mismo objetivo funcional **hoy, vía sideload**, sin depender de Play. Se pierde el botón Cast estándar y la interop de terceros, pero **entre nuestras propias apps la experiencia es equivalente**.

**Arquitectura objetivo (común a C y D):**

```
┌─────────────────────────┐     Descubrimiento + control (Cast [C] o mDNS+websocket [D])   ┌──────────────────────────────┐
│  App móvil (Flutter)     │  ──────────────────────────────────────────────────────────▶ │  App Android TV (Flutter)     │
│  = SENDER + control       │      LOAD {contentId, tipo, tracks, credenciales/token}       │  = RECEPTOR                   │
│                          │      MSG  {zap±, número, audio/sub, pause/seek}                │  • Transporte tras abstracción│
│  • Transporte tras       │  ◀────────────────────────────────────────────────────────── │    (Cast Connect glue | ws)   │
│    abstracción            │      ESTADO {playing, pos, tracks}                            │  • PlayerWidget / media_kit   │
│  • UI de control remoto   │                                                              │    REUTILIZADO (libmpv, subs, │
│  • Libera su player       │                                                              │    zapping, resiliencia)      │
│    ANTES del traspaso      │                                                              │  • credential_scrubber PORTADO│
└─────────────────────────┘                                                              └───────────────┬──────────────┘
                                                                                                         │ TS/HLS/VOD directo
                                                                                                         ▼
                                                                                               ┌──────────────────┐
                                                                                               │  Servidor IPTV    │
                                                                                               │  (Xtream Codes)   │
                                                                                               └──────────────────┘
      (Fase posterior opcional)  token temporal ──▶  Backend propio / proxy  ──▶  Xtream
```

**Pros de este enfoque (activo compartido + transporte diferido):**
- No se apuesta 11–14 semanas a un permiso externo (Play) antes de saber si se obtiene.
- Lo caro y reutilizable (app TV + player) se construye una sola vez, sirva C o D.
- D es un **plan de contingencia real** que entrega el objetivo del usuario aunque Play nunca se destrabe.

**Contras / costes:**
- **Dos apps** desde el mismo repo (sender + app ATV con flavor/entry-point, leanback, D-pad).
- Glue de transporte no cubierto por `flutter_chrome_cast` (Cast Connect) o un stack de websocket+mDNS propio (D) — ambos son trabajo nativo/no trivial.
- **C sigue gated por Play**; **D pierde el botón Cast estándar** e interop con senders de terceros.
- El usuario debe **instalar la app en la TV** (como Netflix/YouTube la primera vez).

### 5.1 Stack técnico de D (decisiones firmes, verificadas contra pub.dev/docs)

Precedente que valida el enfoque: **clubTivi** (open-source) ya combina Flutter + media_kit/libmpv + Xtream Codes + navegación D-pad en Android TV, con "web companion remote" en su roadmap — casi exactamente este modelo. Referencia conceptual de control por LAN: **Kodi + Kore** (JSON-RPC sobre WebSocket, LAN-only).

| Capa | Decisión | Notas / trampas |
|---|---|---|
| **Descubrimiento** | **`bonsoir`** en ambos extremos (TV = `BonsoirBroadcast` de `_rensi._tcp`; móvil = `BonsoirDiscovery`). Alt: `nsd`. | Únicos paquetes que **anuncian Y descubren**. Requiere `CHANGE_WIFI_MULTICAST_STATE` en el manifest. iOS (móvil) necesita `NSLocalNetworkUsageDescription` + `NSBonjourServices`. |
| **Canal de control** | **TV = servidor** (`dart:io` `HttpServer` + `WebSocketTransformer`, o `shelf_web_socket`); **móvil = cliente** (`web_socket_channel`). | Encaja con "la TV espera contenido"; el listener vive en el dispositivo estable/foreground (esquiva las restricciones de background de Android). Multi-remote = fan-in de N sockets en la TV. |
| **Emparejamiento** | PIN mostrado en la TV → tecleado en el móvil → `HKDF/PBKDF2(PIN)` → challenge-response mutuo **HMAC-SHA256** (opcional X25519 ECDH). Lib: **`cryptography`**. | **PAKE real NO existe cross-platform en Dart** (no diseñar alrededor de SPAKE2). PIN corto = baja entropía → validez corta, pocos intentos, rotación. |
| **Transporte seguro** | **`wss://` self-signed con cert-pinning** vía `WebSocket.connect(customClient:)` + `badCertificateCallback` que pinea el SHA-256 del cert aprendido en el pairing. | `web_socket_channel` NO expone `SecurityContext` → hay que usar la ruta `dart:io` `WebSocket.connect`. Alternativa ligera: AES-GCM sobre `ws://` plano (pero la capa de records se hace a mano). |
| **Player en la TV** | **media_kit / libmpv reutilizado** (`Video()` compartido). HLS + MPEG-TS + `httpHeaders` confirmados en media_kit. | El mismo `PlayerWidget` sirve móvil y TV; difieren solo en el chrome de foco/D-pad. |
| **Foco D-pad** | Paquete **`dpad`** (o shim `RawKeyboard`), no confiar en la activación de foco por defecto de Flutter. | Huecos de años del framework: `LogicalKeyboardKey.select` no activa widgets; crash en OK/DPAD_CENTER; traversal direccional salta de carril. |
| **Empaquetado móvil+TV** | Un solo proyecto, **flavors + entrypoints Dart** (`--flavor tv -t lib/main_tv.dart`) + manifest-TV (`LEANBACK_LAUNCHER`, `uses-feature leanback`, `touchscreen required=false`, banner 320×180), compartiendo todo `lib/`. | Patrón soportado y documentado por Flutter; clubTivi lo hace con un solo `lib/`. |

---

## 6. Entregable 1 (núcleo) — Riesgos, limitaciones y compatibilidad

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| R1 | Proveedor sirve solo TS crudo con MPEG-2/AC-3 | Web Receiver inservible | App TV con libmpv (C o D) lo absorbe |
| R2 | **Cast Connect exige app ATV publicada en Play; sideload no habilita C** | **Puede invalidar C para distribución real** | Gate de Play primero; **D como contingencia** |
| R3 | Credenciales en un 2º dispositivo (dongle compartido) + logs no verificados | Fuga | Portar `credential_scrubber` a la app TV; spike de logcat; token/proxy a término |
| R4 | Doble conexión + **el contador `active_cons` del panel no es fiable en tiempo real** (F0: quedó fijo en 3/3, con slots stale sin liberar) | Corte con `max_connections=1`; no se puede consultar el estado de slots por API | Handshake **estricto** stop→open en el cliente + **reintento con backoff ante rechazo**; NO depender de `active_cons` |
| R5 | **HW de decodificación de dongles Cast** (Chromecast/Google TV) no sostiene MPEG-2/SW-decode 1080p realtime | Canal falla en el dispositivo Cast típico (hoy solo probado en boxes Amlogic) | Detección + mensaje; validar en HW real en F0/spike; SW-decode como último recurso |
| R6 | Estimación de un stack sin precedente (Flutter+media_kit+MediaSession/Cast) | Sobrecoste | Spike F3 antes de comprometer; buffer de integración explícito |
| R7 | Ecosistema Flutter Cast no oficial | Deuda/mantenimiento | `flutter_chrome_cast` (sender) + glue propio |
| R8 | Variabilidad entre proveedores Xtream | Comportamiento inconsistente | F0 de auditoría de capacidades (formatos/codecs/CORS/latencia de slot) |
| R9 | Resume/continue-watching desincronizado móvil↔TV | UX inconsistente | Sincronizar `watchDuration` por el canal de control |
| R10 | **Local Network Permission de Android 17** (SDK 37): obligatorio en runtime para mDNS **y** WebSocket, lado servidor **y** cliente. **No exento por sideload.** | Sin él, en Android 17+ el descubrimiento y el socket se bloquean | Declarar `ACCESS_LOCAL_NETWORK` + `requestPermission()` en runtime; en A16 apoyarse en `NEARBY_WIFI_DEVICES` |
| R11 | **AP/client isolation** (modo guest / redes que bloquean multicast cliente-a-cliente) | Descubrimiento mDNS falla; **ningún código lo salva** | Fallback a IP manual/QR con la IP de la TV; detectar y guiar al usuario |
| R12 | Flutter **NO inyecta `INTERNET` permission en release** | El socket falla en silencio solo en builds release | Añadir `<uses-permission android:name="android.permission.INTERNET"/>` explícito al manifest |
| R13 | Huecos de D-pad en Flutter (`select` no activa, crash en OK) | Navegación TV rota | Paquete `dpad` / shim `RawKeyboard` |

**Compatibilidad con proveedores:** C y D son las más tolerantes porque el player en la TV es el mismo libmpv que ya funciona hoy. La variable nueva es el **HW de decodificación de la TV/dongle** (R5), no el formato del proveedor.

---

## 7. Entregable 4 — Estimación de esfuerzo y cronograma (re-basada tras el gate)

Supuestos: 1–2 desarrolladores, reutilizando el codebase Flutter/media_kit. Rangos por incertidumbre de un stack sin precedente público.

| Fase | Alcance | Esfuerzo | Riesgo |
|---|---|---|---|
| **G0 — Gate de Play (externo, bloqueante para C)** | Resolver firma + evaluar/superar política IPTV para publicar la app ATV. **Duración desconocida: depende de Google, no de nosotros.** Si no se cierra → arquitectura **D**. | **Externo** | **Crítico** |
| **F0 — Auditoría de proveedor + HW** | HLS vs TS, codecs, CORS, `max_connections` **y latencia de liberación de slot**; validar decode en un dongle Cast real. | 3–5 días | Medio |
| **S1 — Spike Cast Connect + libmpv** (test device) | Glue Kotlin `MediaSession`↔media_kit + `MediaLoadCommandCallback.onLoad()` abriendo un TS live real. De-riskea F3 (sin precedente público). | 1–2 sem | **Alto** |
| **S2 — Spike de logging de credenciales** | logcat/crash instrumentado en la TV: ¿el SDK de Cast o libmpv exponen `CredentialsData`/URL con user:pass? Definir scrubbing ATV. | 3–5 días | Medio |
| **F1 — App ATV (shell + player)** | Flavor/entry-point ATV: leanback launcher, navegación D-pad, integrar PlayerWidget. **Común a C y D.** | 2–3 sem | Medio |
| **F2 — Transporte de control** | C: glue Cast Connect completo (LaunchRequestChecker, CredentialsData, canal custom). D: mDNS/DNS-SD + websocket + pairing. Tras abstracción. | 2–4 sem | **Alto** |
| **F3 — Auth + límite de conexiones** | Handshake estricto de traspaso, backoff ante rechazo por slot, avisos de `max_connections`. | 1 sem | Medio |
| **F4 — Paridad de reproducción** | Subtítulos, multi-audio, reconexión, zapping por canal de control, resume/continue-watching sincronizado. | 2 sem | Medio |
| **F5 — VOD + series** | Colas de episodios, autoavance, resume por item. | 1 sem | Bajo |
| **F6 — Hardening + release** | QA en HW variado, publicación (Play para C / distribución para D). | 2 sem | Medio |
| **F7 (opcional) — Token/proxy** | Backend de tokens + URL firmadas; fallback Web Receiver. | 2–3 sem | Medio |

- **Fase de de-risking (obligatoria antes de comprometer el build):** G0 + F0 + S1 + S2. Hasta cerrarla, **no** se compromete el cronograma completo.
- **MVP demostrable (castear un canal en vivo, control básico), tras de-risking:** F1+F2(mínimo)+F3 ≈ **6–9 semanas** — **pero condicionado a S1 exitoso**; si el glue MediaSession↔libmpv resulta más duro, se extiende.
- **Producto comercial completo (todo salvo F7):** ≈ **12–16 semanas** (~3–4 meses) con 1–2 devs. (Revisado al alza vs la 1ª versión: el "80% de reuso" se refería al *player*, no a la *app*; la app TV — leanback, D-pad, MediaSession, glue de transporte — es prácticamente toda nueva.)
- **G0 no tiene duración estimable** (permiso externo). C se compromete solo cuando G0 tenga un camino concreto.

---

## 8. Entregable 5 — PoC funcional (especificación, orden de de-risk corregido)

**Meta del PoC:** reproducir **un canal en vivo** desde el móvil hacia un Android TV, con el móvil como control.

> El gate corrigió el orden: hacer primero un "PoC-Rápido" de Web Receiver **de-riskea el camino equivocado** (valida discovery/LOAD contra un receiver que el producto descarta, con un sender-path que quizá no cubra Cast Connect). Hay que atacar primero los riesgos que definen el proyecto.

**PoC recomendado (slice de la arquitectura real), sobre un test device registrado:**
1. App ATV Flutter mínima con media_kit + glue Kotlin (`CastReceiverContext`, `MediaManager`, `MediaLoadCommandCallback`, `MediaSession` alimentado a mano).
2. Sender Flutter con `flutter_chrome_cast` (o platform channel) que lance la app ATV y envíe un LOAD con el `contentId` del canal + credenciales por `CredentialsData`.
3. La app TV abre el **TS live real** en libmpv y confirma "playing"; el móvil libera su player (handshake).
4. Comando de zapping ±1 por el canal custom.

Esto valida a la vez: glue Cast Connect+libmpv (S1), manejo de credenciales (S2) y reproducción IPTV real. ~3–4 semanas.

**Variante de contingencia (arquitectura D):** el mismo PoC pero con descubrimiento mDNS/DNS-SD + control por websocket en vez de Cast Connect. **Ventaja:** corre sobre una app **sideloadeada** sin depender de Play — útil si el gate G0 no se puede cerrar a tiempo para el PoC.

**PoC-Rápido (Web Receiver + VOD HLS) — degradado a opcional:** solo si se quiere una demo visible de "conexión Cast" en 1 semana; **no** valida el caso comercial y usa un camino descartado.

---

## 9. Decisiones de definición pendientes (requieren tu input — bloquean el compromiso)

Tras el gate, estas son las decisiones make-or-break. No las decide el código ni un default razonable:

1. **Gate de Google Play (el decisivo):** ¿hay un camino concreto para publicar la app ATV en Play (resolver firma + política IPTV)? De la respuesta depende **C vs D**. Si no lo hay o es incierto → asumimos **D** como arquitectura primaria.
2. **Transporte:** dado (1), ¿comprometemos **C (Cast Connect, botón Cast estándar, gated por Play)** o **D (control LAN propio, sideload hoy, sin botón Cast estándar)**? ¿O construimos el activo compartido y decidimos tras los spikes?
3. **Alcance del PoC inmediato:** ¿PoC-Real de Cast Connect (test device, ~3–4 sem), variante D (sideload, sin Play), o el PoC-Rápido opcional (1 sem, camino descartado)?
4. **Infraestructura propia:** ¿hay backend disponible? Decide si F7 (token/proxy) y el fallback Web Receiver son viables.
5. **Proveedor(es) objetivo para F0:** ¿contra qué servidor Xtream real validamos formatos/codecs/CORS **y latencia de liberación de slot**? ¿Y en qué dongle Cast validamos el decode (R5)?

---

## 10. Definición de "hecho" del PoC (criterios de aceptación)

- [ ] El móvil descubre y conecta con el Android TV (Cast o mDNS).
- [ ] El móvil envía un canal en vivo real de Xtream; **la TV lo reproduce desde el servidor** (no mirroring).
- [ ] El móvil libera su stream en el traspaso (verificado: no 2 conexiones simultáneas contra un panel real).
- [ ] Zapping ±1 desde el móvil con latencia comparable a la del player local.
- [ ] Las credenciales no aparecen en logcat de la TV (scrubber portado / verificado en S2).

---

## 11. Registro del gate adversarial

- **Etapa:** plan / decisión de definición de alto riesgo (security + dirección de producto + estimación).
- **Retador (Opus, read-only):** VEREDICTO **rechazado para comprometerse**. Fallos clave: universo cerrado (omitía la opción D sin Cast Connect); claim de seguridad "no empeora" como racionalización; distribución de la app ATV subestimada; handshake de traspaso ignora la latencia de liberación de slot; F3 y "80% de reuso" optimistas; PoC-Rápido de-riskea el camino equivocado; HW de decode en dongles minimizado.
- **Auditor (Opus, verificado contra doc oficial de Google):** FALLO **bloqueado** para comprometer C hoy. Confirmado: **Cast Connect exige app ATV publicada en Play; el sideload no la habilita en dispositivos de usuario final** (`APP_NOT_INSTALLED_BY_WHITELISTED_INSTALLER`) → C depende del gate de Play abierto. media_kit es puenteable a MediaSession (F3 realista, spike genuino). CredentialsData: TLS+device-auth en tránsito, pero "no empeora" no es defendible (2º dispositivo + logs no verificados). La 4ª arquitectura (D) es sólida y esquiva Play.
- **Integración (agente principal):** este documento incorpora todas las correcciones — se añadió la opción D a la comparativa, se reformuló la seguridad, se corrigió el handshake y F0, se re-basó la estimación, se invirtió el orden de de-risk y se reestructuró la recomendación hacia "activo compartido + transporte diferido gated por Play".

---

## 12. Resultados F0 — auditoría de proveedor real (ejecutada)

Medido contra un proveedor Xtream real de prueba (panel `player_api.php`, servidor de streaming distinto al del panel). **Sin credenciales en este documento.**

| Dato | Valor medido | Implicación |
|---|---|---|
| Auth / estado | `auth=1`, `status=Active`, `is_trial=0` | Panel operativo |
| **`max_connections`** | **3** | Cómodo; aun así la arquitectura debe soportar `=1` |
| **`allowed_output_formats`** | **`['m3u8','ts','rtmp']`** | El panel **sí sirve HLS** |
| Live streams | 2989 canales | — |
| **Formato `.m3u8`** | `content_type: application/x-mpegurl` (HLS real) | Reproducible por Cast **y** libmpv |
| **Formato `.ts` / sin-ext** | `content_type: video/mp2t` (TS crudo) | Solo libmpv/ExoPlayer (no Web Receiver) |
| **Codecs (2 canales muestreados)** | **video H.264 High @1280×720, audio AAC-LC 48kHz stereo** | **Codecs nativos de Cast** — este proveedor NO tiene el problema MPEG-2/AC-3 |
| Edge / token | El panel redirige (302) al edge (`IP:8080`) añadiendo **`?token=…`**; user/pass **siguen en el path** | El token es de sesión, NO oculta credenciales |
| **`active_cons` (contador API)** | **Fijo en 3/3, no reacciona a abrir/cerrar streams**; slots stale sin liberar | **No fiable para el handshake de conexiones** → confirma R4; usar orden estricto + retry, no la API |

**Lectura F0:**
- Para **este** proveedor, HLS + H.264/AAC hace que incluso un Web Receiver (B) o un futuro botón Cast (C) sean técnicamente viables. Pero **D sigue siendo la elección** por ser **provider-agnóstica**: otros paneles servirán TS crudo/MPEG-2/AC-3 donde solo libmpv sobrevive.
- El **token de sesión en la URL del edge** y el user/pass persistente en el path refuerzan que la app TV debe construir la URL a partir de credenciales recibidas por el canal de control (no cachear URLs firmadas de larga vida).
- **R4 validado empíricamente:** el contador de slots del panel es inservible en tiempo real → el control de "no dos conexiones" debe ser puramente cliente (liberar en el móvil antes de abrir en la TV) con reintento ante rechazo del panel.

---

## 13. Resultados de spikes ejecutados (S1 / PoC de reproducción)

Ejecutado sobre el **emulador Android TV** `tv_1080p` (emulator-5554, Android 16 x86_64, 1920×1080 @ 960dp = la TV AOC real del usuario), contra el proveedor real de F0.

| Spike | Resultado | Evidencia |
|---|---|---|
| **S1a — media_kit corre en Android TV** | ✅ Confirmado | La app instala y lanza en ATV; `libmpv.so` + `media_kit` inicializan sin fallos (logcat) |
| **S1b — libmpv reproduce el canal HLS real** | ✅ **Confirmado** | `flutter drive` + `poc_cast_play.dart` apuntando a `…/live/…/6519.m3u8`: libmpv abrió el stream y montó una **superficie de video 1280×720** (`VideoOutput.Resize {width:1280, height:720}`, `setSurfaceSize 1280 720`, `onSurfaceAvailable`) — resolución que coincide con F0 (H.264 720p). **Test pasa.** |
| **Rendering en emulador** | ⚠️ SW decode | media_kit loguea "Emulator detected. Enforcing S/W rendering" → el decode HW (R5) **no** se valida en emulador; requiere dongle/box real |
| **Captura visual del frame** | ❌ No vía harness | `takeScreenshot` da negro (no captura la textura de video de media_kit); `adb screencap` bajo el harness muestra el launcher (actividad no al frente). Un frame literal exige manejar la UI de la app real |
| **Bug ATV encontrado y corregido** | ✅ Guard añadido | `connectivity_plus` `checkConnectivity()` lanza `type 'String' is not a subtype of List<dynamic>` en la imagen del emulador ATV → excepción asíncrona no capturada que **abortaba la init del player**. Guardado con try/catch en `player_widget.dart:645` (asume online ante fallo). **Verificar si es solo del emulador en HW real.** |

### 13.1 Canal de control móvil↔TV (segundo riesgo de D) — ejecutado end-to-end

Implementado y **probado en el emulador Android TV** (`integration_test/poc_cast_control.dart`, `flutter drive`), **todos los tests pasan, cero excepciones**:

| Paso | Resultado | Evidencia |
|---|---|---|
| **Descubrimiento mDNS** (`bonsoir`) | ✅ | TV anuncia `_rensi-cast._tcp`, el sender lo descubre (`POC_DISCOVERED=1`) |
| **Emparejamiento por PIN** (HKDF→HMAC) | ✅ | PIN incorrecto **rechazado**, correcto **aceptado** (`POC_PAIRED=true`) |
| **LOAD con credenciales cifradas** (AES-GCM) | ✅ | La TV descifra user/pass **intactos** (`credsOk=true`) — nunca en claro por la LAN (mitiga R3) |
| **La TV reproduce el canal que el móvil envió** | ✅ | `VideoOutput.Resize` tras el LOAD; test verde |

**Nota de entorno:** el mDNS entre **dos** emuladores no es fiable (cada emulador está tras su propio NAT, no comparten L2), por eso el canal de control se probó por **loopback + el daemon mDNS del propio dispositivo**. En una LAN real con dos dispositivos físicos el descubrimiento funciona; validar ahí (y contra AP/client-isolation, R11).

### 13.2 App receptora real (`lib/main_tv.dart`)

Entrypoint del televisor: UI de espera con **nombre + PIN de emparejamiento**, levanta el receptor (servidor WS + anuncio mDNS) y reproduce con el `PlayerWidget` real al recibir un LOAD. Arranca con `flutter run -t lib/main_tv.dart`. (El empaquetado leanback definitivo — flavor `tv` + manifest `LEANBACK_LAUNCHER` — queda como tarea F1; para el PoC basta este entrypoint.)

**Captura visual del frame:** ❌ no obtenible **en el emulador** — media_kit fuerza render por software y la superficie de video no la exponen ni `takeScreenshot` (textura) ni `adb screencap` (surface SW). Es limitación del emulador; en **hardware real** (decode HW + surface normal) `screencap` sí toma el frame. La reproducción está probada por logs (`VideoOutput.Resize 1280×720`), no por pixel.

**Artefactos** (rama `feat/cast-second-screen`, sin commitear):
- `lib/services/cast/cast_protocol.dart` — protocolo + cripto (HKDF/HMAC/AES-GCM).
- `lib/services/cast/tv_receiver_service.dart` — receptor TV (WS server + mDNS + pairing + LOAD).
- `lib/services/cast/phone_sender_service.dart` — sender móvil (discover + pair + LOAD + comandos).
- `lib/main_tv.dart` — entrypoint receptor TV.
- `integration_test/poc_cast_play.dart`, `integration_test/poc_cast_control.dart` — tests del PoC.
- Guard de `connectivity_plus` en `lib/widgets/player_widget.dart`; permiso `CHANGE_WIFI_MULTICAST_STATE`; deps `bonsoir` + `web_socket_channel`.

**Lectura:** los **dos riesgos técnicos altos de la arquitectura D quedan despejados** — (1) media_kit/libmpv reproduce el IPTV real en Android TV, y (2) el canal de control (descubrir → emparejar → enviar credenciales cifradas → reproducir) funciona end-to-end. Pendiente de hardware real: decode HW (R5), mDNS en LAN física + AP-isolation (R11), y el empaquetado leanback/distribución.

---

## 14. Estado de productización (feat/cast-second-screen)

Mapeo de cada requisito a su estado. Construido y probado en emulador; la validación final entre dos dispositivos físicos (mDNS real, decode HW, ver el video) requiere el hardware del usuario.

| Requisito | Estado | Evidencia / nota |
|---|---|---|
| Móvil como control, TV reproduce directo (sin mirroring/relay/backend) | ✅ | Arquitectura D end-to-end |
| Descubrimiento en la red (mDNS/DNS-SD, `bonsoir`) | ✅ | `POC_DISCOVERED=1` en emulador |
| Emparejamiento seguro (PIN → HKDF → HMAC) | ✅ | 6 tests de pairing |
| Credenciales sin exponer (AES-GCM por la LAN, sin backend) | ✅ | 6 tests de cifrado (nunca en claro, MAC, clave equivocada) |
| No dos conexiones (handoff stop-móvil→open-TV) | ✅ | Libera el player local al castear (R4) |
| Live, películas y series | ✅ | `container_extension` end-to-end; 4 tests de URL por tipo |
| Cambio rápido de canal (zap) | ✅ | El móvil (que tiene el catálogo) reenvía el LOAD del canal vecino; test |
| Reconexión del canal de control | ✅ | Reconecta con backoff + re-empareja con PIN cacheado; test |
| App TV receptora (leanback) | ✅ | Manifest ya era leanback; receptor integrado en la app (`TvReceiverHost`) |
| **Seguir navegando mientras castea** | ✅ | Mini-control global persistente; el player devuelve a navegar al castear |
| Control remoto real (play/pausa/stop) | ✅ | El receptor aplica los comandos vía EventBus (antes se enviaban sin consumirse) |
| **Subtítulos / pistas de audio sobre el cast** | ✅ | Round-trip: la TV reporta sus pistas reales (libmpv) → selector en el móvil → aplica vía EventBus; test |
| **`wss` + cert-pinning atado al PIN** | ✅ | Cert EC self-signed (`basic_utils`) persistido; `bindSecure`; el móvil pinea el cert y el proof ata el fingerprint al PIN (autenticación mutua, anti-MITM). **Probado end-to-end por loopback headless.** ⚠️ latencia de generación de cert en TV de gama baja: validar en hardware |
| UX comercial (botón Cast, selector, PIN, control) | ✅ | Widgets + widget test |
| i18n | ✅ | 14 cadenas en los 10 idiomas |
| Permiso de red local (Android 13+) | ✅ | `NEARBY_WIFI_DEVICES` declarado |
| Tests | ✅ | ~35 de casting (cripto, wss loopback, máquina de estados, zap, pistas, widget) + suite completa **426 passed, 2 skipped** |
| **Validación final en hardware** (TV AOC + teléfono) | ⏳ tuyo | mDNS en LAN física + AP-isolation (R11), decode HW (R5), frame de video real, y latencia de cert-gen — solo en dispositivos reales. Guía: `CASTING_HARDWARE_VALIDATION.md` |

**Artefactos añadidos** (además de los del PoC): `lib/controllers/cast_sender_controller.dart`, `lib/widgets/cast/{cast_flow,casting_screen,tv_receiver_host}.dart`, `ext` end-to-end en el protocolo, integración en `player_widget.dart` y `main.dart`, cadenas cast en los 10 `.arb`, y tests en `test/services/cast/`, `test/controllers/`, `test/widgets/`.

---

## Apéndice — Fuentes

- Google Cast — Registration, Supported Media, Web Receiver Core Features, Streaming Protocols, Live Streaming, Android TV Receiver / Cast Connect, Troubleshooting (developers.google.com/cast).
- `flutter_chrome_cast` (pub.dev). Protocolo Cast (TLS/device-auth, discovery mDNS): oakbits.com Google Cast protocol.
- Código base: rutas `file:line` citadas a lo largo del documento.
- Contexto de negocio: `memory: play-store-status`.
