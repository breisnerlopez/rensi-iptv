# Handoff — campaña de emulación, diseño 10-pies, poda y v2.2.0

**Fecha:** 2026-07-20 · **Publicado como:** `v2.2.0+15` · **Estado: COMMITEADO Y RELEASED**

Léelo entero antes de tocar el árbol: **queda una acción de seguridad pendiente
que no puede hacer quien escribe esto** (§0).

---

## 0. Lo primero: acción de seguridad pendiente

**Hay que rotar la password de Xtream y la API key de TMDb.** No lo puede hacer
quien escribe esto.

Durante la validación se usaron credenciales reales (autorizadas por el
propietario, declaradas como volátiles). Consecuencias que siguen vivas:

- El AVD `tv_1080p` tiene una base SQLite **sin cifrar** con usuario y password
  en texto plano (`lib/database/database.dart`, tabla `UserInfos`).
- La transcripción de la sesión de trabajo es un canal cuyo daño **no se deshace
  borrando ficheros locales**.

Existe `~/android-lab/teardown.sh` (probado en dry-run, **nunca ejecutado**) que
destruye los AVDs y barre los sumideros del host: `~/.local/share/rtk/`,
`~/.claude/shell-snapshots/`, `~/.bash_history`, scratchpad. Su verificación
final grepea patrones **desde un fichero**, nunca desde la línea de comandos —
escribir el password para buscarlo lo metería en el historial.

La rotación no es opcional: sin ella el riesgo residual no decae con el tiempo.

---

## 1. Qué se publicó

La versión anterior de este documento avisaba de que todo era «un único conjunto
sin commitear» que «ya causó una revisión inauditable». Eso está resuelto: son
**4 commits temáticos sobre `90cb8eb`**, y **cada uno compila por separado**
(verificado en un worktree aparte con `flutter analyze`, no supuesto).

```
a8aa386  test: run the player suite for the first time, and cut v2.2.0
34ec437  i18n: stop shipping Spanish and Turkish to everyone
4255935  refactor: prune ~3,400 dead lines, and reconnect the history they orphaned
f5a069b  feat(tv): ten-foot type scale, and stop the poster printing its title twice
```

⚠️ **Lección del primer intento de separar, que salió mal.** Agrupé las claves
l10n en su propio commit y los intermedios dejaron de compilar: los `.arb`
llevaban *quitadas* las claves de las pantallas podadas, que en ese punto aún
existían. La dependencia era **mutua** — la poda necesita las claves nuevas y
las claves quitadas necesitan la poda — así que no se resolvía reordenando: hubo
que meter l10n dentro del commit de poda. **Separar por temas no basta; hay que
verificar que cada commit compila, y a veces el tema honesto es más grande de lo
que apetece.**

`v2.1.0` **nunca se llegó a taguear** (el release anterior es `v2.0.9`), así que
el enlace de comparación del CHANGELOG apunta a `v2.0.9...v2.2.0`. Si alguien
busca qué salió en 2.1.0: nada, existió sólo en `pubspec.yaml`.

### Métricas verificadas (no estimadas)

| | Baseline (`git stash`) | Ahora |
|---|---|---|
| `flutter analyze` errores | 0 | **0** |
| warnings | 64 | **53** |
| infos | 182 | **166** |
| `flutter test` | — | **338 pasan · 0 fallan · 1 skip** |

⚠️ **La versión anterior de este documento decía aquí que los 5 fallos eran
preexistentes y que no había que perseguirlos. Era un mal consejo.** No eran
cinco tests rotos: era que **todo el E2E del reproductor llevaba su vida entera
sin ejecutarse ni una vez**, muriendo en `MediaKit.ensureInitialized()` porque
faltaba libmpv. Se instaló (`apt install libmpv2`) y al ejecutarse por primera
vez aparecieron dos aserciones falsas que nadie podía detectar (ver §5).

El único skip que queda es `playback_real_test`, que exige credenciales de panel
reales — precisamente lo que no debe usarse mientras la rotación siga pendiente.

**Para tener la suite entera en verde hacen falta dos cosas fuera del repo:**

```bash
sudo apt install libmpv2 ffmpeg     # sin libmpv, todo test de player muere al cargar
scripts/make_testclip.sh            # genera build/testclip.mp4 (sintético, sin red)
flutter test --dart-define=RENSI_TESTCLIP="$PWD/build/testclip.mp4"
```

---

