# [2.16.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.15.0...v2.16.0) (2026-08-01)


### Features

* **Controla el volumen de la TV desde el móvil** al castear: un deslizador en el control de reproducción ajusta el volumen del contenido que suena en la TV (con anti-rebote para que no salte bajo el dedo)
* **La miniatura del contenido casteado ya muestra su carátula** en la TV — en el historial de "continuar viendo" y en el panel de pausa; antes salía vacía (viaja de forma segura como referencia de TMDb, sin exponer URLs arbitrarias)
* **"Mi lista" reúne tus favoritos de TODAS tus listas** en una sola vista (antes solo mostraba los de la lista activa), sin duplicar títulos y marcando de qué lista viene cada uno
* **El receptor de Android TV se rediseñó** — ya no se ve vacío en negro: fondo cálido, estado de conexión visible ("Visible como Rensi TV") y una guía de 3 pasos para enviar desde el móvil


### Bug Fixes

* **Salir de la app ya no pierde tu progreso:** si sales (o la cierras) mientras ves algo, "Continuar viendo" guarda dónde ibas — antes, al salir de golpe, no se guardaba
* **Guardar en favoritos es igual en películas y series:** un mismo icono de **marcador** en todas partes, con confirmación — antes las películas usaban un check y las series un corazón
* **Las series descargadas ahora avanzan al siguiente episodio al castearlas** a la TV (antes se quedaban en el último fotograma; el streaming ya avanzaba)


# [2.15.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.14.0...v2.15.0) (2026-08-01)


### Bug Fixes

* **actualizar la app ya no puede dejarla inutilizable:** una migración de base de datos fallaba al actualizar desde versiones antiguas (o si te habías quedado a medias en una versión reciente) y crasheaba al abrir; ahora la actualización llega bien y **preserva tu historial, favoritos y descargas**
* **casting — "Continuar viendo" ahora sí guarda y REANUDA:** lo que envías a la TV queda en tu historial y, al volver a enviarlo, **la TV arranca donde ibas** (antes empezaba desde el principio y a veces no se guardaba); y el panel de pistas muestra las pistas reales durante el casting
* **reproducción más robusta:** al recuperar la conexión **reanuda donde ibas** (no reinicia); avance rápido más **controlable** (no salta al final); **subtítulos apagados por defecto**; el panel de audio/subtítulos ya no aparece vacío; atrás pide **confirmación** antes de salir y cierra **solo el panel** abierto (no la reproducción); duración en formato reloj
* **búsqueda más precisa:** buscar **por actor** encuentra tus películas aunque el título esté en otro idioma; "Reproducir desde" ya no lista películas que solo comparten una palabra del título; dos películas del mismo nombre pero **distinto año** ya no se mezclan
* **al borrar una lista** también se eliminan sus **descargas** (antes quedaban huérfanas en disco)


# [2.14.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.13.2...v2.14.0) (2026-08-01)


### Features

* **La búsqueda agrupa la misma serie aunque esté escrita distinto entre listas:** "Rick & Morty", "Rick y Morty" y "Rick and Morty" se reconocen como la misma y muestran todas tus copias juntas para elegir
* **Hasta 100 resultados de tu catálogo** en la búsqueda (antes se cortaba mucho antes y podía dejar fuera contenido tuyo)
* **Explorar junta los duplicados por calidad:** una misma película que aparece como "4K", "60FPS", etc. se muestra una sola vez — sin perder títulos distintos ni doblajes (Latino/Castellano se mantienen separados)
* **"Populares por género" ya aparece** al elegir un género (incluidos los compuestos como "Action & Adventure")
* **"Todas las series" ya no queda enterrada** al fondo del inicio — ahora está arriba, junto a "Todas las películas"


### Bug Fixes

* **el aviso de "enviar a la TV" ya no aparece** antes de reproducir una descarga offline
* **arreglado un fallo visual del mini-control de casting** que rompía la pantalla de inicio mientras casteabas
* **la duración de vídeo/episodio se muestra bien** (antes salía con abreviaturas en turco)
* **la contraseña del proveedor ya no se puede copiar** mientras está oculta (solo si la revelas)


# [2.13.2](https://github.com/breisnerlopez/rensi-iptv/compare/v2.13.1...v2.13.2) (2026-07-31)


### Bug Fixes

* **las descargas ya funcionan (arreglo definitivo):** Android bloqueaba las descargas por HTTP (los proveedores IPTV usan HTTP, no HTTPS) mientras que la reproducción no se veía afectada — de ahí el "se reproduce pero no descarga". Se habilitó el tráfico HTTP para el descargador. Reproducido y verificado contra un proveedor real en emulador (descarga real de más de 1 GB sin errores)


# [2.13.1](https://github.com/breisnerlopez/rensi-iptv/compare/v2.13.0...v2.13.1) (2026-07-31)


### Bug Fixes

* **nº de temporadas correcto al elegir una copia:** ya no se queda corto (contaba solo las temporadas con episodios cargados; ahora refleja el total real del proveedor y no cuenta los "especiales")
* **copias en otras listas con nombre distinto:** al elegir dónde reproducir una serie, ahora también aparecen las copias de tus otras listas aunque estén con otro nombre (p. ej. el título en inglés), buscándolas por su ficha en todas tus listas. (Si una lista no la has abierto/sincronizado aún, su contenido no está disponible para buscar hasta que entres a ella)


# [2.13.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.12.2...v2.13.0) (2026-07-31)


### Features

* **Buscar y Explorar en TODAS tus listas a la vez:** la búsqueda y el apartado Explorar ahora fusionan el contenido de todas tus listas y lo de-duplican, en vez de mirar solo la lista activa. Al abrir un título se reproduce con las credenciales de la lista a la que pertenece
* **Elegir entre copias duplicadas:** cuando una serie está repetida (varias listas, o varios paquetes de temporadas), al abrirla ves TODAS las copias con su número de temporadas para elegir la que quieras (p. ej. la de 7 temporadas)
* **"Populares por género" en Explorar:** al elegir un género (p. ej. Animación) aparece un carrusel de populares de ese género — de este mes, de este año o de todo el tiempo
* **"Ver todo" en Todas las películas y nueva sección Todas las series** en el inicio
* **Orden por más recientes** (fecha de añadido a la lista) en Explorar
* **"Mi lista" ahora incluye tu Lista de deseos de TMDb:** los títulos que guardas desde el buscador aparecen junto a tus favoritos de IPTV
* **Sección Desarrollador** (Ajustes → Acerca de): todo el detalle técnico del proveedor — estado y caducidad de la cuenta, conexiones activas/máximas, datos del servidor, versión y más
* **Sinopsis y reparto en la TV al pausar:** ahora los envía el móvil junto a la orden de reproducción, así se ven aunque la TV no tenga configurada la clave de TMDb (y para series usa el nombre de la serie, no el del episodio)


