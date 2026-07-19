import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';

// Regression guard for the app's ErrorWidget.builder.
//
// Flutter's stock error widget is a bare RenderErrorBox because it cannot rely
// on inherited widgets. A builder that uses Text() needs a Directionality
// ancestor; when the error is thrown ABOVE that ancestor, Text throws "No
// Directionality widget found", which re-enters the builder and recurses
// forever. That is not theoretical: an earlier version of this guard hung the
// test runner for 200s and emitted 8.5 MB of output.
class _Boom extends StatelessWidget {
  const _Boom();

  @override
  Widget build(BuildContext context) =>
      throw Exception('Failed to open http://h:8080/live/juan/s3cr3tpass/1.ts');
}

// Mirrors the builder installed in main.dart.
Widget _errorWidgetBuilder(FlutterErrorDetails details) => Directionality(
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

void main() {
  late ErrorWidgetBuilder original;

  setUp(() {
    original = ErrorWidget.builder;
    ErrorWidget.builder = _errorWidgetBuilder;
  });

  tearDown(() => ErrorWidget.builder = original);

  testWidgets('renders without a Directionality ancestor and does not recurse',
      (tester) async {
    // No MaterialApp on purpose — this is the startup/MaterialApp.builder case.
    await tester.pumpWidget(const _Boom());
    expect(tester.takeException(), isNotNull);
    expect(find.byType(Directionality), findsWidgets);
  });

  testWidgets('the message it shows is scrubbed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Boom()));
    tester.takeException();
    expect(find.textContaining('s3cr3tpass'), findsNothing);
    expect(find.textContaining('***'), findsOneWidget);
  });
}