## 1.b Empezar aquí (lo que te ahorra la primera hora)

```bash
source ~/android-lab/env.sh                      # flutter NO está en el PATH por defecto
sudo apt install libmpv2 ffmpeg                  # sin libmpv, TODO test de player muere al cargar
scripts/make_testclip.sh                         # genera build/testclip.mp4 (sintético, sin red)
flutter test --dart-define=RENSI_TESTCLIP="$PWD/build/testclip.mp4"
```

Esperado: **338 pasan · 0 fallan · 1 skip**. Si ves 5 fallos, te falta libmpv;
si ves 3 skips, te falta el clip. **Un skip no es un aprobado**: su resultado por
defecto es «no comprobé nada».

El único skip legítimo es `playback_real_test`, que exige credenciales de panel
reales — y no deben usarse mientras §0 siga abierto.

### Lo próximo que yo cogería, por orden

1. **§0, la rotación de credenciales.** Es lo único cuyo riesgo no decae solo.
2. **`errorMessage` en el camino de carga** (§7): si la consulta del historial
   falla, el riel se queda vacío o rancio sin decir nada. El del *resume* ya se
   cerró; éste no.
3. **El camino que CREA huérfanos** no tiene test — sólo el síntoma al pulsar.
   Un refresh de M3U reasigna uuids (`m3u_parser.dart` + `updateM3UItemIdsByPosition`).
4. **`tmdb.search.history`** quedó huérfana en SharedPreferences: sin lector, sin
   borrador y fuera de `_backupKeys`. Ningún control de privacidad la alcanza.
5. **Los 53 warnings restantes** de `flutter analyze` (eran 64).

---

## 2. El laboratorio de emulación

Vive fuera del repo, en `~/android-lab/`.

```bash
source ~/android-lab/env.sh          # PATH del SDK y de Flutter 3.35.7
sg kvm -c "bash ~/android-lab/boot.sh tv_1080p"
```

**`sg kvm` no es opcional.** El grupo no se hereda en una shell ya abierta y el
emulador falla con «This user doesn't have permissions to use KVM». `boot.sh` no
lo lleva dentro.

AVDs creados: `phone_small` (360dp), `phone_compact`, `phone_large`,
`tablet_10` (800dp), `tv_720p`, `tv_1080p`, `tv_4k`.

### Trampas que costaron horas y no son evidentes

- **Un Android TV de 1080p reporta 960×540 dp LÓGICOS**, no 1920×1080. Todo
  umbral escrito con números de píxel (1200dp, etc.) **nunca se cumple** en un
  televisor. Esta es la causa raíz de media docena de defectos de esta sesión.
- **`pkill -f qemu-system` se mata a sí mismo**: el patrón casa con la propia
  línea de comandos de la shell que lo invoca. Usa `pkill -x qemu-system-x86_64`
  o filtra por PID. Lo mismo con cualquier `pkill -f` sobre un script propio.
- **Una build `--debug` tumba el emulador**: JIT sobre SwiftShader. Usa
  `--profile`. Consecuencia: **los desbordes de layout no se reportan** en las
  campañas de captura, porque las aserciones están desactivadas. No confíes en
  «0 overflows» de un log de profile.
- **Vulkan mata el emulador** con Impeller; `boot.sh` pasa `-feature -Vulkan`.
- La herramienta de shell corta a los 10 min: lanza las campañas en segundo
  plano y haz *polling*, no con un `timeout` mayor.

### Campaña de capturas

```bash
python3 scripts/fake_panel.py &       # 127.0.0.1:8799 por defecto
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/capture_test.dart -d emulator-5554 --profile \
  --dart-define=CAPTURE_PREFIX=tv_1080p
```

`scripts/fake_panel.py` es un panel Xtream mínimo que sólo responde
`get_short_epg`, valida ruta/`action`/credenciales y rechaza lo demás. Sirve para
probar la cadena EPG completa (widget → servicio → HTTP → parser) sin
suscripción. Bind en loopback; `--host 0.0.0.0` para un dispositivo real.

La captura `09b` hace `markTestSkipped` si el panel no está levantado — **su
resultado por defecto es «no comprobó nada»**. Es una asimetría conocida.

Capturas revisadas en `~/android-lab/shots/{tv_1080p,tablet_10,phone_small,...}`.

---

## 3. Qué se hizo

### 3.1 Fugas de credenciales (cerrado)

