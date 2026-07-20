import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

import '../integration/harness.dart';

// Exercises the 10-foot signal the way PRODUCTION reaches it.
//
// `isTenFoot` is `_isTelevisionDevice || navigationMode == directional`, and
// nothing in lib/ ever sets NavigationMode.directional — Flutter does not set it
// on Android TV either. So in a shipped build the second half is dead and the
// native flag is the whole mechanism.
//
// Every other test of this helper injected `directional`, i.e. tested only the
// branch production never takes. Deleting `_isTelevisionDevice ||` therefore
// left the entire suite green while switching the promotion off on every real
// television: the type-scale tests still passed (they inject directional), and
// the settings-clipping test still passed (smaller text fits its box even
// better). This file is the one that fails.
void main() {
  tearDown(tearDownHarness);

  testWidgets('a real television promotes type through the native flag',
      (tester) async {
    await setUpHarness(tv: true);
    expect(ResponsiveHelper.isTelevisionDevice, isTrue,
        reason: 'the harness did not actually mock a television, so nothing '
            'below is evidence');

    late double resolved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        // Traditional navigation ON PURPOSE: this asserts the native path in
        // isolation, with the directional branch unable to mask a regression.
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(navigationMode: NavigationMode.traditional),
          child: Builder(builder: (inner) {
            resolved = AppThemes.tenFoot(inner, 12);
            return const SizedBox.shrink();
          }),
        );
      }),
    ));
    expect(resolved, AppThemes.bodySmallSize,
        reason: '12dp stayed at $resolved on a device that reports itself as a '
            'television — the promotion is off where it matters most');
  });

  testWidgets('a phone does not promote through that path', (tester) async {
    await setUpHarness(tv: false);
    expect(ResponsiveHelper.isTelevisionDevice, isFalse);

    late double resolved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(navigationMode: NavigationMode.traditional),
          child: Builder(builder: (inner) {
            resolved = AppThemes.tenFoot(inner, 12);
            return const SizedBox.shrink();
          }),
        );
      }),
    ));
    expect(resolved, 12);
  });
}
