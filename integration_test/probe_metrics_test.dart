// Diagnostic probe: reports the device's real metrics and what the responsive
// layer decides from them. Screenshots alone cannot tell you whether a layout
// rule failed to apply or simply never bound.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

import '../test/integration/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => setUpHarness());
  tearDown(tearDownHarness);

  testWidgets('report device metrics and layout decisions', (tester) async {
    late Size logical;
    late double dpr;
    late bool isTv;
    late double inset;
    late double maxWidth;

    await pumpScreen(
      tester,
      Builder(builder: (context) {
        final mq = MediaQuery.of(context);
        logical = mq.size;
        dpr = mq.devicePixelRatio;
        isTv = ResponsiveHelper.isDesktopOrTV(context);
        inset = ResponsiveHelper.safeInset(context);
        maxWidth = ResponsiveHelper.tvMaxContentWidth(context);
        return RensiSafeColumn(
          child: Container(key: const Key('probe'), color: Colors.red),
        );
      }),
      size: null,
    );
    await tester.pumpAndSettle();

    final w = tester.getSize(find.byKey(const Key('probe'))).width;
    debugPrint('PROBE logical=${logical.width}x${logical.height} dpr=$dpr '
        'nativeTvFlag=${ResponsiveHelper.isTelevisionDevice} isDesktopOrTV=$isTv '
        'safeInset=$inset maxContentWidth=$maxWidth '
        'measuredContentWidth=$w');
    expect(w, greaterThan(0));
  });
}
