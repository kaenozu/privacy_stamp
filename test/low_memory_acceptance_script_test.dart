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
    expect(workflow, contains('app-debug-integration.apk'));
    expect(
      workflow,
      contains('app-debug-main.apk'),
      reason: 'Lifecycle D must restore and launch the production entry point.',
    );
    expect(
      script.indexOf(r'install_apk_with_retry "$main_apk_path" production'),
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

  test(
    'recovers bounded transient ADB transport failures without weakening AVD',
    () {
      final script = File(
        '.github/scripts/run-low-memory-acceptance.sh',
      ).readAsStringSync();
      final workflow = File(
        '.github/workflows/local-acceptance-scripts.yml',
      ).readAsStringSync();

      expect(script, contains('install_apk_with_retry'));
      expect(script, contains('for attempt in 1 2 3'));
      expect(script, contains('adb reconnect'));
      expect(script, contains('adb kill-server'));
      expect(script, contains('adb shell cmd package list packages'));
      expect(script, contains('capture_adb_failure_diagnostics'));
      expect(script, contains(r'"${prefix}-logcat.txt"'));
      expect(
        script,
        contains(
          r'install_apk_with_retry "$integration_apk_path" integration-test',
        ),
      );
      expect(workflow, contains('api-level: 35'));
      expect(workflow, contains('arch: x86_64'));
      expect(workflow, contains('ram-size: 1536'));
      expect(workflow, contains('emulator-boot-timeout: 900'));
      expect(
        workflow,
        contains('script: bash .github/scripts/run-low-memory-acceptance.sh'),
      );
    },
  );

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

  test('samples PSS without invoking the application dump callback', () {
    final script = File(
      '.github/scripts/run-low-memory-acceptance.sh',
    ).readAsStringSync();

    expect(
      script,
      contains(r'adb shell dumpsys meminfo --local "$package"'),
      reason: 'PSS collection must stay local to system_server.',
    );
    expect(
      script,
      isNot(contains(r'adb shell dumpsys meminfo "$package"')),
      reason: 'Regular dumpsys meminfo can force explicit GC in the app.',
    );
  });
}
