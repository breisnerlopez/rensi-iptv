# Validación en hardware real — Casting / segunda pantalla (Arquitectura D)

**App:** Rensi IPTV (Flutter) · **Rama:** `feat/cast-second-screen` · **applicationId:** `info.breisner.rensi.iptv`

Esta guía valida lo **único que no se puede comprobar en emulador**: descubrimiento mDNS entre **dos dispositivos físicos** distintos en una LAN real, **decode por hardware** del video, y **ver el video real** en la TV. Todo lo demás (pairing, cripto, protocolo, URLs por tipo, reconexión) ya está probado en emulador (26 tests de casting verdes) — ver `CASTING_ARCHITECTURE.md` §13 y §14.

## Cómo funciona (recordatorio de 30 segundos)

- Se instala **la MISMA app (mismo APK)** en el teléfono y en el Android TV AOC. No hay dos binarios.
- En el **teléfono** aparece un botón **"Enviar a la TV"** (icono cast, arriba a la derecha del video). Actúa de **sender/control**.
- En el **Android TV** la app detecta que corre en televisor (`ResponsiveHelper.isTelevisionDevice`) y arranca automáticamente el **receptor integrado** (`TvReceiverHost`): levanta un WebSocket en la LAN y se **anuncia por mDNS** como servicio `_rensi-cast._tcp` con el nombre **"Rensi TV"**. Mientras tanto la TV se usa como IPTV normal.
- **NO usa Google Cast / Cast Connect** → se instala por **sideload** (`adb install`), no hace falta Google Play.
- Descubrimiento por **mDNS (paquete `bonsoir`)**, emparejamiento por **PIN de 6 dígitos**, credenciales del proveedor cifradas **AES-GCM** por el canal de control (nunca en claro por la LAN).
- La TV reproduce el stream **directo desde el servidor Xtream** (no mirroring, no relay). El teléfono **libera su reproducción** al castear para no consumir dos conexiones.

---

## 1. Requisitos de red (el fallo #1 del mDNS)

Ambos dispositivos deben estar en la **MISMA red Wi-Fi / mismo segmento L2**, y esa red **NO debe tener aislamiento de clientes** ("AP isolation" / "client isolation" / "modo invitado"). Si el router aísla clientes, el multicast/mDNS entre teléfono y TV se bloquea y **ningún código de la app puede salvarlo** (riesgo R11 del documento de arquitectura).

### Detectar AP isolation

La prueba definitiva: que un dispositivo haga **ping a la IP LAN del otro**. Si ambos están "online" pero no se pingean entre sí, es AP isolation (o dos SSID/subredes distintas).

```bash
# 1) Averigua la IP LAN de cada dispositivo (por adb, ver §2 para conectar adb).
adb -s <SERIAL_TV>   shell ip -f inet addr show wlan0    # p.ej. 192.168.1.50
adb -s <SERIAL_MOVIL> shell ip -f inet addr show wlan0   # p.ej. 192.168.1.73

# 2) Confirma que están en la MISMA subred (mismos 3 primeros octetos y misma máscara).

# 3) Ping cruzado (la prueba de fuego). Desde el teléfono a la TV:
adb -s <SERIAL_MOVIL> shell ping -c 4 192.168.1.50
#   OK  -> hay conectividad cliente-a-cliente (mDNS debería funcionar).
#   100% packet loss estando ambos conectados -> AP ISOLATION o subredes distintas.
```

Si además quieres verificar el anuncio mDNS en sí (opcional, desde un PC Linux/Mac en la misma red, con la app ya abierta en la TV):

```bash
# Linux (avahi):  el servicio "Rensi TV" debe aparecer.
avahi-browse -rt _rensi-cast._tcp
# macOS:
dns-sd -B _rensi-cast._tcp
```

### Desactivar AP isolation en el router

No hay un nombre único; busca en el panel del router (normalmente `http://192.168.1.1`) alguna de estas opciones y **desactívala**:

- **"AP Isolation" / "Client Isolation" / "Aislamiento de puntos de acceso"** → OFF.
- **"Wireless Isolation" / "Station Isolation"** → OFF.
- **Modo/Red de "Invitados" (Guest Network)** → **no** uses la SSID de invitados; los dispositivos deben ir en la red principal.
- Si tienes **banda 2.4 GHz y 5 GHz con SSID separadas**, conéctalos a la **misma SSID** (algunos routers no puentean multicast entre bandas). Idealmente ambos en la misma banda para la primera prueba.
- Redes **mesh / repetidores**: si el teléfono cuelga de un nodo y la TV de otro, algunos sistemas bloquean multicast entre nodos → prueba primero con ambos colgando del **nodo principal**.

