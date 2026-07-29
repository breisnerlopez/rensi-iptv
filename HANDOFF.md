# Handoff — rensi-iptv

> **Actual (§A):** **v2.7.0 PUBLICADO** (2026-07-29) — filtro por género, búsqueda por
> estudio, reparto tocable, populares, voz en TV, seguir-viendo "ver todo". `main` limpio,
> release firmado por CI en Latest.
>
> **§A-hist:** v2.2.3 (fixes de TV) — superado, se conserva como detalle histórico.
> **§HISTÓRICO (§0 en adelante):** campaña v2.2.0 (emulación, diseño 10-pies, poda) —
> ya released. Las notas de laboratorio (§2) y de disciplina de test (§5) siguen siendo
> la guía evergreen. Detalle de usuario de cada versión: `CHANGELOG.md` + historial de git.

---

# §A — Estado ACTUAL (2026-07-29): v2.7.0 (publicado)

**Rama:** `main` (árbol limpio) · **Versión:** `2.7.0+29` (tag `v2.7.0`, release firmado por CI, assets en Latest: arm64/armeabi-v7a/x86_64 APK + aab + linux.zip).
**Estado:** ✅ Publicado. Suite **392 pass / 2 skip**, `flutter analyze lib/` 0 errores, `flutter gen-l10n` 10 idiomas. Gate adversarial (retador + auditor) resuelto en los dos lotes del release.

> Contexto: entre v2.2.3 y v2.7.0 se shipearon en cadena v2.2.4–v2.6.2 (perf/escala TV, TMDb Phase 1/2, búsqueda por actor, live en búsqueda global, self-heal de extensión, `tmdb_id`). Detalle de usuario en `CHANGELOG.md` + historial de git. Este §A cubre v2.7.0; el §A viejo (v2.2.3) queda abajo como histórico.

## A.0 Qué trae v2.7.0 — mapa de código (detalle de usuario en CHANGELOG.md)
- **Búsqueda por estudio/plataforma:** `TmdbCompany` (`models/tmdb_search_result.dart`), `TmdbService.searchCompany`/`discoverByCompany` (`services/tmdb_service.dart`) con lista curada de networks (ids VERIFICADOS contra la API: HBO 49, Apple TV+ 2552, Netflix 213, Disney+ 2739, Amazon/Prime 1024). Nuevo `SearchFilter.studio`.
- **Reparto tocable → filmografía:** `onActorTap` hilado `TmdbCastRail`→`TmdbEnrichment`→`SearchDetailSheet`→`SearchRedesign.initialPerson`→movie/series. `_tmdbHasCast` (vía `onResolved`) evita duplicar el reparto nativo + TMDb.
- **Búsquedas recientes:** `lib/services/recent_searches_service.dart` (SharedPreferences, cap 10).
- **Voz en TV:** nativo `MainActivity.kt` MethodChannel `.../voice` → `RecognizerIntent` del sistema (sin permiso RECORD_AUDIO) + `lib/services/voice_search_service.dart` (timeout 120s anti-cuelgue). **CRÍTICO:** el manifest declara `<queries>` para `android.speech.action.RECOGNIZE_SPEECH` — sin eso, la visibilidad de paquetes de Android 11+ oculta el mic en todos lados (bloqueante que cazó el retador).
- **Populares en Home:** `_PopularRail` (`redesign/home_redesign.dart`), `PopularWindow {month,year,allTime}`, `GlobalSearchService.popular` (preserva ranking). Se oculta sin key de TMDb.
- **Seguir viendo → Ver todo:** `lib/redesign/continue_watching_all_screen.dart`, `resumableFrom(...).take(20)`, reactivo (`ListenableBuilder` sobre `WatchHistoryController`).
- **Filtro por GÉNERO** (Explorar + Buscar + pulido del selector de categoría en Live) — ver A.0.1.
- **Fixes:** tráiler no tapado + D-pad abajo → botón play (autofocus); dedup de búsqueda por `(id|mediaType)`; dedup de reparto en series; info en el idioma correcto + fallback al original; los avisos no-fatales del player (`force-seekable`) ya no cortan el live.

