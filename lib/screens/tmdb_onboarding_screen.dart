import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/widgets/tv/tv_field_traversal.dart';

/// One-time optional step (shown after the user has a playlist but no personal
/// TMDb key) offering to add their own key for catalogue artwork. Skipping is
/// fine — a shared embedded default may already be active, and the key can be
/// added later in Settings. Marks itself seen so it never nags twice.
class TmdbOnboardingScreen extends StatefulWidget {
  const TmdbOnboardingScreen({super.key, required this.onDone});

  /// Called after Save or Skip (the flag is persisted first).
  final VoidCallback onDone;

  @override
  State<TmdbOnboardingScreen> createState() => _TmdbOnboardingScreenState();
}

class _TmdbOnboardingScreenState extends State<TmdbOnboardingScreen> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool save}) async {
    if (_saving) return;
    setState(() => _saving = true);
    if (save && _controller.text.trim().isNotEmpty) {
      await TmdbCredentialsService.saveCredential(_controller.text);
    }
    await UserPreferences.setTmdbOnboardingSeen(true);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final loc = context.loc;
    final tv = ResponsiveHelper.isDesktopOrTV(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RensiSafeColumn(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.image_outlined, size: 56, color: r.accent),
                    const SizedBox(height: 20),
                    Text(
                      loc.tmdb_onboarding_title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Bricolage Grotesque',
                        fontSize: AppThemes.h2Size,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.tmdb_onboarding_body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppThemes.bodySmallSize,
                        height: 1.5,
                        color: r.text2,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // TvFieldTraversal: on Android TV, keeps D-pad up/down as
                    // focus traversal (not cursor movement) and blurs on BACK —
                    // same wrapper the Settings key field uses. obscureText for
                    // parity (the key is a secret, and TV screens are shared).
                    TvFieldTraversal(
                      child: TextField(
                        controller: _controller,
                        autofocus: false,
                        enabled: !_saving,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: loc.tmdb_credential_field_label,
                          filled: true,
                          fillColor: r.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FocusHighlight(
                      borderRadius: BorderRadius.circular(20),
                      child: FilledButton.icon(
                        autofocus: tv,
                        onPressed:
                            _saving ? null : () => _finish(save: true),
                        icon: const Icon(Icons.check),
                        label: Text(loc.tmdb_credential_save),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle:
                              const TextStyle(fontSize: AppThemes.bodySmallSize),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FocusHighlight(
                      borderRadius: BorderRadius.circular(20),
                      child: TextButton(
                        onPressed: _saving ? null : () => _finish(save: false),
                        child: Text(
                          loc.tmdb_onboarding_skip,
                          style: TextStyle(color: r.text3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