`lib/utils/credential_scrubber.dart` — enmascarado estructural por `Uri`,
*fail-closed*, con lista blanca de segmentos de ruta. Guards de error en
`main.dart` (`FlutterError.onError`, `PlatformDispatcher.onError`,
`ErrorWidget.builder`). Verificado en dispositivo real: **703 líneas de logcat
con la app autenticada contra el panel real, cero ocurrencias** de usuario,
password o key TMDb.

`ErrorWidget.builder` **necesita `Directionality`**: sin él, `Text` lanza, se
re-entra en el builder y recursa sin fondo (observado: 200 s colgado, 8,5 MB de
salida).

### 3.2 Tipografía de 10 pies

`AppThemes.tenFoot(context, phone)` — promueve un tamaño pensado para móvil a la
escala de 10 pies. 46 literales en superficies legacy alcanzables desde TV
(overlay del reproductor + pestaña de ajustes) pasan por ahí.

**`ResponsiveHelper.isTenFoot` ≠ `isDesktopOrTV`.** El primero es sólo TV nativa
o navegación direccional; el segundo dice sí a cualquier ventana ≥900dp — lo que
incluye un móvil grande en apaisado, que se sostiene a 30 cm. El tipo depende de
la **distancia**, el layout puede depender del ancho.

⚠️ En producción `isTenFoot` **es** la bandera nativa: nada en `lib/` fija
`NavigationMode.directional`. Un test que sólo inyecte esa rama no prueba nada.
Por eso existe `test/utils/ten_foot_native_test.dart`.

### 3.3 EPG

`EpgService` + `NowPlayingLine`: qué se emite ahora y barra de progreso en la
lista de canales. **`getShortEpg` devuelve `null` en fallo y `[]` cuando no hay
guía** — tratar «sin guía» como «reintentar» produjo 245 peticiones por scroll.
Backoff de 2 min tras fallo.

### 3.4 Poda de código muerto (~3.400 líneas)

Borrados: `global_search_screen`, `search_screen`, `content_card`,
`content_item_card_widget`, `category_section`, `m3u/m3u_items_screen`,
`watch_history_screen` y los 8 ficheros de `lib/widgets/watch_history/`. Más, en
los dos homes, `_buildContentPage`, `_navigateToSearch` y la cadena entera de
AppBars (7 métodos).

**Método:** borrar el conjunto candidato y dejar que el analizador diga qué
rompe; luego iterar eliminando lo que reporta como no referenciado hasta punto
fijo. Convergió en 3 rondas.

⚠️ **El bucle sólo ve elementos privados.** Los getters públicos son su punto
ciego: cuatro consultas de `WatchHistoryController` sobrevivieron a la poda y se
colaron en el camino caliente al reconectar el riel. Si repites el método,
revisa a mano lo público.

### 3.5 Historial reconectado

El riel «Seguir viendo» **existía desde el rediseño y nunca apareció**:
`continueWatching` tenía valor por defecto lista vacía y ningún llamador pasaba
nada. Ahora ambos homes cargan el historial, se suscriben, filtran y recargan.

- El filtro vive en **un solo sitio**: `resumableFrom()` en
  `lib/models/watch_history.dart`. Estaba duplicado en los dos homes.
- `onResume` es **`required`** en `RedesignHome`: olvidarlo era un home que no
  pintaba ni riel ni estado vacío. Ahora es error de compilación.
- Se repuso «Limpiar todo el historial» en Ajustes: la poda se había llevado la
  **única** forma de borrar historial, en un dispositivo compartido.

---

## 4. Abierto — con dueño pendiente

### 4.1 Bloqueantes del gate adversarial — CERRADOS

Los dos que quedaban abiertos, más el tercero declarado, están cerrados y
verificados por mutación:

1. **Resume fallido invisible** → `playContent` devuelve ahora `bool` y ambos
   homes muestran un SnackBar (clave `resume_failed`, los 10 idiomas).
2. **Retención al borrar una lista** → la purga vive en la transacción de
   `deletePlaylistById`, no en un camino de UI, así que ningún llamador puede
   saltársela. `deletePlaylistHistory` se eliminó por redundante.
3. **`getRecentlyWatched`** (y `getWatchHistoryByPlaylist`) eliminados; su test
   se reorientó a `getContinueWatching`, que es la consulta que alimenta el riel.

### 4.2 Lo que encontró la auditoría de `data` (y yo no)