### Bug Fixes

* **las descargas que fallaban:** ahora la descarga se identifica como un reproductor (User-Agent), que es lo que muchos proveedores exigen — antes rechazaban la conexión y la descarga fallaba sin llegar a bajar nada. Además, si vuelve a fallar, el detalle del error es más específico


# [2.12.2](https://github.com/breisnerlopez/rensi-iptv/compare/v2.12.1...v2.12.2) (2026-07-31)


### Bug Fixes

* **la reproducción en TV ya no se queda "colgada" sin salida:** cuando un contenido abría pero no llegaba a reproducir (buffering infinito en algunas TV), te quedabas en el círculo girando sin ninguna opción. Ahora, si tras unos segundos no arranca, vuelve a aparecer el botón **Reintentar** (alcanzable con el mando) — también entre episodios de una serie. Un stream solo lento (que sí va descargando) no lo dispara


# [2.12.1](https://github.com/breisnerlopez/rensi-iptv/compare/v2.12.0...v2.12.1) (2026-07-31)


### Features

* **Avance rápido incremental en la TV:** al adelantar/retroceder con el mando, mantener pulsado (o pulsar seguido) hace saltos cada vez más grandes — empieza en 15s, luego 1 min, 3 min y 5 min — para recorrer rápido películas y episodios largos. La barra muestra el punto al que vas a saltar y el salto se aplica al soltar (ya no recarga en cada pulsación)
* **"Siguiente episodio" en el reproductor:** botón para pasar al próximo episodio sin esperar a los créditos. En la TV aparece al pausar (baja con el mando y pulsa OK); en el móvil, en la barra de controles. Solo cuando hay un episodio siguiente


### Bug Fixes

* **tras adelantar ya no se queda "cargando":** al terminar de avanzar reanuda solo, sin tener que pulsar OK para que siga (algunas TV dejaban el vídeo en el icono de carga como si estuviera en pausa)


# [2.12.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.11.4...v2.12.0) (2026-07-31)


### Features

* **La TV la controla un móvil a la vez (toma de control):** si envías contenido desde un segundo móvil, ese pasa a mandar la TV y el móvil anterior deja de mostrar los controles de reproducción sin avisos molestos — simplemente su sesión termina (nada de notificaciones ni errores). Pensado para varios móviles en casa
* **Convivencia móvil↔TV — el casting manda:** mientras estás casteando, darle a "reproducir" a otro contenido en el móvil lo **envía a la TV** en vez de abrir doble reproducción; ya no se desincronizan los controles ni se queda "pegado" el contenido anterior
* **Descargas con nombre entendible:** los archivos se guardan con el **título del contenido** (p. ej. `Rick and Morty S01E01`) en vez de un código, y las descargas fallidas tienen un botón **Reintentar** directo en la lista


### Bug Fixes

* **Buscar "rick" ya encuentra "Rick and Morty":** al escribir el principio del título los resultados que coinciden por **nombre** salen primero — antes el orden alfabético + el límite de resultados podían dejar fuera la serie propia aunque la tuvieras
* **"Mi lista" se actualiza al marcar favoritos:** al guardar (o quitar) algo en tu lista aparece/desaparece al instante sin cambiar de pestaña, incluido "borrar todo"
* **Casting más fiable:** ya no se pide el código de emparejamiento de más (se recuerda el dispositivo de confianza aunque no reinicies la TV), no hay doble reproducción por la cuenta atrás de envío, y el envío no se queda colgado si algo falla al conectar


# [2.11.4](https://github.com/breisnerlopez/rensi-iptv/compare/v2.11.3...v2.11.4) (2026-07-31)


### Bug Fixes

* **TV en vivo más resistente con señal débil:** más colchón de buffer y **auto-reconexión de red** — si el stream se corta un instante, reconecta solo en vez de quedarse entrecortado o reiniciar. Pensado para conexiones malas (a cambio de un poco más de latencia al cambiar de canal)


# [2.11.3](https://github.com/breisnerlopez/rensi-iptv/compare/v2.11.2...v2.11.3) (2026-07-31)


### Bug Fixes

* **"Ver todo" en las categorías del inicio:** ahora sí aparece cuando una categoría tiene más títulos de los que caben en el carrusel — antes el inicio solo cargaba 10 por categoría y nunca detectaba que había más, así que el botón no salía nunca (aunque la categoría tuviera cientos)


# [2.11.2](https://github.com/breisnerlopez/rensi-iptv/compare/v2.11.1...v2.11.2) (2026-07-31)


### Bug Fixes

* **"Continuar viendo" se actualiza al instante:** en cuanto ves algo (en el móvil) o lo envías a la TV, la sección "Continuar viendo" del inicio se refresca sin tener que cambiar de pestaña — antes podía parecer que se "perdía" hasta recargar. Recuerda: ahí solo aparece lo que dejaste **a la mitad** (lo terminado y el vivo no)


# [2.11.1](https://github.com/breisnerlopez/rensi-iptv/compare/v2.11.0...v2.11.1) (2026-07-31)


### Bug Fixes

* **el vídeo ya no se reinicia desde el principio a media reproducción:** un pequeño corte de conexión reabría el stream sin necesidad y a veces perdía la posición; ahora solo se reabre si la reproducción se rompe de verdad y siempre reanuda donde ibas
* **primer envío a la TV:** si el primer arranque se atasca, ahora reintenta solo a los pocos segundos (antes había que pulsar Reintentar a mano)
* **el control de casting ya no tapa la barra inferior:** el mini-control se muestra por encima de los iconos de navegación mientras exploras


# [2.11.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.10.4...v2.11.0) (2026-07-31)


### Features

* **reproducir desde una lista al buscar:** en el detalle de búsqueda, "Reproducir desde" ahora **reproduce** el contenido de la lista elegida (antes no hacía nada) y ya no muestra listas duplicadas
* **saber qué se reproduce en la TV:** al pulsar OK / pausar / reanudar aparece la **barra de reproducción con el título** y el tiempo
* **info al pausar en la TV:** al pausar se muestra **título + sinopsis + reparto** (cuando hay datos de TMDb); si no, al menos el título
* **series por casting con avance automático:** al terminar un episodio en la TV, se envía **solo el siguiente** automáticamente
* **historial del casting:** lo que envías a la TV ahora aparece en el **histórico** de la pantalla de la TV y en "Continuar viendo" del móvil
* **"Ver todo" más visible:** las secciones (categorías y recientes) muestran una **flecha ›** para abrir la cuadrícula completa


