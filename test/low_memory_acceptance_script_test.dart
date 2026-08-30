import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses the prebuilt integration-test APK for emulator acceptance', () {
    final script = File(
      '.github/scripts/run-low-memory-acceptance.sh',
    ).readAsStringSync();
    final workflow = File(
      '.github/workflows/local-acceptance-scripts.yml',
    ).readAsStringSync();

    expect(script, contains('flutter drive'));
    expect(script, contains('--no-pub'));
    expect(script, contains('--driver=test_driver/integration_test.dart'));
    expect(
      script,
      contains(r'--use-application-binary="$integration_apk_path"'),
    );
    expect(
      workflow,
      contains(
        'flutter build apk --debug --target=integration_test/'
        'synthetic_low_memory_acceptance_test.dart',
      ),
      reason: 'The reused APK must contain the integration-test entry point.',
    );
    expect(
      workflow,
      contains('app-debug-integration.apk'),
    );
    expect(
      workflow,
      contains('app-debug-main.apk'),
      reason: 'Lifecycle D must restore and launch the production entry point.',
    );
    expect(
      script.indexOf(r'adb install -r "$main_apk_path"'),
      lessThan(script.indexOf("printf 'Running D:")),
    );
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

  test('does not contend with flutter drive while VM service starts', () {
    final script = File(
      '.github/scripts/run-low-memory-acceptance.sh',
    ).readAsStringSync();

    expect(
      script,
      contains(r'''grep -q 'ACCEPTANCE_MILESTONE .* A:start' "$log"'''),
      reason: 'ADB memory sampling must wait until flutter drive is attached.',
    );
    expect(
      script.indexOf("grep -q 'ACCEPTANCE_MILESTONE .* A:start'"),
      lessThan(script.indexOf(r'pid=$(adb shell pidof')),
    );
  });
}