La cascada de §4.1.2 **parecía** cerrada y no lo estaba. `favorites` es la otra
tabla con títulos elegidos por el usuario, con `playlistId` y sin clave foránea:
sobrevivía al borrado de la lista. El argumento escrito en el comentario del
propio cambio aplicaba palabra por palabra a esa tabla.

De las **14 tablas con `playlistId`**, faltaban 6 en la transacción: `favorites`
más 5 de catálogo. Ya están todas. Si añades una tabla con `playlistId`,
añádela también a `deletePlaylistById`.

### 4.2 Huecos de cobertura declarados (no tapados)

- Quitar `_history.addListener` **no rompe ningún test**: en el harness la
  pantalla se repinta igual porque el controlador de categorías notifica. El
  listener protege el orden «el historial resuelve después de que todo se
  asiente», que este entorno no produce. Está escrito en el fichero.
- El guard de recorte de desplegables tiene ~3× de holgura: sólo caza
  regresiones gruesas. **No se estrechó a propósito**: apretarlo para que
  «muerda más» sería falsear el oráculo.

### 4.3 Sin empezar

- **Assets de Play Store con contenido neutro.** Decisión ya tomada por el
  propietario: el catálogo real **no** entra en la ficha de la tienda.
- **Fase 7 (destrucción y rotación).** Script listo, no ejecutado.

---

## 5. Cómo trabajar aquí (lo que esta sesión aprendió a golpes)

Esto es lo más valioso del documento. Cuatro guards de test resultaron **vacuos**
en esta sesión, y **los cuatro los detectó la mutación, ninguno la lectura**:

1. Un test del `ErrorWidget` que verificaba una **copia** declarada en el propio
   test, no la función de producción.
2. Un guard de foco con `Focus.of(...)`, que resuelve al **ancestro** y por tanto
   no podía fallar — dentro de la aserción escrita para cazar ese mismo error.
3. Un guard de recorte que medía la caja exterior: **42dp optimista**, verde
   contra el defecto que existía para ver. Recortar texto dentro de una caja
   acotada **no lanza** `RenderFlex overflow`; hay que medir el ancho
   **intrínseco** contra `paragraph.constraints.maxWidth`.
4. Un bucle que buscaba un `ListTile` que una corrección posterior dejó de
   construir: `continue` incondicional en las cinco anchuras, con un comentario
   convincente al lado.

**Una quinta categoría, peor que las cuatro anteriores: el test que no corre.**
Los dos guards falsos del reproductor no los habría cazado la mutación, porque
el fichero entero moría en `setUpAll`. Un test que no se ejecuta no es un guard
débil: es **cobertura imaginaria**, y en el recuento aparecía como "5 fallos
preexistentes, no los persigas". Lo mismo con `import_test`, cuyo fixture
apuntaba a un scratchpad de una sesión muerta: `markTestSkipped` convertía "no
comprobé nada" en verde. Ambos se ejecutan ahora.

- **Antes de creerte una cifra de cobertura, mira los skips y los ficheros que
  no cargan.** Un `~1` en la salida de `flutter test` es tan sospechoso como un
  `-1`. Si un test se salta solo, su resultado por defecto es "no comprobó
  nada": eso hay que decidirlo, no heredarlo.
- **Nunca fijes una ruta absoluta de `/tmp` en un test.** Sobrevive a la sesión
  que la creó y luego el guard se salta para siempre. Genera el fixture con el
  código de producción (ver `import_test.dart`), que además elimina la
  dependencia de datos reales con credenciales.

**Reglas prácticas que salen de ahí:**

- Un guard nuevo no vale hasta que hayas **ejecutado** la mutación que debería
  matarlo. `cp fichero /tmp/bak`, muta, corre, restaura.
- Un test que alimenta el widget a mano prueba el widget, **no el cableado**. El
  bug real casi siempre está en quién pasa los datos. Monta la pantalla real.
- Cuidado con los **datos del seed**: un test positivo pasó porque el título que
  buscaba también estaba en el catálogo sembrado. Usa valores que sólo puedan
  venir del camino bajo prueba.
- Cuando un informe diga que tu cambio no tuvo efecto, **sospecha primero del
  entorno de medición**. Pasó tres veces: una campaña entera de capturas con el
  layout de TV en móviles (`setUpHarness` mockea `tv: true` por defecto), y dos
  veces leyendo un PNG anterior al cambio.
- Reporta **issues**, no sólo errores. «0 errores» ocultó un `@override` mal
  colocado durante una ronda entera.

