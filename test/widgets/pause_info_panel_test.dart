// El panel de pausa de la TV (receptor de casting) debe pintar la sinopsis + el
// reparto que el MÓVIL resolvió y ENVIÓ con el LOAD, SIN llamar a TMDb (la TV no
// tiene clave). Si no llegó meta, cae a TmdbEnrichment (comportamiento de hoy).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/cast/pause_info_panel.dart';
import 'package:rensi_iptv/widgets/tmdb_cast_rail.dart';
import 'package:rensi_iptv/widgets/tmdb_enrichment.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('es'),
      // Panel now reads RensiColors via rensi(context) for its accent — supply
      // the real app theme (which registers that ThemeExtension).
      theme: AppThemes.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Stack(children: [child])),
    );

void main() {
  testWidgets(
      'con meta enviado pinta sinopsis + reparto y NO instancia TmdbEnrichment',
      (tester) async {
    await tester.pumpWidget(_wrap(const PauseInfoPanel(
      title: 'Ep 1',
      contentType: ContentType.series,
      position: Duration(minutes: 5),
      duration: Duration(minutes: 42),
      // profilePath null → avatar de reserva (sin fetch de red en el test).
      sentMeta: CastMeta(
        overview: 'Sinopsis de prueba enviada por el móvil.',
        cast: [
          CastMetaMember(name: 'Mark Wahlberg', character: 'Mike'),
          CastMetaMember(name: 'Kurt Russell'),
        ],
        title: 'Marea negra',
      ),
    )));
    await tester.pump();

    // Pinta lo enviado…
    expect(find.text('Sinopsis de prueba enviada por el móvil.'), findsOneWidget);
    expect(find.text('Mark Wahlberg'), findsOneWidget);
    expect(find.text('Kurt Russell'), findsOneWidget);
    expect(find.byType(TmdbCastRail), findsOneWidget);
    // …y NO cae al camino que llamaría a TMDb.
    expect(find.byType(TmdbEnrichment), findsNothing,
        reason: 'con meta enviado la TV no debe intentar resolver TMDb');
  });

  testWidgets('sin meta enviado cae a TmdbEnrichment (comportamiento de hoy)',
      (tester) async {
    await tester.pumpWidget(_wrap(const PauseInfoPanel(
      title: 'Alguna peli',
      contentType: ContentType.vod,
      position: Duration(minutes: 5),
      duration: Duration(minutes: 90),
    )));
    await tester.pump();

    expect(find.byType(TmdbEnrichment), findsOneWidget,
        reason: 'sin meta enviado se conserva el camino TmdbEnrichment');
  });

  testWidgets('meta vacío (ni sinopsis ni reparto) también cae a TmdbEnrichment',
      (tester) async {
    await tester.pumpWidget(_wrap(const PauseInfoPanel(
      title: 'X',
      contentType: ContentType.vod,
      position: Duration.zero,
      duration: Duration.zero,
      sentMeta: CastMeta(), // isEmpty → no reemplaza el camino de siempre
    )));
    await tester.pump();

    expect(find.byType(TmdbEnrichment), findsOneWidget);
  });
}
