// Driver for on-device integration runs.
//
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/capture_test.dart \
//     -d <device> --profile
//
// Screenshots requested by the test with `binding.takeScreenshot(name)` are
// written here, on the host, at the device's native resolution.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final out = File('build/screenshots/$name.png')
        ..createSync(recursive: true);
      out.writeAsBytesSync(bytes);
      stdout.writeln('screenshot: ${out.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
