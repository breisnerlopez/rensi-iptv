// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get prebuffer_preparing => 'तैयार हो रहा है…';

  @override
  String get prebuffer_ready => 'सुचारू प्लेबैक के लिए तैयार';

  @override
  String get prebuffer_slow => 'धीमा कनेक्शन';

  @override
  String get prebuffer_stalled => 'कोई डेटा नहीं — कनेक्शन जांचें';

  @override
  String get prebuffer_play_now => 'अभी चलाएं';

  @override
  String get cast_gate_prompt => 'इसे अपने टीवी पर भेजें?';

  @override
  String get cast_gate_play_now => 'यहीं चलाएं';

  @override
  String get cast_to_tv => 'टीवी पर कास्ट करें';

  @override
  String get cast_sent_to_tv => 'टीवी पर भेजा गया';

  @override
  String get cast_send_failed => 'टीवी पर नहीं भेजा जा सका';

  @override
  String get cast_searching => 'आपके नेटवर्क पर टीवी खोजे जा रहे हैं…';

  @override
  String get cast_no_devices =>
      'कोई टीवी नहीं मिला। पक्का करें कि आपके टीवी पर ऐप खुला है और दोनों एक ही Wi-Fi पर हैं।';

  @override
  String get cast_choose_device => 'एक टीवी चुनें';

  @override
  String get cast_connecting => 'कनेक्ट हो रहा है…';

  @override
  String get cast_enter_pin => 'अपने टीवी पर दिखाया गया कोड दर्ज करें';

  @override
  String get cast_pair => 'पेयर करें';

  @override
  String get cast_pairing => 'पेयर हो रहा है…';

  @override
  String get cast_wrong_pin => 'गलत कोड। फिर से कोशिश करें।';

  @override
  String get cast_playing_on => 'अभी चल रहा है:';

  @override
  String get cast_remote_hint => 'आपका फ़ोन ही रिमोट है';

  @override
  String get cast_stop => 'कास्ट करना बंद करें';

  @override
  String get cast_error => 'टीवी से कनेक्ट नहीं हो सका';

  @override
  String get cast_retry => 'फिर से कोशिश करें';

  @override
  String get slogan => 'आईपीटीवी प्लेयर';

  @override
  String get search => 'खोजें';

  @override
  String get search_live_stream => 'लाइव स्ट्रीम खोजें';

  @override
  String get search_movie => 'फिल्म खोजें';

  @override
  String get search_series => 'सीरियल खोजें';

  @override
  String get not_found_in_category => 'इस श्रेणी में कोई सामग्री नहीं मिली';

  @override
  String get live_stream_not_found => 'कोई लाइव स्ट्रीम नहीं मिली';

  @override
  String get movie_not_found => 'कोई फिल्म नहीं मिली';

  @override
  String get see_all => 'सभी देखें';

  @override
  String get popular_section_title => 'लोकप्रिय';

  @override
  String get popular_window_month => 'इस महीने';

  @override
  String get popular_window_year => 'इस साल';

  @override
  String get popular_window_all_time => 'सर्वकालिक';

  @override
  String get preview => 'पूर्वावलोकन';

  @override
  String get info => 'जानकारी';

  @override
  String get close => 'बंद करें';

  @override
  String get reset => 'रीसेट करें';

  @override
  String get delete => 'हटाएं';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get refresh => 'रीफ्रेश करें';

  @override
  String get back => 'वापस';

  @override
  String get clear => 'साफ़ करें';

  @override
  String get clear_all => 'सभी साफ़ करें';

  @override
  String get day => 'दिन';

  @override
  String get clear_all_confirmation_message =>
      'क्या आप वाकई सारा इतिहास हटाना चाहते हैं?';

  @override
  String get try_again => 'फिर से कोशिश करें';

  @override
  String get history => 'इतिहास';

  @override
  String get history_empty_message => 'आपके देखे गए वीडियो यहाँ दिखाई देंगे';

  @override
  String get live => 'लाइव';

  @override
  String get live_streams => 'लाइव स्ट्रीम';

  @override
  String get on_live => 'लाइव';

  @override
  String get other_channels => 'अन्य चैनल';

  @override
  String get movies => 'फिल्में';

  @override
  String get movie => 'फिल्म';

  @override
  String get series_singular => 'सीरियल';

  @override
  String get series_plural => 'सीरियल';

  @override
  String get category_id => 'श्रेणी ID';

  @override
  String get channel_information => 'चैनल की जानकारी';

  @override
  String get channel_id => 'चैनल ID';

  @override
  String get series_id => 'सीरियल ID';

  @override
  String get quality => 'गुणवत्ता';

  @override
  String get stream_type => 'स्ट्रीम प्रकार';

  @override
  String get format => 'फॉर्मेट';

  @override
  String get season => 'सीज़न';

  @override
  String episode_count(Object count) {
    return '$count एपिसोड';
  }

  @override
  String duration(Object duration) {
    return 'अवधि: $duration';
  }

  @override
  String get episode_duration => 'एपिसोड की अवधि';

  @override
  String get creation_date => 'जोड़ने की तारीख';

  @override
  String get release_date => 'रिलीज़ की तारीख';

  @override
  String get genre => 'शैली';

  @override
  String get cast => 'कलाकार';

  @override
  String get director => 'निर्देशक';

  @override
  String get description => 'विवरण';

  @override
  String get video_track => 'वीडियो ट्रैक';

  @override
  String get audio_track => 'ऑडियो ट्रैक';

  @override
  String get speed => 'Speed';

  @override
  String get load => 'Load';

  @override
  String get external_subtitle => 'External subtitle';

  @override
  String get external_subtitle_url => 'External subtitle (URL)';

  @override
  String get subtitle_track => 'सबटाइटल ट्रैक';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get hold_ok_for_options => 'Hold OK for audio & subtitles';

  @override
  String get general_settings => 'सामान्य सेटिंग्स';

  @override
  String get app_language => 'ऐप की भाषा';

  @override
  String get continue_on_background => 'बैकग्राउंड में चलाना जारी रखें';

  @override
  String get continue_on_background_description =>
      'ऐप बैकग्राउंड में होने पर भी प्लेबैक जारी रखें';

  @override
  String get auto_pip_on_home => 'होम पर पिक्चर-इन-पिक्चर';

  @override
  String get auto_pip_on_home_description =>
      'ऐप छोड़ने पर प्लेयर को फ्लोटिंग विंडो में बदलें';

  @override
  String get sleep_timer => 'स्लीप टाइमर';

  @override
  String get sleep_timer_off => 'बंद';

  @override
  String get sleep_timer_minutes_suffix => 'मिनट';

  @override
  String get sleep_timer_hours_suffix => 'घंटा';

  @override
  String get refresh_contents => 'सामग्री रीफ्रेश करें';

  @override
  String get subtitle_settings => 'सबटाइटल सेटिंग्स';

  @override
  String get subtitle_settings_description =>
      'सबटाइटल की दिखावट को कस्टमाइज़ करें';

  @override
  String get sample_text => 'नमूना सबटाइटल टेक्स्ट\nयह इस तरह दिखेगा';

  @override
  String get font_settings => 'फॉन्ट सेटिंग्स';

  @override
  String get font_size => 'फॉन्ट आकार';

  @override
  String get font_height => 'लाइन की ऊंचाई';

  @override
  String get letter_spacing => 'अक्षर अंतराल';

  @override
  String get word_spacing => 'शब्द अंतराल';

  @override
  String get padding => 'पैडिंग';

  @override
  String get color_settings => 'रंग सेटिंग्स';

  @override
  String get text_color => 'टेक्स्ट रंग';

  @override
  String get background_color => 'बैकग्राउंड रंग';

  @override
  String get style_settings => 'स्टाइल सेटिंग्स';

  @override
  String get font_weight => 'फॉन्ट मोटाई';

  @override
  String get thin => 'पतला';

  @override
  String get normal => 'सामान्य';

  @override
  String get medium => 'मध्यम';

  @override
  String get bold => 'बोल्ड';

  @override
  String get extreme_bold => 'अतिरिक्त बोल्ड';

  @override
  String get text_align => 'टेक्स्ट संरेखण';

  @override
  String get left => 'बाएं';

  @override
  String get center => 'केंद्र';

  @override
  String get right => 'दाएं';

  @override
  String get justify => 'जस्टिफाई';

  @override
  String get pick_color => 'रंग चुनें';

  @override
  String get my_playlists => 'मेरी प्लेलिस्ट';

  @override
  String get create_new_playlist => 'नई प्लेलिस्ट बनाएं';

  @override
  String get loading_playlists => 'प्लेलिस्ट लोड हो रही है...';

  @override
  String get playlist_list => 'प्लेलिस्ट सूची';

  @override
  String get playlist_information => 'प्लेलिस्ट की जानकारी';

  @override
  String get playlist_name => 'प्लेलिस्ट का नाम';

  @override
  String get playlist_name_placeholder => 'अपनी प्लेलिस्ट के लिए नाम दर्ज करें';

  @override
  String get playlist_name_required => 'प्लेलिस्ट का नाम आवश्यक है';

  @override
  String get playlist_name_min_2 => 'नाम में कम से कम 2 अक्षर होने चाहिए';

  @override
  String playlist_deleted(Object name) {
    return '$name हटा दी गई';
  }

  @override
  String get playlist_delete_confirmation_title => 'प्लेलिस्ट हटाएं';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'क्या आप वाकई प्लेलिस्ट \'$name\' को हटाना चाहते हैं?\nयह क्रिया पूर्ववत नहीं की जा सकती।';
  }

  @override
  String get empty_playlist_title => 'अभी तक कोई प्लेलिस्ट नहीं';

  @override
  String get empty_playlist_message =>
      'अपनी पहली प्लेलिस्ट बनाकर शुरुआत करें।\nआप Xtream Code या M3U फॉर्मेट में प्लेलिस्ट जोड़ सकते हैं।';

  @override
  String get empty_playlist_button => 'मेरी पहली प्लेलिस्ट बनाएं';

  @override
  String get favorites => 'पसंदीदा';

  @override
  String get see_all_favorites => 'सभी देखें';

  @override
  String get added_to_favorites => 'पसंदीदा में जोड़ा गया';

  @override
  String get removed_from_favorites => 'पसंदीदा से हटाया गया';

  @override
  String get remove_from_favorites => 'पसंदीदा से हटाएं';

  @override
  String get select_playlist_type => 'प्लेलिस्ट प्रकार चुनें';

  @override
  String get select_playlist_message =>
      'आप जो प्लेलिस्ट बनाना चाहते हैं उसका प्रकार चुनें';

  @override
  String get xtream_code_title =>
      'API URL, उपयोगकर्ता नाम और पासवर्ड के साथ कनेक्ट करें';

  @override
  String get xtream_code_description =>
      'अपने IPTV प्रदाता की जानकारी के साथ आसानी से कनेक्ट करें';

  @override
  String get select_playlist_type_footer =>
      'आपकी प्लेलिस्ट की जानकारी आपके डिवाइस पर सुरक्षित रूप से संग्रहीत है।';

  @override
  String get api_url => 'API URL';

  @override
  String get api_url_required => 'API URL आवश्यक है';

  @override
  String get username => 'उपयोगकर्ता नाम';

  @override
  String get username_placeholder => 'अपना उपयोगकर्ता नाम दर्ज करें';

  @override
  String get username_required => 'उपयोगकर्ता नाम आवश्यक है';

  @override
  String get username_min_3 => 'उपयोगकर्ता नाम में कम से कम 3 अक्षर होने चाहिए';

  @override
  String get password => 'पासवर्ड';

  @override
  String get password_placeholder => 'अपना पासवर्ड दर्ज करें';

  @override
  String get password_required => 'पासवर्ड आवश्यक है';

  @override
  String get password_min_3 => 'पासवर्ड में कम से कम 3 अक्षर होने चाहिए';

  @override
  String get server_url => 'सर्वर URL';

  @override
  String get submitting => 'सेव हो रहा है...';

  @override
  String get submit_create_playlist => 'प्लेलिस्ट सेव करें';

  @override
  String get subscription_details => 'सब्सक्रिप्शन विवरण';

  @override
  String subscription_remaining_day(Object days) {
    return 'सब्सक्रिप्शन: $days';
  }

  @override
  String get remaining_day_title => 'शेष समय';

  @override
  String remaining_day(Object days) {
    return '$days दिन';
  }

  @override
  String get connected => 'कनेक्टेड';

  @override
  String get no_connection => 'कोई कनेक्शन नहीं';

  @override
  String get expired => 'समाप्त';

  @override
  String get active_connection => 'सक्रिय कनेक्शन';

  @override
  String get maximum_connection => 'अधिकतम कनेक्शन';

  @override
  String get server_information => 'सर्वर की जानकारी';

  @override
  String get timezone => 'समय क्षेत्र';

  @override
  String get server_message => 'सर्वर संदेश';

  @override
  String get all_datas_are_stored_in_device =>
      'सभी डेटा आपके डिवाइस पर सुरक्षित रूप से संग्रहीत है';

  @override
  String get url_format_validate_message =>
      'URL फॉर्मेट http://server:port की तरह होना चाहिए';

  @override
  String get url_format_validate_error =>
      'कृपया एक वैध URL दर्ज करें (http:// या https:// से शुरू होना चाहिए)';

  @override
  String get playlist_name_already_exists =>
      'इस नाम की प्लेलिस्ट पहले से मौजूद है';

  @override
  String get invalid_credentials =>
      'आपके IPTV प्रदाता से प्रतिक्रिया नहीं मिल सकी, कृपया अपनी जानकारी जांचें';

  @override
  String get error_occurred => 'एक त्रुटि हुई';

  @override
  String get playback_failed => 'यह सामग्री चलाई नहीं जा सकी';

  @override
  String get connecting => 'कनेक्ट हो रहा है';

  @override
  String get preparing_categories => 'श्रेणियां तैयार की जा रही हैं';

  @override
  String preparing_categories_exception(Object error) {
    return 'श्रेणियां लोड नहीं हो सकीं: $error';
  }

  @override
  String get preparing_live_streams => 'लाइव चैनल लोड हो रहे हैं';

  @override
  String get preparing_live_streams_exception_1 => 'लाइव चैनल नहीं मिल सके';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'लाइव चैनल लोड करने में त्रुटि: $error';
  }

  @override
  String get preparing_movies => 'फिल्म लाइब्रेरी खुल रही है';

  @override
  String get preparing_movies_exception_1 => 'फिल्में नहीं मिल सकीं';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'फिल्में लोड करने में त्रुटि: $error';
  }

  @override
  String get preparing_series => 'सीरियल लाइब्रेरी तैयार की जा रही है';

  @override
  String get preparing_series_exception_1 => 'सीरियल नहीं मिल सके';

  @override
  String preparing_series_exception_2(Object error) {
    return 'सीरियल लोड करने में त्रुटि: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'उपयोगकर्ता की जानकारी नहीं मिल सकी';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'उपयोगकर्ता की जानकारी लोड करने में त्रुटि: $error';
  }

  @override
  String get m3u_playlist_title => 'M3U फ़ाइल या URL के साथ प्लेलिस्ट जोड़ें';

  @override
  String get m3u_playlist_description =>
      'पारंपरिक M3U प्रारूप फ़ाइलों का समर्थन करता है';

  @override
  String get m3u_playlist => 'M3U प्लेलिस्ट';

  @override
  String get m3u_playlist_load_description =>
      'M3U प्लेलिस्ट फ़ाइल या URL के साथ IPTV चैनल लोड करें';

  @override
  String get playlist_name_hint => 'प्लेलिस्ट का नाम दर्ज करें';

  @override
  String get playlist_name_min_length =>
      'प्लेलिस्ट का नाम कम से कम 2 अक्षर का होना चाहिए';

  @override
  String get source_type => 'स्रोत प्रकार';

  @override
  String get url => 'URL';

  @override
  String get file => 'फ़ाइल';

  @override
  String get m3u_url => 'M3U URL';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'M3U URL आवश्यक है';

  @override
  String get url_format_error => 'एक वैध URL प्रारूप दर्ज करें';

  @override
  String get url_scheme_error => 'URL http:// या https:// से शुरू होना चाहिए';

  @override
  String get m3u_file => 'M3U फ़ाइल';

  @override
  String get file_selected => 'फ़ाइल चुनी गई';

  @override
  String get select_m3u_file => 'M3U फ़ाइल चुनें (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'कृपया एक M3U फ़ाइल चुनें';

  @override
  String get file_selection_error => 'फ़ाइल चुनने में त्रुटि हुई';

  @override
  String get processing => 'प्रसंस्करण...';

  @override
  String get create_playlist => 'प्लेलिस्ट बनाएं';

  @override
  String get error_occurred_title => 'त्रुटि हुई';

  @override
  String get m3u_info_message =>
      'सभी डेटा आपके डिवाइस पर सुरक्षित रूप से संग्रहीत है।\nसमर्थित प्रारूप: .m3u, .m3u8\nURL प्रारूप: http:// या https:// से शुरू होना चाहिए';

  @override
  String get m3u_parse_error => 'M3U पार्सिंग त्रुटि';

  @override
  String get loading_m3u => 'M3U लोड हो रहा है';

  @override
  String get preparing_m3u_exception_no_source => 'कोई M3U स्रोत नहीं मिला';

  @override
  String get preparing_m3u_exception_empty => 'M3U फ़ाइल खाली है';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'M3U पार्सिंग त्रुटि: $error';
  }

  @override
  String get not_categorized => 'बिना श्रेणी';

  @override
  String get loading_lists => 'सूचियां लोड हो रही हैं...';

  @override
  String get all => 'सभी';

  @override
  String iptv_channels_count(Object count) {
    return 'IPTV चैनल ($count)';
  }

  @override
  String get unknown_channel => 'अज्ञात चैनल';

  @override
  String get live_content => 'लाइव';

  @override
  String get movie_content => 'फिल्म';

  @override
  String get series_content => 'सीरीज';

  @override
  String get media_content => 'मीडिया';

  @override
  String get m3u_error => 'M3U त्रुटि';

  @override
  String get episode_short => 'एप';

  @override
  String season_number(Object number) {
    return 'सीजन $number';
  }

  @override
  String get image_loading => 'चित्र लोड हो रहा है...';

  @override
  String get image_not_found => 'चित्र नहीं मिला';

  @override
  String get select_all => 'सभी चुनें';

  @override
  String get deselect_all => 'सभी का चयन रद्द करें';

  @override
  String get hide_category => 'श्रेणियाँ छिपाएँ';

  @override
  String get rating => 'रेटिंग';

  @override
  String get remove_from_history => 'इतिहास से हटाएं';

  @override
  String get remove_from_history_confirmation =>
      'क्या आप वाकई इस आइटम को देखने के इतिहास से हटाना चाहते हैं?';

  @override
  String get remove => 'हटाएं';

  @override
  String get clear_old_records => 'पुराने रिकॉर्ड साफ़ करें';

  @override
  String get clear_old_records_confirmation =>
      'क्या आप 30 दिन से पुराने देखने के रिकॉर्ड को हटाना चाहते हैं?';

  @override
  String get clear_old => 'पुराने साफ़ करें';

  @override
  String get clear_all_history => 'सभी इतिहास साफ़ करें';

  @override
  String get clear_all_history_confirmation =>
      'क्या आप सभी देखने का इतिहास हटाना चाहते हैं?';

  @override
  String get resume_failed => 'यह शीर्षक अब इस प्लेलिस्ट में उपलब्ध नहीं है';

  @override
  String get search_in_your_library => 'आपकी लाइब्रेरी में';

  @override
  String get search_discover_tmdb => 'TMDb पर खोजें';

  @override
  String get search_not_in_lists => 'आपकी सूचियों में नहीं';

  @override
  String get search_global_disabled =>
      'अपनी सूचियों से परे टाइटल खोजने के लिए अपनी TMDb कुंजी जोड़ें।';

  @override
  String get search_enable_global => 'ग्लोबल सर्च चालू करें';

  @override
  String get search_key_rejected =>
      'आपकी TMDb कुंजी अस्वीकृत हो गई। इसे सेटिंग्स में जाँचें।';

  @override
  String get search_tmdb_rate_limited =>
      'बहुत ज़्यादा खोजें। कुछ देर बाद फिर कोशिश करें।';

  @override
  String get search_tmdb_error => 'TMDb तक नहीं पहुँच सके।';

  @override
  String get search_add_to_wishlist => 'इच्छा-सूची में जोड़ें';

  @override
  String get search_play_from => 'यहाँ से चलाएँ';

  @override
  String get search_not_available_body =>
      'आपकी सूचियों में नहीं। इसे सहेजें, उपलब्ध होने पर हम जाँच लेंगे।';

  @override
  String get search_keep_typing_global => 'TMDb पर खोजने के लिए टाइप करते रहें';

  @override
  String get search_saved => 'सहेजा गया';

  @override
  String get search_saved_confirm => 'आपकी इच्छा-सूची में सहेजा गया';

  @override
  String get search_removed_confirm => 'आपकी इच्छा-सूची से हटाया गया';

  @override
  String get search_in_wishlist_body =>
      'आपकी इच्छा-सूची में। उपलब्ध होने पर हम आपको सूचित करेंगे।';

  @override
  String get key_space => 'स्पेस';

  @override
  String get key_backspace => 'बैकस्पेस';

  @override
  String get home_empty_title =>
      'इस प्लेलिस्ट में अभी कोई फ़िल्म या सीरीज़ नहीं है।';

  @override
  String get home_empty_hint =>
      'चैनल देखने के लिए मेन्यू में “लाइव” चुनें, या सामग्री खोजें।';

  @override
  String get loading => 'लोड हो रहा है...';

  @override
  String get greeting_morning => 'सुप्रभात';

  @override
  String get greeting_afternoon => 'नमस्कार';

  @override
  String get greeting_evening => 'शुभ संध्या';

  @override
  String get featured_today => 'आज का चयन';

  @override
  String get search_catalog_hint => 'अपने पूरे कैटलॉग में खोजें';

  @override
  String get search_placeholder => 'फ़िल्में, सीरीज़, चैनल खोजें…';

  @override
  String get search_recent => 'हाल की खोजें';

  @override
  String get search_recent_remove => 'हटाएं';

  @override
  String get no_channels => 'कोई चैनल नहीं';

  @override
  String get no_results_filter => 'इस फ़िल्टर के लिए कोई परिणाम नहीं';

  @override
  String get preferred_audio => 'पसंदीदा ऑडियो';

  @override
  String get preferred_subtitles => 'पसंदीदा उपशीर्षक';

  @override
  String get decoder_applies_next_video => 'अगली बार वीडियो खोलने पर लागू होगा';

  @override
  String no_results_for(String query) {
    return '\"$query\" के लिए कोई परिणाम नहीं';
  }

  @override
  String saved_titles_count(int count) {
    return '$count सहेजे गए शीर्षक';
  }

  @override
  String get history_cleared => 'देखने का इतिहास साफ़ कर दिया गया';

  @override
  String get history_clear_failed => 'देखने का इतिहास साफ़ नहीं किया जा सका';

  @override
  String get appearance => 'दिखावट';

  @override
  String get theme => 'थीम';

  @override
  String get standard => 'डिफ़ॉल्ट';

  @override
  String get light => 'हल्का';

  @override
  String get dark => 'गहरा';

  @override
  String get trailer => 'ट्रेलर';

  @override
  String get new_ep => 'नया';

  @override
  String get continue_watching => 'देखना जारी रखें';

  @override
  String get start_watching => 'देखना शुरू करें';

  @override
  String continue_watching_label(String season, String episode) {
    return 'जारी रखें: सीजन $season एपिसोड $episode';
  }

  @override
  String get player_settings => 'प्लेयर सेटिंग्स';

  @override
  String get brightness_gesture => 'चमक जेस्चर';

  @override
  String get brightness_gesture_description =>
      'बाईं ओर लंबवत स्वाइप करके चमक नियंत्रित करें';

  @override
  String get volume_gesture => 'वॉल्यूम जेस्चर';

  @override
  String get volume_gesture_description =>
      'दाईं ओर लंबवत स्वाइप करके वॉल्यूम नियंत्रित करें';

  @override
  String get seek_gesture => 'सीक जेस्चर';

  @override
  String get seek_gesture_description => 'क्षैतिज रूप से स्वाइप करके खोजें';

  @override
  String get speed_up_on_long_press => 'लंबे दबाव पर गति बढ़ाएं';

  @override
  String get speed_up_on_long_press_description =>
      'लंबे दबाव पर प्लेबैक गति बढ़ाएं';

  @override
  String get seek_on_double_tap => 'डबल टैप पर खोजें';

  @override
  String get seek_on_double_tap_description => 'डबल टैप करके आगे/पीछे खोजें';

  @override
  String get copied_to_clipboard => 'क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get about => 'के बारे में';

  @override
  String get app_version => 'ऐप संस्करण';

  @override
  String get support_on_github => 'GitHub पर समर्थन करें';

  @override
  String get support_on_github_description =>
      'GitHub पर प्रोजेक्ट में योगदान दें';

  @override
  String get last_channel => 'Last channel';

  @override
  String get select_channel => 'चैनल चुनें';

  @override
  String get episodes => 'एपिसोड';

  @override
  String get categories => 'श्रेणियां';

  @override
  String get seasons => 'सीज़न';

  @override
  String season_number_format(int number) {
    return 'सीज़न $number';
  }

  @override
  String episode_count_format(int count) {
    return '$count एपिसोड';
  }

  @override
  String channel_count_format(int count) {
    return '$count चैनल';
  }

  @override
  String get video_info => 'वीडियो जानकारी';

  @override
  String get video_info_not_found => 'वीडियो जानकारी नहीं मिली';

  @override
  String get name => 'नाम';

  @override
  String get content_type => 'सामग्री प्रकार';

  @override
  String get plot => 'कथानक';

  @override
  String get duration_unknown => 'अज्ञात';

  @override
  String get url_copied_to_clipboard => 'URL क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get stream_id => 'स्ट्रीम ID';

  @override
  String get epg_channel_id => 'EPG चैनल ID';

  @override
  String get category => 'श्रेणी';

  @override
  String get add_to_favorites => 'पसंदीदा में जोड़ें';

  @override
  String get no_tracks_available => 'कोई ट्रैक उपलब्ध नहीं';

  @override
  String get live_stream_content_type => 'लाइव स्ट्रीम';

  @override
  String get movie_content_type => 'फिल्म';

  @override
  String get series_content_type => 'सीरियल';

  @override
  String get last_update => 'अंतिम अपडेट';

  @override
  String get minutes => 'मिनट';

  @override
  String get duration_label => 'अवधि';

  @override
  String get tmdb_global_search => 'TMDb वैश्विक खोज';

  @override
  String get tmdb_credential_configured =>
      'TMDb क्रेडेंशियल सुरक्षित रूप से संग्रहीत';

  @override
  String get tmdb_credential_missing =>
      'वैश्विक खोज सक्षम करने के लिए अपनी TMDb API कुंजी या रीड एक्सेस टोकन जोड़ें';

  @override
  String get tmdb_credential_label => 'TMDb API टोकन';

  @override
  String get tmdb_credential_field_label => 'API कुंजी या रीड एक्सेस टोकन';

  @override
  String get tmdb_credential_save => 'क्रेडेंशियल सहेजें';

  @override
  String get tmdb_credential_saved => 'TMDb क्रेडेंशियल सहेजा गया';

  @override
  String get tmdb_search_hint => 'TMDb पर फ़िल्में और सीरीज़ खोजें';

  @override
  String get tmdb_search_button => 'खोजें';

  @override
  String get tmdb_search_description =>
      'कम से कम 3 अक्षर टाइप करें और खोजें दबाएं। API उपयोग कम करने के लिए परिणाम 24 घंटे तक कैश किए जाते हैं।';

  @override
  String get tmdb_exact_match => 'सटीक मिलान';

  @override
  String get tmdb_not_found_in_playlists => 'आपकी प्लेलिस्ट में नहीं मिला';

  @override
  String tmdb_available_in(Object count) {
    return '$count प्लेलिस्ट आइटम में उपलब्ध';
  }

  @override
  String get tmdb_wishlist => 'विशलिस्ट';

  @override
  String get save => 'सहेजें';

  @override
  String get export_playlists_and_settings =>
      'प्लेलिस्ट और सेटिंग्स निर्यात करें';

  @override
  String get export_subtitle =>
      'सभी प्लेलिस्ट, क्रेडेंशियल और ऐप सेटिंग्स सहेजें';

  @override
  String get import_playlists_and_settings => 'प्लेलिस्ट और सेटिंग्स आयात करें';

  @override
  String get import_subtitle =>
      'प्लेलिस्ट पुनर्स्थापित करें और मेल खाती सेटिंग्स को अधिलेखित करें';

  @override
  String get backup_section => 'बैकअप';

  @override
  String get tmdb_credential_section => 'TMDb API टोकन';

  @override
  String get export_success => 'बैकअप सफलतापूर्वक निर्यात किया गया';

  @override
  String get export_cancelled => 'बैकअप निर्यात रद्द किया गया';

  @override
  String get export_failed => 'बैकअप निर्यात विफल';

  @override
  String import_success(Object count) {
    return 'बैकअप आयात किया गया: $count प्लेलिस्ट पुनर्स्थापित';
  }

  @override
  String get import_cancelled => 'बैकअप आयात रद्द किया गया';

  @override
  String get import_failed => 'बैकअप आयात विफल';

  @override
  String import_summary(int created, int updated, int skipped) {
    return 'आयात किया गया: $created नए, $updated अपडेट किए गए, $skipped छोड़े गए';
  }

  @override
  String get backup_passphrase_title => 'इस बैकअप की सुरक्षा करें';

  @override
  String get backup_passphrase_subtitle =>
      'बैकअप को एन्क्रिप्ट करने के लिए एक पासफ़्रेज़ चुनें। प्लेन JSON निर्यात के लिए खाली छोड़ें (क्रेडेंशियल पढ़ने योग्य होंगे)।';

  @override
  String get backup_passphrase_field => 'पासफ़्रेज़';

  @override
  String get backup_passphrase_confirm => 'पासफ़्रेज़ की पुष्टि करें';

  @override
  String get backup_passphrase_mismatch => 'पासफ़्रेज़ मेल नहीं खाते';

  @override
  String get backup_passphrase_required =>
      'यह बैकअप एन्क्रिप्टेड है। इसे बनाते समय उपयोग किया गया पासफ़्रेज़ दर्ज करें।';

  @override
  String get backup_passphrase_invalid => 'गलत पासफ़्रेज़ या दूषित बैकअप';

  @override
  String get backup_invalid_format => 'अमान्य बैकअप फ़ाइल';

  @override
  String backup_schema_unsupported(String version) {
    return 'असमर्थित बैकअप संस्करण: $version';
  }

  @override
  String get backup_plain_warning =>
      'बिना एन्क्रिप्शन वाला निर्यात URL, उपयोगकर्ता नाम और पासवर्ड को फ़ाइल में पढ़ने योग्य रखता है।';

  @override
  String get backup_strategy_title =>
      'आयात समान आईडी वाली प्लेलिस्ट को बदल देगा।';

  @override
  String get backup_strategy_overwrite => 'मौजूदा को अधिलेखित करें';

  @override
  String get backup_strategy_keep_local => 'स्थानीय संस्करण रखें';

  @override
  String get backup_encrypt => 'एन्क्रिप्ट करें';

  @override
  String get backup_skip_encryption => 'एन्क्रिप्शन छोड़ें';

  @override
  String get search_no_results => 'कोई परिणाम नहीं मिला';

  @override
  String get search_in_your_lists => 'आपकी सूचियों में';

  @override
  String get search_from_your_iptv => 'आपके IPTV से';

  @override
  String get search_tmdb_section => 'TMDb';

  @override
  String get search_watch_action => 'देखें';

  @override
  String playlist_load_failed(String error) {
    return 'प्लेलिस्ट लोड करने में विफल: $error';
  }

  @override
  String playlist_save_failed(String error) {
    return 'प्लेलिस्ट सहेजने में विफल: $error';
  }

  @override
  String playlist_update_failed(String error) {
    return 'प्लेलिस्ट अपडेट करने में विफल: $error';
  }

  @override
  String playlist_delete_failed(String error) {
    return 'प्लेलिस्ट हटाने में विफल: $error';
  }

  @override
  String m3u_file_read_failed(String error) {
    return 'M3U फ़ाइल पढ़ी नहीं जा सकी: $error';
  }

  @override
  String get m3u_url_invalid_scheme =>
      'URL http:// या https:// से शुरू होना चाहिए';

  @override
  String m3u_url_http_status(String status) {
    return 'M3U URL ने HTTP $status लौटाया';
  }

  @override
  String get m3u_url_response_too_large => 'M3U प्लेलिस्ट 50 MB से बड़ी है';

  @override
  String m3u_url_fetch_failed(String error) {
    return 'M3U URL डाउनलोड नहीं किया जा सका: $error';
  }

  @override
  String get search_filter_all => 'सभी';

  @override
  String get search_filter_movies => 'फ़िल्में';

  @override
  String get search_filter_tv => 'TV';

  @override
  String get search_filter_wishlist => 'इच्छा सूची';

  @override
  String get search_filter_people => 'कलाकार';

  @override
  String get search_person_hint =>
      'किसी कलाकार की फ़िल्मोग्राफ़ी देखने के लिए खोजें';

  @override
  String get search_person_no_results => 'इस कलाकार के लिए कोई परिणाम नहीं';

  @override
  String get search_back_to_actors => 'कलाकारों पर वापस जाएँ';

  @override
  String get search_filter_studios => 'स्टूडियो';

  @override
  String get search_studio_hint => 'किसी स्टूडियो के शीर्षक देखने के लिए खोजें';

  @override
  String get search_studio_no_results => 'इस स्टूडियो के लिए कोई परिणाम नहीं';

  @override
  String get search_back_to_studios => 'स्टूडियो पर वापस जाएँ';

  @override
  String get search_filter_genre => 'शैलियाँ';

  @override
  String get search_genre_hint => 'अपने टाइटल देखने के लिए एक शैली चुनें';

  @override
  String get search_genre_no_results =>
      'इस शैली में आपके पास कोई टाइटल नहीं है';

  @override
  String get search_back_to_genres => 'शैलियों पर वापस जाएँ';

  @override
  String get search_voice => 'आवाज़ द्वारा खोज';

  @override
  String get search_clear_history => 'इतिहास साफ़ करें';

  @override
  String get search_clear_history_confirm => 'सभी हाल की खोजें हटाएँ?';

  @override
  String get search_remove_from_wishlist => 'इच्छा सूची से हटाएँ';

  @override
  String get search_wishlist_empty =>
      'आपकी इच्छा सूची खाली है. किसी भी TMDb परिणाम पर बुकमार्क दबाकर उसे यहाँ सहेजें.';

  @override
  String get search_detail_overview => 'सारांश';

  @override
  String get search_detail_genres => 'शैलियाँ';

  @override
  String search_detail_runtime(int minutes) {
    return '$minutes मिनट';
  }

  @override
  String search_detail_open_in_playlist(String playlist) {
    return '$playlist में खोलें';
  }

  @override
  String get search_detail_not_in_playlists =>
      'आपकी किसी भी प्लेलिस्ट में नहीं है';

  @override
  String get stream_info => 'स्ट्रीम जानकारी';

  @override
  String get resolution => 'रिज़ॉल्यूशन';

  @override
  String get frames_per_second => 'फ्रेम प्रति सेकंड';

  @override
  String get video_codec => 'वीडियो कोडेक';

  @override
  String get audio_codec => 'ऑडियो कोडेक';

  @override
  String get audio_channels => 'ऑडियो चैनल';

  @override
  String get bitrate => 'बिटरेट';

  @override
  String get sort_recently_added => 'हाल ही में जोड़ा गया';

  @override
  String get view_all_movies => 'सभी फ़िल्में';

  @override
  String get view_all_series => 'सभी सीरीज़';

  @override
  String get view_all_live => 'सभी चैनल';

  @override
  String get import_from_url => 'URL से आयात करें';

  @override
  String get import_url_subtitle =>
      'HTTP पर बैकअप फ़ाइल डाउनलोड करें — फ़ाइल पिकर के बिना टीवी बॉक्स के लिए उपयोगी';

  @override
  String get import_url_hint => 'https://example.com/backup.aipbak';

  @override
  String get import_url_invalid => 'अमान्य URL';

  @override
  String get import_url_failed => 'बैकअप डाउनलोड नहीं हो सका';

  @override
  String get import_from_device => 'डिवाइस ब्राउज़ करें';

  @override
  String get import_from_device_subtitle =>
      'इन-ऐप फ़ाइल ब्राउज़र — सिस्टम पिकर के बिना टीवी बॉक्स के लिए';

  @override
  String get file_browser_root_picker => 'प्रारंभिक फ़ोल्डर बदलें';

  @override
  String get file_browser_parent_directory => 'मूल फ़ोल्डर';

  @override
  String get file_browser_permission_denied =>
      'स्टोरेज अनुमति अस्वीकार। फ़ाइलें ब्राउज़ करने के लिए सिस्टम सेटिंग्स से अनुमति दें।';

  @override
  String get file_browser_unreadable => 'यह फ़ोल्डर पठनीय नहीं है।';

  @override
  String get file_browser_no_roots =>
      'इस डिवाइस पर कोई एक्सेस योग्य स्टोरेज नहीं मिला।';

  @override
  String get file_browser_empty =>
      'इस फ़ोल्डर में कोई मेल खाने वाली फ़ाइल नहीं।';

  @override
  String get exit_confirm_title => 'क्या आप ऐप से बाहर जाना चाहते हैं?';

  @override
  String get exit_confirm_message => 'आप Rensi IPTV से बाहर जाने वाले हैं।';

  @override
  String get exit_confirm_action => 'बाहर जाएँ';

  @override
  String get nav_home => 'होम';

  @override
  String get nav_browse => 'ब्राउज़';

  @override
  String get nav_live => 'लाइव';

  @override
  String get nav_my_list => 'मेरी सूची';

  @override
  String get onboarding_requirements_hint =>
      'आपको अपने IPTV प्रदाता का URL या लॉगिन विवरण चाहिए होगा';

  @override
  String get nav_settings => 'सेटिंग';

  @override
  String get empty_list_title => 'आपकी सूची खाली है';

  @override
  String get empty_list_body => 'सूची में शीर्षक जोड़ें और उन्हें यहाँ पाएँ।';

  @override
  String get action_browse_catalogue => 'कैटलॉग ब्राउज़ करें';

  @override
  String get video_decoding_label => 'वीडियो डिकोडिंग';

  @override
  String get video_decoding_description =>
      'स्वचालित लगभग सभी डिवाइस पर काम करता है। केवल तभी बदलें जब कोई चैनल न चले।';

  @override
  String get video_decoding_auto => 'स्वचालित';

  @override
  String get video_decoding_hw => 'प्रत्यक्ष हार्डवेयर';

  @override
  String get video_decoding_software => 'सॉफ़्टवेयर';

  @override
  String get downloads_title => 'डाउनलोड';

  @override
  String get downloads_empty => 'अभी तक कोई डाउनलोड नहीं';

  @override
  String get downloads_storage_used => 'उपयोग किया गया स्टोरेज';

  @override
  String get download_status_queued => 'कतार में';

  @override
  String get download_status_downloading => 'डाउनलोड हो रहा है';

  @override
  String get download_status_paused => 'रुका हुआ';

  @override
  String get download_status_complete => 'पूर्ण';

  @override
  String get download_status_failed => 'विफल';

  @override
  String get download_pause => 'रोकें';

  @override
  String get download_resume => 'फिर से शुरू करें';

  @override
  String get download_cancel => 'रद्द करें';

  @override
  String get download_delete => 'हटाएं';

  @override
  String get download_send_to_tv => 'TV पर भेजें';

  @override
  String get download_for_offline => 'ऑफ़लाइन देखने के लिए डाउनलोड करें';

  @override
  String get download_available_offline => 'ऑफ़लाइन उपलब्ध';

  @override
  String get download_failed_retry =>
      'डाउनलोड विफल — पुनः प्रयास के लिए टैप करें';

  @override
  String get tv_ready_subtitle =>
      'आपके फ़ोन से सामग्री प्राप्त करने के लिए तैयार';

  @override
  String get tv_playback_settings => 'प्लेबैक सेटिंग्स';

  @override
  String get tv_replay_failed =>
      'इस सामग्री को चलाने के लिए प्राप्त नहीं किया जा सका।';

  @override
  String get cast_need_wifi =>
      'फ़ाइल भेजने के लिए TV के समान Wi‑Fi नेटवर्क से कनेक्ट करें।';

  @override
  String get download_err_http => 'HTTP त्रुटि';

  @override
  String get download_err_start_failed => 'डाउनलोड शुरू नहीं हो सका';

  @override
  String get download_err_file_missing =>
      'डाउनलोड की गई फ़ाइल अब उपलब्ध नहीं है';

  @override
  String get download_err_canceled => 'डाउनलोड रद्द किया गया या नहीं मिला';

  @override
  String get download_err_server_page =>
      'सर्वर ने एक त्रुटि पृष्ठ लौटाया (सत्र समाप्त हो गया या अमान्य id)';

  @override
  String get download_err_generic => 'डाउनलोड विफल हो गया';

  @override
  String get download_retry => 'पुनः प्रयास करें';

  @override
  String get tv_cast_replay_hint =>
      'Watched by casting from your phone. Send it again from your phone to play it here.';
}
