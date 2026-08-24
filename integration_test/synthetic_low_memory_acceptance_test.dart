import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';
import 'package:privacy_stamp/main.dart';

import '../tool/acceptance/image_metadata.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '48MP synthetic GPS input survives mask/export on a low-memory AVD',
    (tester) async {
      final fixture = await rootBundle.load(
        'test/fixtures/synthetic-high-res-avd.jpg',
      );
      final source = fixture.buffer.asUint8List();
      final sourceInfo = await _inspectBytes(source, 'synthetic-input.jpg');
      expect(sourceInfo.format, 'JPEG');
      expect(sourceInfo.pixels, greaterThanOrEqualTo(40000000));
      expect(sourceInfo.gpsPresent, isTrue);

      final saver = _CapturingSaver();
      final controller = StampController(
        picker: const _NoopPicker(),
        detector: const _NoopDetector(),
        exporter: const RedactionExporter().encodeAsync,
        saver: saver,
        history: const _InMemoryHistory(),
      );
      controller.loadImageForTesting(
        source,
        'synthetic-high-res-avd.jpg',
        PixelSize(sourceInfo.width, sourceInfo.height),
      );

      await tester.pumpWidget(
        MaterialApp(home: StampHomePage(controller: controller)),
      );
      await _pumpBounded(tester);
      expect(controller.imageSize, const PixelSize(6000, 8000));
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.byType(Image));
      await _pumpBounded(tester);
      expect(controller.manualStamps, hasLength(1));

      final exportButton = find.widgetWithText(FilledButton, '書き出す');
      expect(exportButton, findsOneWidget);
      await tester.tap(exportButton);
      await _pumpBounded(tester, frames: 80);

      expect(controller.exportCount, 1);
      final output = saver.bytes;
      expect(output, isNotNull);
      final outputInfo = await _inspectBytes(output!, 'synthetic-output.png');
      expect(outputInfo.format, 'PNG');
      expect(outputInfo.pixels, sourceInfo.pixels);
      expect(outputInfo.gpsPresent, isFalse);
      expect(outputInfo.metadataContainerPresent, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<AcceptanceImageMetadata> _inspectBytes(
  Uint8List bytes,
  String name,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'privacy-stamp-acceptance-',
  );
  final file = File('${directory.path}/$name');
  try {
    await file.writeAsBytes(bytes);
    return inspectAcceptanceImage(file.path);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> _pumpBounded(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _CapturingSaver implements ImageSaverGateway {
  Uint8List? bytes;

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async {
    this.bytes = bytes;
    return true;
  }
}

class _NoopPicker implements ImagePickerGateway {
  const _NoopPicker();

  @override
  Future<PickedImage?> pick() async => null;
}

class _NoopDetector implements DetectionGateway {
  const _NoopDetector();

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const [];
}

class _InMemoryHistory implements ExportHistoryGateway {
  const _InMemoryHistory();

  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
