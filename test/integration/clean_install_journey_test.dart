import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/screens/app_initializer_screen.dart';
import 'package:rensi_iptv/screens/playlist_screen.dart';
import 'package:rensi_iptv/screens/playlist_type_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_home_screen.dart';
import 'package:rensi_iptv/services/playlist_service.dart';

import 'harness.dart';
import 'seed.dart';

/// AppInitializerScreen resolves the last playlist with a Drift query in
/// initState; Drift async can't complete inside the testWidgets FakeAsync zone,
/// so interleave frame pumps with real time until it leaves its loading spinner.
Future<void> _bootInitializer(WidgetTester tester) async {
  // Fully tear down any prior tree first so this is a true cold start: a fresh
  // MaterialApp/Navigator and a fresh AppInitializerScreen State whose initState
  // re-reads last_playlist (otherwise the reused State/route wouldn't re-run).
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await pumpScreen(tester, const AppInitializerScreen());
  for (var i = 0; i < 30; i++) {
    if (find.byType(XtreamCodeHomeScreen).evaluate().isNotEmpty ||
        find.byType(PlaylistScreen).evaluate().isNotEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  }
  await settle(tester);
}

// INTEGRAL JOURNEY from a clean install, driven entirely by the D-pad remote:
//   instalación limpia → onboarding → configuración (tipo de lista) →
//   [lista cargada] → reinicio (persistencia) → home poblado → navegación
//   (rail + pestañas) → BACK → reinicio y persistencia.
//
// Reproducción / cambio de canales / recuperación ante errores se cubren con
// libmpv real en player_remote_e2e_test.dart y player_error_recovery_e2e_test.dart
// (aquí no, porque el render de píxeles de video necesita GPU). Juntos cubren la
// secuencia integral completa exigida, con eventos reales del mando.
//
// Todo headless en `flutter test` con AppInitializerScreen REAL (la misma que
// decide onboarding vs. home), sin red ni credenciales → CI-safe.
void main() {
  setUpAll(loadFonts);
  // Clean install: empty DB, no prefs (no last_playlist).
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets(
    'Viaje integral con mando: instalación limpia → onboarding → lista → home → navegación → persistencia',
    (tester) async {
      // --- 1) INSTALACIÓN LIMPIA → ONBOARDING -------------------------------
      // AppInitializerScreen es el punto de entrada real. Sin last_playlist debe
      // enrutar al onboarding (PlaylistScreen) y, en TV, autoenfocar "Crear".
      await _bootInitializer(tester);
      await shot(tester, 'journey_1_clean_onboarding.png');
      expect(find.byType(PlaylistScreen), findsOneWidget,
          reason: 'instalación limpia debe abrir el onboarding');
      expect(focusedLabel(), contains('Crear'),
          reason: 'la pantalla vacía debe autoenfocar "Crear" en TV');

      // --- 2) CONFIGURACIÓN INICIAL (elegir tipo de lista) por mando --------
      await ok(tester); // OK sobre "Crear"
      await settle(tester);
      await shot(tester, 'journey_2_type.png');
      expect(find.byType(PlaylistTypeScreen), findsOneWidget,
          reason: 'OK en Crear debe navegar a la elección de tipo de lista');
      // Explorar la pantalla de tipo con el mando (no debe perder foco).
      await down(tester);
      await right(tester);
      expect(FocusManager.instance.primaryFocus, isNotNull,
          reason: 'el foco no debe perderse navegando el tipo de lista');

      // --- 3) LISTA IPTV CARGADA -------------------------------------------
      // El final del alta de lista real persiste la playlist y la marca como
      // "última". Reproducimos ese estado (sin red/credenciales) sembrando la DB
      // y fijando la preferencia last_playlist.
      late Playlist p;
      await tester.runAsync(() async {
        p = await seedXtreamHome(harnessDb);
        await UserPreferences.setLastPlaylist(p.id);
        PlaylistService.invalidateCache();
      });

      // --- 4) REINICIO → PERSISTENCIA DE ESTADO ----------------------------
      // Un AppInitializerScreen nuevo simula reabrir la app: ahora debe restaurar
      // directamente al home de la lista cargada, sin volver al onboarding.
      await _bootInitializer(tester);
      await shot(tester, 'journey_3_restored_home.png');
      expect(find.byType(XtreamCodeHomeScreen), findsOneWidget,
          reason: 'al reiniciar con lista cargada debe restaurar su home');
      expect(find.byType(PlaylistScreen), findsNothing,
          reason: 'no debe volver al onboarding tras cargar una lista');

      // --- 5) NAVEGACIÓN por mando -----------------------------------------
      // Foco inicial en el hero (comportamiento TV comercial).
      expect(focusedInfo(), contains('Comenzar a ver'),
          reason: 'el foco inicial debe caer en el hero, no en el rail');
      // El rail lateral se alcanza con LEFT.
      await left(tester);
      bool onRail() => ['Inicio', 'Explorar', 'vivo', 'lista', 'Ajustes']
          .any((s) => focusedInfo().contains(s));
      expect(onRail(), isTrue, reason: 'el rail debe alcanzarse con LEFT');
      // Ir a "En vivo" y conmutar la pestaña; deben aparecer canales sembrados.
      for (var i = 0; i < 6 && !focusedInfo().contains('vivo'); i++) {
        await up(tester);
      }
      for (var i = 0; i < 6 && !focusedInfo().contains('vivo'); i++) {
        await down(tester);
      }
      await ok(tester);
      await settle(tester);
      await shot(tester, 'journey_4_live_tab.png');
      expect(tester.any(find.text('ESPN')), isTrue,
          reason: 'cambiar a En vivo debe mostrar canales sembrados');

      // --- 6) BACK no debe crashear ni dejar la UI en un estado roto --------
      await back(tester);
      await settle(tester);
      expect(find.byType(XtreamCodeHomeScreen), findsOneWidget,
          reason: 'BACK dentro del home no debe romper la pantalla');

      // --- 7) SEGUNDO REINICIO → persistencia estable ----------------------
      await _bootInitializer(tester);
      expect(find.byType(XtreamCodeHomeScreen), findsOneWidget,
          reason: 'la persistencia debe ser estable entre reinicios');
      // El home abre en su pestaña por defecto (hero), no en "En vivo"; el hero
      // solo se renderiza cuando el contenido de la lista cargó → prueba que la
      // lista sigue disponible tras reiniciar.
      expect(tester.any(find.text('Comenzar a ver')), isTrue,
          reason: 'el contenido de la lista sigue disponible tras reiniciar');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