### Bug Fixes

* **buscar por la primera palabra:** "Rick" ahora encuentra "Rick y Morty" (antes una película homónima de TMDb lo tapaba)
* **atrás durante la reproducción en la TV** ya no vuelve a la pantalla de carga: cada sesión de casteo usa una sola ventana de reproducción (antes se apilaban al cambiar de canal/episodio)


# [2.10.4](https://github.com/breisnerlopez/rensi-iptv/compare/v2.10.3...v2.10.4) (2026-07-31)


### Bug Fixes

* **la reproducción en la TV ya no se cuelga en el primer intento:** cada paso de la preparación (config de subtítulos, historial, cola de audio…) tiene ahora un tiempo límite; si uno tarda en tu caja de TV —lo que dejaba "Preparando…" colgado y obligaba a pulsar Reintentar— continúa igual con un valor por defecto, así arranca a la primera


### Features

* **versión de la app visible** en la pantalla de espera de la TV


# [2.10.3](https://github.com/breisnerlopez/rensi-iptv/compare/v2.10.2...v2.10.3) (2026-07-31)


### Bug Fixes

* **la carga en la TV ya no se queda en un círculo infinito sin salida:** la pantalla "Preparando…" ahora muestra el tiempo transcurrido y, si tarda demasiado, un aviso indicando en qué fase se quedó (conectando audio / abriendo el stream) y un botón **Reintentar** usable con el mando — así se puede recuperar en vez de quedarse colgado, y ayuda a diagnosticar dónde falla


# [2.10.2](https://github.com/breisnerlopez/rensi-iptv/compare/v2.10.1...v2.10.2) (2026-07-30)


### Bug Fixes

* **la TV se quedaba en un círculo de carga sin reproducir:** en el televisor ya no se retiene el vídeo en pausa esperando llenar el colchón — algunas cajas de TV no reportan la caché con el vídeo en pausa y quedaba colgado; ahora reproduce y solo monitorea, mostrando velocidad/buffer/estado reales mientras carga
* **indicador de carga más claro:** durante la conexión inicial se muestra "Preparando…" en vez de un círculo sin información


# [2.10.1](https://github.com/breisnerlopez/rensi-iptv/compare/v2.10.0...v2.10.1) (2026-07-30)


### Bug Fixes

* **enviar a la TV se quedaba en carga infinita:** el televisor esperaba a llenar un colchón que en algunas cajas de TV nunca se confirmaba, y el vídeo quedaba retenido para siempre; ahora, si no hay datos o pasa un máximo, arranca igual (y se muestra un breve "preparando" al recibir el contenido)
* **cruce móvil↔TV al detener:** al parar (o cerrar con el mando en la TV) ahora el televisor avisa al móvil, que sale de "transmitiendo" al instante — se acabó el círculo de carga colgado en el celular y el audio fantasma de la película sonando en el móvil tras detener en la TV
* **el "stop" no siempre detenía la TV:** se garantiza que la orden de detener salga antes de cerrar la conexión, y el reproductor local se cierra correctamente al enviar a la TV (antes se cerraba el diálogo en vez del reproductor)
* **icono de la pantalla de la TV:** se reemplaza el emoji de televisor por el logo de la app (la "R")


# [2.10.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.9.0...v2.10.0) (2026-07-30)


### Features

* **descargas en segundo plano de verdad:** una descarga sigue aunque salgas de la app o apagues la pantalla —corre como servicio en primer plano con notificación de progreso— y su estado sobrevive a cerrar la app
* **saber por qué falló una descarga:** cuando una descarga falla ahora se muestra el motivo (página de error del panel, error HTTP, cancelada, archivo no disponible…) y un botón para **Reintentar**
* **lo que envías a la TV queda en "Continuar viendo":** al reproducir en la TV desde el móvil (en vivo, película o serie) se guarda la posición para retomarlo; nunca reduce el avance que ya tenías en ese título


### Bug Fixes

* **contenido que se reproducía pero no se descargaba:** algunos títulos reproducen bien pero el panel sirve una extensión de archivo obsoleta y la descarga bajaba una página de error; ahora la descarga la **auto-corrige** (prueba mp4/mkv/avi) igual que ya hacía el reproductor
* **reproducir una descarga:** al tocar una descarga completa se abre en el reproductor; si el archivo ya no está en el dispositivo, se avisa y se marca en vez de fallar en silencio


# [2.9.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.8.3...v2.9.0) (2026-07-30)


### Features

* **descargas offline (películas y episodios):** ahora puedes **descargar** una película o un episodio para verlo **sin conexión**. Un botón de descarga en la ficha muestra el estado (encolar, en curso, disponible offline) y una nueva pantalla **Descargas** (en Ajustes) lista todo con su progreso y acciones de **pausar/reanudar/cancelar/borrar**, más un indicador del **espacio usado**. Al terminar de ver un contenido descargado, se libera solo (borrar-al-ver, con un tope de espacio que purga lo más antiguo)
* **enviar una descarga a la TV por Wi‑Fi (sin gastar Internet):** desde **Descargas → Enviar a la TV**, el móvil sirve el archivo local por la red y la TV lo reproduce en streaming **sin consumir datos**. Requiere estar en la misma red Wi‑Fi que la TV (si no, lo avisa)
* **la TV como reproductor dedicado:** en un Android TV la app se reduce a lo esencial —**reproductor + histórico de lo reproducido + ajustes de reproducción**—, sin listas ni búsqueda; sigue recibiendo lo que envíes desde el móvil y muestra el PIN de emparejamiento


# [2.8.3](https://github.com/breisnerlopez/rensi-iptv/compare/v2.8.2...v2.8.3) (2026-07-30)


### Features

* **carga inteligente para conexiones lentas:** al abrir un canal, película o episodio, antes de reproducir se muestra **a qué velocidad se está descargando** y cuánto **buffer** se ha acumulado; la reproducción empieza sola cuando hay colchón suficiente para verla **fluida**, o puedes forzarla con **"Reproducir ahora"**. Si la conexión va lenta o no llegan datos, lo indica claramente en vez de quedarse en una carga infinita


# [2.8.2](https://github.com/breisnerlopez/rensi-iptv/compare/v2.8.1...v2.8.2) (2026-07-30)


### Features

* **enviar a la TV sin gastar datos:** al abrir un canal, película o episodio en el móvil, antes de empezar a cargar el video aparece un aviso breve para **"Enviar a la TV"** o **"Reproducir aquí"** (con una cuenta atrás corta que reproduce en el teléfono si no eliges). Así puedes mandarlo al televisor sin consumir datos cargándolo primero en el teléfono


### Bug Fixes