---

## 6. Ficheros nuevos que conviene conocer

| Ruta | Qué es |
|---|---|
| `scripts/fake_panel.py` | Panel Xtream falso para la cadena EPG |
| `test/utils/ten_foot_native_test.dart` | Ejerce la señal de TV **nativa**, no la rama de test |
| `test/utils/ten_foot_scale_test.dart` | Mapeo de la escala: monotonía y jerarquía |
| `test/widgets/promoted_type_overflow_test.dart` | Recorte medido contra el área real del párrafo |
| `test/widgets/poster_title_anchor_test.dart` | El título del póster no se desplaza al enfocar |
| `test/widgets/continue_watching_test.dart` | El riel: progreso y reanudación |
| `test/integration/continue_watching_wiring_test.dart` | El **cableado**, sobre la pantalla real y ambos homes |
| `test/integration/clear_history_test.dart` | La única superficie de borrado del usuario: confirmar y cancelar |
| `scripts/make_testclip.sh` | Genera el clip que desbloquea los E2E reales del reproductor |

---

## 7. Estado del gate adversarial

- Tipografía / póster / desplegables: **4 rondas** de retador (25 refutaciones,
  todas resueltas) + auditoría independiente → **aprobado**, riesgo residual
  bajo, 23 mutantes no equivalentes, 23 muertos.
- Poda + historial: la auditoría de dimensión **data** que faltaba **ya se
  ejecutó**. Falló **NO ACEPTABLE, bloqueado con dos condiciones**; las dos se
  cerraron (cascada de `favorites` + cobertura de la superficie de borrado),
  cada una verificada mutando producción. 9 mutantes no equivalentes, 9 muertos.

### Hallazgos del auditor NO bloqueantes, aún abiertos

- ~~Una fila huérfana es indeleble~~ **CERRADO.** `removeHistory` ya tiene dos
  llamadores: mantener pulsado sobre la tarjeta del riel (OK largo en el mando)
  con diálogo de confirmación, y una acción «Eliminar» en el SnackBar de resume
  fallido — que es el momento exacto en que el usuario descubre la entrada
  muerta. **La retirada es ofrecida, nunca automática**: segar la fila sola al
  fallar el lookup borraría historial válido durante un refresh de catálogo a
  medias. `onRemove` es `required` en `RedesignHome` por la misma razón que
  `onResume`.
- `errorMessage` sigue sin lector en el camino de **carga** (sólo se cerró el de
  resume): si la consulta falla, el riel queda vacío o rancio sin decir nada.
- `_playLiveStream` (rama Xtream) pasa un `liveStream` posiblemente nulo en vez
  de lanzar `StateError` como las otras tres ramas. Hoy inalcanzable sólo
  porque `resumableFrom` excluye live.
- El texto de "limpiar todo el historial" no advierte de que **cruza playlists**
  (el alcance global sí está fijado por test).
- `tmdb.search.history` quedó huérfana en SharedPreferences al borrar
  `global_search_screen`: sin lector, sin borrador y fuera de `_backupKeys`.
- El diálogo de borrado usa **la misma cadena** en el título y en el botón de
  confirmar.

### Deuda de i18n — CERRADA

No eran 7 cadenas: la capa `redesign/` **entera** estaba en español fijo. Se
localizaron **21** cadenas de cara al usuario en 8 ficheros. 14 claves nuevas en
los 10 idiomas; el resto reutiliza claves que ya existían (`search`, `live`,
`speed`, `nav_browse`, `nav_my_list`, `try_again`, `remove`…) — merece la pena
buscar antes de crear, porque había duplicados esperando.

Dos cosas que no eran sólo traducción:

- `loading_widget.dart` mostraba **"Yükleniyor..." en turco a todos los
  usuarios**. La función no recibía `BuildContext`, así que hubo que enhebrarlo
  por sus 3 llamadores.
- El saludo del home estaba fijado a "Buenas noches" — además de no traducirse,
  era **falso media jornada**. Ahora depende de la hora (`_greeting`), leída en
  el `build` para que se corrija al repintar.

**Quedan a propósito** los nombres de producto/protocolo (`Rensi`, `Xtream
Codes`, `M3U Playlist`, `XStream Playlist`) y los ejemplos de URL en los
`hintText`.

⚠️ Al localizar cadenas, comprueba los tests que las buscan por texto:
`find.text('En vivo')` deja de casar si la clave devuelve "En Vivo".
