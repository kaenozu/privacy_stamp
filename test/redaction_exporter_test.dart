import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';

void main() {
  test('burns an opaque mask into a new PNG without changing source bytes', () {
    final sourceImage = img.Image(width: 4, height: 4);
    img.fill(sourceImage, color: img.ColorRgb8(255, 0, 0));
    final source = Uint8List.fromList(img.encodePng(sourceImage));
    final output = RedactionExporter().encode(source, [
      Stamp(id: 'mask', rect: const NormalizedRect(.25, .25, .5, .5)),
    ]);
    expect(output, isNot(equals(source)));
    final decoded = img.decodePng(output)!;
    expect(decoded.getPixel(1, 1).r, 0);
    expect(decoded.getPixel(0, 0).r, 255);
  });
}
