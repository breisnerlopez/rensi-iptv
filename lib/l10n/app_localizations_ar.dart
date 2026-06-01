// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get slogan => 'مشغل IPTV مفتوح المصدر';

  @override
  String get search => 'بحث';

  @override
  String get search_live_stream => 'البحث في البث المباشر';

  @override
  String get search_movie => 'البحث في الأفلام';

  @override
  String get search_series => 'البحث في المسلسلات';

  @override
  String get not_found_in_category => 'لم يتم العثور على محتوى في هذه الفئة';

  @override
  String get live_stream_not_found => 'لم يتم العثور على بث مباشر';

  @override
  String get movie_not_found => 'لم يتم العثور على فيلم';

  @override
  String get see_all => 'عرض الكل';

  @override
  String get preview => 'معاينة';

  @override
  String get info => 'معلومات';

  @override
  String get close => 'إغلاق';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get delete => 'حذف';

  @override
  String get cancel => 'إلغاء';

  @override
  String get refresh => 'تحديث';

  @override
  String get back => 'رجوع';

  @override
  String get clear => 'مسح';

  @override
  String get clear_all => 'مسح الكل';

  @override
  String get day => 'يوم';

  @override
  String get clear_all_confirmation_message =>
      'هل أنت متأكد من رغبتك في حذف كل السجل؟';

  @override
  String get try_again => 'حاول مرة أخرى';

  @override
  String get history => 'السجل';

  @override
  String get history_empty_message => 'ستظهر مقاطع الفيديو التي شاهدتها هنا';

  @override
  String get live => 'مباشر';

  @override
  String get live_streams => 'البث المباشر';

  @override
  String get on_live => 'مباشر';

  @override
  String get other_channels => 'قنوات أخرى';

  @override
  String get movies => 'أفلام';

  @override
  String get movie => 'فيلم';

  @override
  String get series_singular => 'مسلسل';

  @override
  String get series_plural => 'مسلسلات';

  @override
  String get category_id => 'معرف الفئة';

  @override
  String get channel_information => 'معلومات القناة';

  @override
  String get channel_id => 'معرف القناة';

  @override
  String get series_id => 'معرف المسلسل';

  @override
  String get quality => 'الجودة';

  @override
  String get stream_type => 'نوع البث';

  @override
  String get format => 'التنسيق';

  @override
  String get season => 'المواسم';

  @override
  String episode_count(Object count) {
    return '$count حلقة';
  }

  @override
  String duration(Object duration) {
    return 'المدة: $duration';
  }

  @override
  String get episode_duration => 'مدة الحلقة';

  @override
  String get creation_date => 'تاريخ الإضافة';

  @override
  String get release_date => 'تاريخ الإصدار';

  @override
  String get genre => 'النوع';

  @override
  String get cast => 'فريق التمثيل';

  @override
  String get director => 'المخرج';

  @override
  String get description => 'الوصف';

  @override
  String get video_track => 'مسار الفيديو';

  @override
  String get audio_track => 'مسار الصوت';

  @override
  String get subtitle_track => 'مسار الترجمة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get general_settings => 'الإعدادات العامة';

  @override
  String get app_language => 'لغة التطبيق';

  @override
  String get continue_on_background => 'متابعة التشغيل في الخلفية';

  @override
  String get continue_on_background_description =>
      'متابعة التشغيل حتى عندما يكون التطبيق في الخلفية';

  @override
  String get auto_pip_on_home => 'نافذة عائمة عند الخروج';

  @override
  String get auto_pip_on_home_description =>
      'يقلص المشغل إلى نافذة عائمة عند مغادرة التطبيق';

  @override
  String get sleep_timer => 'مؤقت النوم';

  @override
  String get sleep_timer_off => 'متوقف';

  @override
  String get sleep_timer_minutes_suffix => 'د';

  @override
  String get sleep_timer_hours_suffix => 'س';

  @override
  String get refresh_contents => 'تحديث المحتوى';

  @override
  String get subtitle_settings => 'إعدادات الترجمة';

  @override
  String get subtitle_settings_description => 'تخصيص مظهر الترجمة';

  @override
  String get sample_text => 'نص ترجمة تجريبي\nسيبدو هكذا';

  @override
  String get font_settings => 'إعدادات الخط';

  @override
  String get font_size => 'حجم الخط';

  @override
  String get font_height => 'ارتفاع السطر';

  @override
  String get letter_spacing => 'تباعد الأحرف';

  @override
  String get word_spacing => 'تباعد الكلمات';

  @override
  String get padding => 'الحشو';

  @override
  String get color_settings => 'إعدادات الألوان';

  @override
  String get text_color => 'لون النص';

  @override
  String get background_color => 'لون الخلفية';

  @override
  String get style_settings => 'إعدادات النمط';

  @override
  String get font_weight => 'سُمك الخط';

  @override
  String get thin => 'رفيع';

  @override
  String get normal => 'عادي';

  @override
  String get medium => 'متوسط';

  @override
  String get bold => 'عريض';

  @override
  String get extreme_bold => 'عريض جداً';

  @override
  String get text_align => 'محاذاة النص';

  @override
  String get left => 'يسار';

  @override
  String get center => 'وسط';

  @override
  String get right => 'يمين';

  @override
  String get justify => 'ضبط';

  @override
  String get pick_color => 'اختر لوناً';

  @override
  String get my_playlists => 'قوائم التشغيل الخاصة بي';

  @override
  String get create_new_playlist => 'إنشاء قائمة تشغيل جديدة';

  @override
  String get loading_playlists => 'جارٍ تحميل قوائم التشغيل...';

  @override
  String get playlist_list => 'قائمة التشغيل';

  @override
  String get playlist_information => 'معلومات قائمة التشغيل';

  @override
  String get playlist_name => 'اسم قائمة التشغيل';

  @override
  String get playlist_name_placeholder => 'أدخل اسماً لقائمة التشغيل';

  @override
  String get playlist_name_required => 'اسم قائمة التشغيل مطلوب';

  @override
  String get playlist_name_min_2 => 'يجب أن يحتوي الاسم على حرفين على الأقل';

  @override
  String playlist_deleted(Object name) {
    return 'تم حذف $name';
  }

  @override
  String get playlist_delete_confirmation_title => 'حذف قائمة التشغيل';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'هل أنت متأكد من رغبتك في حذف قائمة التشغيل \'$name\'؟\nلا يمكن التراجع عن هذا الإجراء.';
  }

  @override
  String get empty_playlist_title => 'لا توجد قوائم تشغيل بعد';

  @override
  String get empty_playlist_message =>
      'ابدأ بإنشاء قائمة التشغيل الأولى.\nيمكنك إضافة قوائم تشغيل بتنسيق Xtream Code أو M3U.';

  @override
  String get empty_playlist_button => 'إنشاء قائمة التشغيل الأولى';

  @override
  String get favorites => 'المفضلة';

  @override
  String get see_all_favorites => 'عرض الكل';

  @override
  String get added_to_favorites => 'تمت الإضافة إلى المفضلة';

  @override
  String get removed_from_favorites => 'تمت الإزالة من المفضلة';

  @override
  String get remove_from_favorites => 'إزالة من المفضلة';

  @override
  String get select_playlist_type => 'اختر نوع قائمة التشغيل';

  @override
  String get select_playlist_message =>
      'اختر نوع قائمة التشغيل التي تريد إنشاءها';

  @override
  String get xtream_code_title =>
      'الاتصال باستخدام API URL واسم المستخدم وكلمة المرور';

  @override
  String get xtream_code_description =>
      'اتصل بسهولة باستخدام معلومات مزود IPTV الخاص بك';

  @override
  String get select_playlist_type_footer =>
      'يتم تخزين معلومات قائمة التشغيل بأمان على جهازك.';

  @override
  String get api_url => 'رابط API';

  @override
  String get api_url_required => 'رابط API مطلوب';

  @override
  String get username => 'اسم المستخدم';

  @override
  String get username_placeholder => 'أدخل اسم المستخدم';

  @override
  String get username_required => 'اسم المستخدم مطلوب';

  @override
  String get username_min_3 => 'يجب أن يحتوي اسم المستخدم على 3 أحرف على الأقل';

  @override
  String get password => 'كلمة المرور';

  @override
  String get password_placeholder => 'أدخل كلمة المرور';

  @override
  String get password_required => 'كلمة المرور مطلوبة';

  @override
  String get password_min_3 => 'يجب أن تحتوي كلمة المرور على 3 أحرف على الأقل';

  @override
  String get server_url => 'رابط الخادم';

  @override
  String get submitting => 'جارٍ الحفظ...';

  @override
  String get submit_create_playlist => 'حفظ قائمة التشغيل';

  @override
  String get subscription_details => 'تفاصيل الاشتراك';

  @override
  String subscription_remaining_day(Object days) {
    return 'الاشتراك: $days';
  }

  @override
  String get remaining_day_title => 'الوقت المتبقي';

  @override
  String remaining_day(Object days) {
    return '$days يوم';
  }

  @override
  String get connected => 'متصل';

  @override
  String get no_connection => 'لا يوجد اتصال';

  @override
  String get expired => 'منتهي الصلاحية';

  @override
  String get active_connection => 'اتصال نشط';

  @override
  String get maximum_connection => 'الحد الأقصى للاتصال';

  @override
  String get server_information => 'معلومات الخادم';

  @override
  String get timezone => 'المنطقة الزمنية';

  @override
  String get server_message => 'رسالة الخادم';

  @override
  String get all_datas_are_stored_in_device =>
      'يتم تخزين جميع البيانات بأمان على جهازك';

  @override
  String get url_format_validate_message =>
      'يجب أن يكون تنسيق الرابط مثل http://server:port';

  @override
  String get url_format_validate_error =>
      'يرجى إدخال رابط صحيح (يجب أن يبدأ بـ http:// أو https://)';

  @override
  String get playlist_name_already_exists =>
      'توجد قائمة تشغيل بهذا الاسم بالفعل';

  @override
  String get invalid_credentials =>
      'تعذر الحصول على استجابة من مزود IPTV، يرجى التحقق من معلوماتك';

  @override
  String get error_occurred => 'حدث خطأ';

  @override
  String get connecting => 'جارٍ الاتصال';

  @override
  String get preparing_categories => 'جارٍ تحضير الفئات';

  @override
  String preparing_categories_exception(Object error) {
    return 'تعذر تحميل الفئات: $error';
  }

  @override
  String get preparing_live_streams => 'جارٍ تحميل القنوات المباشرة';

  @override
  String get preparing_live_streams_exception_1 =>
      'تعذر الحصول على القنوات المباشرة';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'خطأ في تحميل القنوات المباشرة: $error';
  }

  @override
  String get preparing_movies => 'جارٍ فتح مكتبة الأفلام';

  @override
  String get preparing_movies_exception_1 => 'تعذر الحصول على الأفلام';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'خطأ في تحميل الأفلام: $error';
  }

  @override
  String get preparing_series => 'جارٍ تحضير مكتبة المسلسلات';

  @override
  String get preparing_series_exception_1 => 'تعذر الحصول على المسلسلات';

  @override
  String preparing_series_exception_2(Object error) {
    return 'خطأ في تحميل المسلسلات: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'تعذر الحصول على معلومات المستخدم';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'خطأ في تحميل معلومات المستخدم: $error';
  }

  @override
  String get m3u_playlist_title => 'إضافة قائمة تشغيل بملف M3U أو رابط';

  @override
  String get m3u_playlist_description => 'يدعم ملفات تنسيق M3U التقليدية';

  @override
  String get m3u_playlist => 'قائمة تشغيل M3U';

  @override
  String get m3u_playlist_load_description =>
      'تحميل قنوات IPTV بملف قائمة تشغيل M3U أو رابط';

  @override
  String get playlist_name_hint => 'أدخل اسم قائمة التشغيل';

  @override
  String get playlist_name_min_length =>
      'يجب أن يكون اسم قائمة التشغيل على الأقل حرفين';

  @override
  String get source_type => 'نوع المصدر';

  @override
  String get url => 'رابط';

  @override
  String get file => 'ملف';

  @override
  String get m3u_url => 'رابط M3U';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'رابط M3U مطلوب';

  @override
  String get url_format_error => 'أدخل تنسيق رابط صحيح';

  @override
  String get url_scheme_error => 'يجب أن يبدأ الرابط بـ http:// أو https://';

  @override
  String get m3u_file => 'ملف M3U';

  @override
  String get file_selected => 'تم اختيار الملف';

  @override
  String get select_m3u_file => 'اختر ملف M3U (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'يرجى اختيار ملف M3U';

  @override
  String get file_selection_error => 'حدث خطأ أثناء اختيار الملف';

  @override
  String get processing => 'جارٍ المعالجة...';

  @override
  String get create_playlist => 'إنشاء قائمة التشغيل';

  @override
  String get error_occurred_title => 'حدث خطأ';

  @override
  String get m3u_info_message =>
      'جميع البيانات محفوظة بأمان على جهازك.\nالتنسيقات المدعومة: .m3u, .m3u8\nتنسيق الرابط: يجب أن يبدأ بـ http:// أو https://';

  @override
  String get m3u_parse_error => 'خطأ في تحليل M3U';

  @override
  String get loading_m3u => 'تحميل M3U';

  @override
  String get preparing_m3u_exception_no_source => 'لم يتم العثور على مصدر M3U';

  @override
  String get preparing_m3u_exception_empty => 'ملف M3U فارغ';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'خطأ في تحليل M3U: $error';
  }

  @override
  String get not_categorized => 'غير مصنف';

  @override
  String get loading_lists => 'تحميل القوائم...';

  @override
  String get all => 'الكل';

  @override
  String iptv_channels_count(Object count) {
    return 'قنوات IPTV ($count)';
  }

  @override
  String get unknown_channel => 'قناة غير معروفة';

  @override
  String get live_content => 'مباشر';

  @override
  String get movie_content => 'فيلم';

  @override
  String get series_content => 'مسلسل';

  @override
  String get media_content => 'وسائط';

  @override
  String get m3u_error => 'خطأ M3U';

  @override
  String get episode_short => 'حلقة';

  @override
  String season_number(Object number) {
    return 'الموسم $number';
  }

  @override
  String get image_loading => 'تحميل الصورة...';

  @override
  String get image_not_found => 'الصورة غير موجودة';

  @override
  String get select_all => 'حدد الكل';

  @override
  String get deselect_all => 'إلغاء تحديد الكل';

  @override
  String get hide_category => 'إخفاء الفئة';

  @override
  String get rating => 'تصنيف';

  @override
  String get remove_from_history => 'إزالة من السجل';

  @override
  String get remove_from_history_confirmation =>
      'هل أنت متأكد من أنك تريد إزالة هذا العنصر من سجل المشاهدة؟';

  @override
  String get remove => 'إزالة';

  @override
  String get clear_old_records => 'مسح السجلات القديمة';

  @override
  String get clear_old_records_confirmation =>
      'هل أنت متأكد من أنك تريد حذف سجلات المشاهدة الأقدم من 30 يومًا؟';

  @override
  String get clear_old => 'مسح القديم';

  @override
  String get clear_all_history => 'مسح كل السجل';

  @override
  String get clear_all_history_confirmation =>
      'هل أنت متأكد من أنك تريد حذف كل سجل المشاهدة؟';

  @override
  String get appearance => 'المظهر';

  @override
  String get theme => 'سمة';

  @override
  String get standard => 'قياسي';

  @override
  String get light => 'فاتح';

  @override
  String get dark => 'داكن';

  @override
  String get trailer => 'الإعلان';

  @override
  String get new_ep => 'جديد';

  @override
  String get continue_watching => 'متابعة المشاهدة';

  @override
  String get start_watching => 'ابدأ المشاهدة';

  @override
  String continue_watching_label(String season, String episode) {
    return 'متابعة: الموسم $season الحلقة $episode';
  }

  @override
  String get player_settings => 'إعدادات المشغل';

  @override
  String get brightness_gesture => 'إيماءة السطوع';

  @override
  String get brightness_gesture_description =>
      'التحكم في السطوع عن طريق السحب عموديًا على الجانب الأيسر';

  @override
  String get volume_gesture => 'إيماءة الصوت';

  @override
  String get volume_gesture_description =>
      'التحكم في الصوت عن طريق السحب عموديًا على الجانب الأيمن';

  @override
  String get seek_gesture => 'إيماءة البحث';

  @override
  String get seek_gesture_description => 'البحث عن طريق السحب أفقيًا';

  @override
  String get speed_up_on_long_press => 'تسريع عند الضغط الطويل';

  @override
  String get speed_up_on_long_press_description =>
      'تسريع التشغيل عند الضغط الطويل';

  @override
  String get seek_on_double_tap => 'البحث عند النقر المزدوج';

  @override
  String get seek_on_double_tap_description =>
      'البحث للأمام/للخلف بالنقر المزدوج';

  @override
  String get copied_to_clipboard => 'تم النسخ إلى الحافظة';

  @override
  String get about => 'حول';

  @override
  String get app_version => 'إصدار التطبيق';

  @override
  String get support_on_github => 'دعم على GitHub';

  @override
  String get support_on_github_description => 'ساهم في المشروع على GitHub';

  @override
  String get select_channel => 'اختر القناة';

  @override
  String get episodes => 'حلقات';

  @override
  String get categories => 'الفئات';

  @override
  String get seasons => 'المواسم';

  @override
  String season_number_format(int number) {
    return 'الموسم $number';
  }

  @override
  String episode_count_format(int count) {
    return '$count حلقة';
  }

  @override
  String channel_count_format(int count) {
    return '$count قناة';
  }

  @override
  String get video_info => 'معلومات الفيديو';

  @override
  String get video_info_not_found => 'لم يتم العثور على معلومات الفيديو';

  @override
  String get name => 'الاسم';

  @override
  String get content_type => 'نوع المحتوى';

  @override
  String get plot => 'الحبكة';

  @override
  String get duration_unknown => 'غير معروف';

  @override
  String get url_copied_to_clipboard => 'تم نسخ الرابط إلى الحافظة';

  @override
  String get stream_id => 'معرف البث';

  @override
  String get epg_channel_id => 'معرف قناة EPG';

  @override
  String get category => 'الفئة';

  @override
  String get add_to_favorites => 'إضافة إلى المفضلة';

  @override
  String get no_tracks_available => 'لا توجد مسارات متاحة';

  @override
  String get live_stream_content_type => 'بث مباشر';

  @override
  String get movie_content_type => 'فيلم';

  @override
  String get series_content_type => 'مسلسل';

  @override
  String get last_update => 'آخر تحديث';

  @override
  String get minutes => 'دقيقة';

  @override
  String get duration_label => 'المدة';

  @override
  String get tmdb_global_search => 'البحث الشامل في TMDb';

  @override
  String get tmdb_credential_configured => 'تم تخزين بيانات اعتماد TMDb بأمان';

  @override
  String get tmdb_credential_missing =>
      'أضف مفتاح TMDb API أو رمز الوصول للقراءة لتفعيل البحث الشامل';

  @override
  String get tmdb_credential_label => 'رمز TMDb API';

  @override
  String get tmdb_credential_field_label => 'مفتاح API أو رمز الوصول للقراءة';

  @override
  String get tmdb_credential_save => 'حفظ بيانات الاعتماد';

  @override
  String get tmdb_credential_saved => 'تم حفظ بيانات اعتماد TMDb';

  @override
  String get tmdb_search_hint => 'ابحث عن الأفلام والمسلسلات على TMDb';

  @override
  String get tmdb_search_button => 'بحث';

  @override
  String get tmdb_search_description =>
      'اكتب 3 أحرف على الأقل واضغط على بحث. يتم تخزين النتائج مؤقتًا لمدة 24 ساعة لتقليل استخدام API.';

  @override
  String get tmdb_exact_match => 'تطابق تام';

  @override
  String get tmdb_not_found_in_playlists =>
      'غير موجود في قوائم التشغيل الخاصة بك';

  @override
  String tmdb_available_in(Object count) {
    return 'متاح في $count عنصر من قائمة التشغيل';
  }

  @override
  String get tmdb_wishlist => 'قائمة الرغبات';

  @override
  String get save => 'حفظ';

  @override
  String get export_playlists_and_settings => 'تصدير قوائم التشغيل والإعدادات';

  @override
  String get export_subtitle =>
      'حفظ جميع قوائم التشغيل وبيانات الاعتماد وإعدادات التطبيق';

  @override
  String get import_playlists_and_settings =>
      'استيراد قوائم التشغيل والإعدادات';

  @override
  String get import_subtitle =>
      'استعادة قوائم التشغيل واستبدال الإعدادات المتطابقة';

  @override
  String get backup_section => 'النسخ الاحتياطي';

  @override
  String get tmdb_credential_section => 'رمز TMDb API';

  @override
  String get export_success => 'تم تصدير النسخة الاحتياطية بنجاح';

  @override
  String get export_cancelled => 'تم إلغاء تصدير النسخة الاحتياطية';

  @override
  String get export_failed => 'فشل تصدير النسخة الاحتياطية';

  @override
  String import_success(Object count) {
    return 'تم استيراد النسخة الاحتياطية: تمت استعادة $count قائمة تشغيل';
  }

  @override
  String get import_cancelled => 'تم إلغاء استيراد النسخة الاحتياطية';

  @override
  String get import_failed => 'فشل استيراد النسخة الاحتياطية';

  @override
  String import_summary(int created, int updated, int skipped) {
    return 'تم الاستيراد: $created جديدة، $updated محدثة، $skipped متخطاة';
  }

  @override
  String get backup_passphrase_title => 'حماية هذه النسخة الاحتياطية';

  @override
  String get backup_passphrase_subtitle =>
      'اختر عبارة مرور لتشفير النسخة الاحتياطية. اتركها فارغة لتصدير JSON غير مشفر (ستكون بيانات الاعتماد قابلة للقراءة).';

  @override
  String get backup_passphrase_field => 'عبارة المرور';

  @override
  String get backup_passphrase_confirm => 'تأكيد عبارة المرور';

  @override
  String get backup_passphrase_mismatch => 'عبارات المرور غير متطابقة';

  @override
  String get backup_passphrase_required =>
      'هذه النسخة الاحتياطية مشفرة. أدخل عبارة المرور المستخدمة عند إنشائها.';

  @override
  String get backup_passphrase_invalid =>
      'عبارة مرور خاطئة أو نسخة احتياطية تالفة';

  @override
  String get backup_invalid_format => 'ملف النسخة الاحتياطية غير صالح';

  @override
  String backup_schema_unsupported(String version) {
    return 'إصدار النسخة الاحتياطية غير مدعوم: $version';
  }

  @override
  String get backup_plain_warning =>
      'التصدير بدون تشفير يترك عناوين URL وأسماء المستخدمين وكلمات المرور قابلة للقراءة في الملف.';

  @override
  String get backup_strategy_title =>
      'سيؤدي الاستيراد إلى استبدال قوائم التشغيل التي تحمل نفس المعرف.';

  @override
  String get backup_strategy_overwrite => 'استبدال الموجود';

  @override
  String get backup_strategy_keep_local => 'الاحتفاظ بالنسخ المحلية';

  @override
  String get backup_encrypt => 'تشفير';

  @override
  String get backup_skip_encryption => 'بدون تشفير';

  @override
  String get search_no_results => 'لم يتم العثور على نتائج';

  @override
  String get search_in_your_lists => 'في قوائمك';

  @override
  String get search_from_your_iptv => 'من IPTV الخاص بك';

  @override
  String get search_tmdb_section => 'TMDb';

  @override
  String get search_watch_action => 'مشاهدة';

  @override
  String playlist_load_failed(String error) {
    return 'فشل تحميل قوائم التشغيل: $error';
  }

  @override
  String playlist_save_failed(String error) {
    return 'فشل حفظ قائمة التشغيل: $error';
  }

  @override
  String playlist_update_failed(String error) {
    return 'فشل تحديث قائمة التشغيل: $error';
  }

  @override
  String playlist_delete_failed(String error) {
    return 'فشل حذف قائمة التشغيل: $error';
  }

  @override
  String m3u_file_read_failed(String error) {
    return 'تعذر قراءة ملف M3U: $error';
  }

  @override
  String get m3u_url_invalid_scheme =>
      'يجب أن يبدأ عنوان URL بـ http:// أو https://';

  @override
  String m3u_url_http_status(String status) {
    return 'أعاد عنوان M3U URL استجابة HTTP $status';
  }

  @override
  String get m3u_url_response_too_large => 'قائمة M3U أكبر من 50 ميغابايت';

  @override
  String m3u_url_fetch_failed(String error) {
    return 'تعذر تنزيل عنوان M3U URL: $error';
  }

  @override
  String get search_filter_all => 'الكل';

  @override
  String get search_filter_movies => 'الأفلام';

  @override
  String get search_filter_tv => 'TV';

  @override
  String get search_filter_wishlist => 'قائمة الرغبات';

  @override
  String get search_clear_history => 'مسح السجل';

  @override
  String get search_clear_history_confirm =>
      'هل تريد إزالة جميع عمليات البحث الأخيرة؟';

  @override
  String get search_remove_from_wishlist => 'إزالة من قائمة الرغبات';

  @override
  String get search_wishlist_empty =>
      'قائمة رغباتك فارغة. اضغط على إشارة الحفظ في أي نتيجة من TMDb لحفظها هنا.';

  @override
  String get search_detail_overview => 'نظرة عامة';

  @override
  String get search_detail_genres => 'الأنواع';

  @override
  String search_detail_runtime(int minutes) {
    return '$minutes دقيقة';
  }

  @override
  String search_detail_open_in_playlist(String playlist) {
    return 'فتح في $playlist';
  }

  @override
  String get search_detail_not_in_playlists => 'غير موجود في أي من قوائمك';
}