* el botón de enviar a la TV ya no tapa el botón de configuración del reproductor


# [2.8.1](https://github.com/breisnerlopez/rensi-iptv/compare/v2.8.0...v2.8.1) (2026-07-30)


### Features

* **recordar tu televisor una semana:** ahora solo escribes el código de emparejamiento la **primera** vez que envías a un televisor; durante los **7 días** siguientes los envíos a esa misma TV van directos, sin pedir el código otra vez (incluso si reinicias la app en el televisor). Al cabo de la semana vuelve a pedirlo. Sin ajustes ni pasos extra


# [2.8.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.7.0...v2.8.0) (2026-07-30)


### Features

* **enviar la reproducción a tu Android TV (segunda pantalla):** abre un canal, película o episodio en el móvil y envíalo a tu televisor con el botón "Enviar a la TV" — la TV reproduce el contenido **directamente desde el servidor IPTV** y el teléfono queda como control remoto (sin duplicar la imagen ni retransmitir el video). Mientras la TV reproduce, **puedes seguir navegando y buscando** en el móvil: una barra de control persistente te deja pausar, cambiar de canal, elegir **audio y subtítulos**, y detener, sin volver a la pantalla de reproducción. La TV se descubre sola en tu red Wi-Fi y el emparejamiento es con un **código que aparece en el televisor**. Requiere tener la app **abierta en el Android TV** (funciona instalándola por sideload; no depende de Google Cast ni de Google Play)
* **casting seguro sin exponer tus credenciales:** el usuario y la contraseña de tu proveedor viajan **cifrados** por tu red local (AES-GCM) y nunca a ningún servidor; el canal con la TV usa **wss:// con fijación de certificado atada al código de emparejamiento**, de modo que solo tu televisor recibe el contenido. La reconexión es automática si el Wi-Fi parpadea


### Bug Fixes

* la inicialización del reproductor ya no aborta si `connectivity_plus` lanza un error en el chequeo de conectividad (observado en Android TV): ante el fallo se asume conexión y se continúa, en vez de dejar el player sin arrancar


# [2.7.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.6.2...v2.7.0) (2026-07-27)


### Features

* filter by genre in Explorar and Buscar — pick a genre (Acción, Terror, Comedia, Drama, Ciencia ficción…) and see everything in it across your full catalogue, not just what's on screen. Matching is exact and accent-safe ("Drama" never pulls in "Melodrama"; "Acción" with the accent matches), and compound TMDb genres like "Action & Adventure" stay whole
* search by studio or platform — type A24, HBO, Apple TV+, Netflix, Disney+… and browse its catalogue; owned titles play, the rest are shown as discover
* tap any actor in a title's cast to open that actor's filmography. TMDb cast is now part of the IPTV detail for movies and series, in your language, with the native and TMDb cast no longer duplicated
* recent searches on the search screen, and voice search on TV via the Android system voice overlay
* a "Popular" rail on Home — the most popular movies of the month, the year, or all time, switchable
* "Seguir viendo → Ver todo": a full grid of your last 20 unfinished titles, resumable at the saved position
* Live TV category selector polish — the active category scrolls into view, and a searchable "jump to category" picker appears when a playlist has many categories


### Bug Fixes

* the trailer button is no longer covered on the detail screen, and on TV pressing down through the cast/trailer now reaches the play button (which is focused on entry)
* de-duplicated search results (e.g. "Alien Romulus" no longer shows two dead entries) and removed the duplicated series cast
* content info now shows in the correct language and falls back to the original language when a translation is missing
* live playback no longer aborts on non-fatal player notices (force-seekable / cannot seek)


### Notes

* voice search uses the system voice overlay (no microphone permission required) and hides itself where no speech recognizer is installed; the Android 11+ package-visibility `<queries>` entry for the recognizer is declared so the mic is not silently hidden


# [2.6.2](https://github.com/breisnerlopez/rensi-iptv/compare/v2.6.1...v2.6.2) (2026-07-27)


### Bug Fixes

* the search "discover" detail sheet (a TMDb-only result, e.g. from actor search) now shows the cast — actor photos with name and character below the synopsis. It was fetching the TMDb detail without credits and never rendered a cast rail; the cast rail is now a shared widget reused by the movie/series detail screens and the sheet (verified end-to-end against the live API for both a movie and a series)


# [2.6.1](https://github.com/breisnerlopez/rensi-iptv/compare/v2.6.0...v2.6.1) (2026-07-27)


### Bug Fixes

* resolve TMDb cast/synopsis/trailer for VOD named like a filename — a title such as "Horizonte profundo Desastre en el golfo (2016).mp4" returned nothing from TMDb; the search now strips the extension, year and quality tags and retries with the leading words when a trailing subtitle blocks the match (verified end-to-end against the live API)
* strip the trailing file extension from the movie title shown on the detail screen


# [2.6.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.5.1...v2.6.0) (2026-07-27)


### Features

* the Live (En Vivo) header now shows — and lets you switch — the active playlist, with the same switcher as Home, so you always know which list you're browsing
* store the provider's tmdb_id per title and match search results by it, so an owned movie that TMDb lists under a different (translated) name is no longer also shown as an un-playable "discover" card. The id is filled the first time you open a title (or from the provider's bulk list when it ships one); a full catalogue refresh re-learns it.


### Notes

* database schema migrated 9 → 10 (adds a nullable tmdb_id column to VOD and series). The change is additive — existing catalogue, watch history, favourites and M3U items are preserved on upgrade.


# [2.5.1](https://github.com/breisnerlopez/rensi-iptv/compare/v2.5.0...v2.5.1) (2026-07-27)


### Bug Fixes

* live TV: a non-fatal mpv "force-seekable" hint and a start-of-stream seek on reopen no longer trip the full-screen error on otherwise-playable channels (scoped to live only, so a real VOD resume-seek failure still surfaces)
* enrich a movie whose local title differs from TMDb's (e.g. a translated title like "Horizonte Profundo" → "Marea negra") by trusting TMDb's own match when the release year confirms it, so cast and synopsis finally appear
* localize the search detail sheet's synopsis and genres to the app language, with an original-language fallback when TMDb has no localized synopsis
* series detail uses the provider's tmdb_id when present so cast/synopsis populate reliably


# [2.5.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.4.0...v2.5.0) (2026-07-27)


### Features

* global search now includes live TV channels (Xtream), with a new "Live" filter chip; a channel named like a film/show still lists as a channel, never in "your library"
* the Live section gets an instant channel filter — type to narrow channels by name across every category at once, offline, with the D-pad-safe field


# [2.4.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.3.0...v2.4.0) (2026-07-27)


### Features