> **Plan B si el router no deja desactivarlo:** la app hoy solo descubre por mDNS (no hay entrada de IP manual en la UI). Si el descubrimiento falla por la red, la validación de casting no puede completarse en esa red — cambia a una red doméstica sin aislamiento (un hotspot de móvil de un **tercer** teléfono suele servir para la prueba, ya que los hotspots normalmente **no** aíslan clientes).

---

## 2. Build e instalación en ambos dispositivos

### 2.1 Build del APK (release)

El proyecto **no tiene flavors ni ABI splits** configurados: `flutter build apk --release` genera **un APK universal** que sirve tanto para el teléfono como para la TV.

```bash
cd /home/debian/workspace/rensi-iptv
git switch feat/cast-second-screen        # asegúrate de estar en la rama correcta
flutter pub get
flutter build apk --release
# Salida: build/app/outputs/flutter-apk/app-release.apk   (universal, todas las ABIs)
```

Opcional — APKs más pequeños por ABI (útil si quieres el mínimo para cada dispositivo):

```bash
flutter build apk --release --split-per-abi
# Genera:
#   app-arm64-v8a-release.apk    <- normal para TV AOC y teléfonos modernos (arm64)
#   app-armeabi-v7a-release.apk  <- ARM 32-bit (dispositivos antiguos)
#   app-x86_64-release.apk       <- emuladores / x86
```

> **Qué ABI elegir por dispositivo:** casi todos los Android TV AOC y los teléfonos actuales son **arm64-v8a**. Si dudas, usa el **APK universal** (`app-release.apk`): funciona en ambos sin pensar en la ABI. Para confirmar la ABI real de un dispositivo:
> ```bash
> adb -s <SERIAL> shell getprop ro.product.cpu.abi     # p.ej. arm64-v8a
> ```

### 2.2 Conectar adb a los dos dispositivos

**Teléfono:** activa *Opciones de desarrollador → Depuración USB* y conéctalo por USB.

**Android TV AOC:** activa *Ajustes → Preferencias del dispositivo → Acerca de → pulsa 7 veces en "Compilación"* para desbloquear desarrollador; luego *Opciones para desarrolladores → Depuración USB / Depuración por red* ON. Como la TV suele ser incómoda por USB, conéctala **por red**:

```bash
# Con la TV conectada temporalmente por USB (o si expone adb tcpip), habilita adb por red:
adb -s <SERIAL_TV_USB> tcpip 5555
adb connect 192.168.1.50:5555      # IP LAN de la TV (de §1)

# Verifica que adb ve AMBOS dispositivos y anota sus seriales:
adb devices -l
#   192.168.1.50:5555   device   (TV)
#   ABCD1234XYZ         device   (teléfono por USB)
```

A partir de aquí usa siempre `-s <SERIAL>` para no equivocarte de dispositivo.

### 2.3 Instalar

```bash
# APK universal en ambos:
adb -s <SERIAL_TV>    install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <SERIAL_MOVIL> install -r build/app/outputs/flutter-apk/app-release.apk

# (Si usaste --split-per-abi, instala el arm64 en cada uno:)
# adb -s <SERIAL_TV>    install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# adb -s <SERIAL_MOVIL> install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### 2.4 Permiso de red local (Android 16 / 17) — IMPORTANTE

El proyecto compila con **targetSdk 36 (Android 16)**. El manifest declara `INTERNET` y `CHANGE_WIFI_MULTICAST_STATE`, que es lo que hoy usa mDNS + WebSocket. En Android **16/17** Google está introduciendo un **permiso de red local en runtime** (`NEARBY_WIFI_DEVICES` / el futuro `ACCESS_LOCAL_NETWORK`) que puede exigirse para descubrir/abrir sockets a otros dispositivos de la LAN — y **no está exento por venir de sideload** (riesgo R10).

Comprueba y, si aplica, concede el permiso en **ambos** dispositivos (sender y receptor):

```bash
# Ver el estado de permisos de la app:
adb -s <SERIAL_TV>    shell dumpsys package info.breisner.rensi.iptv | grep -i "permission\|granted"

