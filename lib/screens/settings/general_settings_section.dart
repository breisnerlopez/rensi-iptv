import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/screens/settings/subtitle_settings_section.dart';
import 'package:rensi_iptv/services/backup_service.dart';
import 'package:rensi_iptv/services/pip_service.dart';
import 'package:rensi_iptv/services/recent_searches_service.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/utils/backup_import_flow.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:rensi_iptv/utils/picker_helper.dart';
import 'package:rensi_iptv/utils/show_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/services/parental_service.dart';
import 'package:rensi_iptv/services/epg_refresh_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/parental_pin_dialog.dart';
import 'package:rensi_iptv/controllers/watch_history_controller.dart';
import 'package:provider/provider.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/locale_provider.dart';
import '../../controllers/xtream_code_home_controller.dart';
import '../../controllers/theme_provider.dart';
import '../../l10n/supported_languages.dart';
import '../../models/m3u_item.dart';
import '../../repositories/user_preferences.dart';
import '../../services/app_state.dart';
import '../../services/cast/standalone_consent_store.dart';
import '../../services/m3u_parser.dart';
import '../../redesign/rensi_settings.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/section_title_widget.dart';
import '../developer_screen.dart';
import '../downloads_screen.dart';
import '../m3u/m3u_data_loader_screen.dart';
import '../playlist_screen.dart';
import '../xtream-codes/xtream_code_data_loader_screen.dart';
import 'category_settings_section.dart';
import 'package:rensi_iptv/widgets/tv/tv_field_traversal.dart';

final controller = XtreamCodeHomeController(true);

class GeneralSettingsWidget extends StatefulWidget {
  const GeneralSettingsWidget({super.key});

  @override
  State<GeneralSettingsWidget> createState() => _GeneralSettingsWidgetState();
}

class _GeneralSettingsWidgetState extends State<GeneralSettingsWidget> {
  final AppDatabase database = getIt<AppDatabase>();

  bool _backgroundPlayEnabled = false;
String _videoDecoder = 'auto';
  bool _isLoading = true;
  Uint8List? _selectedFileBytes;
  String _selectedTheme = 'system';
  bool _brightnessGesture = false;
  bool _volumeGesture = false;
  bool _seekGesture = false;
  bool _speedUpOnLongPress = true;
  bool _seekOnDoubleTap = true;
  bool _autoPipOnHome = true;
  bool _pipSupported = false;
  String _prefAudioLang = 'auto';
  String _prefSubLang = 'auto';
  double _playbackSpeed = 1.0;

  static const _audioLangOptions = ['auto', 'spa', 'eng', 'por', 'fra', 'ita', 'deu'];
  static const _subLangOptions = ['auto', 'off', 'spa', 'eng', 'por', 'fra', 'ita', 'deu'];
  static const _langLabels = {
    'auto': 'Automático',
    'off': 'Desactivados',
    'spa': 'Español',
    'eng': 'Inglés',
    'por': 'Portugués',
    'fra': 'Francés',
    'ita': 'Italiano',
    'deu': 'Alemán',
  };
  static const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  String _appVersion = '';
  String _tmdbToken = '';
  bool _hasTmdbCredential = false;
  bool _hasParentalPin = false;
  String _xmltvUrl = '';
  bool _refreshingEpg = false;
  final _xmltvController = TextEditingController();

  // Feature H — "TV / Casting": el permiso maestro (default OFF) para persistir
  // credenciales en la TV, y la lista de consentimientos por-(TV,proveedor)
  // vigentes con su nombre de playlist para el UI de "olvidar".
  bool _tvStandaloneAllowed = false;
  List<({String tvId, String providerId})> _standaloneGrants = const [];
  Map<String, String> _playlistNames = const {};

