import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/l10n/app_localizations.dart';
import 'package:rensi_iptv/services/sleep_timer_service.dart';
import 'package:rensi_iptv/widgets/player-buttons/sleep_timer_widget.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      // Dark background so the white-on-black widget renders sensibly.
      backgroundColor: Colors.black,
      body: Center(child: child),
    ),
  );
}

void main() {
  setUp(() {
    // Shared singleton state must be reset between tests.
    SleepTimerService.instance.cancel();
  });

  tearDown(() {
    SleepTimerService.instance.cancel();
  });

  testWidgets('renders an outlined bedtime icon when idle', (tester) async {
    await tester.pumpWidget(_harness(const SleepTimerWidget()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bedtime), findsNothing);
  });

  testWidgets('tap opens the bottom sheet with the off row + 6 presets',
      (tester) async {
    await tester.pumpWidget(_harness(const SleepTimerWidget()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // Sheet title.
    expect(find.text('Sleep timer'), findsWidgets);
    // Off row.
    expect(find.text('Off'), findsOneWidget);
    // Each preset is rendered as "<n> min" or "<h> h" / "<h> h <m> min".
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('1 h'), findsOneWidget);
    expect(find.text('1 h 30 min'), findsOneWidget);
    expect(find.text('2 h'), findsOneWidget);
  });

  testWidgets('selecting a preset starts the service and closes the sheet',
      (tester) async {
    await tester.pumpWidget(_harness(const SleepTimerWidget()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();

    expect(SleepTimerService.instance.isActive, isTrue);
    expect(
      SleepTimerService.instance.remaining.value,
      const Duration(minutes: 30),
    );
    // The sheet is dismissed.
    expect(find.text('Off'), findsNothing);

    // Cancel before the test exits so the framework doesn't see a
    // pending periodic Timer.
    SleepTimerService.instance.cancel();
  });

  testWidgets('shows the bedtime (filled) icon + countdown chip when active',
      (tester) async {
    SleepTimerService.instance.start(const Duration(minutes: 15));

    await tester.pumpWidget(_harness(const SleepTimerWidget()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bedtime), findsOneWidget);
    expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    // Chip shows MM:SS with leading zeros (initial state: 15:00).
    expect(find.text('15:00'), findsOneWidget);

    SleepTimerService.instance.cancel();
  });

  testWidgets('Off row cancels an active timer', (tester) async {
    SleepTimerService.instance.start(const Duration(minutes: 30));

    await tester.pumpWidget(_harness(const SleepTimerWidget()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();

    expect(SleepTimerService.instance.isActive, isFalse);
    expect(SleepTimerService.instance.remaining.value, isNull);
  });

  testWidgets('formatDuration covers minutes, exact hours, and mixed',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(SleepTimerWidget.formatDuration(const Duration(minutes: 30), ctx),
        '30 min');
    expect(SleepTimerWidget.formatDuration(const Duration(hours: 1), ctx),
        '1 h');
    expect(
        SleepTimerWidget.formatDuration(
            const Duration(hours: 1, minutes: 30), ctx),
        '1 h 30 min');
    expect(SleepTimerWidget.formatDuration(const Duration(hours: 2), ctx),
        '2 h');
  });
}