### A.0.1 Filtro por género (arquitectura clave)
- **`lib/utils/genre_utils.dart`** = parser ÚNICO: `genreOf`/`splitGenres`/`enumerateGenres`/`itemHasGenre`. Match **en memoria, token-exacto**, contra géneros derivados del catálogo → **a prueba de acentos por construcción** (mismos bytes en el chip y en el ítem; NO usar SQL `LIKE`, que pliega solo ASCII y reintroduce el bug de acento). Separadores `,` `/` `\` `|` `;` + coma árabe, **pero NO `&`** (para no fragmentar géneros TMDb como "Action & Adventure"). `controllers/category_detail_controller.dart` refactorizado sobre él. Tests: `test/utils/genre_utils_semantics_test.dart` (7).
- **Explorar (`redesign/browse_redesign.dart`):** chips de género sobre el **catálogo COMPLETO** vía el sentinel `kAllCategoryId` + `ContentService.fetchContentByCategory` (mismo path que "Ver todo"), memoizado una vez. **GUARD:** `useFull = _fullLoaded && (movies||series no vacío)` — `content_service.dart::_fetchM3uContent` NO honra el sentinel → devuelve vacío → cae a previews (M3U no trae `genre`, así que su fila de género simplemente se oculta). Fue un bloqueante del retador (dejaba Explorar en blanco en M3U).
- **Buscar (`services/global_search_service.dart`):** `SearchFilter.genre` local-only (`enumerateLocalGenres`/`searchLocalByGenre`); catálogo **memoizado por `playlist.id`** (el auditor detectó recarga completa por cada tap de género = riesgo de ANR en TV de gama baja).

## A.0.2 Pendientes para el siguiente equipo (por prioridad)
| # | Pendiente | Responsable | Bloqueante |
|---|-----------|-------------|------------|
| 1 | **Rotar credenciales filtradas** (§A-hist.5): token TMDb (aud `1840a927…`) + passwords Xtream | **USUARIO** | Seguridad |
| 2 | Validar en **TV real** lo que el emulador no cubre: **voz** (mando con micrófono), y **género/estudio/populares** contra el catálogo y la lista reales | Usuario/QA | No |
| 3 | **Play Store**: primera subida manual. 2 caveats CRÍTICOS: (a) la re-firma de Play App Signing rompe la actualización in-place del sideload firmado por CI; (b) riesgo real de rechazo por política IPTV (mantener la ficha "reproductor personal M3U/Xtream", sin playlists ni logos con copyright; probar en track interno primero). App ya declara Android TV (leanback/banner). `PRIVACY_POLICY.md` debe hostearse en URL pública. | Usuario | No |
| 4 | Espejar al **M3U home** cualquier fix que siga solo en Xtream (el usuario está en Xtream) | Equipo | No |

## A.0.3 Cómo trabajar aquí
- **Tests:** `flutter test` (392 pass / 2 skip). El host **bloquea todo HTTP real** → los tests de red/panel corren SOLO como `integration_test` en dispositivo, opt-in con `--dart-define`.
- **i18n:** editar `lib/l10n/app_*.arb` (10 idiomas) y correr `flutter gen-l10n`.
- **Emuladores:** `source ~/android-lab/env.sh`; lanzar con `sg kvm`. **tv_1080p (emulator-5554) = 960dp = la TV AOC real del usuario** → las capturas son fieles para layout/escala de TV. Puertos dinámicos por orden de arranque → verificar identidad con `adb -s emulator-XXXX shell wm size`.
- **Capturas de UI con datos reales:** `integration_test/v27_capture_test.dart` + `flutter drive --driver=test_driver/integration_test.dart --target=... --dart-define-from-file=<scratch>/tmdb_env.json` (token runtime-only, NUNCA commiteado). Usa una `AppDatabase` in-memory como shim; ojo con el **gotcha de timing del debounce** al teclear en el teclado TV (ráfaga `tap+pump()` y UN settle largo, no `pumpAndSettle` entre teclas — documentado en el test). Ensamblar en un Artefacto de revisión para el usuario ANTES de publicar.

## A.0.4 Git y release (obligatorio)
- **Nunca firmar** commits/PRs (sin `Co-Authored-By`, sin "Generated with Claude Code", sin trailers).
- **Commit/push solo cuando el usuario lo pida explícitamente.**
- Release: bump `pubspec.yaml` `X.Y.Z+BUILD` → prepend `CHANGELOG.md` → commit → `git tag vX.Y.Z` → `git push origin main` + **`git push origin vX.Y.Z` EXPLÍCITO** (`--follow-tags` NO sube tags ligeros → el CI no dispara). `release.yml` firma con `secrets.ANDROID_KEYSTORE_BASE64` (no hay keystore local — el APK con la MISMA firma solo lo produce el build del tag en CI) y publica los assets.

---

# §A-hist — v2.2.3 (fixes de TV) · SUPERADO por §A (v2.7.0) arriba, se conserva como referencia

**Rama:** `main` · **Versión publicada:** `2.2.3+18` (tag `v2.2.3`). v2.2.2 salió antes el mismo día.
**Estado:** ✅ v2.2.2 released. **v2.2.3 = lote de 4 fixes de Android TV** reportados por el usuario en TV real. Suite 383 pass / 2 skip · analyze 0 errores · gate del retador *aprobado-con-correcciones* (3 correcciones aplicadas, sin auditor — no alto riesgo).

**v2.2.3 — qué se arregló (todo preexistente salvo donde se indica):**
- **#1 Lentitud (durante el uso):** `focus_highlight.dart` — `RepaintBoundary` en cada tile + eliminada la sombra `BoxShadow(blur:18)` animada que se re-rasterizaba en cada salto de foco (causa raíz confirmada por traza). Pestañas perezosas (`IndexedStack` construye cada página al visitarla, `_visitedTabs`). Preview "Ver todo" con SQL `ORDER BY createdAt DESC LIMIT` (`getRecentVodStreamsByPlaylistId`/`getRecentMovies`) en vez de cargar+ordenar 40k filas en el hilo de UI.
- **#2 Franja del nav rail:** overscan movido a `Padding` externo; el panel tintado mide `_tvNavWidth*tvScale` y arranca a ras (antes el overscan se pintaba dentro del rail).
- **#3 "Todo muy grande":** `ResponsiveHelper.tvScale = (ancho/960).clamp(0.72,1.12)` — wrapper `textScaler` en `main.dart` (todo el texto) + tamaños dimensionales del nav; devuelve 1.0 en 960dp (sin cambios) y si el usuario tiene font-scale de accesibilidad (no encoge → evita overflow). Causa raíz: el tamaño de TV se ataba a un booleano, no a la resolución reportada.
- **#4 Overlay de OK que parpadea:** `video_settings_widget.dart` — traga select/enter hasta el primer KeyUp SOLO si OK está físicamente presionado al abrir (`HardwareKeyboard.logicalKeysPressed` en initState), para no comerse el primer OK cuando el panel se abre por Menu/tecla-audio/tap.

**⚠️ Validación pendiente EN TV REAL** (el emulador corre a 960dp/host rápido, no puede validarlo): que la navegación se sienta fluida (#1), que la escala quede bien y en TVs <900dp / con font de accesibilidad (#3), el primer OK del panel de subtítulos (#4), y que la tira "Ver todo" no quede corta con proveedores de nombres basura (#6). Diagnóstico completo por 5 agentes de investigación; el M3U home (`m3u_home_screen.dart`) tiene el MISMO patrón de franja del rail (#2) sin arreglar aún — el usuario está en Xtream.

## A.0 Pendientes para el siguiente equipo (por prioridad)

| # | Pendiente | Responsable | Bloqueante |
|---|-----------|-------------|------------|
| 1 | **Rotar 3 credenciales filtradas** (ver §A.5) — sigue vivo pase lo que pase | **USUARIO** (fuera de mi alcance) | Seguridad |
| 2 | Verificar **Feature A** (playback Jurassic) + **fixes de TV v2.2.3** en dispositivo real | Usuario/QA | No |
| 3 | Espejar el fix #2 (franja del rail) y #3 (tvScale) al **M3U home** si aplica | Equipo | No |

✅ **Commit + push + release `v2.2.2` — HECHO** (2026-07-26). El `release.yml` (tag `v*`) firmó y publicó los assets; run "Create Release" = success.

**✅ Ronda de dispositivo del home post-fix — ejecutada (2026-07-26).** Target nuevo
`integration_test/homecheck_test.dart` (siembra la BD con `seedXtreamHome`, sin red, sin
credenciales y **sin MediaKit** — no se cuelga en las capturas del player como la campaña
completa). Corrido en **phone_compact (393dp)** y **tv_1080p (960dp)** vía `flutter drive --profile`.
Resultado: home móvil y 10-pies renderizan **sin overflow**, con **rails distintos y sin duplicar**
(agregado "Todas las películas" + categoría "Acción", cada una una sola vez → confirma el fix del
auditor en el árbol de widgets real), foco correcto, y **línea de refresh ausente** (correcto: sin
refresh activo, y nunca en TV). Capturas en `build/screenshots/{phone_compact,tv_1080p}_home_hero.png`,
`_home_rail.png`, `_settings.png`. NOTA: esto valida el RENDER; sigue pendiente la validación de
Feature A (playback real) que solo el usuario puede hacer con el título Jurassic.

**✅ Veredicto del auditor (data) — resuelto.** El auditor confirmó los 5 bloqueantes del retador
como bien resueltos, PERO encontró **un defecto nuevo bloqueante**: `_loadCategories` solo hacía
`.add()`/`.insert()` (ningún `.clear()`), así que `refreshInBackground` llamándolo por 2ª vez
**duplicaba todo el catálogo** en Home/Explorar (ruta feliz, garantizado). **Corregido**:
`_loadCategories` ahora construye en listas temporales y las vuelca con `..clear()..addAll()` al
final (publish atómico; un fallo a mitad deja el catálogo viejo intacto). Menor: `isPlayerActive=true`
movido al final de `initState` (un fallo de init ya no deja el refresh desactivado). Verificado por
**mutación** (quitar los `.clear()` hace fallar el test nuevo) + suite 383 verde. Test de regresión:
`test/controllers/home_controllers_test.dart` → grupo "catalogue reload is idempotent".

**Trabajo sin commitear** (todo en `main`, working tree):
```
 M lib/controllers/xtream_code_home_controller.dart   (Feature B + fix auditor: _loadCategories idempotente, hook debugReloadCategories)
 M lib/database/database.dart
 M lib/repositories/iptv_repository.dart
 M lib/repositories/user_preferences.dart
 M lib/screens/xtream-codes/xtream_code_data_loader_screen.dart
 M lib/screens/xtream-codes/xtream_code_home_screen.dart
 M lib/services/player_state.dart
 M lib/utils/build_media_url.dart
 M lib/widgets/player_widget.dart                      (Feature A + fix auditor: isPlayerActive al final de initState)
 M test/controllers/home_controllers_test.dart         (test de idempotencia)
