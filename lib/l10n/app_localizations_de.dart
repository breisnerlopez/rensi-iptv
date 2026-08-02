// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get prebuffer_preparing => 'Wird vorbereitet…';

  @override
  String get prebuffer_ready => 'Bereit für flüssige Wiedergabe';

  @override
  String get prebuffer_slow => 'Langsame Verbindung';

  @override
  String get prebuffer_stalled => 'Keine Daten – Verbindung prüfen';

  @override
  String get prebuffer_play_now => 'Jetzt abspielen';

  @override
  String get cast_gate_prompt => 'An deinen Fernseher senden?';

  @override
  String get cast_gate_play_now => 'Hier abspielen';

  @override
  String get cast_to_tv => 'Auf TV streamen';

  @override
  String get cast_sent_to_tv => 'An TV gesendet';

  @override
  String get cast_send_failed => 'Konnte nicht an TV senden';

  @override
  String get cast_searching => 'Fernseher im Netzwerk werden gesucht…';

  @override
  String get cast_no_devices =>
      'Keine Fernseher gefunden. Stelle sicher, dass die App auf deinem TV geöffnet ist und beide im selben WLAN sind.';

  @override
  String get cast_choose_device => 'Fernseher auswählen';

  @override
  String get cast_connecting => 'Verbindung wird hergestellt…';

  @override
  String get cast_enter_pin =>
      'Gib den Code ein, der auf deinem TV angezeigt wird';

  @override
  String get cast_pair => 'Koppeln';

  @override
  String get cast_pairing => 'Wird gekoppelt…';

  @override
  String get cast_wrong_pin => 'Falscher Code. Versuche es erneut.';

  @override
  String get cast_playing_on => 'Läuft auf';

  @override
  String get cast_remote_hint => 'Dein Handy ist die Fernbedienung';

  @override
  String get cast_stop => 'Streaming beenden';

  @override
  String get cast_error => 'Verbindung zum TV fehlgeschlagen';

  @override
  String get cast_retry => 'Erneut versuchen';

  @override
  String cast_tv_volume(int value) {
    return 'TV-Lautstärke  $value%';
  }

  @override
  String get tv_standalone_section => 'TV / Streaming';

  @override
  String get tv_standalone_master_title =>
      'Auf dem TV ohne Telefon weiterschauen';

  @override
  String get tv_standalone_master_subtitle =>
      'Erlaubt einem vertrauenswürdigen TV, deine Anbieter-Zugangsdaten verschlüsselt zu speichern, damit es nach dem Schließen der App weiter abspielen kann. Standardmäßig aus.';

  @override
  String get pause_cast_on_call_title => 'TV bei Anruf pausieren';

  @override
  String get pause_cast_on_call_subtitle =>
      'Während des Castings pausiert ein eingehender Anruf die Wiedergabe auf dem TV und setzt sie nach dem Anruf fort.';

  @override
  String tv_standalone_consent_title(String device) {
    return 'Sitzung auf $device behalten?';
  }

  @override
  String tv_standalone_consent_body(String provider) {
    return 'Deine $provider-Zugangsdaten werden VERSCHLÜSSELT auf dem TV gespeichert, damit du ohne Telefon weiterschauen kannst. Risiko: Auf einem gerooteten oder kompromittierten TV könnten sie ausgelesen werden; die PIN-Kopplung schützt nicht vor einem Angreifer, der die Kopplung mitschneidet (bekannte Schwachstelle).';
  }

  @override
  String get tv_standalone_consent_accept => 'Aktivieren';

  @override
  String get tv_standalone_consent_decline => 'Jetzt nicht';

  @override
  String get tv_standalone_revoke_empty =>
      'Kein TV hat gespeicherte Zugangsdaten.';

  @override
  String get tv_standalone_revoke_action =>
      'Zugangsdaten auf diesem TV vergessen';

  @override
  String get slogan => 'IPTV-Player';

  @override
  String get search => 'Suchen';

  @override
  String get search_live_stream => 'Live-Stream suchen';

  @override
  String get search_movie => 'Film suchen';

  @override
  String get search_series => 'Serie suchen';

  @override
  String get not_found_in_category =>
      'Kein Inhalt in dieser Kategorie gefunden';

  @override
  String get live_stream_not_found => 'Kein Live-Stream gefunden';

  @override
  String get movie_not_found => 'Kein Film gefunden';

  @override
  String get see_all => 'Alle Anzeigen';

  @override
  String get popular_section_title => 'Beliebt';

  @override
  String get popular_window_month => 'Diesen Monat';

  @override
  String get popular_window_year => 'Dieses Jahr';

  @override
  String get popular_window_all_time => 'Aller Zeiten';

  @override
  String get preview => 'Vorschau';

  @override
  String get info => 'Info';

  @override
  String get close => 'Schließen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get delete => 'Löschen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get back => 'Zurück';

  @override
  String get clear => 'Löschen';

  @override
  String get clear_all => 'Alle Löschen';

  @override
  String get day => 'Tag';

  @override
  String get clear_all_confirmation_message =>
      'Sind Sie sicher, dass Sie die gesamte Verlaufsliste löschen möchten?';

  @override
  String get try_again => 'Erneut Versuchen';

  @override
  String get player_exit_press_back_again =>
      'Zum Beenden erneut Zurück drücken';

  @override
  String get history => 'Verlauf';

  @override
  String get history_empty_message =>
      'Ihre angesehenen Videos werden hier angezeigt';

  @override
  String get live => 'Live';

  @override
  String get live_streams => 'Live-Streams';

  @override
  String get on_live => 'Live';

  @override
  String get other_channels => 'Andere Kanäle';

  @override
  String get movies => 'Filme';

  @override
  String get movie => 'Film';

  @override
  String get series_singular => 'Serie';

  @override
  String get series_plural => 'Serien';

  @override
  String get category_id => 'Kategorie-ID';

  @override
  String get channel_information => 'Kanal-Informationen';

  @override
  String get channel_id => 'Kanal-ID';

  @override
  String get series_id => 'Serien-ID';

  @override
  String get quality => 'Qualität';

  @override
  String get stream_type => 'Stream-Typ';

  @override
  String get format => 'Format';

  @override
  String get season => 'Staffeln';

  @override
  String episode_count(Object count) {
    return '$count Episoden';
  }

  @override
  String duration(Object duration) {
    return 'Dauer: $duration';
  }

  @override
  String get episode_duration => 'Episoden-Dauer';

  @override
  String episode_duration_minutes(String minutes) {
    return '$minutes Min';
  }

  @override
  String get creation_date => 'Hinzugefügt am';

  @override
  String get release_date => 'Erscheinungsdatum';

  @override
  String get genre => 'Genre';

  @override
  String get cast => 'Besetzung';

  @override
  String get director => 'Regisseur';

  @override
  String get description => 'Beschreibung';

  @override
  String get video_track => 'Video-Spur';

  @override
  String get audio_track => 'Audio-Spur';

  @override
  String get speed => 'Speed';

  @override
  String get load => 'Load';

  @override
  String get external_subtitle => 'External subtitle';

  @override
  String get external_subtitle_url => 'External subtitle (URL)';

  @override
  String get subtitle_track => 'Untertitel-Spur';

  @override
  String get settings => 'Einstellungen';

  @override
  String get hold_ok_for_options => 'Hold OK for audio & subtitles';

  @override
  String get general_settings => 'Allgemeine Einstellungen';

  @override
  String get app_language => 'App-Sprache';

  @override
  String get continue_on_background => 'Im Hintergrund Weiterspielen';

  @override
  String get continue_on_background_description =>
      'Wiedergabe fortsetzen, auch wenn die App im Hintergrund ist';

  @override
  String get auto_pip_on_home => 'Bild-in-Bild beim Verlassen';

  @override
  String get auto_pip_on_home_description =>
      'Verkleinert den Player zu einem schwebenden Fenster, wenn Sie die App verlassen';

  @override
  String get sleep_timer => 'Sleep-Timer';

  @override
  String get sleep_timer_off => 'Aus';

  @override
  String get sleep_timer_minutes_suffix => 'Min';

  @override
  String get sleep_timer_hours_suffix => 'Std';

  @override
  String get refresh_contents => 'Inhalte Aktualisieren';

  @override
  String get subtitle_settings => 'Untertitel-Einstellungen';

  @override
  String get subtitle_settings_description => 'Untertitel-Darstellung anpassen';

  @override
  String get sample_text => 'Beispiel-Untertiteltext\nSo wird es aussehen';

  @override
  String get font_settings => 'Schriftart-Einstellungen';

  @override
  String get font_size => 'Schriftgröße';

  @override
  String get font_height => 'Zeilenhöhe';

  @override
  String get letter_spacing => 'Buchstabenabstand';

  @override
  String get word_spacing => 'Wortabstand';

  @override
  String get padding => 'Innenabstand';

  @override
  String get color_settings => 'Farb-Einstellungen';

  @override
  String get text_color => 'Textfarbe';

  @override
  String get background_color => 'Hintergrundfarbe';

  @override
  String get style_settings => 'Stil-Einstellungen';

  @override
  String get font_weight => 'Schriftstärke';

  @override
  String get thin => 'Dünn';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Mittel';

  @override
  String get bold => 'Fett';

  @override
  String get extreme_bold => 'Extra Fett';

  @override
  String get text_align => 'Textausrichtung';

  @override
  String get left => 'Links';

  @override
  String get center => 'Mitte';

  @override
  String get right => 'Rechts';

  @override
  String get justify => 'Blocksatz';

  @override
  String get pick_color => 'Farbe Wählen';

  @override
  String get my_playlists => 'Meine Wiedergabelisten';

  @override
  String get create_new_playlist => 'Neue Wiedergabeliste Erstellen';

  @override
  String get loading_playlists => 'Wiedergabelisten Werden Geladen...';

  @override
  String get playlist_list => 'Wiedergabeliste';

  @override
  String get playlist_information => 'Wiedergabelisten-Informationen';

  @override
  String get playlist_name => 'Name der Wiedergabeliste';

  @override
  String get playlist_name_placeholder =>
      'Namen für Ihre Wiedergabeliste eingeben';

  @override
  String get playlist_name_required =>
      'Name der Wiedergabeliste ist erforderlich';

  @override
  String get playlist_name_min_2 =>
      'Der Name sollte mindestens 2 Zeichen haben';

  @override
  String playlist_deleted(Object name) {
    return '$name gelöscht';
  }

  @override
  String get playlist_delete_confirmation_title => 'Wiedergabeliste Löschen';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'Sind Sie sicher, dass Sie die Wiedergabeliste \'$name\' löschen möchten?\nDiese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get empty_playlist_title => 'Noch Keine Wiedergabeliste';

  @override
  String get empty_playlist_message =>
      'Beginnen Sie mit der Erstellung Ihrer ersten Wiedergabeliste.\nSie können Wiedergabelisten im Xtream Code oder M3U Format hinzufügen.';

  @override
  String get empty_playlist_button => 'Meine Erste Wiedergabeliste Erstellen';

  @override
  String get favorites => 'Favoriten';

  @override
  String get see_all_favorites => 'Alle Anzeigen';

  @override
  String get added_to_favorites => 'Zu Favoriten hinzugefügt';

  @override
  String get removed_from_favorites => 'Aus Favoriten entfernt';

  @override
  String get action_save_to_list => 'Meine Liste';

  @override
  String get action_saved => 'Gespeichert';

  @override
  String get remove_from_favorites => 'Aus Favoriten Entfernen';

  @override
  String get select_playlist_type => 'Wiedergabelisten-Typ Auswählen';

  @override
  String get select_playlist_message =>
      'Wählen Sie den Typ der Wiedergabeliste, die Sie erstellen möchten';

  @override
  String get xtream_code_title =>
      'Mit API-URL, Benutzername und Passwort verbinden';

  @override
  String get xtream_code_description =>
      'Einfach mit den Informationen Ihres IPTV-Anbieters verbinden';

  @override
  String get select_playlist_type_footer =>
      'Ihre Wiedergabelisten-Informationen werden sicher auf Ihrem Gerät gespeichert.';

  @override
  String get api_url => 'API-URL';

  @override
  String get api_url_required => 'API-URL erforderlich';

  @override
  String get username => 'Benutzername';

  @override
  String get username_placeholder => 'Benutzername eingeben';

  @override
  String get username_required => 'Benutzername ist erforderlich';

  @override
  String get username_min_3 => 'Benutzername sollte mindestens 3 Zeichen haben';

  @override
  String get password => 'Passwort';

  @override
  String get password_placeholder => 'Passwort eingeben';

  @override
  String get password_required => 'Passwort ist erforderlich';

  @override
  String get password_min_3 => 'Passwort sollte mindestens 3 Zeichen haben';

  @override
  String get server_url => 'Server-URL';

  @override
  String get submitting => 'Wird Gespeichert...';

  @override
  String get submit_create_playlist => 'Wiedergabeliste Speichern';

  @override
  String get subscription_details => 'Abonnement-Details';

  @override
  String subscription_remaining_day(Object days) {
    return 'Abonnement: $days';
  }

  @override
  String get remaining_day_title => 'Verbleibende Zeit';

  @override
  String remaining_day(Object days) {
    return '$days Tage';
  }

  @override
  String get connected => 'Verbunden';

  @override
  String get no_connection => 'Keine Verbindung';

  @override
  String get expired => 'Abgelaufen';

  @override
  String get active_connection => 'Aktive Verbindung';

  @override
  String get maximum_connection => 'Maximale Verbindung';

  @override
  String get server_information => 'Server-Informationen';

  @override
  String get timezone => 'Zeitzone';

  @override
  String get server_message => 'Server-Nachricht';

  @override
  String get all_datas_are_stored_in_device =>
      'Alle Daten werden sicher auf Ihrem Gerät gespeichert';

  @override
  String get url_format_validate_message =>
      'URL-Format sollte wie http://server:port sein';

  @override
  String get url_format_validate_error =>
      'Bitte geben Sie eine gültige URL ein (muss mit http:// oder https:// beginnen)';

  @override
  String get playlist_name_already_exists =>
      'Eine Wiedergabeliste mit diesem Namen existiert bereits';

  @override
  String get invalid_credentials =>
      'Keine Antwort von Ihrem IPTV-Anbieter erhalten, bitte überprüfen Sie Ihre Informationen';

  @override
  String get error_occurred => 'Ein Fehler ist aufgetreten';

  @override
  String get playback_failed => 'Dieser Inhalt konnte nicht abgespielt werden';

  @override
  String get connecting => 'Verbindung wird hergestellt';

  @override
  String get preparing_categories => 'Kategorien werden vorbereitet';

  @override
  String preparing_categories_exception(Object error) {
    return 'Kategorien konnten nicht geladen werden: $error';
  }

  @override
  String get preparing_live_streams => 'Live-Kanäle werden geladen';

  @override
  String get preparing_live_streams_exception_1 =>
      'Live-Kanäle konnten nicht abgerufen werden';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Fehler beim Laden der Live-Kanäle: $error';
  }

  @override
  String get preparing_movies => 'Film-Bibliothek wird geöffnet';

  @override
  String get preparing_movies_exception_1 =>
      'Filme konnten nicht abgerufen werden';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Fehler beim Laden der Filme: $error';
  }

  @override
  String get preparing_series => 'Serien-Bibliothek wird vorbereitet';

  @override
  String get preparing_series_exception_1 =>
      'Serien konnten nicht abgerufen werden';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Fehler beim Laden der Serien: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'Benutzerinformationen konnten nicht abgerufen werden';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Fehler beim Laden der Benutzerinformationen: $error';
  }

  @override
  String get m3u_playlist_title => 'Playlist mit M3U-Datei oder URL hinzufügen';

  @override
  String get m3u_playlist_description =>
      'Unterstützt traditionelle M3U-Formatdateien';

  @override
  String get m3u_playlist => 'M3U-Playlist';

  @override
  String get m3u_playlist_load_description =>
      'IPTV-Kanäle mit M3U-Playlist-Datei oder URL laden';

  @override
  String get playlist_name_hint => 'Playlist-Namen eingeben';

  @override
  String get playlist_name_min_length =>
      'Playlist-Name muss mindestens 2 Zeichen haben';

  @override
  String get source_type => 'Quellentyp';

  @override
  String get url => 'URL';

  @override
  String get file => 'Datei';

  @override
  String get m3u_url => 'M3U-URL';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'M3U-URL ist erforderlich';

  @override
  String get url_format_error => 'Gültiges URL-Format eingeben';

  @override
  String get url_scheme_error => 'URL muss mit http:// oder https:// beginnen';

  @override
  String get m3u_file => 'M3U-Datei';

  @override
  String get file_selected => 'Datei ausgewählt';

  @override
  String get select_m3u_file => 'M3U-Datei auswählen (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Bitte eine M3U-Datei auswählen';

  @override
  String get file_selection_error => 'Fehler beim Auswählen der Datei';

  @override
  String get processing => 'Verarbeitung läuft...';

  @override
  String get create_playlist => 'Playlist erstellen';

  @override
  String get error_occurred_title => 'Fehler aufgetreten';

  @override
  String get m3u_info_message =>
      'Alle Daten werden sicher auf Ihrem Gerät gespeichert.\nUnterstützte Formate: .m3u, .m3u8\nURL-Format: Muss mit http:// oder https:// beginnen';

  @override
  String get m3u_parse_error => 'M3U-Parsing-Fehler';

  @override
  String get loading_m3u => 'M3U wird geladen';

  @override
  String get preparing_m3u_exception_no_source => 'Keine M3U-Quelle gefunden';

  @override
  String get preparing_m3u_exception_empty => 'M3U-Datei ist leer';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'M3U-Parsing-Fehler: $error';
  }

  @override
  String get not_categorized => 'Nicht kategorisiert';

  @override
  String get loading_lists => 'Listen werden geladen...';

  @override
  String get all => 'Alle';

  @override
  String iptv_channels_count(Object count) {
    return 'IPTV-Kanäle ($count)';
  }

  @override
  String get unknown_channel => 'Unbekannter Kanal';

  @override
  String get live_content => 'LIVE';

  @override
  String get movie_content => 'FILM';

  @override
  String get series_content => 'SERIE';

  @override
  String get media_content => 'MEDIEN';

  @override
  String get m3u_error => 'M3U-Fehler';

  @override
  String get episode_short => 'Folge';

  @override
  String season_number(Object number) {
    return '$number. Staffel';
  }

  @override
  String get image_loading => 'Bild wird geladen...';

  @override
  String get image_not_found => 'Bild nicht gefunden';

  @override
  String get select_all => 'Alle auswählen';

  @override
  String get deselect_all => 'Auswahl aufheben';

  @override
  String get hide_category => 'Kategorien ausblenden';

  @override
  String get rating => 'Bewertung';

  @override
  String get remove_from_history => 'Aus Verlauf entfernen';

  @override
  String get remove_from_history_confirmation =>
      'Sind Sie sicher, dass Sie diesen Artikel aus dem Wiedergabeverlauf entfernen möchten?';

  @override
  String get remove => 'Entfernen';

  @override
  String get clear_old_records => 'Alte Einträge löschen';

  @override
  String get clear_old_records_confirmation =>
      'Sind Sie sicher, dass Sie Wiedergabeeinträge älter als 30 Tage löschen möchten?';

  @override
  String get clear_old => 'Alte löschen';

  @override
  String get clear_all_history => 'Gesamten Verlauf löschen';

  @override
  String get clear_all_history_confirmation =>
      'Sind Sie sicher, dass Sie den gesamten Wiedergabeverlauf löschen möchten?';

  @override
  String get resume_failed =>
      'Dieser Titel ist in dieser Playlist nicht mehr verfügbar';

  @override
  String get search_in_your_library => 'In Ihrer Bibliothek';

  @override
  String get search_discover_tmdb => 'Auf TMDb entdecken';

  @override
  String get search_not_in_lists => 'Nicht in Ihren Listen';

  @override
  String get search_global_disabled =>
      'Fügen Sie Ihren TMDb-Schlüssel hinzu, um Titel über Ihre Listen hinaus zu entdecken.';

  @override
  String get search_enable_global => 'Globale Suche aktivieren';

  @override
  String get search_key_rejected =>
      'Ihr TMDb-Schlüssel wurde abgelehnt. Prüfen Sie ihn in den Einstellungen.';

  @override
  String get search_tmdb_rate_limited =>
      'Zu viele Suchanfragen. Versuchen Sie es gleich noch einmal.';

  @override
  String get search_tmdb_error => 'TMDb nicht erreichbar.';

  @override
  String get search_add_to_wishlist => 'Zur Wunschliste hinzufügen';

  @override
  String get search_play_from => 'Abspielen von';

  @override
  String get search_not_available_body =>
      'Nicht in Ihren Listen. Speichern Sie ihn und wir prüfen, sobald er verfügbar ist.';

  @override
  String get search_keep_typing_global => 'Weitertippen, um auf TMDb zu suchen';

  @override
  String get search_saved => 'Gespeichert';

  @override
  String get search_saved_confirm => 'Zu Ihrer Wunschliste hinzugefügt';

  @override
  String get search_removed_confirm => 'Von Ihrer Wunschliste entfernt';

  @override
  String get search_in_wishlist_body =>
      'Auf Ihrer Wunschliste. Wir benachrichtigen Sie, sobald es verfügbar ist.';

  @override
  String get key_space => 'Leertaste';

  @override
  String get key_backspace => 'Rücktaste';

  @override
  String get home_empty_title =>
      'Noch keine Filme oder Serien in dieser Playlist.';

  @override
  String get home_empty_hint =>
      'Nutzen Sie „Live“ im Menü, um Sender zu sehen, oder suchen Sie nach Inhalten.';

  @override
  String get loading => 'Wird geladen...';

  @override
  String get greeting_morning => 'Guten Morgen';

  @override
  String get greeting_afternoon => 'Guten Tag';

  @override
  String get greeting_evening => 'Guten Abend';

  @override
  String get featured_today => 'HEUTE EMPFOHLEN';

  @override
  String get search_catalog_hint => 'Durchsuchen Sie Ihren gesamten Katalog';

  @override
  String get search_placeholder => 'Filme, Serien, Sender suchen…';

  @override
  String get search_recent => 'Letzte Suchen';

  @override
  String get search_recent_remove => 'Entfernen';

  @override
  String get no_channels => 'Keine Sender';

  @override
  String get no_results_filter => 'Keine Ergebnisse für diesen Filter';

  @override
  String get preferred_audio => 'Bevorzugter Ton';

  @override
  String get preferred_subtitles => 'Bevorzugte Untertitel';

  @override
  String get decoder_applies_next_video =>
      'Gilt ab dem nächsten geöffneten Video';

  @override
  String no_results_for(String query) {
    return 'Keine Ergebnisse für \"$query\"';
  }

  @override
  String saved_titles_count(int count) {
    return '$count gespeicherte Titel';
  }

  @override
  String get history_cleared => 'Wiedergabeverlauf gelöscht';

  @override
  String get history_clear_failed =>
      'Wiedergabeverlauf konnte nicht gelöscht werden';

  @override
  String get appearance => 'Aussehen';

  @override
  String get theme => 'Design';

  @override
  String get standard => 'Standard';

  @override
  String get light => 'Hell';

  @override
  String get dark => 'Dunkel';

  @override
  String get trailer => 'Anhänger';

  @override
  String get new_ep => 'Neu';

  @override
  String get continue_watching => 'Weiter ansehen';

  @override
  String get start_watching => 'Wiedergabe starten';

  @override
  String continue_watching_label(String season, String episode) {
    return 'Fortsetzen: S $season Folge $episode';
  }

  @override
  String get player_settings => 'Player-Einstellungen';

  @override
  String get brightness_gesture => 'Helligkeits-Geste';

  @override
  String get brightness_gesture_description =>
      'Helligkeit durch vertikales Wischen auf der linken Seite steuern';

  @override
  String get volume_gesture => 'Lautstärke-Geste';

  @override
  String get volume_gesture_description =>
      'Lautstärke durch vertikales Wischen auf der rechten Seite steuern';

  @override
  String get seek_gesture => 'Such-Geste';

  @override
  String get seek_gesture_description => 'Durch horizontales Wischen suchen';

  @override
  String get speed_up_on_long_press => 'Bei langem Drücken beschleunigen';

  @override
  String get speed_up_on_long_press_description =>
      'Wiedergabe bei langem Drücken beschleunigen';

  @override
  String get seek_on_double_tap => 'Bei Doppeltippen suchen';

  @override
  String get seek_on_double_tap_description =>
      'Durch Doppeltippen vorwärts/rückwärts suchen';

  @override
  String get copied_to_clipboard => 'In Zwischenablage kopiert';

  @override
  String get about => 'Über';

  @override
  String get app_version => 'App-Version';

  @override
  String get support_on_github => 'Auf GitHub unterstützen';

  @override
  String get support_on_github_description =>
      'Zum Projekt auf GitHub beitragen';

  @override
  String get last_channel => 'Last channel';

  @override
  String get select_channel => 'Kanal Auswählen';

  @override
  String get episodes => 'Episoden';

  @override
  String get next_episode => 'Nächste Folge';

  @override
  String get categories => 'Kategorien';

  @override
  String get seasons => 'Staffeln';

  @override
  String season_number_format(int number) {
    return 'Staffel $number';
  }

  @override
  String episode_count_format(int count) {
    return '$count Episoden';
  }

  @override
  String channel_count_format(int count) {
    return '$count Kanäle';
  }

  @override
  String get video_info => 'Video-Informationen';

  @override
  String get video_info_not_found => 'Video-Informationen nicht gefunden';

  @override
  String get name => 'Name';

  @override
  String get content_type => 'Inhaltstyp';

  @override
  String get plot => 'Handlung';

  @override
  String get duration_unknown => 'Unbekannt';

  @override
  String get url_copied_to_clipboard => 'URL in Zwischenablage kopiert';

  @override
  String get stream_id => 'Stream-ID';

  @override
  String get epg_channel_id => 'EPG-Kanal-ID';

  @override
  String get category => 'Kategorie';

  @override
  String get add_to_favorites => 'Zu Favoriten Hinzufügen';

  @override
  String get no_tracks_available => 'Keine Spuren verfügbar';

  @override
  String get live_stream_content_type => 'Live-Stream';

  @override
  String get movie_content_type => 'Film';

  @override
  String get series_content_type => 'Serie';

  @override
  String get last_update => 'Letzte Aktualisierung';

  @override
  String get minutes => 'Min';

  @override
  String get duration_label => 'Dauer';

  @override
  String get tmdb_global_search => 'TMDb Globale Suche';

  @override
  String get tmdb_credential_configured =>
      'TMDb-Zugangsdaten sicher gespeichert';

  @override
  String get tmdb_credential_missing =>
      'Fügen Sie Ihren TMDb API-Schlüssel oder Read Access Token hinzu, um die globale Suche zu aktivieren';

  @override
  String get tmdb_credential_label => 'TMDb API-Token';

  @override
  String get tmdb_credential_field_label =>
      'API-Schlüssel oder Read Access Token';

  @override
  String get tmdb_credential_save => 'Zugangsdaten speichern';

  @override
  String get tmdb_credential_saved => 'TMDb-Zugangsdaten gespeichert';

  @override
  String get tmdb_search_hint => 'Filme und Serien auf TMDb suchen';

  @override
  String get tmdb_search_button => 'Suchen';

  @override
  String get tmdb_search_description =>
      'Geben Sie mindestens 3 Zeichen ein und drücken Sie Suchen. Ergebnisse werden 24 Stunden zwischengespeichert, um die API-Nutzung zu reduzieren.';

  @override
  String get tmdb_exact_match => 'Exakte Übereinstimmung';

  @override
  String get tmdb_not_found_in_playlists =>
      'Nicht in Ihren Wiedergabelisten gefunden';

  @override
  String tmdb_available_in(Object count) {
    return 'In $count Wiedergabelisten-Eintrag/-Einträgen verfügbar';
  }

  @override
  String get tmdb_wishlist => 'Wunschliste';

  @override
  String get save => 'Speichern';

  @override
  String get export_playlists_and_settings =>
      'Wiedergabelisten und Einstellungen exportieren';

  @override
  String get export_subtitle =>
      'Alle Wiedergabelisten, Zugangsdaten und App-Einstellungen sichern';

  @override
  String get import_playlists_and_settings =>
      'Wiedergabelisten und Einstellungen importieren';

  @override
  String get import_subtitle =>
      'Wiedergabelisten wiederherstellen und passende Einstellungen überschreiben';

  @override
  String get backup_section => 'Sicherung';

  @override
  String get tmdb_credential_section => 'TMDb API-Token';

  @override
  String get export_success => 'Sicherung erfolgreich exportiert';

  @override
  String get export_cancelled => 'Sicherungsexport abgebrochen';

  @override
  String get export_failed => 'Sicherungsexport fehlgeschlagen';

  @override
  String import_success(Object count) {
    return 'Sicherung importiert: $count Wiedergabelisten wiederhergestellt';
  }

  @override
  String get import_cancelled => 'Sicherungsimport abgebrochen';

  @override
  String get import_failed => 'Sicherungsimport fehlgeschlagen';

  @override
  String import_summary(int created, int updated, int skipped) {
    return 'Importiert: $created neu, $updated aktualisiert, $skipped übersprungen';
  }

  @override
  String get backup_passphrase_title => 'Diese Sicherung schützen';

  @override
  String get backup_passphrase_subtitle =>
      'Wähle eine Passphrase zur Verschlüsselung der Sicherung. Lass das Feld leer für einen unverschlüsselten JSON-Export (Zugangsdaten sind dann lesbar).';

  @override
  String get backup_passphrase_field => 'Passphrase';

  @override
  String get backup_passphrase_confirm => 'Passphrase bestätigen';

  @override
  String get backup_passphrase_mismatch => 'Passphrasen stimmen nicht überein';

  @override
  String get backup_passphrase_required =>
      'Diese Sicherung ist verschlüsselt. Gib die zur Erstellung verwendete Passphrase ein.';

  @override
  String get backup_passphrase_invalid =>
      'Falsche Passphrase oder beschädigte Sicherung';

  @override
  String get backup_invalid_format => 'Ungültige Sicherungsdatei';

  @override
  String backup_schema_unsupported(String version) {
    return 'Nicht unterstützte Sicherungsversion: $version';
  }

  @override
  String get backup_plain_warning =>
      'Ein unverschlüsselter Export lässt URLs, Benutzernamen und Passwörter in der Datei lesbar.';

  @override
  String get backup_strategy_title =>
      'Ein Import ersetzt Wiedergabelisten mit derselben ID.';

  @override
  String get backup_strategy_overwrite => 'Vorhandene überschreiben';

  @override
  String get backup_strategy_keep_local => 'Lokale Versionen behalten';

  @override
  String get backup_encrypt => 'Verschlüsseln';

  @override
  String get backup_skip_encryption => 'Verschlüsselung überspringen';

  @override
  String get search_no_results => 'Keine Ergebnisse gefunden';

  @override
  String get search_in_your_lists => 'In Ihren Listen';

  @override
  String get search_from_your_iptv => 'Aus Ihrem IPTV';

  @override
  String get search_tmdb_section => 'TMDb';

  @override
  String get search_watch_action => 'Ansehen';

  @override
  String playlist_load_failed(String error) {
    return 'Fehler beim Laden der Wiedergabelisten: $error';
  }

  @override
  String playlist_save_failed(String error) {
    return 'Fehler beim Speichern der Wiedergabeliste: $error';
  }

  @override
  String playlist_update_failed(String error) {
    return 'Fehler beim Aktualisieren der Wiedergabeliste: $error';
  }

  @override
  String playlist_delete_failed(String error) {
    return 'Fehler beim Löschen der Wiedergabeliste: $error';
  }

  @override
  String m3u_file_read_failed(String error) {
    return 'M3U-Datei konnte nicht gelesen werden: $error';
  }

  @override
  String get m3u_url_invalid_scheme =>
      'URL muss mit http:// oder https:// beginnen';

  @override
  String m3u_url_http_status(String status) {
    return 'M3U-URL gab HTTP $status zurück';
  }

  @override
  String get m3u_url_response_too_large =>
      'M3U-Wiedergabeliste ist größer als 50 MB';

  @override
  String m3u_url_fetch_failed(String error) {
    return 'M3U-URL konnte nicht heruntergeladen werden: $error';
  }

  @override
  String get search_filter_all => 'Alle';

  @override
  String get search_filter_movies => 'Filme';

  @override
  String get search_filter_tv => 'TV';

  @override
  String get search_filter_wishlist => 'Wunschliste';

  @override
  String get search_filter_people => 'Schauspieler';

  @override
  String get search_person_hint =>
      'Suche nach einem Schauspieler, um seine Filmografie zu sehen';

  @override
  String get search_person_no_results =>
      'Keine Ergebnisse für diesen Schauspieler';

  @override
  String get search_back_to_actors => 'Zurück zu Schauspielern';

  @override
  String get search_filter_studios => 'Studios';

  @override
  String get search_studio_hint =>
      'Suche nach einem Studio, um seine Titel zu sehen';

  @override
  String get search_studio_no_results => 'Keine Ergebnisse für dieses Studio';

  @override
  String get search_back_to_studios => 'Zurück zu Studios';

  @override
  String get search_filter_genre => 'Genres';

  @override
  String get search_genre_hint => 'Wähle ein Genre, um deine Titel zu sehen';

  @override
  String get search_genre_no_results =>
      'Du besitzt keine Titel in diesem Genre';

  @override
  String get search_back_to_genres => 'Zurück zu Genres';

  @override
  String get search_voice => 'Sprachsuche';

  @override
  String get search_clear_history => 'Verlauf löschen';

  @override
  String get search_clear_history_confirm => 'Alle letzten Suchen entfernen?';

  @override
  String get search_remove_from_wishlist => 'Von der Wunschliste entfernen';

  @override
  String get search_wishlist_empty =>
      'Ihre Wunschliste ist leer. Tippen Sie auf das Lesezeichen bei einem TMDb-Ergebnis, um es hier zu speichern.';

  @override
  String get search_detail_overview => 'Übersicht';

  @override
  String get search_detail_genres => 'Genres';

  @override
  String search_detail_runtime(int minutes) {
    return '$minutes Min.';
  }

  @override
  String search_detail_open_in_playlist(String playlist) {
    return 'In $playlist öffnen';
  }

  @override
  String get search_detail_not_in_playlists =>
      'In keiner Ihrer Wiedergabelisten';

  @override
  String get stream_info => 'Stream-Infos';

  @override
  String get resolution => 'Auflösung';

  @override
  String get frames_per_second => 'Bilder pro Sekunde';

  @override
  String get video_codec => 'Video-Codec';

  @override
  String get audio_codec => 'Audio-Codec';

  @override
  String get audio_channels => 'Audio-Kanäle';

  @override
  String get bitrate => 'Bitrate';

  @override
  String get sort_recently_added => 'Zuletzt hinzugefügt';

  @override
  String get view_all_movies => 'Alle Filme';

  @override
  String get view_all_series => 'Alle Serien';

  @override
  String get view_all_live => 'Alle Sender';

  @override
  String get import_from_url => 'Aus URL importieren';

  @override
  String get import_url_subtitle =>
      'Sicherung per HTTP herunterladen — nützlich auf TV-Boxen ohne Dateiauswahl';

  @override
  String get import_url_hint => 'https://beispiel.de/backup.aipbak';

  @override
  String get import_url_invalid => 'Ungültige URL';

  @override
  String get import_url_failed =>
      'Sicherung konnte nicht heruntergeladen werden';

  @override
  String get import_from_device => 'Gerätespeicher durchsuchen';

  @override
  String get import_from_device_subtitle =>
      'Integrierter Dateibrowser — funktioniert auf TV-Boxen ohne Systempicker';

  @override
  String get file_browser_root_picker => 'Startordner ändern';

  @override
  String get file_browser_parent_directory => 'Übergeordneter Ordner';

  @override
  String get file_browser_permission_denied =>
      'Speicherberechtigung verweigert. Erteile sie in den Systemeinstellungen, um Dateien zu durchsuchen.';

  @override
  String get file_browser_unreadable => 'Dieser Ordner ist nicht lesbar.';

  @override
  String get file_browser_no_roots =>
      'Kein zugänglicher Speicher auf diesem Gerät gefunden.';

  @override
  String get file_browser_empty => 'Keine passenden Dateien in diesem Ordner.';

  @override
  String get exit_confirm_title => 'App beenden?';

  @override
  String get exit_confirm_message => 'Sie verlassen Rensi IPTV.';

  @override
  String get exit_confirm_action => 'Beenden';

  @override
  String get nav_home => 'Start';

  @override
  String get nav_browse => 'Entdecken';

  @override
  String get nav_live => 'Live';

  @override
  String get nav_my_list => 'Meine Liste';

  @override
  String get onboarding_requirements_hint =>
      'Sie brauchen die URL oder die Zugangsdaten Ihres IPTV-Anbieters';

  @override
  String get nav_settings => 'Einstellungen';

  @override
  String get empty_list_title => 'Ihre Liste ist leer';

  @override
  String get empty_list_body =>
      'Fügen Sie Titel hinzu und finden Sie sie hier wieder.';

  @override
  String get action_browse_catalogue => 'Katalog durchsuchen';

  @override
  String get video_decoding_label => 'Video-Dekodierung';

  @override
  String get video_decoding_description =>
      'Automatisch funktioniert auf fast allen Geräten. Ändere es nur, wenn ein Sender nicht abspielt.';

  @override
  String get video_decoding_auto => 'Automatisch';

  @override
  String get video_decoding_hw => 'Direkte Hardware';

  @override
  String get video_decoding_software => 'Software';

  @override
  String get downloads_title => 'Downloads';

  @override
  String get downloads_empty => 'Noch keine Downloads';

  @override
  String get downloads_storage_used => 'Belegter Speicher';

  @override
  String get download_status_queued => 'In Warteschlange';

  @override
  String get download_status_downloading => 'Wird heruntergeladen';

  @override
  String get download_status_paused => 'Pausiert';

  @override
  String get download_status_complete => 'Abgeschlossen';

  @override
  String get download_status_failed => 'Fehlgeschlagen';

  @override
  String get download_pause => 'Pausieren';

  @override
  String get download_resume => 'Fortsetzen';

  @override
  String get download_cancel => 'Abbrechen';

  @override
  String get download_delete => 'Löschen';

  @override
  String get download_send_to_tv => 'An TV senden';

  @override
  String get download_for_offline => 'Für Offline-Wiedergabe herunterladen';

  @override
  String get download_available_offline => 'Offline verfügbar';

  @override
  String get download_failed_retry =>
      'Download fehlgeschlagen — zum Wiederholen tippen';

  @override
  String get tv_ready_subtitle =>
      'Bereit, Inhalte von deinem Telefon zu empfangen';

  @override
  String get tv_playback_settings => 'Wiedergabeeinstellungen';

  @override
  String get tv_replay_failed =>
      'Dieser Inhalt konnte zum Abspielen nicht abgerufen werden.';

  @override
  String get cast_need_wifi =>
      'Verbinde dich mit demselben Wi‑Fi-Netzwerk wie die TV, um die Datei zu senden.';

  @override
  String get download_err_http => 'HTTP-Fehler';

  @override
  String get download_err_start_failed =>
      'Der Download konnte nicht gestartet werden';

  @override
  String get download_err_file_missing =>
      'Die heruntergeladene Datei ist nicht mehr verfügbar';

  @override
  String get download_err_canceled =>
      'Download abgebrochen oder nicht gefunden';

  @override
  String get download_err_server_page =>
      'Der Server hat eine Fehlerseite zurückgegeben (Sitzung abgelaufen oder ungültige ID)';

  @override
  String get download_err_generic => 'Der Download ist fehlgeschlagen';

  @override
  String get download_retry => 'Wiederholen';

  @override
  String get tv_cast_replay_hint =>
      'Watched by casting from your phone. Send it again from your phone to play it here.';

  @override
  String tv_status_discoverable(String deviceName) {
    return 'Sichtbar als $deviceName';
  }

  @override
  String get tv_status_error => 'Im Netzwerk nicht auffindbar';

  @override
  String get tv_empty_step_wifi => 'Gleiches WLAN wie dein Fernseher';

  @override
  String get tv_empty_step_phone => 'Öffne Rensi auf deinem Handy';

  @override
  String get tv_empty_step_cast =>
      'Tippe auf „Übertragen“ und wähle diesen Fernseher';

  @override
  String get tv_history_hint => 'Mach weiter, wo du aufgehört hast';

  @override
  String get tv_preparing_series => 'Wird vorbereitet…';

  @override
  String get developer => 'Entwickler';

  @override
  String get dev_account => 'Konto';

  @override
  String get dev_server => 'Server';

  @override
  String get dev_application => 'Anwendung';

  @override
  String get dev_catalogue => 'Katalog';

  @override
  String get dev_playlist => 'Wiedergabeliste';

  @override
  String get dev_expires => 'Ablaufdatum';

  @override
  String get dev_trial => 'Testkonto';

  @override
  String get dev_active_connections => 'Aktive Verbindungen';

  @override
  String get dev_max_connections => 'Maximale Verbindungen';

  @override
  String get dev_created => 'Erstellt';

  @override
  String get dev_output_formats => 'Zulässige Formate';

  @override
  String get dev_server_url => 'Server-URL';

  @override
  String get dev_port => 'Port';

  @override
  String get dev_https_port => 'HTTPS-Port';

  @override
  String get dev_protocol => 'Protokoll';

  @override
  String get dev_rtmp_port => 'RTMP-Port';

  @override
  String get dev_server_time => 'Serverzeit';

  @override
  String get dev_build_number => 'Build-Nummer';

  @override
  String get dev_schema_version => 'Datenbankschema';

  @override
  String get dev_last_sync => 'Letzte Synchronisierung';

  @override
  String get dev_never => 'Nie';

  @override
  String get dev_source_url => 'Quell-URL';

  @override
  String get dev_series => 'Serien';

  @override
  String get dev_items => 'Elemente';

  @override
  String get dev_yes => 'Ja';

  @override
  String get dev_no => 'Nein';

  @override
  String get dev_no_data => 'Keine Daten verfügbar';

  @override
  String get dev_status => 'Status';
}
