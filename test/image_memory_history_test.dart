import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

void main() {
  test('rejects source bytes above the configured limit before decoding', () {
    final exporter = RedactionExporter(maxSourceBytes: 2);

    expect(
      () => exporter.encode(
        Uint8List.fromList(<int>[1, 2, 3]),
        <Stamp>[
          Stamp(
            id: 'mask',
            rect: const NormalizedRect(.1, .1, .2, .2),
          ),
        ],
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('asynchronous inspection rejects images above the pixel limit', () async {
    final source = img.encodePng(img.Image(width: 2, height: 2));
    final exporter = RedactionExporter(maxPixels: 3);

    await expectLater(exporter.inspect(source), throwsA(isA<FormatException>()));
  });

  test('history persistence failure does not inflate the displayed count', () async {
    final history = _History(initial: 7, failRecord: true);
    final controller = StampController(
      picker: const _Picker(),
      detector: const _Detector(),
      exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
      saver: const _Saver(),
      history: history,
    );
    await Future<void>.delayed(Duration.zero);
    await controller.pickImage();
    controller.addManualStamp();

    expect(await controller.exportImage(), ExportResult.exported);
    expect(controller.exportCount, 7);
    expect(history.recordCalls, 1);
  });

  test('successful history persistence increments the displayed count', () async {
    final history = _History(initial: 2);
    final controller = StampController(
      picker: const _Picker(),
      detector: const _Detector(),
      exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
      saver: const _Saver(),
      history: history,
    );
    await Future<void>.delayed(Duration.zero);
    await controller.pickImage();
    controller.addManualStamp();

    expect(await controller.exportImage(), ExportResult.exported);
    expect(controller.exportCount, 3);
  });
}

class _Picker implements ImagePickerGateway {
  const _Picker();

  @override
  Future<PickedImage?> pick() async => const PickedImage(
    bytes: <int>[1, 2, 3],
    name: 'source.png',
    imageSize: PixelSize(10, 10),
  );
}

class _Detector implements DetectionGateway {
  const _Detector();

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const <DetectionRegion>[];
}

class _Saver implements ImageSaverGateway {
  const _Saver();

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _History implements ExportHistoryGateway {
  _History({required this.initial, this.failRecord = false});

  final int initial;
  final bool failRecord;
  int recordCalls = 0;

  @override
  Future<int> readCount() async => initial;

  @override
  Future<void> recordExport() async {
    recordCalls++;
    if (failRecord) throw StateError('persistence failed');
  }
}
