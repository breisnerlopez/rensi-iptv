// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get slogan => 'Açık Kaynaklı IPTV Oynatıcı';

  @override
  String get search => 'Ara';

  @override
  String get search_live_stream => 'Canlı yayın ara';

  @override
  String get search_movie => 'Film ara';

  @override
  String get search_series => 'Dizi ara';

  @override
  String get not_found_in_category => 'Bu kategoride içerik bulunamadı';

  @override
  String get live_stream_not_found => 'Canlı yayın bulunamadı';

  @override
  String get movie_not_found => 'Film bulunamadı';

  @override
  String get see_all => 'Tümünü Görüntüle';

  @override
  String get preview => 'Önizleme';

  @override
  String get info => 'Bilgi';

  @override
  String get close => 'Kapat';

  @override
  String get reset => 'Sıfırla';

  @override
  String get delete => 'Sil';

  @override
  String get cancel => 'İptal';

  @override
  String get refresh => 'Yenile';

  @override
  String get back => 'Geri';

  @override
  String get clear => 'Temizle';

  @override
  String get clear_all => 'Tümünü Temizle';

  @override
  String get day => 'Gün';

  @override
  String get clear_all_confirmation_message =>
      'Tüm izleme geçmişini silmek istediğinize emin misiniz?';

  @override
  String get try_again => 'Tekrar Dene';

  @override
  String get history => 'Geçmiş';

  @override
  String get history_empty_message =>
      'Video izlemeye başladığınızda burada görünecek';

  @override
  String get live => 'Canlı';

  @override
  String get live_streams => 'Canlı Yayınlar';

  @override
  String get on_live => 'Canlı';

  @override
  String get other_channels => 'Diğer Kanallar';

  @override
  String get movies => 'Filmler';

  @override
  String get movie => 'Film';

  @override
  String get series_singular => 'Dizi';

  @override
  String get series_plural => 'Diziler';

  @override
  String get category_id => 'Kategori ID';

  @override
  String get channel_information => 'Kanal Bilgileri';

  @override
  String get channel_id => 'Kanal ID';

  @override
  String get series_id => 'Dizi ID';

  @override
  String get quality => 'Kalite';

  @override
  String get stream_type => 'Yayın Türü';

  @override
  String get format => 'Format';

  @override
  String get season => 'Sezonlar';

  @override
  String episode_count(Object count) {
    return '$count Bölüm';
  }

  @override
  String duration(Object duration) {
    return 'Süre: $duration';
  }

  @override
  String get episode_duration => 'Bölüm Süresi';

  @override
  String get creation_date => 'Eklenme Tarihi';

  @override
  String get release_date => 'Çıkış Tarihi';

  @override
  String get genre => 'Tür';

  @override
  String get cast => 'Oyuncular';

  @override
  String get director => 'Yönetmen';

  @override
  String get description => 'Açıklama';

  @override
  String get video_track => 'Video Parçası';

  @override
  String get audio_track => 'Ses Parçası';

  @override
  String get subtitle_track => 'Altyazı Parçası';

  @override
  String get settings => 'Ayarlar';

  @override
  String get general_settings => 'Genel Ayarlar';

  @override
  String get app_language => 'Uygulama Dili';

  @override
  String get continue_on_background => 'Arka Planda Çalmaya Devam Et';

  @override
  String get continue_on_background_description =>
      'Uygulama arka planda olsa da oynatmaya devam et';

  @override
  String get refresh_contents => 'İçerikleri Yenile';

  @override
  String get subtitle_settings => 'Altyazı Ayarları';

  @override
  String get subtitle_settings_description => 'Altyazı görünümünü özelleştirin';

  @override
  String get sample_text => 'Örnek altyazı metni\nBu şekilde görünecek';

  @override
  String get font_settings => 'Yazı Tipi Ayarları';

  @override
  String get font_size => 'Yazı Tipi Boyutu';

  @override
  String get font_height => 'Satır Yüksekliği';

  @override
  String get letter_spacing => 'Harf Aralığı';

  @override
  String get word_spacing => 'Kelime Aralığı';

  @override
  String get padding => 'İç Boşluk';

  @override
  String get color_settings => 'Renk Ayarları';

  @override
  String get text_color => 'Metin Rengi';

  @override
  String get background_color => 'Arka Plan Rengi';

  @override
  String get style_settings => 'Stil Ayarları';

  @override
  String get font_weight => 'Yazı Tipi Kalınlığı';

  @override
  String get thin => 'İnce';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Orta';

  @override
  String get bold => 'Kalın';

  @override
  String get extreme_bold => 'Çok Kalın';

  @override
  String get text_align => 'Metin Hizalama';

  @override
  String get left => 'Sol';

  @override
  String get center => 'Orta';

  @override
  String get right => 'Sağ';

  @override
  String get justify => 'Yasla';

  @override
  String get pick_color => 'Renk Seç';

  @override
  String get my_playlists => 'Playlistlerim';

  @override
  String get create_new_playlist => 'Yeni Playlist Oluştur';

  @override
  String get loading_playlists => 'Playlistler Yükleniyor...';

  @override
  String get playlist_list => 'Playlist Listesi';

  @override
  String get playlist_information => 'Playlist Bilgileri';

  @override
  String get playlist_name => 'Playlist Adı';

  @override
  String get playlist_name_placeholder => 'Playlist için bir isim girin';

  @override
  String get playlist_name_required => 'Playlist adi gerekli';

  @override
  String get playlist_name_min_2 => 'Playlist adı en az 2 karakter olmalı';

  @override
  String playlist_deleted(Object name) {
    return '$name silindi';
  }

  @override
  String get playlist_delete_confirmation_title => 'Playlist\'i Sil';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return '\'$name\' playlist\'ini silmek istediğinizden emin misiniz?\nBu işlem geri alınamaz.';
  }

  @override
  String get empty_playlist_title => 'Henüz Playlist Yok';

  @override
  String get empty_playlist_message =>
      'İlk playlist\'inizi oluşturarak başlayın.\nXtream Code veya M3U formatında\nplaylist ekleyebilirsiniz.';

  @override
  String get empty_playlist_button => 'İlk Playlist\'imi Oluştur';

  @override
  String get favorites => 'Favoriler';

  @override
  String get see_all_favorites => 'Tümünü Gör';

  @override
  String get added_to_favorites => 'Favorilere eklendi';

  @override
  String get removed_from_favorites => 'Favorilerden kaldırıldı';

  @override
  String get remove_from_favorites => 'Favorilerden Kaldır';

  @override
  String get select_playlist_type => 'Playlist Türü Seçin';

  @override
  String get select_playlist_message =>
      'Oluşturmak istediğiniz playlist türünü seçin';

  @override
  String get xtream_code_title =>
      'API URL, Kullanıcı Adı ve Şifre ile bağlanın';

  @override
  String get xtream_code_description =>
      'IPTV sağlayıcınızdan aldığınız bilgilerle kolayca bağlanın';

  @override
  String get select_playlist_type_footer =>
      'Playlist bilgileriniz güvenli bir şekilde cihazınızda saklanır.';

  @override
  String get api_url => 'API URL';

  @override
  String get api_url_required => 'API URL gerekli';

  @override
  String get username => 'Kullanıcı Adı';

  @override
  String get username_placeholder => 'Kullanıcı adınızı girin';

  @override
  String get username_required => 'Kullanıcı Adı gerekli';

  @override
  String get username_min_3 => 'Kullanıcı adı en az 3 karakter olmalı';

  @override
  String get password => 'Parola';

  @override
  String get password_placeholder => 'Parolanızı girin';

  @override
  String get password_required => 'Parola gerekli';

  @override
  String get password_min_3 => 'Parola en az 3 karakter olmalı';

  @override
  String get server_url => 'Sunucu URL';

  @override
  String get submitting => 'Kaydediliyor...';

  @override
  String get submit_create_playlist => 'Playlist\'i Kaydet';

  @override
  String get subscription_details => 'Abonelik Detayları';

  @override
  String subscription_remaining_day(Object days) {
    return 'Abonelik: $days';
  }

  @override
  String get remaining_day_title => 'Kalan Süre';

  @override
  String remaining_day(Object days) {
    return '$days Gün';
  }

  @override
  String get connected => 'Bağlı';

  @override
  String get no_connection => 'Bağlantı yok';

  @override
  String get expired => 'Süresi dolmuş';

  @override
  String get active_connection => 'Aktif Bağlantı';

  @override
  String get maximum_connection => 'Maksimum Bağlantı';

  @override
  String get server_information => 'Sunucu Bilgileri';

  @override
  String get timezone => 'Saat Dilimi';

  @override
  String get server_message => 'Sunucu Mesajı';

  @override
  String get all_datas_are_stored_in_device =>
      'Tüm bilgiler güvenli bir şekilde cihazınızda saklanır';

  @override
  String get url_format_validate_message =>
      'URL formatı http://sunucu:port şeklinde olmalıdır';

  @override
  String get url_format_validate_error =>
      'Geçerli bir URL giriniz (http:// veya https:// ile başlamalı)';

  @override
  String get playlist_name_already_exists =>
      'Bu isimde bir playlist zaten mevcut';

  @override
  String get invalid_credentials =>
      'IPTV sağlayıcınızdan cevap alınamadı, bilgilerinizi kontrol edin';

  @override
  String get error_occurred => 'Hata oluştu';

  @override
  String get connecting => 'Bağlantı kuruluyor';

  @override
  String get preparing_categories => 'Kategoriler hazırlanıyor';

  @override
  String preparing_categories_exception(Object error) {
    return 'Kategoriler yüklenemedi: $error';
  }

  @override
  String get preparing_live_streams => 'Canlı kanallar yükleniyor';

  @override
  String get preparing_live_streams_exception_1 => 'Canlı kanallar alınamadı';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Canlı kanallar yüklenirken hata: $error';
  }

  @override
  String get preparing_movies => 'Film kütüphanesi açılıyor';

  @override
  String get preparing_movies_exception_1 => 'Filmler alınamadı';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Filmler yüklenirken hata: $error';
  }

  @override
  String get preparing_series => 'Dizi arşivi hazırlanıyor';

  @override
  String get preparing_series_exception_1 => 'Diziler alınamadı';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Diziler yüklenirken hata: $error';
  }

  @override
  String get preparing_user_info_exception_1 => 'Kullanıcı bilgileri alınamadı';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Kullanıcı bilgileri yüklenirken hata: $error';
  }

  @override
  String get m3u_playlist_title => 'M3U dosyası veya URL ile playlist ekle';

  @override
  String get m3u_playlist_description =>
      'Geleneksel M3U format dosyalarını destekler';

  @override
  String get m3u_playlist => 'M3U Playlist';

  @override
  String get m3u_playlist_load_description =>
      'M3U playlist dosyası veya URL\'si ile IPTV kanallarını yükleyin';

  @override
  String get playlist_name_hint => 'Playlist adını girin';

  @override
  String get playlist_name_min_length =>
      'Playlist adı en az 2 karakter olmalıdır';

  @override
  String get source_type => 'Kaynak Türü';

  @override
  String get url => 'URL';

  @override
  String get file => 'Dosya';

  @override
  String get m3u_url => 'M3U URL';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'M3U URL gereklidir';

  @override
  String get url_format_error => 'Geçerli bir URL formatı girin';

  @override
  String get url_scheme_error => 'URL http:// veya https:// ile başlamalıdır';

  @override
  String get m3u_file => 'M3U Dosyası';

  @override
  String get file_selected => 'Dosya seçildi';

  @override
  String get select_m3u_file => 'M3U dosyası seçin (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Lütfen bir M3U dosyası seçin';

  @override
  String get file_selection_error => 'Dosya seçilirken hata oluştu';

  @override
  String get processing => 'İşlem yapılıyor...';

  @override
  String get create_playlist => 'Playlist Oluştur';

  @override
  String get error_occurred_title => 'Hata Oluştu';

  @override
  String get m3u_info_message =>
      'Tüm veriler cihazınızda güvenli şekilde saklanır.\nDesteklenen formatlar: .m3u, .m3u8\nURL formatı: http:// veya https:// ile başlamalıdır';

  @override
  String get m3u_parse_error => 'M3U ayrıştırma hatası';

  @override
  String get loading_m3u => 'M3U Yükleniyor';

  @override
  String get preparing_m3u_exception_no_source => 'M3U kaynağı bulunamadı';

  @override
  String get preparing_m3u_exception_empty => 'M3U dosyası boş';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'M3U ayrıştırma hatası: $error';
  }

  @override
  String get not_categorized => 'Kategorilendirilmemiş';

  @override
  String get loading_lists => 'Listeler Yükleniyor...';

  @override
  String get all => 'Tümü';

  @override
  String iptv_channels_count(Object count) {
    return 'IPTV Kanalları ($count)';
  }

  @override
  String get unknown_channel => 'Bilinmeyen Kanal';

  @override
  String get live_content => 'CANLI';

  @override
  String get movie_content => 'FİLM';

  @override
  String get series_content => 'DİZİ';

  @override
  String get media_content => 'MEDYA';

  @override
  String get m3u_error => 'M3U Hatası';

  @override
  String get episode_short => 'Bölüm';

  @override
  String season_number(Object number) {
    return '$number. Sezon';
  }

  @override
  String get image_loading => 'Görsel yükleniyor...';

  @override
  String get image_not_found => 'Görsel Bulunamadı';

  @override
  String get select_all => 'Tümünü Seç';

  @override
  String get deselect_all => 'Tümünün Seçimini Kaldır';

  @override
  String get hide_category => 'Kategorileri Gizle';

  @override
  String get rating => 'Puan';

  @override
  String get remove_from_history => 'Geçmişten Kaldır';

  @override
  String get remove_from_history_confirmation =>
      'Bu öğeyi izleme geçmişinden kaldırmak istediğinizden emin misiniz?';

  @override
  String get remove => 'Kaldır';

  @override
  String get clear_old_records => 'Eski Kayıtları Temizle';

  @override
  String get clear_old_records_confirmation =>
      '30 günden eski izleme kayıtlarını silmek istediğinizden emin misiniz?';

  @override
  String get clear_old => 'Temizle';

  @override
  String get clear_all_history => 'Tümünü Temizle';

  @override
  String get clear_all_history_confirmation =>
      'Tüm izleme geçmişini silmek istediğinizden emin misiniz?';

  @override
  String get appearance => 'Görünüm';

  @override
  String get theme => 'Tema';

  @override
  String get standard => 'Varsayılan';

  @override
  String get light => 'Açık';

  @override
  String get dark => 'Koyu';

  @override
  String get trailer => 'Fragman';

  @override
  String get new_ep => 'Yeni';

  @override
  String get continue_watching => 'Devam Et';

  @override
  String get start_watching => 'İzlemeye Başla';

  @override
  String continue_watching_label(String season, String episode) {
    return 'Devam Et: $season. Sezon $episode. Bölüm';
  }

  @override
  String get player_settings => 'Oynatıcı Ayarları';

  @override
  String get brightness_gesture => 'Parlaklık Hareketi';

  @override
  String get brightness_gesture_description =>
      'Sol tarafta dikey kaydırarak parlaklığı kontrol et';

  @override
  String get volume_gesture => 'Ses Hareketi';

  @override
  String get volume_gesture_description =>
      'Sağ tarafta dikey kaydırarak sesi kontrol et';

  @override
  String get seek_gesture => 'İleri/Sar Hareketi';

  @override
  String get seek_gesture_description => 'Yatay kaydırarak ileri/sar';

  @override
  String get speed_up_on_long_press => 'Uzun Basışta Hızlandır';

  @override
  String get speed_up_on_long_press_description =>
      'Uzun basıldığında oynatmayı hızlandır';

  @override
  String get seek_on_double_tap => 'Çift Dokunuşta İleri/Sar';

  @override
  String get seek_on_double_tap_description => 'Çift dokunarak ileri/geri sar';

  @override
  String get copied_to_clipboard => 'Panoya kopyalandı';

  @override
  String get about => 'Hakkında';

  @override
  String get app_version => 'Uygulama Sürümü';

  @override
  String get support_on_github => 'GitHub\'da Destekle';

  @override
  String get support_on_github_description =>
      'Projeye GitHub üzerinden katkıda bulunun';

  @override
  String get select_channel => 'Kanal Seç';

  @override
  String get episodes => 'Bölümler';

  @override
  String get categories => 'Kategoriler';

  @override
  String get seasons => 'Sezonlar';

  @override
  String season_number_format(int number) {
    return 'Sezon $number';
  }

  @override
  String episode_count_format(int count) {
    return '$count bölüm';
  }

  @override
  String channel_count_format(int count) {
    return '$count kanal';
  }

  @override
  String get video_info => 'Video Bilgileri';

  @override
  String get video_info_not_found => 'Video bilgisi bulunamadı';

  @override
  String get name => 'İsim';

  @override
  String get content_type => 'İçerik Tipi';

  @override
  String get plot => 'Konu';

  @override
  String get duration_unknown => 'Bilinmiyor';

  @override
  String get url_copied_to_clipboard => 'URL panoya kopyalandı';

  @override
  String get stream_id => 'Stream ID';

  @override
  String get epg_channel_id => 'EPG Kanal ID';

  @override
  String get category => 'Kategori';

  @override
  String get add_to_favorites => 'Favorilere Ekle';

  @override
  String get no_tracks_available => 'Parça bulunamadı';

  @override
  String get live_stream_content_type => 'Canlı Yayın';

  @override
  String get movie_content_type => 'Film';

  @override
  String get series_content_type => 'Dizi';

  @override
  String get last_update => 'Son Güncelleme';

  @override
  String get minutes => 'dk';

  @override
  String get duration_label => 'Süre';

  @override
  String get tmdb_global_search => 'TMDb Genel Arama';

  @override
  String get tmdb_credential_configured =>
      'TMDb kimlik bilgileri güvenli şekilde saklandı';

  @override
  String get tmdb_credential_missing =>
      'Genel aramayı etkinleştirmek için TMDb API anahtarınızı veya okuma erişim tokenınızı ekleyin';

  @override
  String get tmdb_credential_label => 'TMDb API tokenı';

  @override
  String get tmdb_credential_field_label =>
      'API anahtarı veya okuma erişim tokenı';

  @override
  String get tmdb_credential_save => 'Kimlik bilgisini kaydet';

  @override
  String get tmdb_credential_saved => 'TMDb kimlik bilgisi kaydedildi';

  @override
  String get tmdb_search_hint => 'TMDb\'de film ve dizi ara';

  @override
  String get tmdb_search_button => 'Ara';

  @override
  String get tmdb_search_description =>
      'En az 3 karakter yazıp Ara\'ya basın. Sonuçlar API kullanımını azaltmak için 24 saat önbelleğe alınır.';

  @override
  String get tmdb_exact_match => 'Tam eşleşme';

  @override
  String get tmdb_not_found_in_playlists => 'Oynatma listelerinizde bulunamadı';

  @override
  String tmdb_available_in(Object count) {
    return '$count oynatma listesi öğesinde mevcut';
  }

  @override
  String get tmdb_wishlist => 'İstek listesi';

  @override
  String get save => 'Kaydet';

  @override
  String get export_playlists_and_settings =>
      'Oynatma listelerini ve ayarları dışa aktar';

  @override
  String get export_subtitle =>
      'Tüm oynatma listelerini, kimlik bilgilerini ve uygulama ayarlarını kaydet';

  @override
  String get import_playlists_and_settings =>
      'Oynatma listelerini ve ayarları içe aktar';

  @override
  String get import_subtitle =>
      'Oynatma listelerini geri yükle ve eşleşen ayarların üzerine yaz';

  @override
  String get backup_section => 'Yedekleme';

  @override
  String get tmdb_credential_section => 'TMDb API tokenı';

  @override
  String get export_success => 'Yedek başarıyla dışa aktarıldı';

  @override
  String get export_cancelled => 'Yedek dışa aktarımı iptal edildi';

  @override
  String get export_failed => 'Yedek dışa aktarımı başarısız oldu';

  @override
  String import_success(Object count) {
    return 'Yedek içe aktarıldı: $count oynatma listesi geri yüklendi';
  }

  @override
  String get import_cancelled => 'Yedek içe aktarımı iptal edildi';

  @override
  String get import_failed => 'Yedek içe aktarımı başarısız oldu';

  @override
  String import_summary(int created, int updated, int skipped) {
    return 'İçe aktarıldı: $created yeni, $updated güncellendi, $skipped atlandı';
  }

  @override
  String get backup_passphrase_title => 'Bu yedeği koru';

  @override
  String get backup_passphrase_subtitle =>
      'Yedeği şifrelemek için bir parola seçin. Şifrelenmemiş bir JSON dışa aktarımı için boş bırakın (kimlik bilgileri okunabilir olacaktır).';

  @override
  String get backup_passphrase_field => 'Parola';

  @override
  String get backup_passphrase_confirm => 'Parolayı onayla';

  @override
  String get backup_passphrase_mismatch => 'Parolalar eşleşmiyor';

  @override
  String get backup_passphrase_required =>
      'Bu yedek şifrelenmiş. Oluştururken kullanılan parolayı girin.';

  @override
  String get backup_passphrase_invalid => 'Yanlış parola veya bozuk yedek';

  @override
  String get backup_invalid_format => 'Geçersiz yedek dosyası';

  @override
  String backup_schema_unsupported(String version) {
    return 'Desteklenmeyen yedek sürümü: $version';
  }

  @override
  String get backup_plain_warning =>
      'Şifrelenmemiş bir dışa aktarım URL\'leri, kullanıcı adlarını ve şifreleri dosyada okunabilir bırakır.';

  @override
  String get backup_strategy_title =>
      'İçe aktarma, aynı kimliğe sahip oynatma listelerini değiştirecek.';

  @override
  String get backup_strategy_overwrite => 'Mevcut olanların üzerine yaz';

  @override
  String get backup_strategy_keep_local => 'Yerel sürümleri koru';

  @override
  String get backup_encrypt => 'Şifrele';

  @override
  String get backup_skip_encryption => 'Şifrelemeyi atla';

  @override
  String get search_no_results => 'Sonuç bulunamadı';

  @override
  String get search_in_your_lists => 'Listelerinizde';

  @override
  String get search_from_your_iptv => 'IPTV\'nizden';

  @override
  String get search_tmdb_section => 'TMDb';

  @override
  String get search_watch_action => 'İzle';

  @override
  String playlist_load_failed(String error) {
    return 'Oynatma listeleri yüklenemedi: $error';
  }

  @override
  String playlist_save_failed(String error) {
    return 'Oynatma listesi kaydedilemedi: $error';
  }

  @override
  String playlist_update_failed(String error) {
    return 'Oynatma listesi güncellenemedi: $error';
  }

  @override
  String playlist_delete_failed(String error) {
    return 'Oynatma listesi silinemedi: $error';
  }

  @override
  String m3u_file_read_failed(String error) {
    return 'M3U dosyası okunamadı: $error';
  }

  @override
  String get m3u_url_invalid_scheme =>
      'URL http:// veya https:// ile başlamalıdır';

  @override
  String m3u_url_http_status(String status) {
    return 'M3U URL\'si HTTP $status döndürdü';
  }

  @override
  String get m3u_url_response_too_large =>
      'M3U oynatma listesi 50 MB\'tan büyük';

  @override
  String m3u_url_fetch_failed(String error) {
    return 'M3U URL\'si indirilemedi: $error';
  }

  @override
  String get search_filter_all => 'Tümü';

  @override
  String get search_filter_movies => 'Filmler';

  @override
  String get search_filter_tv => 'TV';

  @override
  String get search_filter_wishlist => 'İstek listesi';

  @override
  String get search_clear_history => 'Geçmişi temizle';

  @override
  String get search_clear_history_confirm => 'Tüm son aramalar kaldırılsın mı?';

  @override
  String get search_remove_from_wishlist => 'İstek listesinden kaldır';

  @override
  String get search_wishlist_empty =>
      'İstek listeniz boş. Buraya kaydetmek için herhangi bir TMDb sonucundaki yer iminize dokunun.';

  @override
  String get search_detail_overview => 'Özet';

  @override
  String get search_detail_genres => 'Türler';

  @override
  String search_detail_runtime(int minutes) {
    return '$minutes dk';
  }

  @override
  String search_detail_open_in_playlist(String playlist) {
    return '$playlist içinde aç';
  }

  @override
  String get search_detail_not_in_playlists => 'Hiçbir oynatma listenizde yok';
}
