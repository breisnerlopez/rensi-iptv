import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/widgets/channel_number_overlay.dart';

Widget _harness(ValueNotifier<String> buffer) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          ChannelNumberOverlay(buffer: buffer),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('renders nothing when buffer is empty', (tester) async {
    final buffer = ValueNotifier<String>('');
    await tester.pumpWidget(_harness(buffer));
    await tester.pumpAndSettle();
    // The overlay itself exists but renders SizedBox.shrink; no big text.
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows the digits when buffer is non-empty', (tester) async {
    final buffer = ValueNotifier<String>('42');
    await tester.pumpWidget(_harness(buffer));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('reacts to buffer value changes', (tester) async {
    final buffer = ValueNotifier<String>('');
    await tester.pumpWidget(_harness(buffer));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);

    buffer.value = '7';
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);

    buffer.value = '70';
    await tester.pumpAndSettle();
    expect(find.text('70'), findsOneWidget);

    buffer.value = '';
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('digit text has at least one IgnorePointer(ignoring:true) '
      'ancestor', (tester) async {
    final buffer = ValueNotifier<String>('5');
    await tester.pumpWidget(_harness(buffer));
    await tester.pumpAndSettle();

    // The Scaffold introduces other IgnorePointers in the ancestry chain;
    // we just need to confirm that our overlay's own IgnorePointer (the one
    // that actually ignores) is present.
    final hits = find
        .ancestor(
          of: find.text('5'),
          matching: find.byWidgetPredicate(
            (w) => w is IgnorePointer && w.ignoring == true,
          ),
        )
        .evaluate();
    expect(hits, isNotEmpty);
  });
}
