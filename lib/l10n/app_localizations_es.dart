// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get prebuffer_preparing => 'Preparando…';

  @override
  String get prebuffer_ready => 'Listo para reproducción fluida';

  @override
  String get prebuffer_slow => 'Conexión lenta';

  @override
  String get prebuffer_stalled => 'Sin datos: revisa tu conexión';

  @override
  String get prebuffer_play_now => 'Reproducir ahora';

  @override
  String get cast_gate_prompt => '¿Enviar esto a tu TV?';

  @override
  String get cast_gate_play_now => 'Reproducir aquí';

  @override
  String get cast_to_tv => 'Enviar a la TV';

  @override
  String get cast_sent_to_tv => 'Enviado a la TV';

  @override
  String get cast_send_failed => 'No se pudo enviar a la TV';

  @override
  String get cast_searching => 'Buscando televisores en tu red…';

  @override
  String get cast_no_devices =>
      'No se encontraron televisores. Asegúrate de tener la app abierta en la TV y de estar en el mismo Wi-Fi.';

  @override
  String get cast_choose_device => 'Elige un televisor';

  @override
  String get cast_connecting => 'Conectando…';

  @override
  String get cast_enter_pin => 'Ingresa el código que aparece en tu TV';

  @override
  String get cast_pair => 'Emparejar';

  @override
  String get cast_pairing => 'Emparejando…';

  @override
  String get cast_wrong_pin => 'Código incorrecto. Inténtalo de nuevo.';

  @override
  String get cast_playing_on => 'Reproduciendo en';

  @override
  String get cast_remote_hint => 'Tu teléfono es el control';

  @override
  String get cast_stop => 'Dejar de transmitir';

  @override
  String get cast_error => 'No se pudo conectar con la TV';

  @override
  String get cast_retry => 'Reintentar';

  @override
  String get slogan => 'Reproductor IPTV';

  @override
  String get search => 'Buscar';

  @override
  String get search_live_stream => 'Buscar transmisión en vivo';

  @override
  String get search_movie => 'Buscar película';

  @override
  String get search_series => 'Buscar serie';

  @override
  String get not_found_in_category =>
      'No se encontró contenido en esta categoría';

  @override
  String get live_stream_not_found => 'No se encontró transmisión en vivo';

  @override
  String get movie_not_found => 'No se encontró película';

  @override
  String get see_all => 'Ver Todo';

  @override
  String get popular_section_title => 'Populares';

  @override
  String get popular_window_month => 'Este mes';

  @override
  String get popular_window_year => 'Este año';

  @override
  String get popular_window_all_time => 'Todo el tiempo';

  @override
  String get preview => 'Vista Previa';

  @override
  String get info => 'Información';

  @override
  String get close => 'Cerrar';

  @override
  String get reset => 'Restablecer';

  @override
  String get delete => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get refresh => 'Actualizar';

  @override
  String get back => 'Atrás';

  @override
  String get clear => 'Limpiar';

  @override
  String get clear_all => 'Limpiar Todo';

  @override
  String get day => 'Día';

  @override
  String get clear_all_confirmation_message =>
      '¿Estás seguro de que quieres eliminar todo el historial?';

  @override
  String get try_again => 'Intentar de Nuevo';

  @override
  String get player_exit_press_back_again => 'Pulsa atrás de nuevo para salir';

  @override
  String get history => 'Historial';

  @override
  String get history_empty_message => 'Los videos que veas aparecerán aquí';

  @override
  String get live => 'En Vivo';

  @override
  String get live_streams => 'Transmisiones en Vivo';

  @override
  String get on_live => 'En Vivo';

  @override
  String get other_channels => 'Otros Canales';

  @override
  String get movies => 'Películas';

  @override
  String get movie => 'Película';

  @override
  String get series_singular => 'Serie';

  @override
  String get series_plural => 'Series';

  @override
  String get category_id => 'ID de Categoría';

  @override
  String get channel_information => 'Información del Canal';

  @override
  String get channel_id => 'ID del Canal';

  @override
  String get series_id => 'ID de Serie';

  @override
  String get quality => 'Calidad';

  @override
  String get stream_type => 'Tipo de Transmisión';

  @override
  String get format => 'Formato';

  @override
  String get season => 'Temporadas';

  @override
  String episode_count(Object count) {
    return '$count Episodios';
  }

  @override
  String duration(Object duration) {
    return 'Duración: $duration';
  }

  @override
  String get episode_duration => 'Duración del Episodio';

  @override
  String episode_duration_minutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get creation_date => 'Fecha de Agregado';

  @override
  String get release_date => 'Fecha de Estreno';

  @override
  String get genre => 'Género';

  @override
  String get cast => 'Reparto';

  @override
  String get director => 'Director';

  @override
  String get description => 'Descripción';

  @override
  String get video_track => 'Pista de Video';

  @override
  String get audio_track => 'Pista de Audio';

  @override
  String get speed => 'Velocidad';

  @override
  String get load => 'Cargar';

  @override
  String get external_subtitle => 'Subtítulo externo';

  @override
  String get external_subtitle_url => 'Subtítulo externo (URL)';

  @override
  String get subtitle_track => 'Pista de Subtítulos';

  @override
  String get settings => 'Configuración';

  @override
  String get hold_ok_for_options => 'Mantén OK para audio y subtítulos';

  @override
  String get general_settings => 'Configuración General';

  @override
  String get app_language => 'Idioma de la App';

  @override
  String get continue_on_background =>
      'Continuar Reproduciendo en Segundo Plano';

  @override
  String get continue_on_background_description =>
      'Seguir reproduciendo aunque la app esté en segundo plano';

  @override
  String get auto_pip_on_home => 'Picture-in-Picture al salir';

  @override
  String get auto_pip_on_home_description =>
      'Reduce el reproductor a una ventana flotante al salir de la app';

  @override
  String get sleep_timer => 'Temporizador de apagado';

  @override
  String get sleep_timer_off => 'Apagado';

  @override
  String get sleep_timer_minutes_suffix => 'min';

  @override
  String get sleep_timer_hours_suffix => 'h';

  @override
  String get refresh_contents => 'Actualizar Contenido';

  @override
  String get subtitle_settings => 'Configuración de Subtítulos';

  @override
  String get subtitle_settings_description =>
      'Personalizar la apariencia de los subtítulos';

  @override
  String get sample_text => 'Texto de subtítulo de ejemplo\nSe verá así';

  @override
  String get font_settings => 'Configuración de Fuente';

  @override
  String get font_size => 'Tamaño de Fuente';

  @override
  String get font_height => 'Altura de Línea';

  @override
  String get letter_spacing => 'Espaciado de Letras';

  @override
  String get word_spacing => 'Espaciado de Palabras';

  @override
  String get padding => 'Relleno';

  @override
  String get color_settings => 'Configuración de Color';

  @override
  String get text_color => 'Color del Texto';

  @override
  String get background_color => 'Color de Fondo';

  @override
  String get style_settings => 'Configuración de Estilo';

  @override
  String get font_weight => 'Grosor de Fuente';

  @override
  String get thin => 'Delgado';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Medio';

  @override
  String get bold => 'Negrita';

  @override
  String get extreme_bold => 'Extra Negrita';

  @override
  String get text_align => 'Alineación del Texto';

  @override
  String get left => 'Izquierda';

  @override
  String get center => 'Centro';

  @override
  String get right => 'Derecha';

  @override
  String get justify => 'Justificar';

  @override
  String get pick_color => 'Elegir Color';

  @override
  String get my_playlists => 'Mis Listas de Reproducción';

  @override
  String get create_new_playlist => 'Crear Nueva Lista';

  @override
  String get loading_playlists => 'Cargando Listas...';

  @override
  String get playlist_list => 'Lista de Reproducción';

  @override
  String get playlist_information => 'Información de la Lista';

  @override
  String get playlist_name => 'Nombre de la Lista';

  @override
  String get playlist_name_placeholder => 'Ingresa un nombre para tu lista';

  @override
  String get playlist_name_required => 'El nombre de la lista es requerido';

  @override
  String get playlist_name_min_2 =>
      'El nombre debe tener al menos 2 caracteres';

  @override
  String playlist_deleted(Object name) {
    return '$name eliminada';
  }

  @override
  String get playlist_delete_confirmation_title => 'Eliminar Lista';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return '¿Estás seguro de que quieres eliminar la lista \'$name\'?\nEsta acción no se puede deshacer.';
  }

  @override
  String get empty_playlist_title => 'Aún No Hay Listas';

  @override
  String get empty_playlist_message =>
      'Comienza creando tu primera lista de reproducción.\nPuedes agregar listas en formato Xtream Code o M3U.';

  @override
  String get empty_playlist_button => 'Crear Mi Primera Lista';

  @override
  String get favorites => 'Favoritos';

  @override
  String get see_all_favorites => 'Ver Todo';

  @override
  String get added_to_favorites => 'Agregado a favoritos';

  @override
  String get removed_from_favorites => 'Eliminado de favoritos';

  @override
  String get remove_from_favorites => 'Eliminar de Favoritos';

  @override
  String get select_playlist_type => 'Seleccionar Tipo de Lista';

  @override
  String get select_playlist_message =>
      'Elige el tipo de lista que quieres crear';

  @override
  String get xtream_code_title =>
      'Conectar con URL de API, Usuario y Contraseña';

  @override
  String get xtream_code_description =>
      'Conéctate fácilmente con la información de tu proveedor IPTV';

  @override
  String get select_playlist_type_footer =>
      'La información de tu lista se almacena de forma segura en tu dispositivo.';

  @override
  String get api_url => 'URL de API';

  @override
  String get api_url_required => 'URL de API requerida';

  @override
  String get username => 'Usuario';

  @override
  String get username_placeholder => 'Ingresa tu usuario';

  @override
  String get username_required => 'Usuario requerido';

  @override
  String get username_min_3 => 'El usuario debe tener al menos 3 caracteres';

  @override
  String get password => 'Contraseña';

  @override
  String get password_placeholder => 'Ingresa tu contraseña';

  @override
  String get password_required => 'Contraseña requerida';

  @override
  String get password_min_3 => 'La contraseña debe tener al menos 3 caracteres';

  @override
  String get server_url => 'URL del Servidor';

  @override
  String get submitting => 'Guardando...';

  @override
  String get submit_create_playlist => 'Guardar Lista';

  @override
  String get subscription_details => 'Detalles de Suscripción';

  @override
  String subscription_remaining_day(Object days) {
    return 'Suscripción: $days';
  }

  @override
  String get remaining_day_title => 'Tiempo Restante';

  @override
  String remaining_day(Object days) {
    return '$days Días';
  }

  @override
  String get connected => 'Conectado';

  @override
  String get no_connection => 'Sin Conexión';

  @override
  String get expired => 'Expirado';

  @override
  String get active_connection => 'Conexión Activa';

  @override
  String get maximum_connection => 'Conexión Máxima';

  @override
  String get server_information => 'Información del Servidor';

  @override
  String get timezone => 'Zona Horaria';

  @override
  String get server_message => 'Mensaje del Servidor';

  @override
  String get all_datas_are_stored_in_device =>
      'Todos los datos se almacenan de forma segura en tu dispositivo';

  @override
  String get url_format_validate_message =>
      'El formato de URL debe ser como http://servidor:puerto';

  @override
  String get url_format_validate_error =>
      'Ingresa una URL válida (debe comenzar con http:// o https://)';

  @override
  String get playlist_name_already_exists =>
      'Ya existe una lista con este nombre';

  @override
  String get invalid_credentials =>
      'No se pudo obtener respuesta de tu proveedor IPTV, verifica tu información';

  @override
  String get error_occurred => 'Ocurrió un error';

  @override
  String get playback_failed => 'No se pudo reproducir el contenido';

  @override
  String get connecting => 'Conectando';

  @override
  String get preparing_categories => 'Preparando categorías';

  @override
  String preparing_categories_exception(Object error) {
    return 'No se pudieron cargar las categorías: $error';
  }

  @override
  String get preparing_live_streams => 'Cargando canales en vivo';

  @override
  String get preparing_live_streams_exception_1 =>
      'No se pudieron obtener los canales en vivo';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Error al cargar canales en vivo: $error';
  }

  @override
  String get preparing_movies => 'Abriendo biblioteca de películas';

  @override
  String get preparing_movies_exception_1 =>
      'No se pudieron obtener las películas';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Error al cargar películas: $error';
  }

  @override
  String get preparing_series => 'Preparando biblioteca de series';

  @override
  String get preparing_series_exception_1 =>
      'No se pudieron obtener las series';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Error al cargar series: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'No se pudo obtener información del usuario';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Error al cargar información del usuario: $error';
  }

  @override
  String get m3u_playlist_title =>
      'Agregar lista de reproducción con archivo M3U o URL';

  @override
  String get m3u_playlist_description =>
      'Admite archivos de formato M3U tradicionales';

  @override
  String get m3u_playlist => 'Lista de reproducción M3U';

  @override
  String get m3u_playlist_load_description =>
      'Cargar canales IPTV con archivo de lista de reproducción M3U o URL';

  @override
  String get playlist_name_hint =>
      'Ingrese el nombre de la lista de reproducción';

  @override
  String get playlist_name_min_length =>
      'El nombre de la lista de reproducción debe tener al menos 2 caracteres';

  @override
  String get source_type => 'Tipo de fuente';

  @override
  String get url => 'URL';

  @override
  String get file => 'Archivo';

  @override
  String get m3u_url => 'URL M3U';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'URL M3U es requerida';

  @override
  String get url_format_error => 'Ingrese un formato de URL válido';

  @override
  String get url_scheme_error => 'La URL debe comenzar con http:// o https://';

  @override
  String get m3u_file => 'Archivo M3U';

  @override
  String get file_selected => 'Archivo seleccionado';

  @override
  String get select_m3u_file => 'Seleccionar archivo M3U (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Por favor seleccione un archivo M3U';

  @override
  String get file_selection_error => 'Error al seleccionar archivo';

  @override
  String get processing => 'Procesando...';

  @override
  String get create_playlist => 'Crear lista de reproducción';

  @override
  String get error_occurred_title => 'Error ocurrido';

  @override
  String get m3u_info_message =>
      'Todos los datos se almacenan de forma segura en su dispositivo.\nFormatos admitidos: .m3u, .m3u8\nFormato de URL: Debe comenzar con http:// o https://';

  @override
  String get m3u_parse_error => 'Error de análisis M3U';

  @override
  String get loading_m3u => 'Cargando M3U';

  @override
  String get preparing_m3u_exception_no_source => 'No se encontró fuente M3U';

  @override
  String get preparing_m3u_exception_empty => 'El archivo M3U está vacío';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'Error de análisis M3U: $error';
  }

  @override
  String get not_categorized => 'Sin categorizar';

  @override
  String get loading_lists => 'Cargando listas...';

  @override
  String get all => 'Todos';

  @override
  String iptv_channels_count(Object count) {
    return 'Canales IPTV ($count)';
  }

  @override
  String get unknown_channel => 'Canal desconocido';

  @override
  String get live_content => 'EN VIVO';

  @override
  String get movie_content => 'PELÍCULA';

  @override
  String get series_content => 'SERIE';

  @override
  String get media_content => 'MEDIOS';

  @override
  String get m3u_error => 'Error M3U';

  @override
  String get episode_short => 'Ep';

  @override
  String season_number(Object number) {
    return 'Temporada $number';
  }

  @override
  String get image_loading => 'Cargando imagen...';

  @override
  String get image_not_found => 'Imagen no encontrada';

  @override
  String get select_all => 'Seleccionar todo';

  @override
  String get deselect_all => 'Deseleccionar todo';

  @override
  String get hide_category => 'Ocultar categorías';

  @override
  String get rating => 'Clasificación';

  @override
  String get remove_from_history => 'Eliminar del historial';

  @override
  String get remove_from_history_confirmation =>
      '¿Estás seguro de que quieres eliminar este elemento del historial de reproducción?';

  @override
  String get remove => 'Eliminar';

  @override
  String get clear_old_records => 'Limpiar registros antiguos';

  @override
  String get clear_old_records_confirmation =>
      '¿Estás seguro de que quieres eliminar los registros de reproducción de más de 30 días?';

  @override
  String get clear_old => 'Limpiar antiguos';

  @override
  String get clear_all_history => 'Limpiar todo el historial';

  @override
  String get clear_all_history_confirmation =>
      '¿Estás seguro de que quieres eliminar todo el historial de reproducción?';

  @override
  String get resume_failed => 'Este título ya no está disponible en esta lista';

  @override
  String get search_in_your_library => 'En tu biblioteca';

  @override
  String get search_discover_tmdb => 'Descubrir en TMDb';

  @override
  String get search_not_in_lists => 'No en tus listas';

  @override
  String get search_global_disabled =>
      'Añade tu clave de TMDb para descubrir títulos fuera de tus listas.';

  @override
  String get search_enable_global => 'Activar búsqueda global';

  @override
  String get search_key_rejected =>
      'Tu clave de TMDb fue rechazada. Revísala en Ajustes.';

  @override
  String get search_tmdb_rate_limited =>
      'Demasiadas búsquedas. Prueba de nuevo en un momento.';

  @override
  String get search_tmdb_error => 'No se pudo consultar TMDb.';

  @override
  String get search_add_to_wishlist => 'Guardar en lista de deseos';

  @override
  String get search_play_from => 'Reproducir desde';

  @override
  String get search_not_available_body =>
      'No está en tus listas. Guárdalo y lo revisamos cuando aparezca.';

  @override
  String get search_keep_typing_global =>
      'Sigue escribiendo para buscar en TMDb';

  @override
  String get search_saved => 'Guardado';

  @override
  String get search_saved_confirm => 'Guardado en tu lista';

  @override
  String get search_removed_confirm => 'Quitado de tu lista';

  @override
  String get search_in_wishlist_body =>
      'En tu lista de deseos. Te avisamos cuando esté disponible para reproducir.';

  @override
  String get key_space => 'Espacio';

  @override
  String get key_backspace => 'Retroceso';

  @override
  String get home_empty_title =>
      'No hay películas ni series en esta lista todavía.';

  @override
  String get home_empty_hint =>
      'Usa “En Vivo” en el menú para ver canales, o busca contenido.';

  @override
  String get loading => 'Cargando...';

  @override
  String get greeting_morning => 'Buenos días';

  @override
  String get greeting_afternoon => 'Buenas tardes';

  @override
  String get greeting_evening => 'Buenas noches';

  @override
  String get featured_today => 'DESTACADO HOY';

  @override
  String get search_catalog_hint => 'Busca en todo tu catálogo';

  @override
  String get search_placeholder => 'Buscar películas, series, canales…';

  @override
  String get search_recent => 'Búsquedas recientes';

  @override
  String get search_recent_remove => 'Eliminar';

  @override
  String get no_channels => 'Sin canales';

  @override
  String get no_results_filter => 'Sin resultados para este filtro';

  @override
  String get preferred_audio => 'Audio preferido';

  @override
  String get preferred_subtitles => 'Subtítulos preferidos';

  @override
  String get decoder_applies_next_video =>
      'Se aplicará al abrir el próximo video';

  @override
  String no_results_for(String query) {
    return 'Sin resultados para \"$query\"';
  }

  @override
  String saved_titles_count(int count) {
    return '$count títulos guardados';
  }

  @override
  String get history_cleared => 'Historial de reproducción borrado';

  @override
  String get history_clear_failed =>
      'No se pudo borrar el historial de reproducción';

  @override
  String get appearance => 'Apariencia';

  @override
  String get theme => 'Tema';

  @override
  String get standard => 'Predeterminado';

  @override
  String get light => 'Claro';

  @override
  String get dark => 'Oscuro';

  @override
  String get trailer => 'Tráiler';

  @override
  String get new_ep => 'Nuevo';

  @override
  String get continue_watching => 'Seguir viendo';

  @override
  String get start_watching => 'Comenzar a ver';

  @override
  String continue_watching_label(String season, String episode) {
    return 'Continuar: T $season Episodio $episode';
  }

  @override
  String get player_settings => 'Configuración del reproductor';

  @override
  String get brightness_gesture => 'Gesto de brillo';

  @override
  String get brightness_gesture_description =>
      'Controlar el brillo deslizando verticalmente en el lado izquierdo';

  @override
  String get volume_gesture => 'Gesto de volumen';

  @override
  String get volume_gesture_description =>
      'Controlar el volumen deslizando verticalmente en el lado derecho';

  @override
  String get seek_gesture => 'Gesto de búsqueda';

  @override
  String get seek_gesture_description => 'Buscar deslizando horizontalmente';

  @override
  String get speed_up_on_long_press => 'Acelerar con presión larga';

  @override
  String get speed_up_on_long_press_description =>
      'Acelerar la reproducción al mantener presionado';

  @override
  String get seek_on_double_tap => 'Buscar con doble toque';

  @override
  String get seek_on_double_tap_description =>
      'Buscar adelante/atrás con doble toque';

  @override
  String get copied_to_clipboard => 'Copiado al portapapeles';

  @override
  String get about => 'Acerca de';

  @override
  String get app_version => 'Versión de la aplicación';

  @override
  String get support_on_github => 'Apoyar en GitHub';

  @override
  String get support_on_github_description =>
      'Contribuir al proyecto en GitHub';

  @override
  String get last_channel => 'Último canal';

  @override
  String get select_channel => 'Seleccionar Canal';

  @override
  String get episodes => 'Episodios';

  @override
  String get next_episode => 'Siguiente episodio';

  @override
  String get categories => 'Categorías';

  @override
  String get seasons => 'Temporadas';

  @override
  String season_number_format(int number) {
    return 'Temporada $number';
  }

  @override
  String episode_count_format(int count) {
    return '$count episodios';
  }

  @override
  String channel_count_format(int count) {
    return '$count canales';
  }

  @override
  String get video_info => 'Información del Video';

  @override
  String get video_info_not_found => 'Información del video no encontrada';

  @override
  String get name => 'Nombre';

  @override
  String get content_type => 'Tipo de Contenido';

  @override
  String get plot => 'Trama';

  @override
  String get duration_unknown => 'Desconocido';

  @override
  String get url_copied_to_clipboard => 'URL copiada al portapapeles';

  @override
  String get stream_id => 'ID de Transmisión';

  @override
  String get epg_channel_id => 'ID de Canal EPG';

  @override
  String get category => 'Categoría';

  @override
  String get add_to_favorites => 'Agregar a Favoritos';

  @override
  String get no_tracks_available => 'No hay pistas disponibles';

  @override
  String get live_stream_content_type => 'Transmisión en Vivo';

  @override
  String get movie_content_type => 'Película';

  @override
  String get series_content_type => 'Serie';

  @override
  String get last_update => 'Última Actualización';

  @override
  String get minutes => 'min';

  @override
  String get duration_label => 'Duración';

  @override
  String get tmdb_global_search => 'Búsqueda Global TMDb';

  @override
  String get tmdb_credential_configured =>
      'Credencial TMDb almacenada de forma segura';

  @override
  String get tmdb_credential_missing =>
      'Añade tu API key o token de acceso TMDb para habilitar la búsqueda global';

  @override
  String get tmdb_credential_label => 'Token API TMDb';

  @override
  String get tmdb_credential_field_label => 'API key o token de acceso';

  @override
  String get tmdb_credential_save => 'Guardar credencial';

  @override
  String get tmdb_credential_saved => 'Credencial TMDb guardada';

  @override
  String get tmdb_search_hint => 'Buscar películas y series en TMDb';

  @override
  String get tmdb_search_button => 'Buscar';

  @override
  String get tmdb_search_description =>
      'Escribe al menos 3 caracteres y pulsa Buscar. Los resultados se cachean 24 horas para reducir el uso de la API.';

  @override
  String get tmdb_exact_match => 'Coincidencia exacta';

  @override
  String get tmdb_not_found_in_playlists => 'No encontrado en tus listas';

  @override
  String tmdb_available_in(Object count) {
    return 'Disponible en $count elemento(s) de lista';
  }

  @override
  String get tmdb_wishlist => 'Lista de deseos';

  @override
  String get save => 'Guardar';

  @override
  String get export_playlists_and_settings => 'Exportar listas y configuración';

  @override
  String get export_subtitle =>
      'Guardar todas las listas, credenciales y ajustes';

  @override
  String get import_playlists_and_settings => 'Importar listas y configuración';

  @override
  String get import_subtitle =>
      'Restaurar listas y sobrescribir ajustes coincidentes';

  @override
  String get backup_section => 'Respaldo';

  @override
  String get tmdb_credential_section => 'Token API TMDb';

  @override
  String get export_success => 'Respaldo exportado correctamente';

  @override
  String get export_cancelled => 'Exportación de respaldo cancelada';

  @override
  String get export_failed => 'Error al exportar respaldo';

  @override
  String import_success(Object count) {
    return 'Respaldo importado: $count listas restauradas';
  }

  @override
  String get import_cancelled => 'Importación de respaldo cancelada';

  @override
  String get import_failed => 'Error al importar respaldo';

  @override
  String import_summary(int created, int updated, int skipped) {
    return 'Importado: $created nuevos, $updated actualizados, $skipped omitidos';
  }

  @override
  String get backup_passphrase_title => 'Proteger este respaldo';

  @override
  String get backup_passphrase_subtitle =>
      'Elige una contraseña para cifrar el respaldo. Déjalo en blanco para un JSON sin cifrar (las credenciales serán legibles).';

  @override
  String get backup_passphrase_field => 'Contraseña';

  @override
  String get backup_passphrase_confirm => 'Confirmar contraseña';

  @override
  String get backup_passphrase_mismatch => 'Las contraseñas no coinciden';

  @override
  String get backup_passphrase_required =>
      'Este respaldo está cifrado. Introduce la contraseña usada al crearlo.';

  @override
  String get backup_passphrase_invalid =>
      'Contraseña incorrecta o respaldo corrupto';

  @override
  String get backup_invalid_format => 'Archivo de respaldo no válido';

  @override
  String backup_schema_unsupported(String version) {
    return 'Versión de respaldo no soportada: $version';
  }

  @override
  String get backup_plain_warning =>
      'Una exportación sin cifrar deja URLs, usuarios y contraseñas legibles en el archivo.';

  @override
  String get backup_strategy_title =>
      'Importar reemplazará las listas con el mismo id.';

  @override
  String get backup_strategy_overwrite => 'Sobrescribir existentes';

  @override
  String get backup_strategy_keep_local => 'Conservar las locales';

  @override
  String get backup_encrypt => 'Cifrar';

  @override
  String get backup_skip_encryption => 'Sin cifrar';

  @override
  String get search_no_results => 'No se encontraron resultados';

  @override
  String get search_in_your_lists => 'En tus listas';

  @override
  String get search_from_your_iptv => 'Desde tu IPTV';

  @override
  String get search_tmdb_section => 'TMDb';

  @override
  String get search_watch_action => 'Ver';

  @override
  String playlist_load_failed(String error) {
    return 'Error al cargar las listas: $error';
  }

  @override
  String playlist_save_failed(String error) {
    return 'Error al guardar la lista: $error';
  }

  @override
  String playlist_update_failed(String error) {
    return 'Error al actualizar la lista: $error';
  }

  @override
  String playlist_delete_failed(String error) {
    return 'Error al eliminar la lista: $error';
  }

  @override
  String m3u_file_read_failed(String error) {
    return 'No se pudo leer el archivo M3U: $error';
  }

  @override
  String get m3u_url_invalid_scheme =>
      'La URL debe comenzar con http:// o https://';

  @override
  String m3u_url_http_status(String status) {
    return 'La URL M3U devolvió HTTP $status';
  }

  @override
  String get m3u_url_response_too_large => 'La lista M3U supera los 50 MB';

  @override
  String m3u_url_fetch_failed(String error) {
    return 'No se pudo descargar la URL M3U: $error';
  }

  @override
  String get search_filter_all => 'Todo';

  @override
  String get search_filter_movies => 'Películas';

  @override
  String get search_filter_tv => 'TV';

  @override
  String get search_filter_wishlist => 'Lista de deseos';

  @override
  String get search_filter_people => 'Actores';

  @override
  String get search_person_hint => 'Busca un actor para ver su filmografía';

  @override
  String get search_person_no_results => 'Sin resultados para este actor';

  @override
  String get search_back_to_actors => 'Volver a actores';

  @override
  String get search_filter_studios => 'Estudios';

  @override
  String get search_studio_hint => 'Busca un estudio para ver sus títulos';

  @override
  String get search_studio_no_results => 'Sin resultados para este estudio';

  @override
  String get search_back_to_studios => 'Volver a estudios';

  @override
  String get search_filter_genre => 'Géneros';

  @override
  String get search_genre_hint => 'Elige un género para ver tus títulos';

  @override
  String get search_genre_no_results => 'No tienes títulos en este género';

  @override
  String get search_back_to_genres => 'Volver a géneros';

  @override
  String get search_voice => 'Búsqueda por voz';

  @override
  String get search_clear_history => 'Borrar historial';

  @override
  String get search_clear_history_confirm =>
      '¿Quitar todas las búsquedas recientes?';

  @override
  String get search_remove_from_wishlist => 'Quitar de la lista de deseos';

  @override
  String get search_wishlist_empty =>
      'Tu lista de deseos está vacía. Toca el marcador en cualquier resultado de TMDb para guardarlo aquí.';

  @override
  String get search_detail_overview => 'Sinopsis';

  @override
  String get search_detail_genres => 'Géneros';

  @override
  String search_detail_runtime(int minutes) {
    return '$minutes min';
  }

  @override
  String search_detail_open_in_playlist(String playlist) {
    return 'Abrir en $playlist';
  }

  @override
  String get search_detail_not_in_playlists =>
      'No está en ninguna de tus listas';

  @override
  String get stream_info => 'Información del stream';

  @override
  String get resolution => 'Resolución';

  @override
  String get frames_per_second => 'Fotogramas por segundo';

  @override
  String get video_codec => 'Códec de video';

  @override
  String get audio_codec => 'Códec de audio';

  @override
  String get audio_channels => 'Canales de audio';

  @override
  String get bitrate => 'Bitrate';

  @override
  String get sort_recently_added => 'Recientes';

  @override
  String get view_all_movies => 'Todas las películas';

  @override
  String get view_all_series => 'Todas las series';

  @override
  String get view_all_live => 'Todos los canales';

  @override
  String get import_from_url => 'Importar desde URL';

  @override
  String get import_url_subtitle =>
      'Descarga un respaldo por HTTP — útil en TV boxes sin selector de archivos';

  @override
  String get import_url_hint => 'https://ejemplo.com/respaldo.aipbak';

  @override
  String get import_url_invalid => 'URL inválida';

  @override
  String get import_url_failed => 'No se pudo descargar el respaldo';

  @override
  String get import_from_device => 'Explorar el dispositivo';

  @override
  String get import_from_device_subtitle =>
      'Explorador de archivos integrado — funciona en TV boxes sin selector del sistema';

  @override
  String get file_browser_root_picker => 'Cambiar carpeta inicial';

  @override
  String get file_browser_parent_directory => 'Carpeta superior';

  @override
  String get file_browser_permission_denied =>
      'El permiso de almacenamiento fue denegado. Otórgalo desde ajustes del sistema para explorar archivos.';

  @override
  String get file_browser_unreadable => 'No se puede leer esta carpeta.';

  @override
  String get file_browser_no_roots =>
      'No se encontró almacenamiento accesible en este dispositivo.';

  @override
  String get file_browser_empty =>
      'No hay archivos compatibles en esta carpeta.';

  @override
  String get exit_confirm_title => '¿Salir de la app?';

  @override
  String get exit_confirm_message => 'Estás a punto de salir de Rensi IPTV.';

  @override
  String get exit_confirm_action => 'Salir';

  @override
  String get nav_home => 'Inicio';

  @override
  String get nav_browse => 'Explorar';

  @override
  String get nav_live => 'En vivo';

  @override
  String get nav_my_list => 'Mi lista';

  @override
  String get onboarding_requirements_hint =>
      'Necesitarás la URL o los datos de acceso de tu proveedor IPTV';

  @override
  String get nav_settings => 'Ajustes';

  @override
  String get empty_list_title => 'Tu lista está vacía';

  @override
  String get empty_list_body =>
      'Añade títulos a tu lista y los encontrarás aquí.';

  @override
  String get action_browse_catalogue => 'Explorar catálogo';

  @override
  String get video_decoding_label => 'Decodificación de video';

  @override
  String get video_decoding_description =>
      'Automático funciona en casi todos los equipos. Cambia solo si un canal no se ve.';

  @override
  String get video_decoding_auto => 'Automático';

  @override
  String get video_decoding_hw => 'Hardware directo';

  @override
  String get video_decoding_software => 'Software';

  @override
  String get downloads_title => 'Descargas';

  @override
  String get downloads_empty => 'Aún no hay descargas';

  @override
  String get downloads_storage_used => 'Almacenamiento usado';

  @override
  String get download_status_queued => 'En cola';

  @override
  String get download_status_downloading => 'Descargando';

  @override
  String get download_status_paused => 'Pausada';

  @override
  String get download_status_complete => 'Completa';

  @override
  String get download_status_failed => 'Fallida';

  @override
  String get download_pause => 'Pausar';

  @override
  String get download_resume => 'Reanudar';

  @override
  String get download_cancel => 'Cancelar';

  @override
  String get download_delete => 'Eliminar';

  @override
  String get download_send_to_tv => 'Enviar a la TV';

  @override
  String get download_for_offline => 'Descargar para ver sin conexión';

  @override
  String get download_available_offline => 'Disponible sin conexión';

  @override
  String get download_failed_retry => 'Falló la descarga: toca para reintentar';

  @override
  String get tv_ready_subtitle => 'Listo para recibir contenido desde tu móvil';

  @override
  String get tv_playback_settings => 'Ajustes de reproducción';

  @override
  String get tv_replay_failed =>
      'No se pudo recuperar este contenido para reproducirlo.';

  @override
  String get cast_need_wifi =>
      'Conéctate a la misma red Wi‑Fi que la TV para enviar el archivo.';

  @override
  String get download_err_http => 'Error HTTP';

  @override
  String get download_err_start_failed => 'No se pudo iniciar la descarga';

  @override
  String get download_err_file_missing =>
      'El archivo descargado ya no está disponible';

  @override
  String get download_err_canceled => 'Descarga cancelada o no encontrada';

  @override
  String get download_err_server_page =>
      'El servidor devolvió una página de error (sesión caducada o id inválido)';

  @override
  String get download_err_generic => 'La descarga falló';

  @override
  String get download_retry => 'Reintentar';

  @override
  String get tv_cast_replay_hint =>
      'Reproducido por casting desde tu móvil. Vuelve a enviarlo desde el móvil para verlo aquí.';

  @override
  String get developer => 'Desarrollador';

  @override
  String get dev_account => 'Cuenta';

  @override
  String get dev_server => 'Servidor';

  @override
  String get dev_application => 'Aplicación';

  @override
  String get dev_catalogue => 'Catálogo';

  @override
  String get dev_playlist => 'Lista de reproducción';

  @override
  String get dev_expires => 'Vencimiento';

  @override
  String get dev_trial => 'Cuenta de prueba';

  @override
  String get dev_active_connections => 'Conexiones activas';

  @override
  String get dev_max_connections => 'Conexiones máximas';

  @override
  String get dev_created => 'Creado';

  @override
  String get dev_output_formats => 'Formatos permitidos';

  @override
  String get dev_server_url => 'URL del servidor';

  @override
  String get dev_port => 'Puerto';

  @override
  String get dev_https_port => 'Puerto HTTPS';

  @override
  String get dev_protocol => 'Protocolo';

  @override
  String get dev_rtmp_port => 'Puerto RTMP';

  @override
  String get dev_server_time => 'Hora del servidor';

  @override
  String get dev_build_number => 'Número de compilación';

  @override
  String get dev_schema_version => 'Esquema de base de datos';

  @override
  String get dev_last_sync => 'Última sincronización';

  @override
  String get dev_never => 'Nunca';

  @override
  String get dev_source_url => 'URL de origen';

  @override
  String get dev_series => 'Series';

  @override
  String get dev_items => 'Elementos';

  @override
  String get dev_yes => 'Sí';

  @override
  String get dev_no => 'No';

  @override
  String get dev_no_data => 'No hay datos disponibles';

  @override
  String get dev_status => 'Estado';
}
