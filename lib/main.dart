import 'package:rensi_iptv/controllers/playlist_controller.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'controllers/locale_provider.dart';
import 'controllers/theme_provider.dart';
import 'controllers/active_playlist_controller.dart';
import 'l10n/app_localizations.dart';
import 'l10n/supported_languages.dart';
import 'utils/app_themes.dart';
import 'utils/responsive_helper.dart';

Future<void> main() async {
  await setupServiceLocator();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ActivePlaylistController()),
        ChangeNotifierProvider(create: (_) => PlaylistController()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
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
        return Theme(
          data: AppThemes.applyTvOverrides(base),
          child: child,
        );
      },
      home: AppInitializerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
