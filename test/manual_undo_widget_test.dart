import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';
import 'package:privacy_stamp/main.dart';

void main() {
  testWidgets('undo button restores the previous manual mask state', (
    tester,
  ) async {
    final controller = StampController(
      picker: const _Picker(),
      detector: _Detector(),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _Saver(),
      history: _History(),
    );

    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );
    await controller.pickImage();
    await tester.pump();

    final undoButton = find.text('元に戻す');
    expect(undoButton, findsOneWidget);

    await tester.tap(find.text('手動スタンプを追加'));
    await tester.pump();
    expect(controller.manualStamps, hasLength(1));

    await tester.tap(undoButton);
    await tester.pump();
    expect(controller.manualStamps, isEmpty);
  });
}

class _Picker implements ImagePickerGateway {
  const _Picker();

  @override
  Future<PickedImage?> pick() async => const PickedImage(
    bytes: [1, 2, 3],
    name: 'test.png',
    imageSize: PixelSize(100, 100),
  );
}

class _Detector implements DetectionGateway {
  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const [];
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
