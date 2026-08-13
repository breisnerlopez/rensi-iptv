// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get prebuffer_too_slow => 'Connection too slow for this quality';

  @override
  String get prebuffer_preparing => 'Preparing…';

  @override
  String get prebuffer_ready => 'Ready for smooth playback';

  @override
  String get prebuffer_slow => 'Slow connection';

  @override
  String get prebuffer_stalled => 'No data — check your connection';

  @override
  String get prebuffer_play_now => 'Play now';

  @override
  String get cast_gate_prompt => 'Send this to your TV?';

  @override
  String get cast_gate_play_now => 'Play here';

  @override
  String get cast_to_tv => 'Cast to TV';

  @override
  String get cast_sent_to_tv => 'Sent to TV';

  @override
  String get cast_send_failed => 'Couldn\'t send to TV';

  @override
  String get cast_searching => 'Searching for TVs on your network…';

  @override
  String get cast_no_devices =>
      'No TVs found. Make sure your TV has the app open and is on the same Wi-Fi.';

  @override
  String get cast_choose_device => 'Choose a TV';

  @override
  String get cast_connecting => 'Connecting…';

  @override
  String get cast_enter_pin => 'Enter the code shown on your TV';

  @override
  String get cast_pair => 'Pair';

  @override
  String get cast_pairing => 'Pairing…';

  @override
  String get cast_wrong_pin => 'Incorrect code. Try again.';

  @override
  String get cast_playing_on => 'Playing on';

  @override
  String get cast_remote_hint => 'Your phone is the remote';

  @override
  String get cast_stop => 'Stop casting';

  @override
  String get cast_error => 'Couldn\'t connect to the TV';

  @override
  String get cast_retry => 'Retry';

  @override
  String cast_tv_volume(int value) {
    return 'TV volume  $value%';
  }

  @override
  String get tv_standalone_section => 'TV / Casting';

  @override
  String get tv_standalone_master_title =>
      'Keep playing on the TV without the phone';

  @override
  String get tv_standalone_master_subtitle =>
      'Lets a trusted TV store your provider credentials, encrypted, so it can keep playing after you close the app. Off by default.';

  @override
  String get pause_cast_on_call_title => 'Pause the TV during a call';

  @override
  String get pause_cast_on_call_subtitle =>
      'While casting, an incoming call pauses playback on the TV and resumes it when the call ends.';

  @override
  String tv_standalone_consent_title(String device) {
    return 'Keep the session on $device?';
  }

  @override
  String tv_standalone_consent_body(String provider) {
    return 'Your $provider credentials will be stored ENCRYPTED on the TV so you can keep watching without your phone. Risk: on a rooted or compromised TV they could be extracted, and PIN pairing is not proof against an attacker who captures the pairing (a known vulnerability).';
  }

  @override
  String get tv_standalone_consent_accept => 'Turn on';

  @override
  String get tv_standalone_consent_decline => 'Not now';

  @override
  String get tv_standalone_revoke_empty => 'No TV has stored credentials.';

  @override
  String get tv_standalone_revoke_action => 'Forget credentials on this TV';

  @override
  String get slogan => 'IPTV Player';

  @override
  String get search => 'Search';

  @override
  String get search_live_stream => 'Search live stream';

  @override
  String get search_movie => 'Search movie';

  @override
  String get search_series => 'Search series';

  @override
  String get not_found_in_category => 'No content found in this category';

  @override
  String get live_stream_not_found => 'No live stream found';

  @override
  String get movie_not_found => 'No movie found';

  @override
  String get see_all => 'View All';

  @override
  String get popular_section_title => 'Popular';

  @override
  String get popular_window_month => 'This month';

  @override
  String get popular_window_year => 'This year';

  @override
  String get popular_window_all_time => 'All time';

  @override
  String get preview => 'Preview';

  @override
  String get info => 'Info';

  @override
  String get close => 'Close';

  @override
  String get reset => 'Reset';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get refresh => 'Refresh';

  @override
  String get back => 'Back';

  @override
  String get clear => 'Clear';

  @override
  String get clear_all => 'Clear All';

  @override
  String get day => 'Day';

  @override
  String get clear_all_confirmation_message =>
      'Are you sure want to delete all history?';

  @override
  String get try_again => 'Try Again';

  @override
  String get player_exit_press_back_again => 'Press back again to exit';

  @override
  String get history => 'History';

  @override
  String get history_empty_message => 'Your watched videos will appear here';

  @override
  String get live => 'Live';

  @override
  String get live_streams => 'Live Streams';

  @override
  String get on_live => 'Live';

  @override
  String get other_channels => 'Other Channels';

  @override
  String get movies => 'Movies';

  @override
  String get movie => 'Movie';

  @override
  String get series_singular => 'Series';

  @override
  String get series_plural => 'Series';

  @override
  String get category_id => 'Category ID';

  @override
  String get channel_information => 'Channel Information';

  @override
  String get channel_id => 'Channel ID';

  @override
  String get series_id => 'Series ID';

  @override
  String get quality => 'Quality';

  @override
  String get stream_type => 'Stream Type';

  @override
  String get format => 'Format';

  @override
  String get season => 'Seasons';

  @override
  String episode_count(Object count) {
    return '$count Episodes';
  }

  @override
  String duration(Object duration) {
    return 'Duration: $duration';
  }

  @override
  String get episode_duration => 'Episode Duration';

  @override
  String episode_duration_minutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get creation_date => 'Added Date';

  @override
  String get release_date => 'Release Date';

  @override
  String get genre => 'Genre';

  @override
  String get cast => 'Cast';

  @override
  String get director => 'Director';

  @override
  String get description => 'Description';

  @override
  String get video_track => 'Video Track';

  @override
  String get audio_track => 'Audio Track';

  @override
  String get speed => 'Speed';

  @override
  String get load => 'Load';

  @override
  String get external_subtitle => 'External subtitle';

  @override
  String get external_subtitle_url => 'External subtitle (URL)';

  @override
  String get subtitle_track => 'Subtitle Track';

  @override
  String get settings => 'Settings';

  @override
  String get hold_ok_for_options => 'Hold OK for audio & subtitles';

  @override
  String get general_settings => 'General Settings';

  @override
  String get app_language => 'App Language';

  @override
  String get continue_on_background => 'Continue Playing in Background';

  @override
  String get continue_on_background_description =>
      'Keep playing even when app is in the background';

  @override
  String get auto_pip_on_home => 'Picture-in-Picture on home';

  @override
  String get auto_pip_on_home_description =>
      'Shrink the player to a floating window when you leave the app';

  @override
  String get sleep_timer => 'Sleep timer';

  @override
  String get sleep_timer_off => 'Off';

  @override
  String get sleep_timer_minutes_suffix => 'min';

  @override
  String get sleep_timer_hours_suffix => 'h';

  @override
  String get refresh_contents => 'Refresh Content';

  @override
  String get subtitle_settings => 'Subtitle Settings';

  @override
  String get subtitle_settings_description => 'Customize subtitle appearance';

  @override
  String get sample_text => 'Sample subtitle text\nIt will look like this';

  @override
  String get font_settings => 'Font Settings';

  @override
  String get font_size => 'Font Size';

  @override
  String get font_height => 'Line Height';

  @override
  String get letter_spacing => 'Letter Spacing';

  @override
  String get word_spacing => 'Word Spacing';

  @override
  String get padding => 'Padding';

  @override
  String get color_settings => 'Color Settings';

  @override
  String get text_color => 'Text Color';

  @override
  String get background_color => 'Background Color';

  @override
  String get style_settings => 'Style Settings';

  @override
  String get font_weight => 'Font Weight';

  @override
  String get thin => 'Thin';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Medium';

  @override
  String get bold => 'Bold';

  @override
  String get extreme_bold => 'Extra Bold';

  @override
  String get text_align => 'Text Alignment';

  @override
  String get left => 'Left';

  @override
  String get center => 'Center';

  @override
  String get right => 'Right';

  @override
  String get justify => 'Justify';

  @override
  String get pick_color => 'Pick Color';

  @override
  String get my_playlists => 'My Playlists';

  @override
  String get create_new_playlist => 'Create New Playlist';

  @override
  String get loading_playlists => 'Loading Playlists...';

  @override
  String get playlist_list => 'Playlist List';

  @override
  String get playlist_information => 'Playlist Information';

  @override
  String get playlist_name => 'Playlist Name';

  @override
  String get playlist_name_placeholder => 'Name for your playlist';

  @override
  String get playlist_name_required => 'Playlist name is required';

  @override
  String get playlist_name_min_2 => 'Playlist should at least 2 character';

  @override
  String playlist_deleted(Object name) {
    return '$name deleted';
  }

  @override
  String get playlist_delete_confirmation_title => 'Delete Playlist';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'Are you sure you want to delete the playlist \'$name\'?\nThis action cannot be undone.';
  }

  @override
  String get empty_playlist_title => 'No Playlist Yet';

  @override
  String get empty_playlist_message =>
      'Start by creating your first playlist.\nYou can add playlists in Xtream Code or M3U format.';

  @override
  String get empty_playlist_button => 'Create My First Playlist';

  @override
  String get favorites => 'Favorites';

  @override
  String get see_all_favorites => 'See All';

  @override
  String get added_to_favorites => 'Added to favorites';

  @override
  String get removed_from_favorites => 'Removed from favorites';

  @override
  String get action_save_to_list => 'My List';

  @override
  String get action_saved => 'Saved';

  @override
  String get remove_from_favorites => 'Remove from Favorites';

  @override
  String get select_playlist_type => 'Select Playlist Type';

  @override
  String get select_playlist_message =>
      'Choose the type of playlist you want to create';

  @override
  String get xtream_code_title =>
      'Connect with API URL, Username, and Password';

  @override
  String get xtream_code_description =>
      'Easily connect with information from your IPTV provider';

  @override
  String get select_playlist_type_footer =>
      'Your playlist information is securely stored on your device.';

  @override
  String get api_url => 'API URL';

  @override
  String get api_url_required => 'API URL required';

  @override
  String get username => 'Username';

  @override
  String get username_placeholder => 'Enter your username';

  @override
  String get username_required => 'Username is required';

  @override
  String get username_min_3 => 'Username should at least 3 character';

  @override
  String get password => 'Password';

  @override
  String get password_placeholder => 'Enter your password';

  @override
  String get password_required => 'Password is required';

  @override
  String get password_min_3 => 'Password should at least 3 character';

  @override
  String get server_url => 'Server URL';

  @override
  String get submitting => 'Saving...';

  @override
  String get submit_create_playlist => 'Save Playlist';

  @override
  String get subscription_details => 'Subscription Details';

  @override
  String subscription_remaining_day(Object days) {
    return 'Subscription: $days';
  }

  @override
  String get remaining_day_title => 'Time Remaining';

  @override
  String remaining_day(Object days) {
    return '$days Days';
  }

  @override
  String get connected => 'Connected';

  @override
  String get no_connection => 'No Connection';

  @override
  String get expired => 'Expired';

  @override
  String get active_connection => 'Active Connection';

  @override
  String get maximum_connection => 'Maximum Connection';

  @override
  String get server_information => 'Server Information';

  @override
  String get timezone => 'Time Zone';

  @override
  String get server_message => 'Server Message';

  @override
  String get all_datas_are_stored_in_device =>
      'All data is securely stored on your device';

  @override
  String get url_format_validate_message =>
      'URL format should be like http://server:port';

  @override
  String get url_format_validate_error =>
      'Please enter a valid URL (must start with http:// or https://)';

  @override
  String get playlist_name_already_exists =>
      'A playlist with this name already exists';

  @override
  String get invalid_credentials =>
      'Could not get a response from your IPTV provider, please check your information';

  @override
  String get error_occurred => 'An error occurred';

  @override
  String get playback_failed => 'This content couldn\'t be played';

  @override
  String get connecting => 'Connecting';

  @override
  String get preparing_categories => 'Preparing categories';

  @override
  String preparing_categories_exception(Object error) {
    return 'Could not load categories: $error';
  }

  @override
  String get preparing_live_streams => 'Loading live channels';

  @override
  String get preparing_live_streams_exception_1 =>
      'Could not get live channels';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Error loading live channels: $error';
  }

  @override
  String get preparing_movies => 'Opening movie library';

  @override
  String get preparing_movies_exception_1 => 'Could not get movies';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Error loading movies: $error';
  }

  @override
  String get preparing_series => 'Preparing series library';

  @override
  String get preparing_series_exception_1 => 'Could not get series';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Error loading series: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'Could not get user information';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Error loading user information: $error';
  }

  @override
  String get m3u_playlist_title => 'Add playlist with M3U file or URL';

  @override
  String get m3u_playlist_description =>
      'Supports traditional M3U format files';

  @override
  String get m3u_playlist => 'M3U Playlist';

  @override
  String get m3u_playlist_load_description =>
      'Load IPTV channels with M3U playlist file or URL';

  @override
  String get playlist_name_hint => 'Enter playlist name';

  @override
  String get playlist_name_min_length =>
      'Playlist name must be at least 2 characters';

  @override
  String get source_type => 'Source Type';

  @override
  String get url => 'URL';

  @override
  String get file => 'File';

  @override
  String get m3u_url => 'M3U URL';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'M3U URL is required';

  @override
  String get url_format_error => 'Enter a valid URL format';

  @override
  String get url_scheme_error => 'URL must start with http:// or https://';

  @override
  String get m3u_file => 'M3U File';

  @override
  String get file_selected => 'File selected';

  @override
  String get select_m3u_file => 'Select M3U file (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Please select an M3U file';

  @override
  String get file_selection_error => 'Error occurred while selecting file';

  @override
  String get processing => 'Processing...';

  @override
  String get create_playlist => 'Create Playlist';

  @override
  String get error_occurred_title => 'Error Occurred';

  @override
  String get m3u_info_message =>
      'All data is securely stored on your device.\nSupported formats: .m3u, .m3u8\nURL format: Must start with http:// or https://';

  @override
  String get m3u_parse_error => 'M3U parsing error';

  @override
  String get loading_m3u => 'Loading M3U';

  @override
  String get preparing_m3u_exception_no_source => 'No M3U source found';

  @override
  String get preparing_m3u_exception_empty => 'M3U file is empty';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'M3U parsing error: $error';
  }

  @override
  String get not_categorized => 'Uncategorized';

  @override
  String get loading_lists => 'Loading Lists...';

  @override
  String get all => 'All';

  @override
  String iptv_channels_count(Object count) {
    return 'IPTV Channels ($count)';
  }

  @override
  String get unknown_channel => 'Unknown Channel';

  @override
  String get live_content => 'LIVE';

  @override
  String get movie_content => 'MOVIE';

  @override
  String get series_content => 'SERIES';

  @override
  String get media_content => 'MEDIA';

  @override
  String get m3u_error => 'M3U Error';

  @override
  String get episode_short => 'Ep';

  @override
  String season_number(Object number) {
    return '$number. Season';
  }

  @override
  String get image_loading => 'Loading image...';

  @override
  String get image_not_found => 'Image Not Found';

  @override
  String get select_all => 'Select All';

  @override
  String get deselect_all => 'Deselect All';

  @override
  String get hide_category => 'Hide categories';

  @override
  String get rating => 'Rating';

  @override
  String get remove_from_history => 'Remove from History';

  @override
  String get remove_from_history_confirmation =>
      'Are you sure you want to remove this item from watch history?';

  @override
  String get remove => 'Remove';

  @override
  String get clear_old_records => 'Clear Old Records';

  @override
  String get clear_old_records_confirmation =>
      'Are you sure you want to delete watch records older than 30 days?';

  @override
  String get clear_old => 'Clear Old';

  @override
  String get clear_all_history => 'Clear All History';

  @override
  String get clear_all_history_confirmation =>
      'Are you sure you want to delete all watch history?';

  @override
  String get resume_failed =>
      'This title is no longer available in this playlist';

  @override
  String get search_in_your_library => 'In your library';

  @override
  String get search_discover_tmdb => 'Discover on TMDb';

  @override
  String get search_not_in_lists => 'Not in your lists';

  @override
  String get search_global_disabled =>
      'Add your TMDb key to discover titles beyond your lists.';

  @override
  String get search_enable_global => 'Enable global search';

  @override
  String get search_key_rejected =>
      'Your TMDb key was rejected. Check it in Settings.';

  @override
  String get search_tmdb_rate_limited =>
      'Too many searches. Try again in a moment.';

  @override
  String get search_tmdb_error => 'Could not reach TMDb.';

  @override
  String get search_add_to_wishlist => 'Add to wishlist';

  @override
  String get search_play_from => 'Play from';

  @override
  String get search_not_available_body =>
      'Not in your lists. Save it and we\'ll check when it shows up.';

  @override
  String get search_keep_typing_global => 'Keep typing to search TMDb';

  @override
  String get search_saved => 'Saved';

  @override
  String get search_saved_confirm => 'Saved to your wishlist';

  @override
  String get search_removed_confirm => 'Removed from your wishlist';

  @override
  String get search_in_wishlist_body =>
      'In your wishlist. We\'ll let you know when it\'s available to play.';

  @override
  String get key_space => 'Space';

  @override
  String get key_backspace => 'Backspace';

  @override
  String get home_empty_title => 'No films or series in this playlist yet.';

  @override
  String get home_empty_hint =>
      'Use “Live” in the menu to watch channels, or search for content.';

  @override
  String get loading => 'Loading...';

  @override
  String get greeting_morning => 'Good morning';

  @override
  String get greeting_afternoon => 'Good afternoon';

  @override
  String get greeting_evening => 'Good evening';

  @override
  String get featured_today => 'FEATURED TODAY';

  @override
  String get search_catalog_hint => 'Search your whole catalogue';

  @override
  String get search_placeholder => 'Search films, series, channels…';

  @override
  String get search_recent => 'Recent searches';

  @override
  String get search_recent_remove => 'Remove';

  @override
  String get no_channels => 'No channels';

  @override
  String get no_results_filter => 'No results for this filter';

  @override
  String get preferred_audio => 'Preferred audio';

  @override
  String get preferred_subtitles => 'Preferred subtitles';

  @override
  String get decoder_applies_next_video =>
      'Applies the next time you open a video';

  @override
  String no_results_for(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String saved_titles_count(int count) {
    return '$count saved titles';
  }

  @override
  String get history_cleared => 'Watch history cleared';

  @override
  String get history_clear_failed => 'Could not clear watch history';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get standard => 'Default';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get trailer => 'Trailer';

  @override
  String get new_ep => 'New';

  @override
  String get continue_watching => 'Continue Watching';

  @override
  String get start_watching => 'Start Watching';

  @override
  String continue_watching_label(String season, String episode) {
    return 'Continue: S $season Episode $episode';
  }

  @override
  String get player_settings => 'Player Settings';

  @override
  String get brightness_gesture => 'Brightness Gesture';

  @override
  String get brightness_gesture_description =>
      'Control brightness by swiping vertically on the left side';

  @override
  String get volume_gesture => 'Volume Gesture';

  @override
  String get volume_gesture_description =>
      'Control volume by swiping vertically on the right side';

  @override
  String get seek_gesture => 'Seek Gesture';

  @override
  String get seek_gesture_description => 'Seek by swiping horizontally';

  @override
  String get speed_up_on_long_press => 'Speed Up on Long Press';

  @override
  String get speed_up_on_long_press_description =>
      'Speed up playback when long pressing';

  @override
  String get seek_on_double_tap => 'Seek on Double Tap';

  @override
  String get seek_on_double_tap_description =>
      'Seek forward/backward by double tapping';

  @override
  String get copied_to_clipboard => 'Copied to clipboard';

  @override
  String get about => 'About';

  @override
  String get app_version => 'App Version';

  @override
  String get support_on_github => 'Support on GitHub';

  @override
  String get support_on_github_description =>
      'Contribute to the project on GitHub';

  @override
  String get last_channel => 'Last channel';

  @override
  String get select_channel => 'Select Channel';

  @override
  String get episodes => 'Episodes';

  @override
  String get next_episode => 'Next episode';

  @override
  String get categories => 'Categories';

  @override
  String get seasons => 'Seasons';

  @override
  String season_number_format(int number) {
    return 'Season $number';
  }

  @override
  String episode_count_format(int count) {
    return '$count episodes';
  }

  @override
  String channel_count_format(int count) {
    return '$count channels';
  }

  @override
  String get video_info => 'Video Information';

  @override
  String get video_info_not_found => 'Video information not found';

  @override
  String get name => 'Name';

  @override
  String get content_type => 'Content Type';

  @override
  String get plot => 'Plot';

  @override
  String get duration_unknown => 'Unknown';

  @override
  String get url_copied_to_clipboard => 'URL copied to clipboard';

  @override
  String get stream_id => 'Stream ID';

  @override
  String get epg_channel_id => 'EPG Channel ID';

  @override
  String get category => 'Category';

  @override
  String get add_to_favorites => 'Add to Favorites';

  @override
  String get no_tracks_available => 'No tracks available';

  @override
  String get live_stream_content_type => 'Live Stream';

  @override
  String get movie_content_type => 'Movie';

  @override
  String get series_content_type => 'Series';

  @override
  String get last_update => 'Last Update';

  @override
  String get minutes => 'min';

  @override
  String get duration_label => 'Duration';

  @override
  String get tmdb_global_search => 'TMDb Global Search';

  @override
  String get tmdb_credential_configured => 'TMDb credential stored securely';

  @override
  String get tmdb_credential_missing =>
      'Add your TMDb API key or read access token to enable global search';

  @override
  String get tmdb_credential_label => 'TMDb API token';

  @override
  String get tmdb_credential_field_label => 'API key or read access token';

  @override
  String get tmdb_credential_save => 'Save credential';

  @override
  String get tmdb_credential_saved => 'TMDb credential saved';

  @override
  String get tmdb_search_hint => 'Search movies and series on TMDb';

  @override
  String get tmdb_search_button => 'Search';

  @override
  String get tmdb_search_description =>
      'Type at least 3 characters and press Search. Results are cached for 24 hours to reduce API usage.';

  @override
  String get tmdb_exact_match => 'Exact match';

  @override
  String get tmdb_not_found_in_playlists => 'Not found in your playlists';

  @override
  String tmdb_available_in(Object count) {
    return 'Available in $count playlist item(s)';
  }

  @override
  String get tmdb_wishlist => 'Wishlist';

  @override
  String get save => 'Save';

  @override
  String get export_playlists_and_settings => 'Export playlists and settings';

  @override
  String get export_subtitle =>
      'Save all playlists, credentials, and app settings';

  @override
  String get import_playlists_and_settings => 'Import playlists and settings';

  @override
  String get import_subtitle =>
      'Restore playlists and overwrite matching settings';

  @override
  String get backup_section => 'Backup';

  @override
  String get tmdb_credential_section => 'TMDb API token';

  @override
  String get export_success => 'Backup exported successfully';

  @override
  String get export_cancelled => 'Backup export cancelled';

  @override
  String get export_failed => 'Backup export failed';

  @override
  String import_success(Object count) {
    return 'Backup imported: $count playlists restored';
  }

  @override
  String get import_cancelled => 'Backup import cancelled';

  @override
  String get import_failed => 'Backup import failed';

  @override
  String import_summary(int created, int updated, int skipped) {
    return 'Imported: $created new, $updated updated, $skipped skipped';
  }

  @override
  String get backup_passphrase_title => 'Protect this backup';

  @override
  String get backup_passphrase_subtitle =>
      'Pick a passphrase to encrypt the backup. Leave blank for a plain JSON export (credentials will be readable).';

  @override
  String get backup_passphrase_field => 'Passphrase';

  @override
  String get backup_passphrase_confirm => 'Confirm passphrase';

  @override
  String get backup_passphrase_mismatch => 'Passphrases do not match';

  @override
  String get backup_passphrase_required =>
      'This backup is encrypted. Enter the passphrase used to create it.';

  @override
  String get backup_passphrase_invalid =>
      'Wrong passphrase or corrupted backup';

  @override
  String get backup_invalid_format => 'Invalid backup file';

  @override
  String backup_schema_unsupported(String version) {
    return 'Unsupported backup version: $version';
  }

  @override
  String get backup_plain_warning =>
      'Plain export keeps URLs, usernames and passwords readable in the file.';

  @override
  String get backup_strategy_title =>
      'An import will replace playlists with the same id.';

  @override
  String get backup_strategy_overwrite => 'Overwrite existing';

  @override
  String get backup_strategy_keep_local => 'Keep local versions';

  @override
  String get backup_encrypt => 'Encrypt';

  @override
  String get backup_skip_encryption => 'Skip encryption';

  @override
  String get search_no_results => 'No results found';

  @override
  String get search_in_your_lists => 'In your lists';

  @override
  String get search_from_your_iptv => 'From your IPTV';

  @override
  String get search_tmdb_section => 'TMDb';

  @override
  String get search_watch_action => 'Watch';

  @override
  String playlist_load_failed(String error) {
    return 'Failed to load playlists: $error';
  }

  @override
  String playlist_save_failed(String error) {
    return 'Failed to save playlist: $error';
  }

  @override
  String playlist_update_failed(String error) {
    return 'Failed to update playlist: $error';
  }

  @override
  String playlist_delete_failed(String error) {
    return 'Failed to delete playlist: $error';
  }

  @override
  String m3u_file_read_failed(String error) {
    return 'Could not read M3U file: $error';
  }

  @override
  String get m3u_url_invalid_scheme =>
      'URL must start with http:// or https://';

  @override
  String m3u_url_http_status(String status) {
    return 'M3U URL returned HTTP $status';
  }

  @override
  String get m3u_url_response_too_large => 'M3U playlist is larger than 50 MB';

  @override
  String m3u_url_fetch_failed(String error) {
    return 'Could not download M3U URL: $error';
  }

  @override
  String get search_filter_all => 'All';

  @override
  String get search_filter_movies => 'Movies';

  @override
  String get search_filter_tv => 'TV';

  @override
  String get search_filter_wishlist => 'Wishlist';

  @override
  String get search_filter_people => 'Actors';

  @override
  String get search_person_hint =>
      'Search for an actor to see their filmography';

  @override
  String get search_person_no_results => 'No results for this actor';

  @override
  String get search_back_to_actors => 'Back to actors';

  @override
  String get search_filter_studios => 'Studios';

  @override
  String get search_studio_hint => 'Search for a studio to see its titles';

  @override
  String get search_studio_no_results => 'No results for this studio';

  @override
  String get search_back_to_studios => 'Back to studios';

  @override
  String get search_filter_genre => 'Genres';

  @override
  String get search_genre_hint => 'Pick a genre to see your titles';

  @override
  String get search_genre_no_results =>
      'You don\'t own any titles in this genre';

  @override
  String get search_back_to_genres => 'Back to genres';

  @override
  String get search_voice => 'Voice search';

  @override
  String get search_clear_history => 'Clear history';

  @override
  String get search_clear_history_confirm => 'Remove all recent searches?';

  @override
  String get search_remove_from_wishlist => 'Remove from wishlist';

  @override
  String get search_wishlist_empty =>
      'Your wishlist is empty. Tap the bookmark on any TMDb result to save it here.';

  @override
  String get search_detail_overview => 'Overview';

  @override
  String get search_detail_genres => 'Genres';

  @override
  String search_detail_runtime(int minutes) {
    return '$minutes min';
  }

  @override
  String search_detail_open_in_playlist(String playlist) {
    return 'Open in $playlist';
  }

  @override
  String get search_detail_not_in_playlists => 'Not in any of your playlists';

  @override
  String get stream_info => 'Stream info';

  @override
  String get resolution => 'Resolution';

  @override
  String get frames_per_second => 'Frames per second';

  @override
  String get video_codec => 'Video codec';

  @override
  String get audio_codec => 'Audio codec';

  @override
  String get audio_channels => 'Audio channels';

  @override
  String get bitrate => 'Bitrate';

  @override
  String get sort_recently_added => 'Recently added';

  @override
  String get view_all_movies => 'All Movies';

  @override
  String get view_all_series => 'All Series';

  @override
  String get view_all_live => 'All Channels';

  @override
  String get import_from_url => 'Import from URL';

  @override
  String get import_url_subtitle =>
      'Download a backup file over HTTP — useful on TV boxes without a file picker';

  @override
  String get import_url_hint => 'https://example.com/backup.aipbak';

  @override
  String get import_url_invalid => 'Invalid URL';

  @override
  String get import_url_failed => 'Could not download the backup file';

  @override
  String get import_from_device => 'Browse device storage';

  @override
  String get import_from_device_subtitle =>
      'In-app file browser — works on TV boxes without a system file picker';

  @override
  String get file_browser_root_picker => 'Change starting folder';

  @override
  String get file_browser_parent_directory => 'Parent folder';

  @override
  String get file_browser_permission_denied =>
      'Storage permission was denied. Grant it from system settings to browse files.';

  @override
  String get file_browser_unreadable => 'This folder is not readable.';

  @override
  String get file_browser_no_roots =>
      'No accessible storage was found on this device.';

  @override
  String get file_browser_empty => 'No matching files in this folder.';

  @override
  String get exit_confirm_title => 'Exit the app?';

  @override
  String get exit_confirm_message => 'You are about to leave Rensi IPTV.';

  @override
  String get exit_confirm_action => 'Exit';

  @override
  String get nav_home => 'Home';

  @override
  String get nav_browse => 'Browse';

  @override
  String get nav_live => 'Live';

  @override
  String get nav_my_list => 'My List';

  @override
  String get onboarding_requirements_hint =>
      'You\'ll need the URL or sign-in details from your IPTV provider';

  @override
  String get nav_settings => 'Settings';

  @override
  String get empty_list_title => 'Your list is empty';

  @override
  String get empty_list_body => 'Add titles to your list and find them here.';

  @override
  String get action_browse_catalogue => 'Browse catalogue';

  @override
  String get video_decoding_label => 'Video decoding';

  @override
  String get video_decoding_description =>
      'Automatic works on almost every device. Change it only if a channel will not play.';

  @override
  String get video_decoding_auto => 'Automatic';

  @override
  String get video_decoding_hw => 'Direct hardware';

  @override
  String get video_decoding_software => 'Software';

  @override
  String get downloads_title => 'Downloads';

  @override
  String get downloads_empty => 'No downloads yet';

  @override
  String get downloads_storage_used => 'Storage used';

  @override
  String get download_status_queued => 'Queued';

  @override
  String get download_status_downloading => 'Downloading';

  @override
  String get download_status_paused => 'Paused';

  @override
  String get download_status_complete => 'Complete';

  @override
  String get download_status_failed => 'Failed';

  @override
  String get download_pause => 'Pause';

  @override
  String get download_resume => 'Resume';

  @override
  String get download_cancel => 'Cancel';

  @override
  String get download_delete => 'Delete';

  @override
  String get download_send_to_tv => 'Send to TV';

  @override
  String get download_for_offline => 'Download for offline';

  @override
  String get download_available_offline => 'Available offline';

  @override
  String get download_failed_retry => 'Download failed — tap to retry';

  @override
  String get tv_ready_subtitle => 'Ready to receive content from your phone';

  @override
  String get tv_playback_settings => 'Playback settings';

  @override
  String get tv_replay_failed => 'Couldn\'t retrieve this content to play it.';

  @override
  String get cast_need_wifi =>
      'Connect to the same Wi‑Fi network as the TV to send the file.';

  @override
  String get download_err_http => 'HTTP error';

  @override
  String get download_err_start_failed => 'Couldn\'t start the download';

  @override
  String get download_err_file_missing =>
      'The downloaded file is no longer available';

  @override
  String get download_err_canceled => 'Download canceled or not found';

  @override
  String get download_err_server_page =>
      'The server returned an error page (expired session or invalid id)';

  @override
  String get download_err_generic => 'The download failed';

  @override
  String get download_retry => 'Retry';

  @override
  String get tv_cast_replay_hint =>
      'Watched by casting from your phone. Send it again from your phone to play it here.';

  @override
  String tv_status_discoverable(String deviceName) {
    return 'Discoverable as $deviceName';
  }

  @override
  String get tv_status_error => 'Can\'t be found on this network';

  @override
  String get tv_empty_step_wifi => 'Same Wi-Fi as your TV';

  @override
  String get tv_empty_step_phone => 'Open Rensi on your phone';

  @override
  String get tv_empty_step_cast => 'Tap Cast and pick this TV';

  @override
  String get tv_history_hint => 'Resume where you left off';

  @override
  String get tv_preparing_series => 'Preparing…';

  @override
  String get developer => 'Developer';

  @override
  String get dev_account => 'Account';

  @override
  String get dev_server => 'Server';

  @override
  String get dev_application => 'Application';

  @override
  String get dev_catalogue => 'Catalogue';

  @override
  String get dev_playlist => 'Playlist';

  @override
  String get dev_expires => 'Expiration';

  @override
  String get dev_trial => 'Trial account';

  @override
  String get dev_active_connections => 'Active connections';

  @override
  String get dev_max_connections => 'Max connections';

  @override
  String get dev_created => 'Created';

  @override
  String get dev_output_formats => 'Allowed formats';

  @override
  String get dev_server_url => 'Server URL';

  @override
  String get dev_port => 'Port';

  @override
  String get dev_https_port => 'HTTPS port';

  @override
  String get dev_protocol => 'Protocol';

  @override
  String get dev_rtmp_port => 'RTMP port';

  @override
  String get dev_server_time => 'Server time';

  @override
  String get dev_build_number => 'Build number';

  @override
  String get dev_schema_version => 'Database schema';

  @override
  String get dev_last_sync => 'Last sync';

  @override
  String get dev_never => 'Never';

  @override
  String get dev_source_url => 'Source URL';

  @override
  String get dev_series => 'Series';

  @override
  String get dev_items => 'Items';

  @override
  String get dev_yes => 'Yes';

  @override
  String get dev_no => 'No';

  @override
  String get dev_no_data => 'No data available';

  @override
  String get dev_status => 'Status';
}
