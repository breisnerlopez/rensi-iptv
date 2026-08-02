// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get prebuffer_preparing => 'Préparation…';

  @override
  String get prebuffer_ready => 'Prêt pour une lecture fluide';

  @override
  String get prebuffer_slow => 'Connexion lente';

  @override
  String get prebuffer_stalled => 'Pas de données : vérifiez votre connexion';

  @override
  String get prebuffer_play_now => 'Lire maintenant';

  @override
  String get cast_gate_prompt => 'Envoyer ceci sur votre TV ?';

  @override
  String get cast_gate_play_now => 'Lire ici';

  @override
  String get cast_to_tv => 'Diffuser sur la TV';

  @override
  String get cast_sent_to_tv => 'Envoyé sur la TV';

  @override
  String get cast_send_failed => 'Impossible d\'envoyer sur la TV';

  @override
  String get cast_searching => 'Recherche de téléviseurs sur votre réseau…';

  @override
  String get cast_no_devices =>
      'Aucun téléviseur trouvé. Vérifiez que l\'application est ouverte sur votre TV et que vous êtes sur le même Wi-Fi.';

  @override
  String get cast_choose_device => 'Choisir un téléviseur';

  @override
  String get cast_connecting => 'Connexion…';

  @override
  String get cast_enter_pin => 'Saisissez le code affiché sur votre TV';

  @override
  String get cast_pair => 'Associer';

  @override
  String get cast_pairing => 'Association…';

  @override
  String get cast_wrong_pin => 'Code incorrect. Réessayez.';

  @override
  String get cast_playing_on => 'Lecture sur';

  @override
  String get cast_remote_hint => 'Votre téléphone est la télécommande';

  @override
  String get cast_stop => 'Arrêter la diffusion';

  @override
  String get cast_error => 'Impossible de se connecter au téléviseur';

  @override
  String get cast_retry => 'Réessayer';

  @override
  String cast_tv_volume(int value) {
    return 'Volume TV  $value %';
  }

  @override
  String get tv_standalone_section => 'TV / Diffusion';

  @override
  String get tv_standalone_master_title =>
      'Continuer sur la TV sans le téléphone';

  @override
  String get tv_standalone_master_subtitle =>
      'Permet à une TV de confiance d\'enregistrer vos identifiants de fournisseur, chiffrés, pour continuer la lecture après la fermeture de l\'app. Désactivé par défaut.';

  @override
  String get pause_cast_on_call_title =>
      'Mettre la TV en pause pendant un appel';

  @override
  String get pause_cast_on_call_subtitle =>
      'Pendant la diffusion, un appel entrant met la lecture en pause sur la TV et la reprend à la fin de l\'appel.';

  @override
  String tv_standalone_consent_title(String device) {
    return 'Garder la session sur $device ?';
  }

  @override
  String tv_standalone_consent_body(String provider) {
    return 'Vos identifiants $provider seront enregistrés CHIFFRÉS sur la TV pour continuer à regarder sans votre téléphone. Risque : sur une TV rootée ou compromise, ils pourraient être extraits ; l\'appairage par code PIN ne protège pas contre un attaquant qui capture l\'appairage (vulnérabilité connue).';
  }

  @override
  String get tv_standalone_consent_accept => 'Activer';

  @override
  String get tv_standalone_consent_decline => 'Pas maintenant';

  @override
  String get tv_standalone_revoke_empty =>
      'Aucune TV n\'a d\'identifiants enregistrés.';

  @override
  String get tv_standalone_revoke_action =>
      'Oublier les identifiants sur cette TV';

  @override
  String get slogan => 'Lecteur IPTV';

  @override
  String get search => 'Rechercher';

  @override
  String get search_live_stream => 'Rechercher un direct';

  @override
  String get search_movie => 'Rechercher un film';

  @override
  String get search_series => 'Rechercher une série';

  @override
  String get not_found_in_category =>
      'Aucun contenu trouvé dans cette catégorie';

  @override
  String get live_stream_not_found => 'Aucun direct trouvé';

  @override
  String get movie_not_found => 'Aucun film trouvé';

  @override
  String get see_all => 'Voir tout';

  @override
  String get popular_section_title => 'Populaires';

  @override
  String get popular_window_month => 'Ce mois-ci';

  @override
  String get popular_window_year => 'Cette année';

  @override
  String get popular_window_all_time => 'De tous les temps';

  @override
  String get preview => 'Aperçu';

  @override
  String get info => 'Informations';

  @override
  String get close => 'Fermer';

  @override
  String get reset => 'Réinitialiser';

  @override
  String get delete => 'Supprimer';

  @override
  String get cancel => 'Annuler';

  @override
  String get refresh => 'Actualiser';

  @override
  String get back => 'Retour';

  @override
  String get clear => 'Effacer';

  @override
  String get clear_all => 'Tout effacer';

  @override
  String get day => 'Jour';

  @override
  String get clear_all_confirmation_message =>
      'Êtes-vous sûr de vouloir supprimer tout l\'historique ?';

  @override
  String get try_again => 'Réessayer';

  @override
  String get player_exit_press_back_again =>
      'Appuyez à nouveau sur retour pour quitter';

  @override
  String get history => 'Historique';

  @override
  String get history_empty_message => 'Vos vidéos regardées apparaîtront ici';

  @override
  String get live => 'Direct';

  @override
  String get live_streams => 'Diffusions en direct';

  @override
  String get on_live => 'En direct';

  @override
  String get other_channels => 'Autres chaînes';

  @override
  String get movies => 'Films';

  @override
  String get movie => 'Film';

  @override
  String get series_singular => 'Série';

  @override
  String get series_plural => 'Séries';

  @override
  String get category_id => 'ID de catégorie';

  @override
  String get channel_information => 'Informations de la chaîne';

  @override
  String get channel_id => 'ID de la chaîne';

  @override
  String get series_id => 'ID de la série';

  @override
  String get quality => 'Qualité';

  @override
  String get stream_type => 'Type de flux';

  @override
  String get format => 'Format';

  @override
  String get season => 'Saisons';

  @override
  String episode_count(Object count) {
    return '$count épisodes';
  }

  @override
  String duration(Object duration) {
    return 'Durée : $duration';
  }

  @override
  String get episode_duration => 'Durée de l\'épisode';

  @override
  String episode_duration_minutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get creation_date => 'Date d\'ajout';

  @override
  String get release_date => 'Date de sortie';

  @override
  String get genre => 'Genre';

  @override
  String get cast => 'Distribution';

  @override
  String get director => 'Réalisateur';

  @override
  String get description => 'Description';

  @override
  String get video_track => 'Piste vidéo';

  @override
  String get audio_track => 'Piste audio';

  @override
  String get speed => 'Speed';

  @override
  String get load => 'Load';

  @override
  String get external_subtitle => 'External subtitle';

  @override
  String get external_subtitle_url => 'External subtitle (URL)';

  @override
  String get subtitle_track => 'Piste de sous-titres';

  @override
  String get settings => 'Paramètres';

  @override
  String get hold_ok_for_options => 'Hold OK for audio & subtitles';

  @override
  String get general_settings => 'Paramètres généraux';

  @override
  String get app_language => 'Langue de l\'application';

  @override
  String get continue_on_background => 'Continuer la lecture en arrière-plan';

  @override
  String get continue_on_background_description =>
      'Continuer la lecture même quand l\'app est en arrière-plan';

  @override
  String get auto_pip_on_home => 'Picture-in-Picture en quittant';

  @override
  String get auto_pip_on_home_description =>
      'Réduit le lecteur en fenêtre flottante quand vous quittez l\'app';

  @override
  String get sleep_timer => 'Minuteur de veille';

  @override
  String get sleep_timer_off => 'Désactivé';

  @override
  String get sleep_timer_minutes_suffix => 'min';

  @override
  String get sleep_timer_hours_suffix => 'h';

  @override
  String get refresh_contents => 'Actualiser le contenu';

  @override
  String get subtitle_settings => 'Paramètres des sous-titres';

  @override
  String get subtitle_settings_description =>
      'Personnaliser l\'apparence des sous-titres';

  @override
  String get sample_text =>
      'Exemple de texte de sous-titre\nCela ressemblera à ceci';

  @override
  String get font_settings => 'Paramètres de police';

  @override
  String get font_size => 'Taille de police';

  @override
  String get font_height => 'Hauteur de ligne';

  @override
  String get letter_spacing => 'Espacement des lettres';

  @override
  String get word_spacing => 'Espacement des mots';

  @override
  String get padding => 'Espacement interne';

  @override
  String get color_settings => 'Paramètres de couleur';

  @override
  String get text_color => 'Couleur du texte';

  @override
  String get background_color => 'Couleur d\'arrière-plan';

  @override
  String get style_settings => 'Paramètres de style';

  @override
  String get font_weight => 'Épaisseur de police';

  @override
  String get thin => 'Fin';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Moyen';

  @override
  String get bold => 'Gras';

  @override
  String get extreme_bold => 'Extra gras';

  @override
  String get text_align => 'Alignement du texte';

  @override
  String get left => 'Gauche';

  @override
  String get center => 'Centre';

  @override
  String get right => 'Droite';

  @override
  String get justify => 'Justifié';

  @override
  String get pick_color => 'Choisir une couleur';

  @override
  String get my_playlists => 'Mes listes de lecture';

  @override
  String get create_new_playlist => 'Créer une nouvelle liste';

  @override
  String get loading_playlists => 'Chargement des listes...';

  @override
  String get playlist_list => 'Liste de lecture';

  @override
  String get playlist_information => 'Informations de la liste';

  @override
  String get playlist_name => 'Nom de la liste';

  @override
  String get playlist_name_placeholder => 'Entrez un nom pour votre liste';

  @override
  String get playlist_name_required => 'Le nom de la liste est requis';

  @override
  String get playlist_name_min_2 =>
      'Le nom doit contenir au moins 2 caractères';

  @override
  String playlist_deleted(Object name) {
    return '$name supprimée';
  }

  @override
  String get playlist_delete_confirmation_title => 'Supprimer la liste';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'Êtes-vous sûr de vouloir supprimer la liste \'$name\' ?\nCette action ne peut pas être annulée.';
  }

  @override
  String get empty_playlist_title => 'Aucune liste pour le moment';

  @override
  String get empty_playlist_message =>
      'Commencez par créer votre première liste de lecture.\nVous pouvez ajouter des listes au format Xtream Code ou M3U.';

  @override
  String get empty_playlist_button => 'Créer ma première liste';

  @override
  String get favorites => 'Favoris';

  @override
  String get see_all_favorites => 'Voir Tout';

  @override
  String get added_to_favorites => 'Ajouté aux favoris';

  @override
  String get removed_from_favorites => 'Retiré des favoris';

  @override
  String get action_save_to_list => 'Ma liste';

  @override
  String get action_saved => 'Enregistré';

  @override
  String get remove_from_favorites => 'Retirer des Favoris';

  @override
  String get select_playlist_type => 'Sélectionner le type de liste';

  @override
  String get select_playlist_message =>
      'Choisissez le type de liste que vous voulez créer';

  @override
  String get xtream_code_title =>
      'Se connecter avec l\'URL API, nom d\'utilisateur et mot de passe';

  @override
  String get xtream_code_description =>
      'Connectez-vous facilement avec les informations de votre fournisseur IPTV';

  @override
  String get select_playlist_type_footer =>
      'Les informations de votre liste sont stockées en sécurité sur votre appareil.';

  @override
  String get api_url => 'URL de l\'API';

  @override
  String get api_url_required => 'URL de l\'API requise';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get username_placeholder => 'Entrez votre nom d\'utilisateur';

  @override
  String get username_required => 'Nom d\'utilisateur requis';

  @override
  String get username_min_3 =>
      'Le nom d\'utilisateur doit contenir au moins 3 caractères';

  @override
  String get password => 'Mot de passe';

  @override
  String get password_placeholder => 'Entrez votre mot de passe';

  @override
  String get password_required => 'Mot de passe requis';

  @override
  String get password_min_3 =>
      'Le mot de passe doit contenir au moins 3 caractères';

  @override
  String get server_url => 'URL du serveur';

  @override
  String get submitting => 'Sauvegarde...';

  @override
  String get submit_create_playlist => 'Sauvegarder la liste';

  @override
  String get subscription_details => 'Détails de l\'abonnement';

  @override
  String subscription_remaining_day(Object days) {
    return 'Abonnement : $days';
  }

  @override
  String get remaining_day_title => 'Temps restant';

  @override
  String remaining_day(Object days) {
    return '$days jours';
  }

  @override
  String get connected => 'Connecté';

  @override
  String get no_connection => 'Pas de connexion';

  @override
  String get expired => 'Expiré';

  @override
  String get active_connection => 'Connexion active';

  @override
  String get maximum_connection => 'Connexion maximale';

  @override
  String get server_information => 'Informations du serveur';

  @override
  String get timezone => 'Fuseau horaire';

  @override
  String get server_message => 'Message du serveur';

  @override
  String get all_datas_are_stored_in_device =>
      'Toutes les données sont stockées en sécurité sur votre appareil';

  @override
  String get url_format_validate_message =>
      'Le format de l\'URL doit être comme http://serveur:port';

  @override
  String get url_format_validate_error =>
      'Veuillez entrer une URL valide (doit commencer par http:// ou https://)';

  @override
  String get playlist_name_already_exists =>
      'Une liste avec ce nom existe déjà';

  @override
  String get invalid_credentials =>
      'Impossible d\'obtenir une réponse de votre fournisseur IPTV, vérifiez vos informations';

  @override
  String get error_occurred => 'Une erreur s\'est produite';

  @override
  String get playback_failed => 'Impossible de lire ce contenu';

  @override
  String get connecting => 'Connexion en cours';

  @override
  String get preparing_categories => 'Préparation des catégories';

  @override
  String preparing_categories_exception(Object error) {
    return 'Impossible de charger les catégories : $error';
  }

  @override
  String get preparing_live_streams => 'Chargement des chaînes en direct';

  @override
  String get preparing_live_streams_exception_1 =>
      'Impossible d\'obtenir les chaînes en direct';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Erreur lors du chargement des chaînes en direct : $error';
  }

  @override
  String get preparing_movies => 'Ouverture de la bibliothèque de films';

  @override
  String get preparing_movies_exception_1 => 'Impossible d\'obtenir les films';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Erreur lors du chargement des films : $error';
  }

  @override
  String get preparing_series => 'Préparation de la bibliothèque de séries';

  @override
  String get preparing_series_exception_1 => 'Impossible d\'obtenir les séries';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Erreur lors du chargement des séries : $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'Impossible d\'obtenir les informations utilisateur';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Erreur lors du chargement des informations utilisateur : $error';
  }

  @override
  String get m3u_playlist_title =>
      'Ajouter une playlist avec un fichier M3U ou une URL';

  @override
  String get m3u_playlist_description =>
      'Prend en charge les fichiers au format M3U traditionnel';

  @override
  String get m3u_playlist => 'Playlist M3U';

  @override
  String get m3u_playlist_load_description =>
      'Charger les chaînes IPTV avec un fichier de playlist M3U ou une URL';

  @override
  String get playlist_name_hint => 'Entrez le nom de la playlist';

  @override
  String get playlist_name_min_length =>
      'Le nom de la playlist doit comporter au moins 2 caractères';

  @override
  String get source_type => 'Type de source';

  @override
  String get url => 'URL';

  @override
  String get file => 'Fichier';

  @override
  String get m3u_url => 'URL M3U';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'L\'URL M3U est requise';

  @override
  String get url_format_error => 'Entrez un format d\'URL valide';

  @override
  String get url_scheme_error =>
      'L\'URL doit commencer par http:// ou https://';

  @override
  String get m3u_file => 'Fichier M3U';

  @override
  String get file_selected => 'Fichier sélectionné';

  @override
  String get select_m3u_file => 'Sélectionner un fichier M3U (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Veuillez sélectionner un fichier M3U';

  @override
  String get file_selection_error => 'Erreur lors de la sélection du fichier';

  @override
  String get processing => 'Traitement en cours...';

  @override
  String get create_playlist => 'Créer une playlist';

  @override
  String get error_occurred_title => 'Erreur survenue';

  @override
  String get m3u_info_message =>
      'Toutes les données sont stockées en toute sécurité sur votre appareil.\nFormats pris en charge : .m3u, .m3u8\nFormat d\'URL : Doit commencer par http:// ou https://';

  @override
  String get m3u_parse_error => 'Erreur d\'analyse M3U';

  @override
  String get loading_m3u => 'Chargement M3U';

  @override
  String get preparing_m3u_exception_no_source => 'Aucune source M3U trouvée';

  @override
  String get preparing_m3u_exception_empty => 'Le fichier M3U est vide';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'Erreur d\'analyse M3U : $error';
  }

  @override
  String get not_categorized => 'Non catégorisé';

  @override
  String get loading_lists => 'Chargement des listes...';

  @override
  String get all => 'Tous';

  @override
  String iptv_channels_count(Object count) {
    return 'Chaînes IPTV ($count)';
  }

  @override
  String get unknown_channel => 'Chaîne inconnue';

  @override
  String get live_content => 'EN DIRECT';

  @override
  String get movie_content => 'FILM';

  @override
  String get series_content => 'SÉRIE';

  @override
  String get media_content => 'MÉDIA';

  @override
  String get m3u_error => 'Erreur M3U';

  @override
  String get episode_short => 'Ép';

  @override
  String season_number(Object number) {
    return 'Saison $number';
  }

  @override
  String get image_loading => 'Chargement de l\'image...';

  @override
  String get image_not_found => 'Image non trouvée';

  @override
  String get select_all => 'Tout Sélectionner';

  @override
  String get deselect_all => 'Tout Désélectionner';

  @override
  String get hide_category => 'Masquer les catégories';

  @override
  String get rating => 'Note';

  @override
  String get remove_from_history => 'Retirer de l\'historique';

  @override
  String get remove_from_history_confirmation =>
      'Êtes-vous sûr de vouloir retirer cet élément de l\'historique de lecture ?';

  @override
  String get remove => 'Retirer';

  @override
  String get clear_old_records => 'Effacer les anciens enregistrements';

  @override
  String get clear_old_records_confirmation =>
      'Êtes-vous sûr de vouloir supprimer les enregistrements de lecture de plus de 30 jours ?';

  @override
  String get clear_old => 'Effacer anciens';

  @override
  String get clear_all_history => 'Effacer tout l\'historique';

  @override
  String get clear_all_history_confirmation =>
      'Êtes-vous sûr de vouloir supprimer tout l\'historique de lecture ?';

  @override
  String get resume_failed =>
      'Ce titre n\'est plus disponible dans cette liste';

  @override
  String get search_in_your_library => 'Dans votre bibliothèque';

  @override
  String get search_discover_tmdb => 'Découvrir sur TMDb';

  @override
  String get search_not_in_lists => 'Absent de vos listes';

  @override
  String get search_global_disabled =>
      'Ajoutez votre clé TMDb pour découvrir des titres au-delà de vos listes.';

  @override
  String get search_enable_global => 'Activer la recherche globale';

  @override
  String get search_key_rejected =>
      'Votre clé TMDb a été refusée. Vérifiez-la dans les Réglages.';

  @override
  String get search_tmdb_rate_limited =>
      'Trop de recherches. Réessayez dans un instant.';

  @override
  String get search_tmdb_error => 'Impossible de joindre TMDb.';

  @override
  String get search_add_to_wishlist => 'Ajouter à la liste de souhaits';

  @override
  String get search_play_from => 'Lire depuis';

  @override
  String get search_not_available_body =>
      'Absent de vos listes. Enregistrez-le et nous vérifierons dès qu’il apparaît.';

  @override
  String get search_keep_typing_global =>
      'Continuez à taper pour rechercher sur TMDb';

  @override
  String get search_saved => 'Enregistré';

  @override
  String get search_saved_confirm => 'Ajouté à votre liste de souhaits';

  @override
  String get search_removed_confirm => 'Retiré de votre liste de souhaits';

  @override
  String get search_in_wishlist_body =>
      'Dans votre liste de souhaits. Nous vous préviendrons dès qu\'il sera disponible.';

  @override
  String get key_space => 'Espace';

  @override
  String get key_backspace => 'Retour arrière';

  @override
  String get home_empty_title =>
      'Aucun film ni série dans cette liste pour l\'instant.';

  @override
  String get home_empty_hint =>
      'Utilisez “En direct” dans le menu pour regarder des chaînes, ou lancez une recherche.';

  @override
  String get loading => 'Chargement...';

  @override
  String get greeting_morning => 'Bonjour';

  @override
  String get greeting_afternoon => 'Bon après-midi';

  @override
  String get greeting_evening => 'Bonsoir';

  @override
  String get featured_today => 'À LA UNE';

  @override
  String get search_catalog_hint => 'Cherchez dans tout votre catalogue';

  @override
  String get search_placeholder => 'Rechercher films, séries, chaînes…';

  @override
  String get search_recent => 'Recherches récentes';

  @override
  String get search_recent_remove => 'Supprimer';

  @override
  String get no_channels => 'Aucune chaîne';

  @override
  String get no_results_filter => 'Aucun résultat pour ce filtre';

  @override
  String get preferred_audio => 'Audio préféré';

  @override
  String get preferred_subtitles => 'Sous-titres préférés';

  @override
  String get decoder_applies_next_video =>
      'S\'appliquera à la prochaine vidéo ouverte';

  @override
  String no_results_for(String query) {
    return 'Aucun résultat pour \"$query\"';
  }

  @override
  String saved_titles_count(int count) {
    return '$count titres enregistrés';
  }

  @override
  String get history_cleared => 'Historique de lecture effacé';

  @override
  String get history_clear_failed =>
      'Impossible d\'effacer l\'historique de lecture';

  @override
  String get appearance => 'Apparence';

  @override
  String get theme => 'Thème';

  @override
  String get standard => 'Défaut';

  @override
  String get light => 'Clair';

  @override
  String get dark => 'Sombre';

  @override
  String get trailer => 'Bande-annonce';

  @override
  String get new_ep => 'Nouveau';

  @override
  String get continue_watching => 'Continuer à regarder';

  @override
  String get start_watching => 'Commencer à regarder';

  @override
  String continue_watching_label(String season, String episode) {
    return 'Continuer : S $season Épisode $episode';
  }

  @override
  String get player_settings => 'Paramètres du lecteur';

  @override
  String get brightness_gesture => 'Geste de luminosité';

  @override
  String get brightness_gesture_description =>
      'Contrôler la luminosité en glissant verticalement sur le côté gauche';

  @override
  String get volume_gesture => 'Geste de volume';

  @override
  String get volume_gesture_description =>
      'Contrôler le volume en glissant verticalement sur le côté droit';

  @override
  String get seek_gesture => 'Geste de recherche';

  @override
  String get seek_gesture_description =>
      'Rechercher en glissant horizontalement';

  @override
  String get speed_up_on_long_press => 'Accélérer avec appui long';

  @override
  String get speed_up_on_long_press_description =>
      'Accélérer la lecture lors d\'un appui long';

  @override
  String get seek_on_double_tap => 'Rechercher avec double tap';

  @override
  String get seek_on_double_tap_description =>
      'Rechercher avant/arrière avec double tap';

  @override
  String get copied_to_clipboard => 'Copié dans le presse-papiers';

  @override
  String get about => 'À propos';

  @override
  String get app_version => 'Version de l\'application';

  @override
  String get support_on_github => 'Soutenir sur GitHub';

  @override
  String get support_on_github_description => 'Contribuer au projet sur GitHub';

  @override
  String get last_channel => 'Last channel';

  @override
  String get select_channel => 'Sélectionner la Chaîne';

  @override
  String get episodes => 'Épisodes';

  @override
  String get next_episode => 'Épisode suivant';

  @override
  String get categories => 'Catégories';

  @override
  String get seasons => 'Saisons';

  @override
  String season_number_format(int number) {
    return 'Saison $number';
  }

  @override
  String episode_count_format(int count) {
    return '$count épisodes';
  }

  @override
  String channel_count_format(int count) {
    return '$count chaînes';
  }

  @override
  String get video_info => 'Informations Vidéo';

  @override
  String get video_info_not_found => 'Informations vidéo introuvables';

  @override
  String get name => 'Nom';

  @override
  String get content_type => 'Type de Contenu';

  @override
  String get plot => 'Intrigue';

  @override
  String get duration_unknown => 'Inconnu';

  @override
  String get url_copied_to_clipboard => 'URL copiée dans le presse-papiers';

  @override
  String get stream_id => 'ID de Flux';

  @override
  String get epg_channel_id => 'ID de Chaîne EPG';

  @override
  String get category => 'Catégorie';

  @override
  String get add_to_favorites => 'Ajouter aux Favoris';

  @override
  String get no_tracks_available => 'Aucune piste disponible';

  @override
  String get live_stream_content_type => 'Diffusion en Direct';

  @override
  String get movie_content_type => 'Film';

  @override
  String get series_content_type => 'Série';

  @override
  String get last_update => 'Dernière Mise à Jour';

  @override
  String get minutes => 'min';

  @override
  String get duration_label => 'Durée';

  @override
  String get tmdb_global_search => 'Recherche globale TMDb';

  @override
  String get tmdb_credential_configured =>
      'Identifiants TMDb stockés en toute sécurité';

  @override
  String get tmdb_credential_missing =>
      'Ajoutez votre clé API TMDb ou jeton d\'accès en lecture pour activer la recherche globale';

  @override
  String get tmdb_credential_label => 'Jeton API TMDb';

  @override
  String get tmdb_credential_field_label =>
      'Clé API ou jeton d\'accès en lecture';

  @override
  String get tmdb_credential_save => 'Enregistrer les identifiants';

  @override
  String get tmdb_credential_saved => 'Identifiants TMDb enregistrés';

  @override
  String get tmdb_search_hint => 'Rechercher des films et séries sur TMDb';

  @override
  String get tmdb_search_button => 'Rechercher';

  @override
  String get tmdb_search_description =>
      'Saisissez au moins 3 caractères et appuyez sur Rechercher. Les résultats sont mis en cache pendant 24 heures pour réduire l\'utilisation de l\'API.';

  @override
  String get tmdb_exact_match => 'Correspondance exacte';

  @override
  String get tmdb_not_found_in_playlists => 'Introuvable dans vos listes';

  @override
  String tmdb_available_in(Object count) {
    return 'Disponible dans $count élément(s) de liste';
  }

  @override
  String get tmdb_wishlist => 'Liste de souhaits';

  @override
  String get save => 'Enregistrer';

  @override
  String get export_playlists_and_settings =>
      'Exporter les listes et paramètres';

  @override
  String get export_subtitle =>
      'Sauvegarder toutes les listes, identifiants et paramètres de l\'application';

  @override
  String get import_playlists_and_settings =>
      'Importer les listes et paramètres';

  @override
  String get import_subtitle =>
      'Restaurer les listes et écraser les paramètres correspondants';

  @override
  String get backup_section => 'Sauvegarde';

  @override
  String get tmdb_credential_section => 'Jeton API TMDb';

  @override
  String get export_success => 'Sauvegarde exportée avec succès';

  @override
  String get export_cancelled => 'Exportation de la sauvegarde annulée';

  @override
  String get export_failed => 'Échec de l\'exportation de la sauvegarde';

  @override
  String import_success(Object count) {
    return 'Sauvegarde importée : $count listes restaurées';
  }

  @override
  String get import_cancelled => 'Importation de la sauvegarde annulée';

  @override
  String get import_failed => 'Échec de l\'importation de la sauvegarde';

  @override
  String import_summary(int created, int updated, int skipped) {
    return 'Importé : $created nouveaux, $updated mis à jour, $skipped ignorés';
  }

  @override
  String get backup_passphrase_title => 'Protéger cette sauvegarde';

  @override
  String get backup_passphrase_subtitle =>
      'Choisissez une phrase secrète pour chiffrer la sauvegarde. Laissez vide pour un export JSON en clair (les identifiants seront lisibles).';

  @override
  String get backup_passphrase_field => 'Phrase secrète';

  @override
  String get backup_passphrase_confirm => 'Confirmer la phrase secrète';

  @override
  String get backup_passphrase_mismatch =>
      'Les phrases secrètes ne correspondent pas';

  @override
  String get backup_passphrase_required =>
      'Cette sauvegarde est chiffrée. Saisissez la phrase secrète utilisée lors de sa création.';

  @override
  String get backup_passphrase_invalid =>
      'Phrase secrète incorrecte ou sauvegarde corrompue';

  @override
  String get backup_invalid_format => 'Fichier de sauvegarde invalide';

  @override
  String backup_schema_unsupported(String version) {
    return 'Version de sauvegarde non prise en charge : $version';
  }

  @override
  String get backup_plain_warning =>
      'Un export en clair laisse les URL, noms d\'utilisateur et mots de passe lisibles dans le fichier.';

  @override
  String get backup_strategy_title =>
      'Une importation remplacera les listes ayant le même identifiant.';

  @override
  String get backup_strategy_overwrite => 'Écraser les existantes';

  @override
  String get backup_strategy_keep_local => 'Conserver les versions locales';

  @override
  String get backup_encrypt => 'Chiffrer';

  @override
  String get backup_skip_encryption => 'Sans chiffrement';

  @override
  String get search_no_results => 'Aucun résultat trouvé';

  @override
  String get search_in_your_lists => 'Dans vos listes';

  @override
  String get search_from_your_iptv => 'Depuis votre IPTV';

  @override
  String get search_tmdb_section => 'TMDb';

  @override
  String get search_watch_action => 'Regarder';

  @override
  String playlist_load_failed(String error) {
    return 'Échec du chargement des listes : $error';
  }

  @override
  String playlist_save_failed(String error) {
    return 'Échec de l\'enregistrement de la liste : $error';
  }

  @override
  String playlist_update_failed(String error) {
    return 'Échec de la mise à jour de la liste : $error';
  }

  @override
  String playlist_delete_failed(String error) {
    return 'Échec de la suppression de la liste : $error';
  }

  @override
  String m3u_file_read_failed(String error) {
    return 'Impossible de lire le fichier M3U : $error';
  }

  @override
  String get m3u_url_invalid_scheme =>
      'L\'URL doit commencer par http:// ou https://';

  @override
  String m3u_url_http_status(String status) {
    return 'L\'URL M3U a renvoyé HTTP $status';
  }

  @override
  String get m3u_url_response_too_large => 'La liste M3U dépasse 50 Mo';

  @override
  String m3u_url_fetch_failed(String error) {
    return 'Impossible de télécharger l\'URL M3U : $error';
  }

  @override
  String get search_filter_all => 'Tout';

  @override
  String get search_filter_movies => 'Films';

  @override
  String get search_filter_tv => 'TV';

  @override
  String get search_filter_wishlist => 'Liste de souhaits';

  @override
  String get search_filter_people => 'Acteurs';

  @override
  String get search_person_hint =>
      'Recherchez un acteur pour voir sa filmographie';

  @override
  String get search_person_no_results => 'Aucun résultat pour cet acteur';

  @override
  String get search_back_to_actors => 'Retour aux acteurs';

  @override
  String get search_filter_studios => 'Studios';

  @override
  String get search_studio_hint => 'Recherchez un studio pour voir ses titres';

  @override
  String get search_studio_no_results => 'Aucun résultat pour ce studio';

  @override
  String get search_back_to_studios => 'Retour aux studios';

  @override
  String get search_filter_genre => 'Genres';

  @override
  String get search_genre_hint => 'Choisissez un genre pour voir vos titres';

  @override
  String get search_genre_no_results =>
      'Vous ne possédez aucun titre dans ce genre';

  @override
  String get search_back_to_genres => 'Retour aux genres';

  @override
  String get search_voice => 'Recherche vocale';

  @override
  String get search_clear_history => 'Effacer l\'historique';

  @override
  String get search_clear_history_confirm =>
      'Supprimer toutes les recherches récentes ?';

  @override
  String get search_remove_from_wishlist => 'Retirer de la liste de souhaits';

  @override
  String get search_wishlist_empty =>
      'Votre liste de souhaits est vide. Touchez le marque-page d\'un résultat TMDb pour l\'enregistrer ici.';

  @override
  String get search_detail_overview => 'Synopsis';

  @override
  String get search_detail_genres => 'Genres';

  @override
  String search_detail_runtime(int minutes) {
    return '$minutes min';
  }

  @override
  String search_detail_open_in_playlist(String playlist) {
    return 'Ouvrir dans $playlist';
  }

  @override
  String get search_detail_not_in_playlists => 'Absent de toutes vos listes';

  @override
  String get stream_info => 'Infos du flux';

  @override
  String get resolution => 'Résolution';

  @override
  String get frames_per_second => 'Images par seconde';

  @override
  String get video_codec => 'Codec vidéo';

  @override
  String get audio_codec => 'Codec audio';

  @override
  String get audio_channels => 'Canaux audio';

  @override
  String get bitrate => 'Débit binaire';

  @override
  String get sort_recently_added => 'Récemment ajoutés';

  @override
  String get view_all_movies => 'Tous les films';

  @override
  String get view_all_series => 'Toutes les séries';

  @override
  String get view_all_live => 'Toutes les chaînes';

  @override
  String get import_from_url => 'Importer depuis une URL';

  @override
  String get import_url_subtitle =>
      'Télécharge une sauvegarde via HTTP — utile sur les TV box sans sélecteur de fichiers';

  @override
  String get import_url_hint => 'https://exemple.com/backup.aipbak';

  @override
  String get import_url_invalid => 'URL invalide';

  @override
  String get import_url_failed => 'Impossible de télécharger la sauvegarde';

  @override
  String get import_from_device => 'Parcourir l\'appareil';

  @override
  String get import_from_device_subtitle =>
      'Explorateur de fichiers intégré — fonctionne sur les TV box sans sélecteur système';

  @override
  String get file_browser_root_picker => 'Changer de dossier de départ';

  @override
  String get file_browser_parent_directory => 'Dossier parent';

  @override
  String get file_browser_permission_denied =>
      'Permission de stockage refusée. Accordez-la dans les paramètres pour parcourir les fichiers.';

  @override
  String get file_browser_unreadable => 'Ce dossier n\'est pas lisible.';

  @override
  String get file_browser_no_roots =>
      'Aucun stockage accessible trouvé sur cet appareil.';

  @override
  String get file_browser_empty => 'Aucun fichier compatible dans ce dossier.';

  @override
  String get exit_confirm_title => 'Quitter l\'application ?';

  @override
  String get exit_confirm_message =>
      'Vous êtes sur le point de quitter Rensi IPTV.';

  @override
  String get exit_confirm_action => 'Quitter';

  @override
  String get nav_home => 'Accueil';

  @override
  String get nav_browse => 'Explorer';

  @override
  String get nav_live => 'En direct';

  @override
  String get nav_my_list => 'Ma liste';

  @override
  String get onboarding_requirements_hint =>
      'Vous aurez besoin de l\'URL ou des identifiants de votre fournisseur IPTV';

  @override
  String get nav_settings => 'Réglages';

  @override
  String get empty_list_title => 'Votre liste est vide';

  @override
  String get empty_list_body =>
      'Ajoutez des titres à votre liste et retrouvez-les ici.';

  @override
  String get action_browse_catalogue => 'Parcourir le catalogue';

  @override
  String get video_decoding_label => 'Décodage vidéo';

  @override
  String get video_decoding_description =>
      'Automatique fonctionne sur presque tous les appareils. Ne le changez que si une chaîne ne s\'affiche pas.';

  @override
  String get video_decoding_auto => 'Automatique';

  @override
  String get video_decoding_hw => 'Matériel direct';

  @override
  String get video_decoding_software => 'Logiciel';

  @override
  String get downloads_title => 'Téléchargements';

  @override
  String get downloads_empty => 'Aucun téléchargement pour l\'instant';

  @override
  String get downloads_storage_used => 'Stockage utilisé';

  @override
  String get download_status_queued => 'En file d\'attente';

  @override
  String get download_status_downloading => 'Téléchargement en cours';

  @override
  String get download_status_paused => 'En pause';

  @override
  String get download_status_complete => 'Terminé';

  @override
  String get download_status_failed => 'Échec';

  @override
  String get download_pause => 'Mettre en pause';

  @override
  String get download_resume => 'Reprendre';

  @override
  String get download_cancel => 'Annuler';

  @override
  String get download_delete => 'Supprimer';

  @override
  String get download_send_to_tv => 'Envoyer vers la TV';

  @override
  String get download_for_offline =>
      'Télécharger pour un visionnage hors ligne';

  @override
  String get download_available_offline => 'Disponible hors ligne';

  @override
  String get download_failed_retry =>
      'Échec du téléchargement — appuyez pour réessayer';

  @override
  String get tv_ready_subtitle =>
      'Prêt à recevoir du contenu depuis votre téléphone';

  @override
  String get tv_playback_settings => 'Paramètres de lecture';

  @override
  String get tv_replay_failed =>
      'Impossible de récupérer ce contenu pour le lire.';

  @override
  String get cast_need_wifi =>
      'Connectez-vous au même réseau Wi‑Fi que la TV pour envoyer le fichier.';

  @override
  String get download_err_http => 'Erreur HTTP';

  @override
  String get download_err_start_failed =>
      'Impossible de démarrer le téléchargement';

  @override
  String get download_err_file_missing =>
      'Le fichier téléchargé n\'est plus disponible';

  @override
  String get download_err_canceled => 'Téléchargement annulé ou introuvable';

  @override
  String get download_err_server_page =>
      'Le serveur a renvoyé une page d\'erreur (session expirée ou identifiant invalide)';

  @override
  String get download_err_generic => 'Le téléchargement a échoué';

  @override
  String get download_retry => 'Réessayer';

  @override
  String get tv_cast_replay_hint =>
      'Watched by casting from your phone. Send it again from your phone to play it here.';

  @override
  String tv_status_discoverable(String deviceName) {
    return 'Visible sous le nom $deviceName';
  }

  @override
  String get tv_status_error => 'Introuvable sur ce réseau';

  @override
  String get tv_empty_step_wifi => 'Même Wi-Fi que votre TV';

  @override
  String get tv_empty_step_phone => 'Ouvrez Rensi sur votre téléphone';

  @override
  String get tv_empty_step_cast => 'Appuyez sur Caster et choisissez cette TV';

  @override
  String get tv_history_hint => 'Reprenez là où vous vous êtes arrêté';

  @override
  String get tv_preparing_series => 'Préparation…';

  @override
  String get developer => 'Développeur';

  @override
  String get dev_account => 'Compte';

  @override
  String get dev_server => 'Serveur';

  @override
  String get dev_application => 'Application';

  @override
  String get dev_catalogue => 'Catalogue';

  @override
  String get dev_playlist => 'Liste de lecture';

  @override
  String get dev_expires => 'Expiration';

  @override
  String get dev_trial => 'Compte d\'essai';

  @override
  String get dev_active_connections => 'Connexions actives';

  @override
  String get dev_max_connections => 'Connexions maximales';

  @override
  String get dev_created => 'Créé le';

  @override
  String get dev_output_formats => 'Formats autorisés';

  @override
  String get dev_server_url => 'URL du serveur';

  @override
  String get dev_port => 'Port';

  @override
  String get dev_https_port => 'Port HTTPS';

  @override
  String get dev_protocol => 'Protocole';

  @override
  String get dev_rtmp_port => 'Port RTMP';

  @override
  String get dev_server_time => 'Heure du serveur';

  @override
  String get dev_build_number => 'Numéro de build';

  @override
  String get dev_schema_version => 'Schéma de la base de données';

  @override
  String get dev_last_sync => 'Dernière synchronisation';

  @override
  String get dev_never => 'Jamais';

  @override
  String get dev_source_url => 'URL source';

  @override
  String get dev_series => 'Séries';

  @override
  String get dev_items => 'Éléments';

  @override
  String get dev_yes => 'Oui';

  @override
  String get dev_no => 'Non';

  @override
  String get dev_no_data => 'Aucune donnée disponible';

  @override
  String get dev_status => 'Statut';
}
