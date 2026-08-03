import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';

void main() {
  test(
    'burns an opaque black mask into a new PNG without changing source bytes',
    () {
      final sourceImage = img.Image(width: 4, height: 4);
      img.fill(sourceImage, color: img.ColorRgb8(255, 0, 0));
      final source = Uint8List.fromList(img.encodePng(sourceImage));
      final sourceCopy = Uint8List.fromList(source);
      final output = RedactionExporter().encode(source, [
        Stamp(id: 'mask', rect: const NormalizedRect(.25, .25, .5, .5)),
      ]);
      expect(output, isNot(equals(source)));
      expect(source, orderedEquals(sourceCopy));
      final decoded = img.decodePng(output)!;
      expect(decoded.getPixel(1, 1).r, 0);
      expect(decoded.getPixel(1, 1).g, 0);
      expect(decoded.getPixel(1, 1).b, 0);
      expect(decoded.getPixel(1, 1).a, 255);
      expect(decoded.getPixel(0, 0).r, 255);
      expect(decoded.getPixel(0, 0).a, 255);
      expect(img.decodePng(source)!.getPixel(1, 1).r, 255);
    },
  );

  test('writes an opaque white mask and keeps pixels outside the mask', () {
    final sourceImage = img.Image(width: 4, height: 4);
    img.fill(sourceImage, color: img.ColorRgb8(12, 34, 56));
    final source = Uint8List.fromList(img.encodePng(sourceImage));

    final output = RedactionExporter().encode(source, [
      Stamp(
        id: 'white-mask',
        kind: 'white',
        rect: const NormalizedRect(.5, .5, .5, .5),
      ),
    ]);

    final decoded = img.decodePng(output)!;
    expect(decoded.getPixel(2, 2).r, 255);
    expect(decoded.getPixel(2, 2).g, 255);
    expect(decoded.getPixel(2, 2).b, 255);
    expect(decoded.getPixel(2, 2).a, 255);
    expect(decoded.getPixel(1, 1).r, 12);
    expect(decoded.getPixel(1, 1).g, 34);
    expect(decoded.getPixel(1, 1).b, 56);
    expect(decoded.getPixel(1, 1).a, 255);
  });

  test('rejects invalid mask geometry instead of silently exporting', () {
    final source = _png(width: 4, height: 4, color: const [255, 0, 0]);
    final invalidRects = <NormalizedRect>[
      const NormalizedRect(double.nan, 0, .5, .5),
      const NormalizedRect(0, 0, double.infinity, .5),
      const NormalizedRect(-.1, 0, .5, .5),
      const NormalizedRect(.2, .2, -.1, .5),
      const NormalizedRect(.8, .8, .3, .3),
      const NormalizedRect(.2, .2, 0, .5),
      const NormalizedRect(.2, .2, .5, 0),
      const NormalizedRect(.2, .2, .1, .5),
    ];

    for (final rect in invalidRects) {
      expect(
        () => RedactionExporter().encode(source, [
          Stamp(id: 'invalid', rect: rect),
        ]),
        throwsA(isA<FormatException>()),
        reason: 'Expected $rect to be rejected',
      );
    }
  });

  test('maps all four normalized corners to their corresponding pixels', () {
    final source = _png(width: 4, height: 4, color: const [255, 0, 0]);
    const corners = <NormalizedRect>[
      NormalizedRect(0, 0, .25, .25),
      NormalizedRect(.75, 0, .25, .25),
      NormalizedRect(0, .75, .25, .25),
      NormalizedRect(.75, .75, .25, .25),
    ];
    const pixels = <List<int>>[
      [0, 0],
      [3, 0],
      [0, 3],
      [3, 3],
    ];

    for (var i = 0; i < corners.length; i++) {
      final output = RedactionExporter().encode(source, [
        Stamp(id: 'corner-$i', rect: corners[i]),
      ]);
      final decoded = img.decodePng(output)!;
      expect(decoded.getPixel(pixels[i][0], pixels[i][1]).r, 0);
      expect(decoded.getPixel(1, 1).r, 255);
    }
  });

  test('rejects corrupt, empty, and zero-sized image input', () {
    final exporter = RedactionExporter();
    final stamp = <Stamp>[
      Stamp(id: 'mask', rect: const NormalizedRect(.25, .25, .5, .5)),
    ];

    expect(
      () => exporter.encode(Uint8List(0), stamp),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => exporter.encode(Uint8List.fromList([1, 2, 3, 4]), stamp),
      throwsA(isA<FormatException>()),
    );

    final zeroSized = img.Image(width: 0, height: 0);
    expect(
      () =>
          exporter.encode(Uint8List.fromList(img.encodePng(zeroSized)), stamp),
      throwsA(isA<FormatException>()),
    );
  });

  test('bakes EXIF orientation before applying normalized coordinates', () {
    for (final orientation in [3, 6, 8]) {
      final source = _jpegWithOrientation(orientation);
      final orientedSource = img.bakeOrientation(img.decodeImage(source)!);
      final output = RedactionExporter().encode(source, [
        Stamp(id: 'top-left', rect: const NormalizedRect(0, 0, .5, .5)),
      ]);

      final decoded = img.decodePng(output)!;
      final expectedSize = orientation == 3
          ? const PixelSize(2, 3)
          : const PixelSize(3, 2);
      expect(
        decoded.width,
        expectedSize.width,
        reason: 'orientation $orientation',
      );
      expect(
        decoded.height,
        expectedSize.height,
        reason: 'orientation $orientation',
      );
      expect(
        decoded.getPixel(0, 0).r,
        lessThan(10),
        reason: 'orientation $orientation',
      );
      var blueX = 0;
      var blueY = 0;
      num blueDelta = -1;
      for (var y = 0; y < orientedSource.height; y++) {
        for (var x = 0; x < orientedSource.width; x++) {
          final pixel = orientedSource.getPixel(x, y);
          final delta = pixel.b - pixel.r;
          if (delta > blueDelta) {
            blueDelta = delta;
            blueX = x;
            blueY = y;
          }
        }
      }
      final blue = decoded.getPixel(blueX, blueY);
      expect(blue.b, greaterThan(blue.r), reason: 'orientation $orientation');
    }
  });
}

Uint8List _png({
  required int width,
  required int height,
  required List<int> color,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(color[0], color[1], color[2]));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _jpegWithOrientation(int orientation) {
  final image = img.Image(width: 2, height: 3);
  img.fill(image, color: img.ColorRgb8(240, 20, 20));
  image.setPixel(0, 0, img.ColorRgb8(0, 0, 240));
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 100));
  final exif = img.ExifData()..imageIfd.orientation = orientation;
  return img.injectJpgExif(jpeg, exif)!;
}
