import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

void main() {
  test('undo restores the state before manual add', () async {
    final controller = _controller();
    await controller.pickImage();

    controller.addManualStamp();
    expect(controller.manualStamps, hasLength(1));
    expect(controller.canUndoManualEdit, isTrue);

    controller.undoManualEdit();
    expect(controller.manualStamps, isEmpty);
    expect(controller.canUndoManualEdit, isFalse);
  });

  test('undo restores move, resize, and removal without touching detections', () async {
    final automatic = DetectionRegion(
      id: 'automatic-1',
      kind: DetectionKind.email,
      normalizedRect: const NormalizedRect(.05, .05, .2, .1),
    );
    final controller = _controller(detections: [automatic]);
    await controller.pickImage();
    controller.addManualStamp();
    final id = controller.manualStamps.single.id;

    final beforeMove = controller.manualStamps.single.rect;
    controller.moveManualStamp(id, const Offset(.1, .05));
    expect(controller.manualStamps.single.rect, isNot(beforeMove));
    controller.undoManualEdit();
    expect(controller.manualStamps.single.rect, beforeMove);
    expect(controller.detections.single.id, automatic.id);

    final beforeResize = controller.manualStamps.single.rect;
    controller.resizeManualStamp(id, const Offset(.1, .1));
    expect(controller.manualStamps.single.rect, isNot(beforeResize));
    controller.undoManualEdit();
    expect(controller.manualStamps.single.rect, beforeResize);
    expect(controller.detections.single.id, automatic.id);

    controller.removeManualStamp(id);
    expect(controller.manualStamps, isEmpty);
    controller.undoManualEdit();
    expect(controller.manualStamps.single.id, id);
    expect(controller.detections.single.id, automatic.id);
  });

  test('reset and image replacement clear undo state', () async {
    final picker = _SequencePicker([
      const PickedImage(
        bytes: [1, 2, 3],
        name: 'a.png',
        imageSize: PixelSize(100, 100),
      ),
      const PickedImage(
        bytes: [4, 5, 6],
        name: 'b.png',
        imageSize: PixelSize(200, 100),
      ),
    ]);
    final controller = StampController(
      picker: picker,
      detector: _Detector(const []),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _Saver(),
      history: _History(),
    );

    await controller.pickImage();
    controller.addManualStamp();
    expect(controller.canUndoManualEdit, isTrue);

    controller.reset();
    expect(controller.canUndoManualEdit, isFalse);

    await controller.pickImage();
    controller.addManualStamp();
    expect(controller.canUndoManualEdit, isTrue);

    controller.reset();
    await controller.pickImage();
    expect(controller.canUndoManualEdit, isFalse);
  });
}

StampController _controller({List<DetectionRegion> detections = const []}) =>
    StampController(
      picker: const _Picker(),
      detector: _Detector(detections),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _Saver(),
      history: _History(),
    );

class _Picker implements ImagePickerGateway {
  const _Picker();

  @override
  Future<PickedImage?> pick() async => const PickedImage(
    bytes: [1, 2, 3],
    name: 'test.png',
    imageSize: PixelSize(100, 100),
  );
}

class _SequencePicker implements ImagePickerGateway {
  _SequencePicker(this.images);
  final List<PickedImage> images;

  @override
  Future<PickedImage?> pick() async => images.removeAt(0);
}

class _Detector implements DetectionGateway {
  _Detector(this.result);
  final List<DetectionRegion> result;

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      result;
}

class _Saver implements ImageSaverGateway {
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _History implements ExportHistoryGateway {
  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
