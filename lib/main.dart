import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:rensi_iptv/controllers/playlist_controller.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'controllers/locale_provider.dart';
import 'controllers/theme_provider.dart';
import 'controllers/active_playlist_controller.dart';
import 'controllers/cast_sender_controller.dart';
import 'widgets/cast/tv_receiver_host.dart';
import 'l10n/app_localizations.dart';
import 'l10n/supported_languages.dart';
import 'utils/app_themes.dart';
import 'utils/credential_scrubber.dart';
import 'utils/responsive_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorGuards();
  // Resolve the TV/leanback flag once so ResponsiveHelper.isDesktopOrTV has a
  // real platform signal instead of relying on screen width alone.
  await ResponsiveHelper.initTelevisionFlag();
  await setupServiceLocator();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ActivePlaylistController()),
        ChangeNotifierProvider(create: (_) => PlaylistController()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CastSenderController()),
      ],
      child: const MyApp(),
    ),
  );
}

/// Keeps raw exception text off the screen and out of the logs.
///
/// In debug builds an uncaught exception paints Flutter's red `ErrorWidget`
/// with the full message and stack trace. IPTV error strings routinely embed
/// the stream URL, which for Xtream carries the subscription user and password
/// — so the default behaviour turns any playback hiccup into a full-screen
/// credential disclosure (and, on a shared or cast screen, a permanent one).
@visibleForTesting
void installErrorGuards() => _installErrorGuards();

/// The widget the app paints when a build throws. Exposed so a test can
/// exercise the real one: the guard used to be verified against a copy declared
/// inside the test, so removing the scrubbing from THIS function left the suite
/// green — a credential-disclosure fix with no net under it.
@visibleForTesting
Widget buildScrubbedErrorWidget(FlutterErrorDetails details) => Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF0B0B0D),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              scrubCredentials(details.exception),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      ),
    );

void _installErrorGuards() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final scrubbed = scrubCredentials(details.exception);
    // Only wrap when scrubbing actually removed something: replacing the
    // exception object unconditionally would break `is FlutterError` checks
    // downstream and lose the framework's richer formatting.
    if (scrubbed == details.exception.toString()) {
      defaultOnError?.call(details);
      return;
    }
    defaultOnError?.call(
      FlutterErrorDetails(
        exception: _ScrubbedException(scrubbed),
        stack: details.stack,
        library: details.library,
        // `context` and `informationCollector` are rendered by the framework
        // too, and carry things like `ImageProvider: NetworkImage("http://…")`.
        // Once we know this error contained credentials, drop them rather than
        // forward text we have not scrubbed.
        context: null,
        stackFilter: details.stackFilter,
        silent: details.silent,
      ),
    );
  };

  // FlutterError.onError only sees what the framework catches. Async errors
  // raised outside the widget layer (bare futures, http callbacks, work
  // returned from compute()) reach the engine directly and would print raw.
  PlatformDispatcher.instance.onError = (error, stack) {
    // Report it ourselves, scrubbed and with the stack — losing the trace was
    // the reason not to claim the error. Then return true ("handled"): the SDK
    // contract is that returning false falls back to printing to stderr, which
    // would re-emit the same exception *unscrubbed* right next to our clean
    // line. Handling it is what keeps credentials out of logcat.
    debugPrint('Uncaught: ${scrubCredentials(error)}\n${scrubCredentials(stack)}');
    return true;
  };

  // Directionality is mandatory here. Flutter's stock ErrorWidget is a bare
  // RenderErrorBox precisely because it cannot rely on inherited widgets: an
  // error thrown above (or outside) the Directionality — during startup, or in
  // MaterialApp.builder — makes Text throw "No Directionality widget found",
  // which re-enters this builder and recurses without bottom. Observed before
  // this wrapper: the app hangs and dumps megabytes to the log.
  ErrorWidget.builder = buildScrubbedErrorWidget;
}

class _ScrubbedException implements Exception {
  final String _message;
  _ScrubbedException(this._message);

  @override
  String toString() => _message;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      locale: localeProvider.locale,
      supportedLocales: supportedLanguages
          .map((lang) => Locale(lang['code']))
          .toList(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'Rensi IPTV',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeProvider.themeMode,
      // TV-grade focus visuals (fat coloured borders + tinted overlays)
      // only land on large screens / Android TV. Phones keep the stock
      // Material 3 look so the heavier strokes never bleed into a touch
      // UI that doesn't need them.
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        if (!ResponsiveHelper.isDesktopOrTV(context)) return child;
        final base = Theme.of(context);
        Widget themed = Theme(
          data: AppThemes.applyTvOverrides(base),
          child: child,
        );
        // Adapt to the panel: a TV box that reports fewer logical dp than the
        // ~960dp the 10-foot type was tuned for makes everything read as
        // oversized. Scale ALL text down by the same factor. 1.0 on a 960dp TV
        // → no change. tvScale already returns 1.0 when the user has an
        // accessibility font scale, so this never stomps that preference.
        final scale = ResponsiveHelper.tvScale(context);
        if (scale != 1.0) {
          final mq = MediaQuery.of(context);
          themed = MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scale)),
            child: themed,
          );
        }
        return themed;
      },
      home: TvReceiverHost(child: AppInitializerScreen()),
      debugShowCheckedModeBanner: false,
    );
  }
}
