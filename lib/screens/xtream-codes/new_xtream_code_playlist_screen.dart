import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_data_loader_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../controllers/playlist_controller.dart';
import '../../../../models/api_configuration_model.dart';
import '../../../../models/playlist_model.dart';
import '../../../../repositories/iptv_repository.dart';
import 'package:rensi_iptv/widgets/tv/tv_field_traversal.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

class NewXtreamCodePlaylistScreen extends StatefulWidget {
  const NewXtreamCodePlaylistScreen({super.key});

  @override
  NewXtreamCodePlaylistScreenState createState() =>
      NewXtreamCodePlaylistScreenState();
}

class NewXtreamCodePlaylistScreenState
    extends State<NewXtreamCodePlaylistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Playlist-1');
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  // FocusNodes drive D-pad / IME-next traversal between the four fields
  // and the submit button. Without explicit nodes a TV remote cannot
  // chain through the form without going back to a pointer gesture.
  final _nameNode = FocusNode(debugLabel: 'xc-name');
  final _urlNode = FocusNode(debugLabel: 'xc-url');
  final _usernameNode = FocusNode(debugLabel: 'xc-username');
  final _passwordNode = FocusNode(debugLabel: 'xc-password');
  final _submitNode = FocusNode(debugLabel: 'xc-submit');

  bool _obscurePassword = true;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_validateForm);
    _urlController.addListener(_validateForm);
    _usernameController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameNode.dispose();
    _urlNode.dispose();
    _usernameNode.dispose();
    _passwordNode.dispose();
    _submitNode.dispose();
    super.dispose();
  }

  // Lets a remote-control user drop a long URL/user/pass into a field
  // without typing it character-by-character on a D-pad keyboard.
  Future<void> _pasteInto(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      controller.text = text.trim();
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }
  }

  void _validateForm() {
    setState(() {
      _isFormValid =
          _nameController.text.trim().isNotEmpty &&
          _urlController.text.trim().isNotEmpty &&
          _usernameController.text.trim().isNotEmpty &&
          _passwordController.text.trim().isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('XStream Playlist')),
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
                  _buildHeader(colorScheme),
                  SizedBox(height: 32),
                  _buildPlaylistNameField(colorScheme),
                  SizedBox(height: 20),
                  _buildUrlField(colorScheme),
                  SizedBox(height: 20),
                  _buildUsernameField(colorScheme),
                  SizedBox(height: 20),
                  _buildPasswordField(colorScheme),
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
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Icon(Icons.stream, size: 30, color: colorScheme.onPrimary),
        ),
        SizedBox(height: 16),
        Text(
          'XStream Code Playlist',
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
          context.loc.xtream_code_description,
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
          onFieldSubmitted: (_) => _urlNode.requestFocus(),
          decoration: InputDecoration(
            hintText: context.loc.playlist_name_placeholder,
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
              return context.loc.playlist_name_min_2;
            }
            return null;
          },
        )),
      ],
    );
  }

  Widget _buildUrlField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.api_url,
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
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _usernameNode.requestFocus(),
          decoration: InputDecoration(
            hintText: 'http://example.com:8080',
            prefixIcon: Icon(Icons.link, color: colorScheme.primary),
            suffixIcon: IconButton(
              icon: Icon(
                Icons.content_paste,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
              tooltip: 'Pegar',
              onPressed: () => _pasteInto(_urlController),
            ),
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
              return context.loc.api_url_required;
            }

            final uri = Uri.tryParse(value.trim());
            if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
              return context.loc.url_format_validate_error;
            }

            if (!['http', 'https'].contains(uri.scheme)) {
              return context.loc.url_format_validate_error;
            }

            return null;
          },
        )),
      ],
    );
  }

  Widget _buildUsernameField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.username,
          style: TextStyle(
            fontSize: AppThemes.bodySmallSize,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        TvFieldTraversal(child: TextFormField(
          controller: _usernameController,
          focusNode: _usernameNode,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _passwordNode.requestFocus(),
          decoration: InputDecoration(
            hintText: context.loc.username_placeholder,
            prefixIcon: Icon(Icons.person, color: colorScheme.primary),
            suffixIcon: IconButton(
              icon: Icon(
                Icons.content_paste,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
              tooltip: 'Pegar',
              onPressed: () => _pasteInto(_usernameController),
            ),
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
              return context.loc.username_required;
            }
            if (value.trim().length < 3) {
              return context.loc.username_min_3;
            }
            return null;
          },
        )),
      ],
    );
  }

  Widget _buildPasswordField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.password,
          style: TextStyle(
            fontSize: AppThemes.bodySmallSize,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        TvFieldTraversal(child: TextFormField(
          controller: _passwordController,
          focusNode: _passwordNode,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            _passwordNode.unfocus();
            _submitNode.requestFocus();
          },
          decoration: InputDecoration(
            hintText: context.loc.password_placeholder,
            prefixIcon: Icon(Icons.lock, color: colorScheme.primary),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.content_paste,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  tooltip: context.loc.paste,
                  onPressed: () => _pasteInto(_passwordController),
                ),
                IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  // Localized label so a screen reader announces the sensitive
                  // reveal-password control (was unlabelled: read as "button").
                  tooltip: _obscurePassword
                      ? context.loc.show_password
                      : context.loc.hide_password,
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ],
            ),
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
              return context.loc.password_required;
            }
            if (value.length < 3) {
              return context.loc.password_min_3;
            }
            return null;
          },
        )),
      ],
    );
  }

  Widget _buildSaveButton(
    PlaylistController controller,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      height: 56,
      // F4: FilledButton toma accentInk (relleno) + onAccent (texto) del tema →
      // el label pasa AA (≥4.5) en los 6 presets. Antes ElevatedButton con
      // backgroundColor: primary (accent crudo) daba ~3.8:1 (fallaba AA).
      child: FilledButton(
        focusNode: _submitNode,
        onPressed: controller.isLoading
            ? null
            : (_isFormValid ? _savePlaylist : null),
        style: FilledButton.styleFrom(
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
                  Flexible(
                    child: Text(
                      context.loc.submitting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppThemes.bodySmallSize, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save, size: 20),
                  SizedBox(width: 8),
                  // Flexible+ellipsis: long localisations (e.g. de) overflowed the
                  // button on narrow phones — mirror of the M3U save-button fix.
                  Flexible(
                    child: Text(
                      context.loc.submit_create_playlist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppThemes.bodySmallSize, fontWeight: FontWeight.w600),
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
                  context.loc.error_occurred,
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
            '${context.loc.all_datas_are_stored_in_device}\n${context.loc.url_format_validate_message}',
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
      final controller = Provider.of<PlaylistController>(
        context,
        listen: false,
      );

      controller.clearError();

      final repository = IptvRepository(
        ApiConfig(
          baseUrl: _urlController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
        ),
        _nameController.text.trim(),
      );

      var playerInfo = await repository.getPlayerInfo(forceRefresh: true);

      if (playerInfo == null) {
        if (!mounted) return;
        // getPlayerInfo() collapses every failure (timeout, DNS, server down,
        // bad password) to null. Don't blame the credentials when the device is
        // simply offline — that's the most common and most misleading case.
        final conn = await Connectivity().checkConnectivity();
        final offline =
            conn.isEmpty || conn.every((c) => c == ConnectivityResult.none);
        if (!mounted) return;
        controller.setError(offline
            ? context.loc.no_connection
            : context.loc.invalid_credentials);
        return;
      }

      final playlist = await controller.createPlaylist(
        name: _nameController.text.trim(),
        type: PlaylistType.xtream,
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return; // createPlaylist awaited; guard before navigating
      if (playlist != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                XtreamCodeDataLoaderScreen(playlist: playlist),
          ),
        );
      } else {
        // Don't leave the user tapping "Guardar" with nothing happening when
        // createPlaylist returns null (persistence failure).
        controller.setError(context.loc.error_occurred);
      }
    }
  }
}
