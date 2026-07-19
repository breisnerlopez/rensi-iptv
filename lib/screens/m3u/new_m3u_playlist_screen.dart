import 'package:rensi_iptv/controllers/m3u_controller.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/m3u/m3u_data_loader_screen.dart';
import 'package:rensi_iptv/services/m3u_parser.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/utils/picker_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart';
import 'package:provider/provider.dart';
import '../../../../controllers/playlist_controller.dart';
import '../../models/m3u_item.dart';
import '../../utils/show_loading_dialog.dart';
import 'package:rensi_iptv/widgets/tv/tv_field_traversal.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

class NewM3uPlaylistScreen extends StatefulWidget {
  const NewM3uPlaylistScreen({super.key});

  @override
  NewM3uPlaylistScreenState createState() => NewM3uPlaylistScreenState();
}

class NewM3uPlaylistScreenState extends State<NewM3uPlaylistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'M3U Playlist-1');
  final _urlController = TextEditingController();
  // Focus nodes drive D-pad / IME-next navigation between fields and the
  // submit button. Without them a TV remote cannot move from one field to
  // the next without going back to a touch gesture.
  final _nameNode = FocusNode(debugLabel: 'm3u-name');
  final _urlNode = FocusNode(debugLabel: 'm3u-url');
  final _submitNode = FocusNode(debugLabel: 'm3u-submit');
  bool _isUrlSource = true;
  bool _isFormValid = false;
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_validateForm);
    _urlController.addListener(_validateForm);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _nameNode.dispose();
    _urlNode.dispose();
    _submitNode.dispose();
    super.dispose();
  }

  void _validateForm() {
    setState(() {
      _isFormValid =
          _nameController.text.trim().isNotEmpty &&
          (_isUrlSource
              ? _urlController.text.trim().isNotEmpty
              : _selectedFileBytes != null);
    });
  }

  void _onSourceTypeChanged(bool isUrl) {
    setState(() {
      _isUrlSource = isUrl;
      if (isUrl) {
        _selectedFileName = null;
        _selectedFileBytes = null;
      } else {
        _urlController.clear();
      }
    });
    _validateForm();
  }

  Future<void> _pickFile() async {
    try {
      // pickFileBytes dispatches to the in-app FileBrowserScreen on
      // TV / large screens (Mi Box, where the SAF picker is missing)
      // and to file_picker everywhere else. Either channel returns
      // the bytes ready to feed M3uParser.parseM3uBytes.
      final picked = await pickFileBytes(
        context: context,
        title: context.loc.select_m3u_file,
        extensions: const ['m3u', 'm3u8'],
      );
      if (picked != null) {
        setState(() {
          _selectedFileName = picked.name;
          _selectedFileBytes = picked.bytes;
        });
        _validateForm();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.loc.file_selection_error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.loc.m3u_playlist)),
      body: Consumer<PlaylistController>(
        builder: (context, controller, child) {
          return SingleChildScrollView(
            // Room to scroll the active field clear of the on-screen keyboard.
            // Without it the IME simply covers the middle of the form: the TV
            // keyboard is a large overlay and the fields ran the full width, so
            // the user could not read what they were typing.
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            // RensiSafeColumn instead of a flat 24dp: on TV that margin sat
            // inside the 5% overscan crop, so the form's own focus rings were
            // partly off the picture.
            child: RensiSafeColumn(
              child: ConstrainedBox(
                // A 910dp-wide field is unreadable next to a centred keyboard.
                // Capping the measure keeps the text beside the caret visible.
                constraints: BoxConstraints(
                  maxWidth: ResponsiveHelper.isDesktopOrTV(context)
                      ? 620
                      : double.infinity,
                ),
                child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isLoading)
                    Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  _buildHeader(colorScheme),
                  SizedBox(height: 32),
                  _buildPlaylistNameField(colorScheme),
                  SizedBox(height: 20),
                  _buildSourceTypeSelector(colorScheme),
                  SizedBox(height: 20),
                  _isUrlSource
                      ? _buildUrlField(colorScheme)
                      : _buildFilePickerField(colorScheme),
                  SizedBox(height: 32),
                  _buildSaveButton(controller, colorScheme),
                  if (controller.error != null) ...[
                    SizedBox(height: 20),
                    _buildErrorCard(controller.error!, colorScheme),
                  ],
                  SizedBox(height: 20),
                  _buildInfoCard(colorScheme),
                ],
              ),
            ),
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: colorScheme.tertiary,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Icon(
            Icons.playlist_play,
            size: 30,
            color: colorScheme.onTertiary,
          ),
        ),
        SizedBox(height: 16),
        Text(
          context.loc.m3u_playlist,
          style: TextStyle(
            fontFamily: 'Bricolage Grotesque',
            letterSpacing: -0.7,
            fontSize: AppThemes.h1Size,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        Text(
          context.loc.m3u_playlist_load_description,
          style: TextStyle(
            fontSize: AppThemes.bodySmallSize,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistNameField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.playlist_name,
          style: TextStyle(
            fontSize: AppThemes.bodySmallSize,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        TvFieldTraversal(child: TextFormField(
          controller: _nameController,
          focusNode: _nameNode,
          // Focus the first field on every platform. On TV the IME does pop
          // up with it, which is not ideal, but the alternative shipped worse:
          // no autofocus left the screen with NOTHING focused, and the submit
          // button starts disabled so it cannot take focus either — a remote
          // user was stranded. TvFieldTraversal below is what lets the D-pad
          // leave the field once the keyboard is dismissed.
          autofocus: true,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) {
            if (_isUrlSource) {
              _urlNode.requestFocus();
            } else {
              _submitNode.requestFocus();
            }
          },
          decoration: InputDecoration(
            hintText: context.loc.playlist_name_hint,
            prefixIcon: Icon(Icons.playlist_add, color: colorScheme.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            // No local focusedBorder: the theme owns the focus ring, and this
            // override painted it orange while every other screen used the
            // white one — the single convention a remote user has to learn.
            
            filled: true,
            fillColor: colorScheme.surface,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return context.loc.playlist_name_required;
            }
            if (value.trim().length < 2) {
              return context.loc.playlist_name_min_length;
            }
            return null;
          },
        )),
      ],
    );
  }

  Widget _buildSourceTypeSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.source_type,
          style: TextStyle(
            fontSize: AppThemes.bodySmallSize,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: FocusHighlight(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                  child: InkWell(
                  onTap: () => _onSourceTypeChanged(true),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: _isUrlSource
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.link,
                          color: _isUrlSource
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                        ),
                        SizedBox(width: 8),
                        // Flexible + ellipsis: the localised label overflowed
                        // this segment by 17px on a 360dp phone.
                        Flexible(
                          child: Text(
                            context.loc.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isUrlSource
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
              Container(width: 1, height: 56, color: colorScheme.outline),
              Expanded(
                child: FocusHighlight(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: InkWell(
                  onTap: () => _onSourceTypeChanged(false),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: !_isUrlSource
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder,
                          color: !_isUrlSource
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                        ),
                        SizedBox(width: 8),
                        // Flexible + ellipsis: the localised label overflowed
                        // this segment by 17px on a 360dp phone.
                        Flexible(
                          child: Text(
                            context.loc.file,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: !_isUrlSource
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUrlField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.m3u_url,
          style: TextStyle(
            fontSize: AppThemes.bodySmallSize,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        TvFieldTraversal(child: TextFormField(
          controller: _urlController,
          focusNode: _urlNode,
          keyboardType: TextInputType.url,
          // An M3U URL carries username= and password=. Without these the IME
          // learns the credential into its dictionary and then offers it as a
          // suggestion pill above the keyboard — on a screen the whole room
          // can see.
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            _urlNode.unfocus();
            _submitNode.requestFocus();
          },
          decoration: InputDecoration(
            hintText: context.loc.m3u_url_hint,
            prefixIcon: Icon(Icons.link, color: colorScheme.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            // No local focusedBorder: the theme owns the focus ring, and this
            // override painted it orange while every other screen used the
            // white one — the single convention a remote user has to learn.
            
            filled: true,
            fillColor: colorScheme.surface,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return context.loc.m3u_url_required;
            }

            final uri = Uri.tryParse(value.trim());
            if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
              return context.loc.url_format_error;
            }

            if (!['http', 'https'].contains(uri.scheme)) {
              return context.loc.url_scheme_error;
            }

            return null;
          },
        )),
      ],
    );
  }

  Widget _buildFilePickerField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.m3u_file,
          style: TextStyle(
            fontSize: AppThemes.bodySmallSize,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        FocusHighlight(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outline),
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.surface,
            ),
            child: Row(
              children: [
                Icon(
                  _selectedFileBytes != null ? Icons.check_circle : Icons.folder,
                  color: _selectedFileBytes != null
                      ? colorScheme.primary
                      : colorScheme.primary.withOpacity(0.6),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedFileBytes != null
                        ? _selectedFileName ?? context.loc.file_selected
                        : context.loc.select_m3u_file,
                    style: TextStyle(
                      color: _selectedFileBytes != null
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ],
            ),
          ),
        ),
        ),
        if (_selectedFileBytes == null && !_isUrlSource)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              context.loc.please_select_m3u_file,
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveButton(
    PlaylistController controller,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        focusNode: _submitNode,
        onPressed: controller.isLoading
            ? null
            : (_isFormValid ? _savePlaylist : null),
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: controller.isLoading ? 0 : 2,
        ),
        child: controller.isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    context.loc.processing,
                    style: TextStyle(fontSize: AppThemes.bodySmallSize, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save, size: 20),
                  SizedBox(width: 8),
                  // Flexible: the label is localised, and on a 360dp phone the
                  // Spanish string overflowed the button by 199px — a hard
                  // layout error, invisible in a profile build.
                  Flexible(
                    child: Text(
                      context.loc.create_playlist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: AppThemes.bodySmallSize, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildErrorCard(String error, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.error_occurred_title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  error,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: AppThemes.labelSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
              SizedBox(width: 8),
              Text(
                context.loc.info,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            context.loc.m3u_info_message,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePlaylist() async {
    if (_formKey.currentState!.validate()) {
      final playlistController = Provider.of<PlaylistController>(
        context,
        listen: false,
      );

      playlistController.clearError();

      var playlist = await playlistController.createPlaylist(
        name: _nameController.text.trim(),
        type: PlaylistType.m3u,
        url: _isUrlSource ? _urlController.text : _selectedFileName,
      );

      List<M3uItem> m3uItems = [];
      showLoadingDialog(context, context.loc.loading_m3u);

      try {
        if (_isUrlSource) {
          // Never log the playlist URL: M3U/Xtream get.php URLs embed
          // username/password in the query string.
          final params = {'id': playlist!.id, 'url': _urlController.text};

          m3uItems = await compute(M3uParser.parseM3uUrl, params);
        } else {
          // Read straight from the bytes the picker handed us — no second
          // file-system hop, no permission prompt.
          final params = <String, Object>{
            'id': playlist!.id,
            'bytes': _selectedFileBytes!,
          };

          m3uItems = await compute(M3uParser.parseM3uBytes, params);
        }
      } catch (ex) {}

      Navigator.of(context).pop();

      if (m3uItems.length == 0) {
        playlistController.setError(context.loc.m3u_error);
        await playlistController.deletePlaylist(playlist!.id);
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              M3uDataLoaderScreen(playlist: playlist!, m3uItems: m3uItems),
        ),
      );
    }
  }
}