* search by actor — a new search mode lists people from TMDb; picking one shows their filmography cross-referenced against your own catalogue (owned titles play, the rest open as TMDb discovery), reusing the existing search buckets and cards. Needs a TMDb key; degrades to the same typed banner without one.


# [2.3.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.2.6...v2.3.0) (2026-07-27)


### Features

* enrich movie and series detail screens with TMDb metadata — a cast rail with actor photos, a richer overview when the provider's is empty, and a TMDb trailer used as a fallback when the provider ships none. Movies match on the provider's tmdb_id; series match by title + year. The feature needs a TMDb key set in Settings and stays completely invisible (and never blocks playback) without one or when no match is found.


# [2.2.6](https://github.com/breisnerlopez/rensi-iptv/compare/v2.2.5...v2.2.6) (2026-07-26)


### Bug Fixes

* shrink the TV top bar (Rensi wordmark + playlist name) — its padding scales with the UI density and the wordmark is trimmed
* give the audio/subtitle track options a strong D-pad focus highlight (bright fill + thick border) so it's obvious which one is selected on a TV
* during playback, the first OK now reveals the progress/time info bar instead of pausing immediately; a second OK pauses (live streams still toggle directly)


# [2.2.5](https://github.com/breisnerlopez/rensi-iptv/compare/v2.2.4...v2.2.5) (2026-07-26)


### Bug Fixes

* compact the Android TV UI to ~0.65 of the previous size (tuned to a real 960dp panel) so text, nav and posters stop reading as oversized
* drop the empty margin to the left of the TV navigation rail — it now sits flush against the screen edge
* let the D-pad / BACK leave a text field on TV: BACK (or escape) now blurs the field and moves focus to a neighbour instead of leaving the user trapped, and three previously unprotected fields (backup passphrase, external-subtitle URL, category search) are covered
* remove the temporary screen-diagnostic line from Settings


# [2.2.4](https://github.com/breisnerlopez/rensi-iptv/compare/v2.2.3...v2.2.4) (2026-07-26)


### Bug Fixes

* apply the TV size adaptation whenever the 10-foot layout is active (keyed on the same signal that switches on the large TV chrome), and only ever scale down — a box whose native TV flag was unset previously rendered the big sizes without adapting
* temporarily surface a screen-metrics line in Settings → About to tune the TV scale to real hardware


# [2.2.3](https://github.com/breisnerlopez/rensi-iptv/compare/v2.2.2...v2.2.3) (2026-07-26)


### Bug Fixes

