// El botón de descarga, en DATOS MÓVILES, pide confirmación antes de encolar
// (una descarga VOD puede ser de 1+ GB). Verifica: aparece el diálogo y
// "Cancelar" NO encola nada. La red se fuerza con el seam de ConnectivityHelper.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/download_service.dart';
import 'package:rensi_iptv/utils/connectivity_helper.dart';
import 'package:rensi_iptv/widgets/download_button.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
    if (GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.unregister<AppDatabase>();
    }
    GetIt.instance.registerSingleton<AppDatabase>(db);
    AppState.currentPlaylist = Playlist(
      id: 'p',
      name: 'P',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026, 1, 1),
    );
  });

  tearDown(() async {
    ConnectivityHelper.debugIsCellularOnly = null;
    await db.close();
    if (GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.unregister<AppDatabase>();
    }
  });

  Widget wrap(ContentItem item) => MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: DownloadButton(item: item)),
      );

  final item = ContentItem('http://h/movie.mp4', 'Peli', '', ContentType.vod);

  testWidgets(
      'datos móviles: pide confirmación y "Cancelar" no encola nada',
      (tester) async {
    ConnectivityHelper.debugIsCellularOnly = () async => true;
    await tester.pumpWidget(wrap(item));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    expect(find.text('¿Descargar con datos móviles?'), findsOneWidget,
        reason: 'en celular debe confirmar antes de gastar datos');

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Descargar con datos móviles?'), findsNothing);
    expect(await DownloadService.instance.findByContentId(item.id), isNull,
        reason: 'cancelar no debe crear una fila de descarga');
  });
}
