import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';

import 'fixtures/privacy_image_fixture.dart';

void main() {
  final exporter = RedactionExporter();

  test(
    're-decodes PNG output without EXIF GPS, XMP, text, or filename metadata',
    () {
      final source = metadataBearingPng();
      expect(
        pngChunkTypes(source),
        containsAll(<String>['eXIf', 'iTXt', 'tEXt']),
      );
      expect(String.fromCharCodes(source), contains(fixtureSourceFileName));

      final output = exporter.encode(source, [
        Stamp(id: 'center', rect: const NormalizedRect(.25, .25, .5, .5)),
      ]);
      final decoded = img.decodePng(output);

      expect(decoded, isNotNull);
      expect(pngChunkTypes(output), isNot(contains('eXIf')));
      expect(pngChunkTypes(output), isNot(contains('iTXt')));
      expect(pngChunkTypes(output), isNot(contains('tEXt')));
      expect(
        String.fromCharCodes(output),
        isNot(contains(fixtureSourceFileName)),
      );
    },
  );

  test(
    'preserves transparent non-target pixels and makes target pixels opaque',
    () {
      final source = rgbaPng();
      final output = exporter.encode(source, [
        Stamp(id: 'right', rect: const NormalizedRect(.5, 0, .5, 1)),
      ]);
      final decoded = img.decodePng(output)!;

      final untouched = decoded.getPixel(0, 0);
      final target = decoded.getPixel(1, 0);
      expect(untouched.r, 220);
      expect(untouched.a, 0);
      expect(target.r, 0);
      expect(target.g, 0);
      expect(target.b, 0);
      expect(target.a, 255);
    },
  );

  test('re-encodes transparent images when no stamps are present', () {
    final output = exporter.encode(rgbaPng(), const <Stamp>[]);
    final decoded = img.decodePng(output)!;

    expect(decoded.width, 2);
    expect(decoded.height, 1);
    expect(decoded.getPixel(0, 0).a, 0);
    expect(decoded.getPixel(1, 0).a, 96);
  });

  test('rejects a partially outside stamp instead of silently clipping', () {
    expect(
      () => exporter.encode(solidPng(4, 4), [
        Stamp(id: 'corner', rect: const NormalizedRect(-.25, -.25, .5, .5)),
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zero-area, negative-area, and fully outside stamps', () {
    for (final stamp in <Stamp>[
      Stamp(id: 'zero', rect: const NormalizedRect(.2, .2, 0, .4)),
      Stamp(id: 'negative', rect: const NormalizedRect(.2, .2, -.1, .4)),
      Stamp(id: 'outside', rect: const NormalizedRect(1.1, 1.1, .2, .2)),
    ]) {
      expect(
        () => exporter.encode(solidPng(4, 4), [stamp]),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('re-encodes one-pixel-wide and one-pixel-tall images', () {
    for (final size in <({int width, int height})>[
      (width: 1, height: 8),
      (width: 8, height: 1),
    ]) {
      final output = exporter.encode(solidPng(size.width, size.height), [
        Stamp(id: 'edge', rect: const NormalizedRect(0, 0, 1, 1)),
      ]);
      final decoded = img.decodePng(output)!;

      expect(decoded.width, size.width);
      expect(decoded.height, size.height);
      expect(decoded.getPixel(0, 0).r, 0);
      expect(decoded.getPixel(size.width - 1, size.height - 1).r, 0);
    }
  });

  test('re-encodes a larger image with an edge stamp', () {
    final output = exporter.encode(solidPng(512, 384), [
      Stamp(id: 'edge', rect: const NormalizedRect(.75, .75, .25, .25)),
    ]);
    final decoded = img.decodePng(output);

    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 384);
    expect(decoded.getPixel(511, 383).r, 0);
    expect(decoded.getPixel(0, 0).r, 40);
  });

  test('rejects corrupt and truncated image bytes', () {
    expect(
      () => exporter.encode(
        Uint8List.fromList(<int>[0, 1, 2, 3]),
        const <Stamp>[],
      ),
      throwsA(isA<FormatException>()),
    );
    final valid = solidPng(2, 2);
    expect(
      () =>
          exporter.encode(valid.sublist(0, valid.length - 5), const <Stamp>[]),
      throwsA(isA<FormatException>()),
    );
  });
}