?? test/utils/build_media_url_test.dart
?? integration_test/homecheck_test.dart                (ronda de dispositivo solo-home, sin player)
```

## A.1 Feature A — Auto-heal de extensión VOD (fix de "failed to recognize file format")

**Causa raíz:** el panel Xtream a veces reporta una `container_extension` obsoleta
(app guardó `.mkv`, panel sirve `.mp4`). Pedir el `.ext` equivocado devuelve **HTTP 200
con una página HTML de error**, que libmpv rechaza con *"failed to recognize file format"*.
Reproducido con *Jurassic World: El Renacer* (stream_id 1075332; panel=`mp4`, app=`mkv`;
`.mkv`→HTML, `.mp4`→media real).

**Cambios:**
- **`lib/utils/build_media_url.dart`** — `buildMediaUrl` defensivo (nunca genera `.null`);
  `swapUrlExtension(url, ext)` respeta query strings; `const kVodExtensionCandidates = ['mp4','mkv','avi']`.
- **`lib/database/database.dart`** — `updateVodStreamContainerExtension(streamId, playlistId, extension)`
  persiste la ext ganadora. PK de `VodStreams` = `{streamId, playlistId}`.
- **`lib/widgets/player_widget.dart`** — self-heal: solo VOD+Xtream, solo si el error contiene
  `recognize`/`format`, prueba candidatos no intentados (`_triedExtensions`), **cap 2 intentos**.
  `_reopenCurrent()` reconstruye la `Playlist` **preservando la cola** (no rompe "siguiente").
  Al reproducir OK, **persiste la ext en DB**. `_resetHealStateIfContentChanged()` resetea al cambiar `contentItem.id`.
- **`test/utils/build_media_url_test.dart`** (NUEVO) — 10 tests deterministas.

⚠️ El test on-device de heal se **eliminó**: el error de demux de media_kit se emite
*después* del pump budget + teardown (que anula `AppState.currentPlaylist`), no reproducible
en emulador. La lógica es correcta en producción (currentPlaylist siempre existe durante
reproducción). **Única verificación 100% válida = dispositivo real con el título Jurassic** (pendiente A.0.3).

## A.2 Feature B — Refresh de catálogo en 2º plano tras 4h (con indicador)

Pedido: *"si un usuario entra después de 4 horas actualice en segundo plano mostrando algún
indicador que está actualizando las listas"*. Revisado por gate adversarial completo (retador
REFUTÓ con 5 bloqueantes → corregidos; UX pidió quitar anuncios ruidosos; **auditor de data
cerró un 6º bloqueante** — duplicación de rails, ver §A.0).

**Cambios:**
- **`lib/repositories/iptv_repository.dart`** — los 3 fetch (live/movies/series) envuelven
  **delete+insert en `_database.transaction(...)`** → sin ventana en que un lector
  (historial/búsqueda/favoritos) vea la tabla vacía.
- **`lib/repositories/user_preferences.dart`** — `setLastSync(playlistId, when)` / `getLastSync(playlistId)`.
- **`lib/controllers/xtream_code_home_controller.dart`** — `refreshInBackground()`: guard de
  reentrancy síncrono (`_isRefreshing`), guard `_disposed`, fetch espaciados (el panel throttlea
  ráfagas → 400); si cualquiera devuelve null **aborta sin marcar `lastSync`** (no miente sobre
  sync exitosa); bail si cambió la playlist (`AppState.currentPlaylist?.id != pid`). Override de
  `notifyListeners()` con guard `_disposed` (patrón de `WatchHistoryController`).
- **`lib/services/player_state.dart`** — `static bool isPlayerActive` (set en initState/dispose
  del player) → no refresca durante reproducción/PiP.
- **`lib/screens/xtream-codes/xtream_code_home_screen.dart`** — `with WidgetsBindingObserver`;
  trigger en **arranque** (post-frame) y **resume**. `_maybeBackgroundRefresh()` guards: mounted,
  playlist Xtream, `!isPlayerActive`, `!isRefreshing`, `lastSync > 4h`, y en **móvil solo Wi-Fi/ethernet**
  (TV siempre), connectivity en try/catch. `_RefreshLine`: `LinearProgressIndicator` 2.5px neutro,
  **visible solo si el refresh tarda >3s**, **nunca en TV** (`ResponsiveHelper.isTelevisionDevice`).
- **`lib/screens/xtream-codes/xtream_code_data_loader_screen.dart`** — marca `setLastSync(...)`
  tras la carga completa inicial exitosa. `const _staleAfter = Duration(hours: 4)`.

**Fix notable:** `Connectivity().checkConnectivity()` lanzaba `_TypeError` en tests (mock del
harness devuelve String, la API espera `List<ConnectivityResult>`). Solución: try/catch que omite
el refresh ante error — robusto también en producción.

## A.3 Test de escala real (ya commiteado)

`integration_test/real_panel_scale_test.dart` — ingesta real, opt-in vía dart-defines
`PANEL_HOST`/`PANEL_USER`/`PANEL_PASS`. Verificado: **40,025 VOD + 3,016 live + 4,671 series
en ~4.8s**. **Nunca hardcodear credenciales** — solo `--dart-define` en runtime. El panel
throttlea ráfagas (400 transitorio); los métodos del repo lo tragan como `null` sin reintento.

## A.4 Cómo correr los tests

- **Unit/widget host:** `flutter test` (esperado 382 pass / 2 skip). ⚠️ El host **bloquea HTTP real**.
- **Red/panel reales:** SOLO como `integration_test` en dispositivo, opt-in con `--dart-define`.
- Recordatorio de §1.b: `source ~/android-lab/env.sh` + `sudo apt install libmpv2 ffmpeg` + `scripts/make_testclip.sh`.

## A.5 🔴 SEGURIDAD — 3 credenciales filtradas (acción del USUARIO)

En un backup subido antes se filtraron credenciales reales. **DEBEN rotarse por el usuario**
(fuera de mi alcance) y **NUNCA re-exponerse** en archivos versionados, commits, capturas ni logs
(por eso este documento NO nombra hosts, cuentas ni claves):
- **La API key de TMDb** — rotar en la consola de TMDb.
- **Las dos cuentas Xtream** usadas durante el desarrollo — cambiar su password en cada panel.

Se guardaron solo en scratch gitignored (ya purgados) y se pasaron solo por `--dart-define`.
**Verificar que `git log -p` / archivos versionados no las contengan antes de cualquier push.**
(Esta es la misma clase de deuda que §0 histórico; sigue viva.)

## A.6 Git y release (obligatorio)

- **Nunca firmar** commits/PRs (sin `Co-Authored-By`, sin "Generated with Claude Code", sin trailers).
- **Commit/push solo cuando el usuario lo pida explícitamente.** El usuario prefiere `[skip ci]`.
- Release se dispara por **tag `v*`** → GitHub Actions `release.yml` firma el APK desde
  `secrets.ANDROID_KEYSTORE_BASE64` y publica assets.

## A.7 Siguiente paso concreto

1. ✅ Gate adversarial completo (retador + auditor de data) — bloqueante de duplicación de rails
   corregido y verificado por mutación. Suite 383 verde, analyze 0 errores.
2. ✅ Ronda de dispositivo del home post-fix ejecutada en phone (393dp) + TV (960dp) — render limpio,
   sin overflow, rails sin duplicar (ver §A.0).
3. Pedir al usuario verificación de Feature A en dispositivo real (título Jurassic) — playback, único
   punto que el emulador no puede validar.
4. Con OK del usuario: commit (`[skip ci]`, sin firmar) + push, luego tag `v2.2.2`.
5. Confirmar que la rotación de credenciales (§A.5) la hizo el usuario.

---

# §HISTÓRICO — campaña v2.2.0 (emulación, 10-pies, poda) · COMMITEADO Y RELEASED

**Fecha:** 2026-07-20 · **Publicado como:** `v2.2.0+15` · **Estado: COMMITEADO Y RELEASED**

Las secciones §2 (laboratorio de emulación) y §5 (disciplina de test) siguen siendo la
referencia evergreen para trabajar en este repo.

---

## 0. Nota de seguridad histórica (v2.2.0)

**Hay que rotar la password de Xtream y la API key de TMDb.** No lo puede hacer
quien escribe esto. *(Se solapa con §A.5; sigue vigente.)*

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
