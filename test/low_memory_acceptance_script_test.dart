import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses the prebuilt APK for emulator acceptance', () {
    final script = File(
      '.github/scripts/run-low-memory-acceptance.sh',
    ).readAsStringSync();

    expect(script, contains('flutter drive'));
    expect(script, contains('--no-pub'));
    expect(script, contains('--driver=test_driver/integration_test.dart'));
    expect(script, contains(r'--use-application-binary="$apk_path"'));
    expect(
      script,
      isNot(contains('flutter test -d emulator-5554 integration_test/')),
    );

    final integrationTest = File(
      'integration_test/synthetic_low_memory_acceptance_test.dart',
    ).readAsStringSync();
    expect(
      integrationTest,
      isNot(contains('pumpAndSettle()')),
      reason: 'The low-memory 48MP route must use bounded waits.',
    );
  });
}
