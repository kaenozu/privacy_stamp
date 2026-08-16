import 'package:flutter_test/flutter_test.dart';

import '../tool/acceptance/android_runtime_evidence.dart';

void main() {
  test('parses privacy-safe memory values from App Summary', () {
    const meminfo = '''
** MEMINFO in pid 4321 [com.privacy_stamp] **
 App Summary
                       Pss(KB)                        Rss(KB)
                        ------                         ------
           Java Heap:     1,200                          2,400
         Native Heap:     3,400                          4,800
                TOTAL:     8,500                         12,600
''';

    final sample = parseDumpsysMeminfo(meminfo);

    expect(sample.pid, 4321);
    expect(sample.totalPssKb, 8500);
    expect(sample.totalRssKb, 12600);
    expect(sample.javaHeapKb, 1200);
    expect(sample.nativeHeapKb, 3400);
  });

  test('rejects a meminfo PID that differs from the monitored process', () {
    const meminfo = '''
** MEMINFO in pid 4322 [com.privacy_stamp] **
 App Summary
                TOTAL:     8,500                         12,600
''';

    expect(
      () => parseDumpsysMeminfo(meminfo, expectedPid: 4321),
      throwsFormatException,
    );
  });

  test('aggregates peaks and fails when the process restarts', () {
    const first = AcceptanceMemorySample(
      pid: 100,
      totalPssKb: 1000,
      totalRssKb: 2000,
      javaHeapKb: 300,
      nativeHeapKb: 400,
    );
    const second = AcceptanceMemorySample(
      pid: 100,
      totalPssKb: 1500,
      totalRssKb: 2500,
      javaHeapKb: 500,
      nativeHeapKb: 450,
    );
    const restarted = AcceptanceMemorySample(
      pid: 101,
      totalPssKb: 900,
      totalRssKb: 1800,
      javaHeapKb: 250,
      nativeHeapKb: 350,
    );

    final summary = AcceptanceRuntimeSummary.fromEvidence(
      samples: const <AcceptanceMemorySample>[first, second, restarted],
      logcat: '',
      packageName: 'com.privacy_stamp',
      processAliveAfterExport: true,
    );

    expect(summary.sampleCount, 3);
    expect(summary.peakTotalPssKb, 1500);
    expect(summary.peakTotalRssKb, 2500);
    expect(summary.peakJavaHeapKb, 500);
    expect(summary.peakNativeHeapKb, 450);
    expect(summary.processRestartCount, 1);
    expect(summary.passed, isFalse);
  });

  test('detects fatal events by monitored PID without storing raw logs', () {
    const logcat = '''
08-06 10:00:01.000  4321  4500 E AndroidRuntime: FATAL EXCEPTION: main
08-06 10:00:01.010  4321  4500 E AndroidRuntime: java.lang.OutOfMemoryError
08-06 10:00:01.020  4321  4500 W lmkd: killing process due to low memory
08-06 10:00:02.000  9999  9999 E AndroidRuntime: FATAL EXCEPTION: unrelated
''';

    final events = parseRuntimeEvents(
      logcat,
      packageName: 'com.privacy_stamp',
      monitoredPids: const <int>{4321},
    );

    expect(events, contains(AcceptanceRuntimeEventType.fatalException));
    expect(events, contains(AcceptanceRuntimeEventType.outOfMemory));
    expect(events, contains(AcceptanceRuntimeEventType.lowMemoryKill));
    expect(events, hasLength(3));
  });

  test('detects package-level ANR, process death, and low-memory kill', () {
    const packageName = 'com.privacy_stamp';
    const logcat = '''
08-06 10:00:01.000  1000  1000 E ActivityManager: ANR in com.privacy_stamp
08-06 10:00:02.000  1000  1000 I ActivityManager: Process com.privacy_stamp has died
08-06 10:00:03.000  1000  1000 W lmkd: killing com.privacy_stamp due to low memory
''';

    final events = parseRuntimeEvents(
      logcat,
      packageName: packageName,
      monitoredPids: const <int>{4321},
    );

    expect(events, contains(AcceptanceRuntimeEventType.anr));
    expect(events, contains(AcceptanceRuntimeEventType.processDeath));
    expect(events, contains(AcceptanceRuntimeEventType.lowMemoryKill));
  });

  test('passes only with stable process, samples, and no fatal events', () {
    final summary = AcceptanceRuntimeSummary.fromEvidence(
      samples: const <AcceptanceMemorySample>[
        AcceptanceMemorySample(
          pid: 4321,
          totalPssKb: 8000,
          totalRssKb: 12000,
          javaHeapKb: 2000,
          nativeHeapKb: 3000,
        ),
      ],
      logcat: 'normal lifecycle output',
      packageName: 'com.privacy_stamp',
      processAliveAfterExport: true,
    );

    expect(summary.passed, isTrue);
    expect(summary.toJson()['events'], isEmpty);
  });

  test('rejects evidence without memory samples', () {
    expect(
      () => AcceptanceRuntimeSummary.fromEvidence(
        samples: const <AcceptanceMemorySample>[],
        logcat: '',
        packageName: 'com.privacy_stamp',
        processAliveAfterExport: true,
      ),
      throwsFormatException,
    );
  });
}