# Conceder el permiso de dispositivos cercanos (si el dispositivo lo pide):
adb -s <SERIAL_TV>    shell pm grant info.breisner.rensi.iptv android.permission.NEARBY_WIFI_DEVICES
adb -s <SERIAL_MOVIL> shell pm grant info.breisner.rensi.iptv android.permission.NEARBY_WIFI_DEVICES
```

> **Nota honesta:** estos permisos **no están declarados aún en el `AndroidManifest.xml`** de esta rama. En la mayoría de Android TV y teléfonos actuales (Android 13–15) el descubrimiento funciona solo con `CHANGE_WIFI_MULTICAST_STATE`, y el `pm grant` de arriba puede responder *"Unknown permission"* o *"not declared"* — es esperable, ignóralo. **Solo** si la validación falla en un dispositivo con **Android 16+** por descubrimiento bloqueado, la causa probable es este permiso faltante: habría que declararlo en el manifest y reconstruir (queda como tarea de la fase F1, fuera del alcance de esta guía).

---

## 3. En el Android TV: abrir la app y que quede de receptor

1. En el **launcher leanback** de la TV aparece **"Rensi IPTV"** (tiene banner de TV y categoría `LEANBACK_LAUNCHER`). Ábrela. O por adb:

   ```bash
   adb -s <SERIAL_TV> shell monkey -p info.breisner.rensi.iptv -c android.intent.category.LEANBACK_LAUNCHER 1
   ```

2. **Navega IPTV con normalidad** (reproduce un canal, entra al catálogo). La app funciona igual que siempre.
3. **En paralelo, ya está escuchando como receptor** de forma transparente: el `TvReceiverHost` levantó el WebSocket y el anuncio mDNS al arrancar. No hay que activar nada. Verás el **PIN** solo cuando un teléfono intente conectarse (§4).

Verificación por logcat de que el receptor arrancó (opcional pero recomendable dejarlo corriendo en otra terminal):

```bash
adb -s <SERIAL_TV> logcat -c    # limpia el buffer
adb -s <SERIAL_TV> logcat | grep -iE "bonsoir|_rensi-cast|WebSocket|flutter"
# Deberías ver actividad de bonsoir/broadcast al abrir la app.
```

---

## 4. En el teléfono: enviar un canal a la TV

1. Abre **Rensi IPTV** en el teléfono y reproduce un **canal en vivo**.
2. Sobre el video, arriba a la derecha, pulsa el botón **cast** ("Enviar a la TV").
3. La app **descubre** la TV (fase *buscando* → aparece **"Rensi TV"**). Con una sola TV, conecta directo; con varias, aparece una lista para elegir.
4. En la **TV** aparece a pantalla completa un **PIN de 6 dígitos** (naranja, grande).
5. **Teclea ese PIN en el teléfono** y confirma ("Emparejar").
6. Si el PIN es correcto, el modal se cierra, el teléfono muestra la **pantalla de control** (`CastingScreen`: destino, título, ± canal, play/pausa, detener) y la **TV empieza a reproducir el canal**. El video local del teléfono se libera (handoff).

> El botón "Enviar a la TV" está disponible para **vivo, películas (VOD) y series**. Los controles de canal ± solo se muestran en vivo.

---

## 5. Checklist de verificación

Marca cada punto sobre el hardware real:

- [ ] **Descubrimiento OK** — el teléfono encuentra "Rensi TV" en pocos segundos.
- [ ] **PIN OK** — el PIN de la TV se acepta en el teléfono; un PIN incorrecto se **rechaza** (y tras 3 intentos fallidos la TV cierra la conexión — hay que reintentar el flujo).
- [ ] **La TV reproduce el canal real** — se ve el video en vivo en la TV (no un mirror del teléfono; es stream directo del servidor).
- [ ] **El móvil libera su reproducción** — al empezar a castear, el teléfono deja de reproducir (pasa a la pantalla de control). **No hay doble conexión** contra el proveedor. Verifícalo idealmente en un proveedor con `max_connections=1`: si el canal sigue en la TV sin cortarse por "límite de conexiones", el handoff funcionó.
- [ ] **Zap ±** — desde el teléfono, "canal siguiente/anterior" cambia el canal en la TV con latencia comparable a la del player local.
- [ ] **Película (VOD)** — abre una película en el teléfono → "Enviar a la TV" → la TV la reproduce (URL `/movie/…` con extensión correcta).
- [ ] **Episodio (series)** — abre un episodio → "Enviar a la TV" → la TV lo reproduce (URL `/series/…`).
- [ ] **Reconexión** — con el casting activo, **apaga y vuelve a encender el Wi-Fi del teléfono** unos segundos. El teléfono debe **reconectar solo** (backoff 1-2-4-8-16 s) y **recuperar el control sin volver a pedir el PIN** (lo tiene cacheado). La TV debe seguir/retomar la reproducción.
- [ ] **Decode por HW fluido** — el video va fluido, sin tirones ni frames perdidos (esto es lo que el emulador **no** valida: forzaba render por software). Ver §6 para confirmar por logcat que usa `mediacodec` y no SW decode.
- [ ] **Subtítulos / audio** — las pistas embebidas (subtítulos y audios) del stream se reproducen en la TV. *Nota:* elegir pista de sub/audio **desde el teléfono** es una función aún **pendiente** (§14 del doc de arquitectura); en esta validación solo se comprueba que las pistas por defecto/embebidas funcionan en la TV.

---

## 6. Troubleshooting

### No descubre la TV
Es el fallo más común y casi siempre es de red, no de la app:

- **AP isolation / client isolation** → repite la prueba de ping cruzado de §1. Si el ping falla, arregla el router (§1) antes de seguir.
- **SSID / subredes distintas** → teléfono y TV deben estar en la **misma SSID y subred** (mismos 3 primeros octetos). Ojo con 2.4 vs 5 GHz separadas y con redes de invitados.
- **Multicast bloqueado** → algunos routers/mesh filtran multicast (mDNS es multicast a `224.0.0.251:5353`). Prueba en una red simple o en un hotspot de móvil de un tercer teléfono.
- **Firewall del router / "IoT VLAN"** → si tienes VLAN separadas para IoT o "smart devices", pon ambos en la misma VLAN.
- **Permiso de red local (Android 16+)** → ver §2.4; concede `NEARBY_WIFI_DEVICES` en ambos dispositivos.
- **Diagnóstico:** confirma que la TV **sí anuncia** con `avahi-browse -rt _rensi-cast._tcp` desde un PC en la red. Si el PC lo ve pero el teléfono no, el problema está entre teléfono↔TV (aislamiento), no en la TV.
- **Reintento rápido:** cierra y reabre la app en la TV (reinicia el anuncio mDNS) y vuelve a pulsar "Enviar a la TV" en el teléfono (la ventana de descubrimiento es de ~4 s).

### PIN rechazado
- Teclea exactamente los **6 dígitos** mostrados en la TV, sin espacios. El PIN es **por sesión**: si cerraste la conexión o reabriste la app en la TV, se genera un PIN nuevo — lee el que se ve **ahora** en pantalla.
- Tras **3 intentos fallidos** la TV cierra la conexión (`too_many_attempts`). Vuelve a pulsar "Enviar a la TV" para empezar de cero y obtener un reto nuevo.
- Si el campo de PIN no acepta entrada, asegúrate de que el modal está en fase de emparejamiento (mostró el nombre "Rensi TV" arriba).

### Video negro o verde en la TV
Casi siempre es **códec / decode por HW**, no la app (riesgo R5):

- Muchos canales IPTV usan **MPEG-2 video** y **AC-3 / E-AC-3 audio**, que **no todos** los chips de Android TV decodifican por HW. Un decode que falla puede dar **pantalla negra o verde** o solo audio.
- **Prueba primero con otro canal** que sea **H.264 + AAC** (lo más compatible). Si ese se ve bien y el otro no, es un problema de códec/HW de ese canal concreto, no del casting.
- Confirma qué decode está usando la TV por logcat mientras reproduce:

  ```bash
  adb -s <SERIAL_TV> logcat | grep -iE "mediacodec|hwdec|Enforcing S/W|codec|VideoOutput"
  ```
  - Ver `mediacodec` activo = decode por **hardware** (lo deseable; el player está afinado con `hwdec: mediacodec`, `vo: mediacodec_embed`).
  - Ver `Enforcing S/W rendering` = cayó a software (esperado en emulador, **no** debería pasar en la TV real; si pasa, ese chip no acelera ese códec).
- El mismo canal reproducido **directamente** en la app de la TV (sin casting) confirma si es la TV o el casting: si tampoco se ve directo, es la TV/códec.

### Se corta a los pocos segundos
- **Límite de conexiones del proveedor (`max_connections`)** — si el panel Xtream tiene `max_connections=1` y **no libera el slot al instante** cuando el teléfono suelta el stream, la TV puede ser rechazada al abrir (riesgo R4: algunos paneles tardan **decenas de segundos** en liberar). Síntoma: la TV reproduce 1-2 s y corta. Mitigación: espera ~30-60 s tras liberar el teléfono y reintenta, o usa un proveedor/cuenta con `max_connections ≥ 2` para la prueba.
- **Otra sesión activa** — cierra cualquier otra reproducción de esa cuenta (otro dispositivo, la web del panel) que esté ocupando slots.
- **Watchdog de stall** — en vivo, el player reabre el stream tras 15 s de estancamiento; cortes periódicos exactos pueden indicar un stream inestable del proveedor, no del casting.

### La reconexión no recupera el control
- Tras apagar/encender el Wi-Fi del teléfono, dale hasta ~30 s (el backoff llega a 16 s en el 5º intento). Si la TV cambió de IP al reconectar (DHCP), la reconexión puede fallar: detén y vuelve a castear.
- Verifica que el teléfono volvió a la **misma** red (no a datos móviles).

---

## Referencias

- `CASTING_ARCHITECTURE.md` — §3 opción **D**, §5.1 stack técnico, §6 riesgos (R5 decode HW, R10 permiso red local, R11 AP isolation, R12 INTERNET en release), §13-§14 estado y qué falta validar en hardware.
- Código: `lib/services/cast/` (protocolo + receptor + sender), `lib/controllers/cast_sender_controller.dart`, `lib/widgets/cast/` (UI: botón, modal, pantalla de control, `TvReceiverHost`), integración en `lib/widgets/player_widget.dart` y `lib/main.dart`.
