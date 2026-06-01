import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/screens/settings/subtitle_settings_section.dart';
import 'package:rensi_iptv/services/backup_service.dart';
import 'package:rensi_iptv/services/pip_service.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/utils/backup_import_flow.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:rensi_iptv/utils/show_loading_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../../services/m3u_parser.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/section_title_widget.dart';
import '../m3u/m3u_data_loader_screen.dart';
import '../playlist_screen.dart';
import '../xtream-codes/xtream_code_data_loader_screen.dart';
import 'category_settings_section.dart';

final controller = XtreamCodeHomeController(true);

class GeneralSettingsWidget extends StatefulWidget {
  const GeneralSettingsWidget({super.key});

  @override
  State<GeneralSettingsWidget> createState() => _GeneralSettingsWidgetState();
}

class _GeneralSettingsWidgetState extends State<GeneralSettingsWidget> {
  final AppDatabase database = getIt<AppDatabase>();

  bool _backgroundPlayEnabled = false;
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
  String _appVersion = '';
  String _tmdbToken = '';
  bool _hasTmdbCredential = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
      final pipSupported = await PipService.instance.isAvailable();
      final packageInfo = await PackageInfo.fromPlatform();
      final tmdb = await TmdbCredentialsService.getCredential();
      setState(() {
        _backgroundPlayEnabled = backgroundPlay;
        _selectedTheme = _themeModeToString(themeMode);
        _brightnessGesture = brightnessGesture;
        _volumeGesture = volumeGesture;
        _seekGesture = seekGesture;
        _speedUpOnLongPress = speedUpOnLongPress;
        _seekOnDoubleTap = seekOnDoubleTap;
        _autoPipOnHome = autoPipOnHome;
        _pipSupported = pipSupported;
        _appVersion = packageInfo.version;
        _hasTmdbCredential = tmdb != null;
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
                    TextField(
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
                        errorText: errorText,
                      ),
                    ),
                    if (requireConfirm) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: confirmController,
                        focusNode: confirmNode,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => confirmSubmit(),
                        decoration: InputDecoration(
                          labelText: context.loc.backup_passphrase_confirm,
                        ),
                      ),
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

  Future<BackupMergeStrategy?> _askMergeStrategy() async {
    return showDialog<BackupMergeStrategy?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.loc.backup_strategy_title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: Text(context.loc.backup_strategy_overwrite),
                onTap: () =>
                    Navigator.pop(dialogContext, BackupMergeStrategy.overwrite),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(context.loc.backup_strategy_keep_local),
                onTap: () =>
                    Navigator.pop(dialogContext, BackupMergeStrategy.keepLocal),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: Text(context.loc.cancel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: ListTile(
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
              ),
              const SizedBox(height: 10),
              SectionTitleWidget(title: context.loc.general_settings),
              Card(
                child: Column(
                  children: [
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
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 12, right: 12),
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
                                TextField(
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (v) => _tmdbToken = v,
                                  onSubmitted: (_) => _saveTmdbCredential(),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    labelText:
                                        context.loc.tmdb_credential_field_label,
                                  ),
                                ),
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
              SectionTitleWidget(title: context.loc.backup_section),
              Card(
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
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionTitleWidget(title: context.loc.player_settings),
              Card(
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
              SectionTitleWidget(title: context.loc.about),
              Card(
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
                      leading: const Icon(Icons.code),
                      title: Text(context.loc.support_on_github),
                      subtitle: Text(context.loc.support_on_github_description),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      dense: true,
                      onTap: () async {
                        final url = Uri.parse(
                          'https://github.com/bsogulcan/another-iptv-player',
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
      // withData: true so we get the bytes via SAF without needing
      // READ_EXTERNAL_STORAGE; works the same on Android 9 through 14+.
      // FileType.any matches BackupService.pickBackupFile — see that
      // comment for why FileType.custom + allowedExtensions is rejected
      // by Mi Box and similar TV-class SAF providers.
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result != null) {
        setState(() {
          _selectedFileBytes = result.files.single.bytes;
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