* speed up the Android TV UI — isolate focus tiles with repaint boundaries and drop the per-focus blurred drop-shadow that repainted every frame, so D-pad navigation no longer lags
* build the five home tabs lazily instead of all up front, cutting the stall when a playlist first opens
* preview the "View all" rail with a SQL-limited query instead of loading and sorting the whole catalogue on the UI thread
* adapt TV component and text sizes to the panel's reported resolution so smaller-dp TV boxes no longer render everything oversized (respects a user's accessibility font scale)
* remove the empty strip to the left of the TV navigation rail (the overscan margin was painted into the rail's tint)
* stop the audio/subtitle panel flashing shut when opened by holding OK (its key-repeats were activating the close button)


# [2.2.2](https://github.com/breisnerlopez/rensi-iptv/compare/v2.2.1...v2.2.2) (2026-07-26)


### Features

* self-heal a VOD's container extension when the panel serves a stale one: on a "failed to recognize file format" error the player retries the other known extensions and persists the one that plays
* refresh the catalogue in the background when the app is opened or resumed after 4h idle, with a progress line that only appears if it takes over 3s and never on TV; mobile refreshes on Wi-Fi/ethernet only


### Bug Fixes

* rebuild the home rails on a background refresh instead of appending to them, which had duplicated every category on screen
* stop building VOD URLs with a literal `.null` extension when the panel omits the container extension


# [2.2.0](https://github.com/breisnerlopez/rensi-iptv/compare/v2.0.9...v2.2.0) (2026-07-20)


### Features

* reconnect the "Continue watching" rail, which shipped with the redesign and never once appeared: the parameter existed and no screen ever passed it
* let the viewer remove a single entry from the rail (long-press / long OK), and offer it again from the snackbar when a resume fails
* restore "Clear all watch history" in Settings — pruning had removed the only way to delete history at all
* surface a failed resume instead of leaving the card inert on tap
* localize the redesign layer: 21 user-facing strings across 8 files, 14 new keys in all 10 languages
* make the home greeting time-aware instead of a fixed "good evening"


### Bug Fixes

* delete a playlist's watch history and favourites when the playlist is deleted — both survived forever and a reused playlist id resurrected them
* stop showing a hard-coded Turkish "Yükleniyor..." to every user in every language
* translate the player's Retry button, which was hard-coded English


### Tests

* run the player end-to-end suite for the first time: it had always died in setUpAll for want of libmpv, hiding two assertions that could never have failed
* rebuild the backup import test as a round-trip through the real export code, dropping its dependency on a personal backup file and a dead /tmp path


# [](https://github.com/bsogulcan/iptv-player/compare/v1.2.0...v) (2025-11-30)


### Bug Fixes

* series shows empty seasons and episodes counter problem ([#64](https://github.com/bsogulcan/iptv-player/issues/64)) ([1f1d735](https://github.com/bsogulcan/iptv-player/commit/1f1d7352f6f9de52b88e4e4e0093c1246c9ab6cd))



# [1.2.0](https://github.com/bsogulcan/iptv-player/compare/v1.1.0...v1.2.0) (2025-11-25)


### Bug Fixes

* removes duplicate duration text ([#56](https://github.com/bsogulcan/iptv-player/issues/56)) ([1f54c38](https://github.com/bsogulcan/iptv-player/commit/1f54c38ea9a93837195fde13ee72091b17d2b5b8))


### Features

* **ci:** adds pr trigger to ci workflows ([#57](https://github.com/bsogulcan/iptv-player/issues/57)) ([df2f315](https://github.com/bsogulcan/iptv-player/commit/df2f315b19bad4a31d2f3222f3ea88202cfa2f15))


### Reverts

* Revert "Temporary Fix: video player pause when entering fullscreen in iOS (#62)" ([85e1070](https://github.com/bsogulcan/iptv-player/commit/85e107076a804c62246327b5bfbd5a7b3b91beb6)), closes [#62](https://github.com/bsogulcan/iptv-player/issues/62)



# [1.1.0](https://github.com/bsogulcan/iptv-player/compare/v1.0.1...v1.1.0) (2025-11-07)


### Bug Fixes

* db ([d339b44](https://github.com/bsogulcan/iptv-player/commit/d339b44baea6eb200ffb7df8346bd0806e7e8411))
* updates flutter version to 3.35.7 ([b5137d1](https://github.com/bsogulcan/iptv-player/commit/b5137d13262e183d0e5f330583e0a976a3ee1187))


### Features

* adds url launcher dependency ([f10b220](https://github.com/bsogulcan/iptv-player/commit/f10b220a91b90b6c019178286b2291adad097045))
* localization and ui issues ([03a4294](https://github.com/bsogulcan/iptv-player/commit/03a42940050b871435fa2278f3d26f8c7702c72a))



## [1.0.1](https://github.com/bsogulcan/iptv-player/compare/v1.0.0...v1.0.1) (2025-10-04)


### Bug Fixes

* improves series season handling ([b1b3e51](https://github.com/bsogulcan/iptv-player/commit/b1b3e514799d44cbcd3b85426da8d56d6e63984c)), closes [#18](https://github.com/bsogulcan/iptv-player/issues/18)



# [1.0.0](https://github.com/bsogulcan/iptv-player/compare/v0.9.4...v1.0.0) (2025-10-03)


### Bug Fixes

* reload playlist unncessarily refreshes after close hide category ([#26](https://github.com/bsogulcan/iptv-player/issues/26)) ([efbe5a5](https://github.com/bsogulcan/iptv-player/commit/efbe5a5d2c7d2e5ef6fd76a17b802237f5b245c7))
* sorting options moved to app bar ([fb9a35f](https://github.com/bsogulcan/iptv-player/commit/fb9a35f88d3a11b140308de78eb2b4c071fe986b))
* **watch-history:** missing localization ([855d624](https://github.com/bsogulcan/iptv-player/commit/855d6247a0b4fd73314534dd916d6ecc61a69f68)), closes [#16](https://github.com/bsogulcan/iptv-player/issues/16) [#21](https://github.com/bsogulcan/iptv-player/issues/21)



## [0.9.4](https://github.com/bsogulcan/iptv-player/compare/v0.9.3...v0.9.4) (2025-10-02)


### Bug Fixes

* build error ([22434b3](https://github.com/bsogulcan/iptv-player/commit/22434b31b4ddfcbf8d84766c37e6dc0a63ff65ee))
* hide categories only xtream type ([8c0b75c](https://github.com/bsogulcan/iptv-player/commit/8c0b75cb04155666626d87046c7ff990ad2eadd6))



## [0.9.3](https://github.com/bsogulcan/iptv-player/compare/v0.9.2...v0.9.3) (2025-09-24)


### Features

* adds null checks for stream data ([211bb05](https://github.com/bsogulcan/iptv-player/commit/211bb05c7590e8a014fb533c97397222d020e8e0))



## [0.9.2](https://github.com/bsogulcan/iptv-player/compare/v0.9.1...v0.9.2) (2025-08-04)


### Bug Fixes

* live stream network issue ([0da55b4](https://github.com/bsogulcan/iptv-player/commit/0da55b483a7dc42ab988446b83d95d603e6ee7e3))



## [0.9.1](https://github.com/bsogulcan/iptv-player/compare/v0.9.0...v0.9.1) (2025-08-02)


### Bug Fixes

* exponential retry ([0ea33a5](https://github.com/bsogulcan/iptv-player/commit/0ea33a5ee129bf79b522a6f4a31c89318a2ea7d1))
* live stream playing continuesly ([924748d](https://github.com/bsogulcan/iptv-player/commit/924748df7a498f5a133fa3d39da7fab8091c2b57))
* player error ([8a891c9](https://github.com/bsogulcan/iptv-player/commit/8a891c988818eaea7d5285663760e106699789d7))
* snack bar queue ([f3bfa6e](https://github.com/bsogulcan/iptv-player/commit/f3bfa6ef51ad1914279e5c7e422e374853349a8f))


### Features

* refresh m3u playlist ([3bdafb8](https://github.com/bsogulcan/iptv-player/commit/3bdafb8f69e4c3e3d4fd3d40173ad8bc1bbf354a))



# [0.9.0](https://github.com/bsogulcan/iptv-player/compare/v0.8.2...v0.9.0) (2025-07-27)


### Bug Fixes

* **docs:** google play store link in downloads ([c19720d](https://github.com/bsogulcan/iptv-player/commit/c19720df1550514d587ec786f80d2d7766d39a31))
* responsive home page ([297697f](https://github.com/bsogulcan/iptv-player/commit/297697ffbb3bea28ea21036c06baed0645743473))
* separate api call and get services ([0f4809e](https://github.com/bsogulcan/iptv-player/commit/0f4809ed484003f98e24b513022b45fd09b42bc1))
* ui improvements ([dc28f08](https://github.com/bsogulcan/iptv-player/commit/dc28f0803b5609f7edac7f68d73f6eeaf63c762b))


### Features

* favorites ([#13](https://github.com/bsogulcan/iptv-player/issues/13)) ([3fb1743](https://github.com/bsogulcan/iptv-player/commit/3fb17431498b50b0b3f7258dcf2cd9a6f340193c))



## [0.8.2](https://github.com/bsogulcan/iptv-player/compare/v0.8.1...v0.8.2) (2025-07-24)


### Bug Fixes

* live streams network issues ([#8](https://github.com/bsogulcan/iptv-player/issues/8)) ([cba25dd](https://github.com/bsogulcan/iptv-player/commit/cba25dd9b26bf1775e533b811aad88c1945afe97))



## [0.8.1](https://github.com/bsogulcan/iptv-player/compare/v0.8.0...v0.8.1) (2025-07-22)


### Bug Fixes

* duplicate m3u urls ([bbeaa71](https://github.com/bsogulcan/iptv-player/commit/bbeaa71ab03b84c16153945fd77b2335455ddbdc))
* permissions ([685458a](https://github.com/bsogulcan/iptv-player/commit/685458aab64c6c5752bf1d8560763693207c7c04))



# [0.8.0](https://github.com/bsogulcan/iptv-player/compare/v0.7.1...v0.8.0) (2025-07-22)


### Features

* m3u support ([9af3bc0](https://github.com/bsogulcan/iptv-player/commit/9af3bc09ff6cdd37df66ef00560861857d125720))



## [0.7.1](https://github.com/bsogulcan/iptv-player/compare/v0.7.0...v0.7.1) (2025-07-15)


### Bug Fixes

* dialog text color ([54eed78](https://github.com/bsogulcan/iptv-player/commit/54eed7852f4165867f38ac9d70688c24ace71cb1))
* dropdown text color ([4a768bf](https://github.com/bsogulcan/iptv-player/commit/4a768bf09cb6f8570431204f511126f641d762b7))
* empty episode info exception ([8bf11d6](https://github.com/bsogulcan/iptv-player/commit/8bf11d64b683b0f8d0e12b804a11c4b1b62209a0))
* set last playlist on data loader screen ([5306942](https://github.com/bsogulcan/iptv-player/commit/5306942039ce732802d602d016196a450f4e2222))
* **xtream-code:** app bars localizations ([3f55990](https://github.com/bsogulcan/iptv-player/commit/3f55990cf35bee31cad3ac3de581700f3edf0dae))



# [0.7.0](https://github.com/bsogulcan/iptv-player/compare/v0.6.0...v0.7.0) (2025-07-14)


### Features

* localization ([e8936db](https://github.com/bsogulcan/iptv-player/commit/e8936db4663ab0a26d0b8c096808e44115029b14))



# [0.6.0](https://github.com/bsogulcan/iptv-player/compare/v0.5.6...v0.6.0) (2025-07-12)


### Bug Fixes

* sqlite import ([0ab76e2](https://github.com/bsogulcan/iptv-player/commit/0ab76e2c52d3fe825043039944f3af024d03274e))


### Features

* settings page ([43b50a3](https://github.com/bsogulcan/iptv-player/commit/43b50a34099bfe45354454492db90bb6a624a039))
* **settings:** background play option ([dfd4896](https://github.com/bsogulcan/iptv-player/commit/dfd4896f4a4f458ae92da446080128fd63cf175e))
* **settings:** subtitle customization ([4b88106](https://github.com/bsogulcan/iptv-player/commit/4b8810626d97595997e222f5dcbc643ed9565894))



## [0.5.6](https://github.com/bsogulcan/iptv-player/compare/v0.5.5...v0.5.6) (2025-07-10)


### Features

* changelogs ([3ff5297](https://github.com/bsogulcan/iptv-player/commit/3ff5297be1798b155191d0ee46eb5c431681c441))



## [0.5.5](https://github.com/bsogulcan/iptv-player/compare/v0.5.4...v0.5.5) (2025-07-08)


### Bug Fixes

* detached app still playing content ([1694afe](https://github.com/bsogulcan/iptv-player/commit/1694afe132b4fadf2375a5c201dbce0991abb1e4))
* ios release ([24b2569](https://github.com/bsogulcan/iptv-player/commit/24b2569dcb482ac3abafe74cad7e75a555c67eac))
* missing sqlite import ([5a00bff](https://github.com/bsogulcan/iptv-player/commit/5a00bff5ef65bd5109945742c403dfce209614c1))
* release action ([0a95b23](https://github.com/bsogulcan/iptv-player/commit/0a95b235e504a69dd505a290a23ecb3fbc18a063))
* version for google play ([72379d5](https://github.com/bsogulcan/iptv-player/commit/72379d524122ff0c6a194f75ed072c0979e1d338))



## [0.5.4](https://github.com/bsogulcan/iptv-player/compare/v0.5.3...v0.5.4) (2025-07-07)


### Bug Fixes

* android build error ([581c7df](https://github.com/bsogulcan/iptv-player/commit/581c7df2de9fc92cd5b1f0af7e6bb051574059ae))
* android build error ([5e3769c](https://github.com/bsogulcan/iptv-player/commit/5e3769cbb733cd7b517ebef8e62d57b4159c922a))
* android key ([3925d98](https://github.com/bsogulcan/iptv-player/commit/3925d983fda4e8b4a65de1a46e4a6117ada8565a))
* audio controls ([6497055](https://github.com/bsogulcan/iptv-player/commit/64970556ba7cb8193ee821c75f9c2d829ce80544))
* audio service controls ([03aeac0](https://github.com/bsogulcan/iptv-player/commit/03aeac065c39980a9e0f00c0fc62abddd3ea998a))
* **docs:** vitepress ssr ([8909261](https://github.com/bsogulcan/iptv-player/commit/89092614fa17bcad1f2912cbd842495f8077828a))
* macos build error ([4973ff2](https://github.com/bsogulcan/iptv-player/commit/4973ff2e0aa2e4d611bdabe7623890b28e0de109))
* macos build error ([18c3ba4](https://github.com/bsogulcan/iptv-player/commit/18c3ba4ba0ed052926d71eb2b30b0c9fbf392815))



## [0.5.3](https://github.com/bsogulcan/iptv-player/compare/v0.5.1...v0.5.3) (2025-07-05)


### Bug Fixes

* actions ([eb42775](https://github.com/bsogulcan/iptv-player/commit/eb427753ec2dbe50bf0ca2a1d650ef08631ba1b5))
* actions ([8551795](https://github.com/bsogulcan/iptv-player/commit/855179539100b8331b45cfecff3e12a4633e40d8))
* docs base path ([ece40b6](https://github.com/bsogulcan/iptv-player/commit/ece40b6e77bd2f8b71c0bd5fab5a394e4a9f66b4))
* iptv provider credential check before saving playlists ([08fb882](https://github.com/bsogulcan/iptv-player/commit/08fb882cbdb82de1a77f67c0ba88c04c520d3825))
* macos sign ([4a273a9](https://github.com/bsogulcan/iptv-player/commit/4a273a9556fbcb38d36749eabfd231c0a4381b25))
* typo ([73b9b2b](https://github.com/bsogulcan/iptv-player/commit/73b9b2b466f2c826700a76fa142dc4dc59646d44))


### Features

* initial vitepress docs project ([30ca73a](https://github.com/bsogulcan/iptv-player/commit/30ca73a34afc4ffe0ac80b6d9c9a57cbccd7d201))


### Reverts

* Revert "chore: macos props" ([65359b3](https://github.com/bsogulcan/iptv-player/commit/65359b3d3c4eb6c88108a070c26a6ec64f5f59dc))



## [0.5.1](https://github.com/bsogulcan/iptv-player/compare/v0.5.0...v0.5.1) (2025-07-01)



# [0.5.0](https://github.com/bsogulcan/iptv-player/compare/v0.4.1...v0.5.0) (2025-06-29)


### Bug Fixes

* dart fix ([7a336aa](https://github.com/bsogulcan/iptv-player/commit/7a336aa1f1c40861b40ad867b36f7d7c65cf902d))
* divide by zero ([888a7f2](https://github.com/bsogulcan/iptv-player/commit/888a7f22e8451fc05e552bf250954fc1095de88b))


### Features

* playlist for episode screen ([5f16195](https://github.com/bsogulcan/iptv-player/commit/5f161957a6753ceee1f8dab26ba82d21260d7faa))



## [0.4.1](https://github.com/bsogulcan/iptv-player/compare/v0.4.0...v0.4.1) (2025-06-28)


### Bug Fixes

* history page contents filtered by current playlist ([8e442aa](https://github.com/bsogulcan/iptv-player/commit/8e442aa829fc2968c53efdb2f784dc446e3e7d91))
* minor fixes ([5ef9500](https://github.com/bsogulcan/iptv-player/commit/5ef9500d2cf1e0e645859bee5a1d0ce95587f94a))



# [0.4.0](https://github.com/bsogulcan/iptv-player/compare/v0.3.0...v0.4.0) (2025-06-25)


### Features

* audio_service implementation ([ea6bc2b](https://github.com/bsogulcan/iptv-player/commit/ea6bc2baa8a8a474aa2706175e372f311b8f7682))
* background play ([d2ffd9c](https://github.com/bsogulcan/iptv-player/commit/d2ffd9c5f5c8b5b8b08927cc698a783a31d98c7b))
* navigate live channels on live stream screen or player ([cda9b25](https://github.com/bsogulcan/iptv-player/commit/cda9b250433b82454f75d2745e5e5ba849b7b27f))
* player top bar buttons ([f343a2c](https://github.com/bsogulcan/iptv-player/commit/f343a2c411b55f410aaec3e735dce0f083342c98))



# [0.3.0](https://github.com/bsogulcan/iptv-player/compare/v0.2.0...v0.3.0) (2025-06-21)


### Bug Fixes

* removed ios folder ([d8ec605](https://github.com/bsogulcan/iptv-player/commit/d8ec605b5ee2c9060da6ce3280324e8951f45268))


### Features

* watch history ([ba64a83](https://github.com/bsogulcan/iptv-player/commit/ba64a83cf01770633fc09eaa19608f0711b94362))



# [0.2.0](https://github.com/bsogulcan/iptv-player/compare/0.1.0...v0.2.0) (2025-06-19)


### Bug Fixes

* podfile ([5bdf88a](https://github.com/bsogulcan/iptv-player/commit/5bdf88a82697d9c157d27f667803518715e89678))
* search input text color ([10a5e5b](https://github.com/bsogulcan/iptv-player/commit/10a5e5b58eef3bfbb63453ec2b1294d51c03934d))
* windows app title ([53ff89e](https://github.com/bsogulcan/iptv-player/commit/53ff89e69b953892ee1d6bf20cdf1040ba17e54d))


### Features

* horizontal scrollbar on desktop ([f0b7804](https://github.com/bsogulcan/iptv-player/commit/f0b78043966c37d7727fdcdabb4c5adc96f8d25c))
* more stable video controls ([303ef6b](https://github.com/bsogulcan/iptv-player/commit/303ef6b645e9803023e3609aca11412dd53b7178))
* player settings on mobile devices ([99340c6](https://github.com/bsogulcan/iptv-player/commit/99340c6334fc6b10c14ec5d6c3047dce2da6cfd6))
* player track options ([51f9821](https://github.com/bsogulcan/iptv-player/commit/51f9821f3961ea33bd1358e3094cb61534408a6e))
* playlist detail screen ([9b8880f](https://github.com/bsogulcan/iptv-player/commit/9b8880f64bc193654480ca26ded7882bdd705edc))
* user preferences ([21ac893](https://github.com/bsogulcan/iptv-player/commit/21ac8936860d8df1db9a510d32bb965042545561))
* volume preferences ([91f212b](https://github.com/bsogulcan/iptv-player/commit/91f212bd07ae265910b712d6b008268c5126a909))



# [0.1.0](https://github.com/bsogulcan/iptv-player/compare/5255add1f032dc6751b01ad9f94542d96d2fc108...0.1.0) (2025-06-15)


### Bug Fixes

* app descriptions ([3962df5](https://github.com/bsogulcan/iptv-player/commit/3962df5656ad63b599f7c0bedc3706714cdeb980))
* separate models ([375db2c](https://github.com/bsogulcan/iptv-player/commit/375db2c34f19a4e6a71e5f45df95fee9e37d8793))
* unusing imports ([bfa6e25](https://github.com/bsogulcan/iptv-player/commit/bfa6e2559fc0821caa6d334f29508e1913a6c7dd))


### Features

* branding ([8805cfc](https://github.com/bsogulcan/iptv-player/commit/8805cfc09068e3d1c5138e769c0cd1854cc16aca))
* initial project ([5255add](https://github.com/bsogulcan/iptv-player/commit/5255add1f032dc6751b01ad9f94542d96d2fc108))
* new layout ([d2069eb](https://github.com/bsogulcan/iptv-player/commit/d2069ebe0e4671820abb9ddc97b1b93f408e4940))
* player ([4ae175b](https://github.com/bsogulcan/iptv-player/commit/4ae175bbc3a68774226df1059e914b39fd097927))
* player ([acd7d73](https://github.com/bsogulcan/iptv-player/commit/acd7d73474113c904212b337edd8cc43382ef876))
* playlist content screen ([3b6b5b4](https://github.com/bsogulcan/iptv-player/commit/3b6b5b46bb789416c3da6b0725d2b37b266e48a6))
* safe type convertions ([c35f84c](https://github.com/bsogulcan/iptv-player/commit/c35f84c5f75d85554b56c9d88d408a27509568df))
* saving live_streams ([a1504ae](https://github.com/bsogulcan/iptv-player/commit/a1504ae69a24775b88d403d7c2a211f7580d88cc))
* saving series_streams ([0fcf465](https://github.com/bsogulcan/iptv-player/commit/0fcf465608912e24c9ca6cc701347b2ace0cb700))
* saving user_info and server_info ([03b1ed7](https://github.com/bsogulcan/iptv-player/commit/03b1ed7b361cf228a33c058ce1b5e053034d0c37))
* saving vod_streams ([beac4bd](https://github.com/bsogulcan/iptv-player/commit/beac4bd476dd229000d1e07f2a0e043cea5edb9b))
* search for categories ([5a9ee96](https://github.com/bsogulcan/iptv-player/commit/5a9ee963bbd0a81a9310faba5c2e66ee3b30590a))
* search screen ([f0b1906](https://github.com/bsogulcan/iptv-player/commit/f0b190630553de07599690413d8151777b6f72ba))
* series episodes ([9b90a8c](https://github.com/bsogulcan/iptv-player/commit/9b90a8cde01e85036a102a2b19d9fa420f6c3f3f))
* series screen ([de16fd4](https://github.com/bsogulcan/iptv-player/commit/de16fd4e37e34fb255c3a8ca37433af2ef2f6ca1))
* web compatibility ([639ff9b](https://github.com/bsogulcan/iptv-player/commit/639ff9b99b3df7bfc7e161b983d796bb0836b2af))



