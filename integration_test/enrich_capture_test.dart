// Opt-in visual proof of TMDb enrichment. Runs on a networked device with a
// real key (runtime-only, never committed/logged):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/enrich_capture_test.dart -d <device> --profile \
//     --dart-define-from-file=<path>/tmdb_env.json
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/l10n/supported_languages.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/redesign/search_detail_sheet.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/services/tmdb_credentials_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/tmdb_enrichment.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const token = String.fromEnvironment('TMDB_TOKEN');

  setUpAll(() async {
    await binding.convertFlutterSurfaceToImage();
  });

  Widget wrap(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales:
            supportedLanguages.map((l) => Locale(l['code'])).toList(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppThemes.darkTheme,
        home: Scaffold(backgroundColor: Colors.black, body: child),
      );

  testWidgets('SERIES enrichment renders cast (tv path)', (tester) async {
    await tester.runAsync(() => TmdbCredentialsService.saveCredential(token));
    await tester.pumpWidget(wrap(
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Breaking Bad (serie)',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 16),
              TmdbEnrichment(
                title: 'Breaking Bad',
                mediaType: TmdbMediaType.tv,
                year: 2008,
                locale: Locale('es'),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 9)));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await binding.takeScreenshot('enrich_series');
    await tester.runAsync(() => TmdbCredentialsService.deleteCredential());
  });

  testWidgets('DISCOVER sheet renders cast', (tester) async {
    await tester.runAsync(() => TmdbCredentialsService.saveCredential(token));
    const result = GlobalSearchResult(
      tmdb: TmdbSearchResult(
        id: 299534, // Avengers: Endgame
        mediaType: TmdbMediaType.movie,
        title: 'Vengadores: Endgame',
        voteAverage: 8.2,
      ),
      localMatches: [],
      isWishlisted: false,
    );
    await tester.pumpWidget(wrap(
      SearchDetailSheet(
        result: result,
        service: GlobalSearchService(),
        onPlayLocal: (_) {},
        onToggleWishlist: () async => false,
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 9)));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await binding.takeScreenshot('discover_sheet_cast');
    await tester.runAsync(() => TmdbCredentialsService.deleteCredential());
  });
}