  // Pausar la TV al recibir una llamada mientras se castea (solo móvil; usa el
  // permiso READ_PHONE_STATE). Default true.
  bool _pauseCastOnCall = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _xmltvController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final backgroundPlay = await UserPreferences.getBackgroundPlay();
      final themeMode = await UserPreferences.getThemeMode();
      final brightnessGesture = await UserPreferences.getBrightnessGesture();
      final volumeGesture = await UserPreferences.getVolumeGesture();
      final seekGesture = await UserPreferences.getSeekGesture();
      final speedUpOnLongPress = await UserPreferences.getSpeedUpOnLongPress();
      final seekOnDoubleTap = await UserPreferences.getSeekOnDoubleTap();
      final autoPipOnHome = await UserPreferences.getAutoPipOnHome();
      // Hide the PiP toggle on Android TV / large screens — PiP isn't a
      // lean-back feature and arming it there can hang the device.
      final pipSupported = await PipService.instance.isAvailable() &&
          mounted &&
          !ResponsiveHelper.isDesktopOrTV(context);
      final prefAudio = await UserPreferences.getAudioTrack();
      final prefSub = await UserPreferences.getSubtitleTrack();
      final speed = await UserPreferences.getPlaybackSpeed();
      final decoder = await UserPreferences.getVideoDecoder();
      final packageInfo = await PackageInfo.fromPlatform();
      // hasStored (not getCredential): the display reflects whether the USER
      // saved their OWN key, not whether the shared embedded default is active.
      final hasOwnTmdb = await TmdbCredentialsService.hasStoredCredential();
      final hasParentalPin = await ParentalService.instance.hasPin();
      final xmltvUrl = await UserPreferences.getXmltvUrl();
      final tvStandaloneAllowed =
          await UserPreferences.getTvStandaloneAllowed();
      final pauseCastOnCall = await UserPreferences.getPauseCastOnCall();
      final standaloneGrants = await StandaloneConsentStore.listGranted();
      final playlistNames = await _loadPlaylistNames();
      setState(() {
        _prefAudioLang =
            _audioLangOptions.contains(prefAudio) ? prefAudio : 'auto';
        _prefSubLang = _subLangOptions.contains(prefSub) ? prefSub : 'auto';
        _playbackSpeed = _speedOptions.contains(speed) ? speed : 1.0;
        _backgroundPlayEnabled = backgroundPlay;
        _videoDecoder =
            const ['auto', 'hw_direct', 'software'].contains(decoder)
                ? decoder
                : 'auto';
        _selectedTheme = _themeModeToString(themeMode);
        _brightnessGesture = brightnessGesture;
        _volumeGesture = volumeGesture;
        _seekGesture = seekGesture;
        _speedUpOnLongPress = speedUpOnLongPress;
        _seekOnDoubleTap = seekOnDoubleTap;
        _autoPipOnHome = autoPipOnHome;
        _pipSupported = pipSupported;
        _appVersion = packageInfo.version;
        _hasTmdbCredential = hasOwnTmdb;
        _hasParentalPin = hasParentalPin;
        _xmltvUrl = xmltvUrl;
        _xmltvController.text = xmltvUrl;
        _tvStandaloneAllowed = tvStandaloneAllowed;
        _pauseCastOnCall = pauseCastOnCall;
        _standaloneGrants = standaloneGrants;
        _playlistNames = playlistNames;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  ThemeMode _stringToThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// providerId (id de playlist) → nombre legible, para el UI de "olvidar"
  /// credenciales. Best-effort: si la consulta falla, el UI cae al id crudo.
  Future<Map<String, String>> _loadPlaylistNames() async {
    try {
      final playlists = await database.getAllPlaylists();
      return {for (final p in playlists) p.id: p.name};
    } catch (_) {
      return const {};
    }
  }

  /// Feature H — permiso maestro de reproducción standalone en la TV. Optimista
  /// con reversión en caso de fallo, igual que las otras switches de esta
  /// pantalla. Apagarlo NO borra los consentimientos ya otorgados (para no
  /// perderlos si el usuario lo reactiva); solo deja de enviar el flag de
  /// persistencia (ver CastSenderController._resolveStandalonePid).
  Future<void> _saveTvStandaloneAllowed(bool value) async {
    setState(() => _tvStandaloneAllowed = value);
    try {
      await UserPreferences.setTvStandaloneAllowed(value);
    } catch (_) {
      if (mounted) setState(() => _tvStandaloneAllowed = !value);
    }
  }

  /// Pausar la TV al recibir una llamada mientras se castea. Optimista con
  /// reversión ante fallo, como las otras switches. El permiso READ_PHONE_STATE
  /// se pide de forma perezosa (la primera vez que se castea con el toggle ON),
  /// no aquí, para no molestar al usuario que solo abre Ajustes.
  Future<void> _savePauseCastOnCall(bool value) async {
    setState(() => _pauseCastOnCall = value);
    try {
      await UserPreferences.setPauseCastOnCall(value);
    } catch (_) {
      if (mounted) setState(() => _pauseCastOnCall = !value);
    }
  }

  /// Olvida el consentimiento standalone de un par (TV, proveedor): revoca el
  /// permiso del móvil Y encola un borrado REAL de las credenciales en la TV. El
  /// móvil no suele estar conectado a la TV en Ajustes, así que el wipe se envía
  /// (CmdType.wipeStandalone) la próxima vez que se conecta a ese tvId
  /// (ver CastSenderController._flushPendingStandaloneWipes); el auto-wipe al
  /// desemparejar es el respaldo último. Así la etiqueta "Olvidar credenciales en
  /// esta TV" se cumple de verdad, no solo del lado del móvil.
  Future<void> _forgetStandaloneGrant(String tvId, String providerId) async {
    await StandaloneConsentStore.revoke(tvId, providerId);
    await StandaloneConsentStore.markPendingWipe(tvId, providerId);
    final grants = await StandaloneConsentStore.listGranted();
    if (mounted) setState(() => _standaloneGrants = grants);
  }

  Future<void> _saveAutoPipSetting(bool value) async {
    try {
      await UserPreferences.setAutoPipOnHome(value);
      await PipService.instance.setAutoEnter(value);
      setState(() {
        _autoPipOnHome = value;
      });
    } catch (e) {
      setState(() {
        _autoPipOnHome = !value;
      });
    }
  }

  Future<void> _savePrefAudio(String? v) async {
    if (v == null) return;
    await UserPreferences.setAudioTrack(v);
    setState(() => _prefAudioLang = v);
  }

  Future<void> _savePrefSub(String? v) async {
    if (v == null) return;
    await UserPreferences.setSubtitleTrack(v);
    setState(() => _prefSubLang = v);
  }

  Future<void> _savePlaybackSpeed(double? v) async {
    if (v == null) return;
    await UserPreferences.setPlaybackSpeed(v);
    setState(() => _playbackSpeed = v);
  }

  Future<void> _saveBackgroundPlaySetting(bool value) async {
    try {
      await UserPreferences.setBackgroundPlay(value);
      setState(() {
        _backgroundPlayEnabled = value;
      });
    } catch (e) {
      setState(() {
        _backgroundPlayEnabled = !value;
      });
    }
  }

  Future<void> _saveVideoDecoder(String? value) async {
    if (value == null) return;
    await UserPreferences.setVideoDecoder(value);
    setState(() => _videoDecoder = value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc.decoder_applies_next_video),
        ),
      );
    }
  }

  Future<void> _saveTmdbCredential() async {
    if (_tmdbToken.trim().isEmpty) return;
    await TmdbCredentialsService.saveCredential(_tmdbToken);
    setState(() {
      _hasTmdbCredential = true;
      _tmdbToken = '';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.loc.tmdb_credential_saved)));
  }

  // ---- Parental control PIN ----
  Future<void> _setOrChangeParentalPin() async {
    final svc = ParentalService.instance;
    if (await svc.hasPin()) {
      if (!mounted) return;
      // Verify the current PIN before allowing a change.
      if (!await showParentalPinDialog(context)) return;
    }
    if (!mounted) return;
    final newPin = await _promptNewPin();
    if (newPin == null) return;
    await svc.setPin(newPin);
    if (!mounted) return;
    setState(() => _hasParentalPin = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.loc.parental_set_pin)));
  }

  Future<void> _saveAndRefreshEpg() async {
    if (_refreshingEpg) return;
    final url = _xmltvController.text.trim();
    await UserPreferences.setXmltvUrl(url);
    final messenger = ScaffoldMessenger.of(context);
    final loc = context.loc;
    final pid = AppState.currentPlaylist?.id;
    setState(() {
      _xmltvUrl = url;
      _refreshingEpg = true;
    });
    try {
      if (url.isEmpty || pid == null) throw EpgRefreshException('no_url');
      final n = await EpgRefreshService(database).refreshFromXmltv(url, pid);
      messenger.showSnackBar(SnackBar(content: Text(loc.epg_refreshed(n))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(loc.epg_refresh_failed)));
    } finally {
      if (mounted) setState(() => _refreshingEpg = false);
    }
  }

  Future<void> _removeParentalPin() async {
    if (!await showParentalPinDialog(context)) return; // verify first
    await ParentalService.instance.clearPin();
    if (!mounted) return;
    setState(() => _hasParentalPin = false);
  }

  /// Prompt a new PIN twice; returns it only if ≥4 digits and both match.
  Future<String?> _promptNewPin() {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(context.loc.parental_set_pin),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFieldTraversal(
                  child: TextField(
                    controller: c1,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: context.loc.parental_pin_hint,
                      prefixIcon: Icon(Icons.lock_outline,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
                TvFieldTraversal(
                  child: TextField(
                    controller: c2,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                        labelText: context.loc.parental_enter_pin,
                        prefixIcon: Icon(Icons.lock_outline,
                            color: Theme.of(context).colorScheme.primary),
                        errorText: err),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.loc.cancel)),
              FilledButton(
                onPressed: () {
                  final p1 = c1.text.trim();
                  if (p1.length < 4 || p1 != c2.text.trim()) {
                    setLocal(() => err = context.loc.parental_wrong_pin);
                    return;
                  }
                  Navigator.pop(ctx, p1);
                },
                child: Text(context.loc.confirm),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.loc.clear_all_history),
        content: Text(context.loc.clear_all_history_confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.loc.clear_all_history),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final controller = WatchHistoryController();
    // clearAllHistory rethrows on purpose. This is wired to onTap, which drops
    // the future, so an uncaught failure reached the error guard and told the
    // viewer nothing — on the one surface where silently not deleting is the
    // worst possible outcome. Report which of the two actually happened.
    var cleared = true;
    try {
      await controller.clearAllHistory();
      // Recent searches are private session data — wipe them here too so "Clear
      // All History" leaves nothing behind. Best-effort: a failure here must not
      // flip the (successful) history-clear result.
      await RecentSearchesService.clear();
    } catch (_) {
      cleared = false;
    } finally {
      controller.dispose();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared ? context.loc.history_cleared : context.loc.history_clear_failed,
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    final passphrase = await _askPassphrase(
      title: context.loc.backup_passphrase_title,
      subtitle: context.loc.backup_passphrase_subtitle,
      requireConfirm: true,
    );
    // Returns null when the user cancels the dialog. An empty string means
    // "export without encryption" and is still a valid choice.
    if (passphrase == null) return;

    try {
      final exported = await BackupService.exportToFile(
        passphrase: passphrase.isEmpty ? null : passphrase,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            exported
                ? context.loc.export_success
                : context.loc.export_cancelled,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.loc.export_failed)));
    }
  }

  Future<void> _importBackup() async {
    final result = await runBackupImportFlow(context);
    if (!mounted) return;
    if (result != null && result.total > 0) {
      await _loadSettings();
    }
  }

  Future<void> _importBackupFromUrl() async {
    final result = await runBackupImportFromUrlFlow(context);
    if (!mounted) return;
    if (result != null && result.total > 0) {
      await _loadSettings();
    }
  }

  Future<String?> _askPassphrase({
    required String title,
    required String subtitle,
    bool requireConfirm = false,
    bool forImport = false,
  }) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;
    try {
      return await showDialog<String?>(
        context: context,
        builder: (dialogContext) {
          final confirmNode = FocusNode();
          return StatefulBuilder(
            builder: (statefulContext, setLocal) {
              void confirmSubmit() {
                final value = controller.text;
                if (requireConfirm && value != confirmController.text) {
                  setLocal(() {
                    errorText = context.loc.backup_passphrase_mismatch;
                  });
                  return;
                }
                Navigator.pop(dialogContext, value);
              }

              return AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle),
                    const SizedBox(height: 12),
                    TvFieldTraversal(child: TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      textInputAction: requireConfirm
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: (_) {
                        if (requireConfirm) {
                          confirmNode.requestFocus();
                        } else {
                          confirmSubmit();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: context.loc.backup_passphrase_field,
                        prefixIcon: Icon(Icons.lock_outline,
                            color: Theme.of(context).colorScheme.primary),
                        errorText: errorText,
                      ),
                    )),
                    if (requireConfirm) ...[
                      const SizedBox(height: 8),
                      TvFieldTraversal(child: TextField(
                        controller: confirmController,
                        focusNode: confirmNode,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => confirmSubmit(),
                        decoration: InputDecoration(
                          labelText: context.loc.backup_passphrase_confirm,
                          prefixIcon: Icon(Icons.lock_outline,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      )),
                      const SizedBox(height: 8),
                      Text(
                        context.loc.backup_plain_warning,
                        style: TextStyle(
                          color: Theme.of(statefulContext).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, null),
                    child: Text(context.loc.cancel),
                  ),
                  if (!forImport && !requireConfirm)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, ''),
                      child: Text(context.loc.backup_skip_encryption),
                    ),
                  if (requireConfirm)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, ''),
                      child: Text(context.loc.backup_skip_encryption),
                    ),
                  FilledButton(
                    onPressed: confirmSubmit,
                    child: Text(
                      forImport
                          ? context.loc.tmdb_search_button
                          : context.loc.backup_encrypt,
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
      confirmController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group 1 — Playlists / account & content: switch playlist,
              // refresh its contents, filter categories, and the TMDb
              // credential that enriches that content with metadata.
              SectionTitleWidget(title: context.loc.general_settings),
              RensiSettingsCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.home),
                      title: Text(context.loc.playlist_list),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await UserPreferences.removeLastPlaylist();
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlaylistScreen(),
                            ),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(context.loc.refresh_contents),
                      trailing: const Icon(Icons.cloud_download),
                      onTap: () {
                        if (isXtreamCode) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => XtreamCodeDataLoaderScreen(
                                playlist: AppState.currentPlaylist!,
                                refreshAll: true,
                              ),
                            ),
                          );
                        }

                        if (isM3u) {
                          refreshM3uPlaylist();
                        }
                      },
                    ),
                    if (isXtreamCode) const Divider(height: 1),
                    if (isXtreamCode)
                      ListTile(
                        leading: const Icon(Icons.subtitles_outlined),
                        title: Text(context.loc.hide_category),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CategorySettingsScreen(
                                controller: controller,
                              ),
                            ),
                          );

                          if (result == true) {
                            if (isXtreamCode) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      XtreamCodeDataLoaderScreen(
                                        playlist: AppState.currentPlaylist!,
                                        refreshAll: true,
                                      ),
                                ),
                              );
                            }

                            if (isM3u) {
                              refreshM3uPlaylist();
                            }
                          }
                        },
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsetsDirectional.only(top: 12, end: 12),
                            child: Icon(Icons.key, size: 24),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.loc.tmdb_credential_label,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                if (_hasTmdbCredential)
                                  Text(
                                    context.loc.tmdb_credential_configured,
                                    style: const TextStyle(color: Colors.green),
                                  )
                                else
                                  Text(context.loc.tmdb_credential_missing),
                                const SizedBox(height: 8),
                                TvFieldTraversal(child: TextField(
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (v) => _tmdbToken = v,
                                  onSubmitted: (_) => _saveTmdbCredential(),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.vpn_key_outlined,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    labelText:
                                        context.loc.tmdb_credential_field_label,
                                  ),
                                )),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    onPressed: _saveTmdbCredential,
                                    child: Text(context.loc.save),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // TV Guide (EPG): optional external XMLTV source for the full guide.
              SectionTitleWidget(title: context.loc.epg_section),
              RensiSettingsCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.loc.epg_xmltv_hint,
                          style: TextStyle(
                              fontSize: AppThemes.bodySmallSize,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      const SizedBox(height: 10),
                      TvFieldTraversal(
                        child: TextField(
                          controller: _xmltvController,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: context.loc.epg_xmltv_url,
                            hintText: 'https://…',
                            prefixIcon: Icon(Icons.link,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _refreshingEpg ? null : _saveAndRefreshEpg,
                          icon: _refreshingEpg
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.refresh),
                          label: Text(context.loc.epg_refresh),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Group 2 — Playback: decoder, audio/subtitle tracks, speed,
              // resume-in-background/PiP, and touch gestures.
              SectionTitleWidget(title: context.loc.player_settings),
              RensiSettingsCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.play_circle_outline),
                      title: Text(context.loc.continue_on_background),
                      subtitle: Text(
                        context.loc.continue_on_background_description,
                      ),
                      value: _backgroundPlayEnabled,
                      onChanged: _saveBackgroundPlaySetting,
                    ),
                    if (_pipSupported) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.picture_in_picture_alt),
                        title: Text(context.loc.auto_pip_on_home),
                        subtitle: Text(context.loc.auto_pip_on_home_description),
                        value: _autoPipOnHome,
                        onChanged: _saveAutoPipSetting,
                      ),
                    ],
                    const Divider(height: 1),
                    // The option labels are values, not advice. They used to
                    // carry their own parentheticals — "Automático
                    // (recomendado)", "Hardware directo (experimental)" — which
                    // made the longest one ~390dp at 10-foot type, wider than
                    // the control can be on a 360dp handset even at full width.
                    // The guidance did not need to be inside the closed
                    // dropdown, where it is repeated on every glance at a
                    // setting nobody is changing; it belongs to the row.
                    //
                    // Localised on the way past. The label was already hardcoded
                    // Spanish before this change, and adding a new Spanish
                    // sentence beside it would have left an English user reading
                    // advice they cannot read, two rows under the language
                    // picker that promises otherwise.
                    DropdownTileWidget<String>(
                      icon: Icons.memory,
                      label: context.loc.video_decoding_label,
                      description: context.loc.video_decoding_description,
                      value: _videoDecoder,
                      items: [
                        DropdownMenuItem(
                            value: 'auto',
                            child: Text(context.loc.video_decoding_auto)),
                        DropdownMenuItem(
                            value: 'hw_direct',
                            child: Text(context.loc.video_decoding_hw)),
                        DropdownMenuItem(
                            value: 'software',
                            child: Text(context.loc.video_decoding_software)),
                      ],
                      onChanged: _saveVideoDecoder,
                    ),
                    const Divider(height: 1),
                    DropdownTileWidget<String>(
                      icon: Icons.translate,
                      label: context.loc.preferred_audio,
                      value: _prefAudioLang,
                      items: [
                        for (final o in _audioLangOptions)
                          DropdownMenuItem(
                              value: o, child: Text(_langLabels[o] ?? o)),
                      ],
                      onChanged: _savePrefAudio,
                    ),
                    const Divider(height: 1),
                    DropdownTileWidget<String>(
                      icon: Icons.closed_caption_outlined,
                      label: context.loc.preferred_subtitles,
                      value: _prefSubLang,
                      items: [
                        for (final o in _subLangOptions)
                          DropdownMenuItem(
                              value: o, child: Text(_langLabels[o] ?? o)),
                      ],
                      onChanged: _savePrefSub,
                    ),
                    const Divider(height: 1),
                    DropdownTileWidget<double>(
                      icon: Icons.speed,
                      label: context.loc.speed,
                      value: _playbackSpeed,
                      items: [
                        for (final s in _speedOptions)
                          DropdownMenuItem(
                              value: s,
                              child: Text(s == 1.0 ? 'Normal' : '${s}x')),
                      ],
                      onChanged: _savePlaybackSpeed,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.subtitles_outlined),
                      title: Text(context.loc.subtitle_settings),
                      subtitle: Text(context.loc.subtitle_settings_description),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const SubtitleSettingsScreen(),
                          ),
                        );
                      },
                    ),
                    if (Theme.of(context).platform == TargetPlatform.android ||
                        Theme.of(context).platform == TargetPlatform.iOS) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.brightness_6),
                        title: Text(context.loc.brightness_gesture),
                        subtitle: Text(
                          context.loc.brightness_gesture_description,
                        ),
                        value: _brightnessGesture,
                        onChanged: (value) async {
                          await UserPreferences.setBrightnessGesture(value);
                          setState(() {
                            _brightnessGesture = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.volume_up),
                        title: Text(context.loc.volume_gesture),
                        subtitle: Text(context.loc.volume_gesture_description),
                        value: _volumeGesture,
                        onChanged: (value) async {
                          await UserPreferences.setVolumeGesture(value);
                          setState(() {
                            _volumeGesture = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.swipe),
                        title: Text(context.loc.seek_gesture),
                        subtitle: Text(context.loc.seek_gesture_description),
                        value: _seekGesture,
                        onChanged: (value) async {
                          await UserPreferences.setSeekGesture(value);
                          setState(() {
                            _seekGesture = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.fast_forward),
                        title: Text(context.loc.speed_up_on_long_press),
                        subtitle: Text(
                          context.loc.speed_up_on_long_press_description,
                        ),
                        value: _speedUpOnLongPress,
                        onChanged: (value) async {
                          await UserPreferences.setSpeedUpOnLongPress(value);
                          setState(() {
                            _speedUpOnLongPress = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.touch_app),
                        title: Text(context.loc.seek_on_double_tap),
                        subtitle: Text(
                          context.loc.seek_on_double_tap_description,
                        ),
                        value: _seekOnDoubleTap,
                        onChanged: (value) async {
                          await UserPreferences.setSeekOnDoubleTap(value);
                          setState(() {
                            _seekOnDoubleTap = value;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Group 3 — Downloads/storage.
              RensiSettingsCard(
                child: ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: Text(context.loc.downloads_title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DownloadsScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Group 3.5 — TV / Casting (feature H): master opt-in for letting a
              // trusted TV keep your provider creds so it can play standalone,
              // plus a list to forget per-(TV, provider) grants.
              SectionTitleWidget(title: context.loc.tv_standalone_section),
              RensiSettingsCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.cast_connected),
                      title: Text(context.loc.tv_standalone_master_title),
                      subtitle:
                          Text(context.loc.tv_standalone_master_subtitle),
                      value: _tvStandaloneAllowed,
                      onChanged: _saveTvStandaloneAllowed,
                    ),
                    // Pausar la TV al recibir una llamada: solo en móvil Android
                    // (usa READ_PHONE_STATE y castear se hace desde el teléfono).
                    if (Theme.of(context).platform == TargetPlatform.android &&
                        !ResponsiveHelper.isDesktopOrTV(context)) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.phone_paused_outlined),
                        title: Text(context.loc.pause_cast_on_call_title),
                        subtitle:
                            Text(context.loc.pause_cast_on_call_subtitle),
                        value: _pauseCastOnCall,
                        onChanged: _savePauseCastOnCall,
                      ),
                    ],
                    if (_standaloneGrants.isEmpty) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.tv_off_outlined),
                        title:
                            Text(context.loc.tv_standalone_revoke_empty),
                        dense: true,
                      ),
                    ] else
                      for (final g in _standaloneGrants) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.tv),
                          title: Text(
                              _playlistNames[g.providerId] ?? g.providerId),
                          subtitle:
                              Text(context.loc.tv_standalone_revoke_action),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: context.loc.tv_standalone_revoke_action,
                            onPressed: () => _forgetStandaloneGrant(
                                g.tvId, g.providerId),
                          ),
                          onTap: () =>
                              _forgetStandaloneGrant(g.tvId, g.providerId),
                        ),
                      ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Group 4 — Appearance/language.
              SectionTitleWidget(title: context.loc.appearance),
              RensiSettingsCard(
                child: Column(
                  children: [
                    DropdownTileWidget<Locale>(
                      icon: Icons.language,
                      label: context.loc.app_language,
                      value: Localizations.localeOf(context),
                      items: [
                        ...supportedLanguages.map(
                          (language) => DropdownMenuItem(
                            value: Locale(language['code']),
                            child: Text(language['name']),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        Provider.of<LocaleProvider>(
                          context,
                          listen: false,
                        ).setLocale(v!);
                      },
                    ),
                    const Divider(height: 1),
                    DropdownTileWidget<String>(
                      icon: Icons.color_lens_outlined,
                      label: context.loc.theme,
                      value: _selectedTheme,
                      items: [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text(context.loc.standard),
                        ),
                        DropdownMenuItem(
                          value: 'light',
                          child: Text(context.loc.light),
                        ),
                        DropdownMenuItem(
                          value: 'dark',
                          child: Text(context.loc.dark),
                        ),
                      ],
                      onChanged: (value) async {
                        if (value != null) {
                          final themeMode = _stringToThemeMode(value);
                          await themeProvider.setTheme(themeMode);
                          setState(() {
                            _selectedTheme = value;
                          });
                        }
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.contrast),
                      title: Text(context.loc.amoled_dark),
                      value: themeProvider.amoled,
                      onChanged: (v) => themeProvider.setAmoled(v),
                    ),
                    const Divider(height: 1),
                    // F4 — selector de acento (presets curados, cada uno
                    // pre-validado WCAG en claro/oscuro/AMOLED).
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: Text(context.loc.accent_color),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 12,
                        children: [
                          for (final a in AppThemes.accents)
                            _AccentSwatch(
                              accent: a,
                              selected: themeProvider.accent.id == a.id,
                              onTap: () => themeProvider.setAccent(a),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Parental control: set/remove the PIN. Categories are locked from
              // the "hide categories" screen (lock icon per row); a locked
              // category asks for this PIN when opened.
              SectionTitleWidget(title: context.loc.parental_control),
              RensiSettingsCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(context.loc.parental_set_pin),
                      subtitle: Text(context.loc.parental_locked_note),
                      onTap: _setOrChangeParentalPin,
                    ),
                    if (_hasParentalPin) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.lock_open_outlined),
                        title: Text(context.loc.parental_remove_pin),
                        onTap: _removeParentalPin,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Group 5 — Backup/data: export/import plus clearing local
              // history, all operations on the app's stored data.
              SectionTitleWidget(title: context.loc.backup_section),
              RensiSettingsCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.upload_file),
                      title: Text(context.loc.export_playlists_and_settings),
                      subtitle: Text(context.loc.export_subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _exportBackup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.download),
                      title: Text(context.loc.import_playlists_and_settings),
                      subtitle: Text(context.loc.import_subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _importBackup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(context.loc.import_from_url),
                      subtitle: Text(context.loc.import_url_subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _importBackupFromUrl,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      // Restores a capability the app lost when the unreachable
                      // history screen was deleted: that screen was the only
                      // place clearAllHistory was ever called from, so removing
                      // it left viewing history with no way out of the database
                      // at all — on a TV box, which is a shared device by
                      // definition.
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: Text(context.loc.clear_all_history),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _confirmClearHistory,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Group 6 — About/diagnostics.
              SectionTitleWidget(title: context.loc.about),
              RensiSettingsCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(context.loc.app_version),
                      subtitle: Text(
                        _appVersion.isNotEmpty ? _appVersion : 'Loading...',
                      ),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.developer_mode),
                      title: Text(context.loc.developer),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      dense: true,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DeveloperScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: Text(context.loc.support_on_github),
                      subtitle: Text(context.loc.support_on_github_description),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      dense: true,
                      onTap: () async {
                        final url = Uri.parse(
                          'https://github.com/breisnerlopez/rensi-iptv',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
  }

  refreshM3uPlaylist() async {
    List<M3uItem> oldM3uItems = AppState.m3uItems!;
    List<M3uItem> newM3uItems = [];

    if (AppState.currentPlaylist!.url!.startsWith('http')) {
      showLoadingDialog(context, context.loc.loading_m3u);
      final params = {
        'id': AppState.currentPlaylist!.id,
        'url': AppState.currentPlaylist!.url!,
      };
      newM3uItems = await compute(M3uParser.parseM3uUrl, params);
    } else {
      await _pickFile();
      if (_selectedFileBytes == null) return;

      showLoadingDialog(context, context.loc.loading_m3u);
      final params = <String, Object>{
        'id': AppState.currentPlaylist!.id,
        'bytes': _selectedFileBytes!,
      };
      newM3uItems = await compute(M3uParser.parseM3uBytes, params);
    }

    newM3uItems = updateM3UItemIdsByPosition(
      oldItems: oldM3uItems,
      newItems: newM3uItems,
    );

    await database.deleteAllM3uItems(AppState.currentPlaylist!.id);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => M3uDataLoaderScreen(
          playlist: AppState.currentPlaylist!,
          m3uItems: newM3uItems,
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    _selectedFileBytes = null;
    try {
      final picked = await pickFileBytes(
        context: context,
        title: context.loc.refresh_contents,
        extensions: const ['m3u', 'm3u8'],
      );
      if (picked != null) {
        setState(() {
          _selectedFileBytes = picked.bytes;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.loc.file_selection_error)));
    }
  }

  List<M3uItem> updateM3UItemIdsByPosition({
    required List<M3uItem> oldItems,
    required List<M3uItem> newItems,
  }) {
    Map<String, List<MapEntry<int, String>>> groupedOldItems = {};
    for (int i = 0; i < oldItems.length; i++) {
      M3uItem item = oldItems[i];
      String key = "${item.url}|||${item.name}";
      groupedOldItems.putIfAbsent(key, () => []);
      groupedOldItems[key]!.add(MapEntry(i, item.id));
    }

    Map<String, int> groupUsageCounter = {};
    List<M3uItem> updatedItems = [];

    for (int i = 0; i < newItems.length; i++) {
      M3uItem newItem = newItems[i];
      String key = "${newItem.url}|||${newItem.name}";

      if (groupedOldItems.containsKey(key)) {
        List<MapEntry<int, String>> oldGroup = groupedOldItems[key]!;
        int usageCount = groupUsageCounter[key] ?? 0;

        if (usageCount < oldGroup.length) {
          String oldId = oldGroup[usageCount].value;
          updatedItems.add(newItem.copyWith(id: oldId));
          groupUsageCounter[key] = usageCount + 1;
        } else {
          updatedItems.add(newItem);
        }
      } else {
        updatedItems.add(newItem);
      }
    }

    return updatedItems;
  }
}

/// F4 — muestra de un preset de acento: un círculo relleno del color, con un
/// anillo + check cuando está seleccionado. Tappable para elegirlo.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AccentSet accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: accent.id,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.accent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 20, color: accent.onAccent)
              : null,
        ),
      ),
    );
  }
}
