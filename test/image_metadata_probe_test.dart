import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../tool/acceptance/image_metadata.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'privacy-stamp-image-probe-',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('reads JPEG dimensions without reporting GPS metadata', () async {
    final source = image.Image(width: 11, height: 7);
    final path = '${tempDirectory.path}${Platform.pathSeparator}input.jpg';
    await File(path).writeAsBytes(image.encodeJpg(source));

    final metadata = await inspectAcceptanceImage(path);

    expect(metadata.format, 'JPEG');
    expect(metadata.width, 11);
    expect(metadata.height, 7);
    expect(metadata.pixels, 77);
    expect(metadata.gpsPresent, isFalse);
  });

  test('reads clean PNG and reports no metadata container', () async {
    final source = image.Image(width: 13, height: 5);
    final path = '${tempDirectory.path}${Platform.pathSeparator}output.png';
    await File(path).writeAsBytes(image.encodePng(source));

    final metadata = await inspectAcceptanceImage(path);

    expect(metadata.format, 'PNG');
    expect(metadata.width, 13);
    expect(metadata.height, 5);
    expect(metadata.pixels, 65);
    expect(metadata.gpsPresent, isFalse);
    expect(metadata.metadataContainerPresent, isFalse);
  });

  test('rejects corrupt image data', () async {
    final path = '${tempDirectory.path}${Platform.pathSeparator}broken.png';
    await File(path).writeAsBytes(Uint8List.fromList(<int>[1, 2, 3, 4]));

    await expectLater(
      inspectAcceptanceImage(path),
      throwsA(isA<FormatException>()),
    );
  });
}
