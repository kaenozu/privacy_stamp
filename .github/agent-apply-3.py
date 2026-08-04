from pathlib import Path
import subprocess

exporter = Path('lib/features/redaction/export/redaction_exporter.dart')
text = exporter.read_text(encoding='utf-8')
old = '''List<int> _inspectImage(Map<String, Object> payload) {
  final oriented = _decodeAndOrient(
    payload['source']! as Uint8List,
    maxSourceBytes: payload['maxSourceBytes']! as int,
    maxPixels: payload['maxPixels']! as int,
  );
  return <int>[oriented.width, oriented.height];
}
'''
new = '''List<int> _inspectImage(Map<String, Object> payload) {
  final source = payload['source']! as Uint8List;
  final maxSourceBytes = payload['maxSourceBytes']! as int;
  final maxPixels = payload['maxPixels']! as int;
  if (source.isEmpty) throw const FormatException('画像データが空です');
  if (source.lengthInBytes > maxSourceBytes) {
    throw const FormatException('画像ファイルが大きすぎます');
  }

  try {
    final decoder = img.findDecoderForData(source);
    if (decoder == null || !decoder.isValidFile(source)) {
      throw const FormatException('画像を読み込めませんでした');
    }
    final info = decoder.startDecode(source);
    if (info == null || info.numFrames < 1) {
      throw const FormatException('画像を読み込めませんでした');
    }
    _validateDimensions(info.width, info.height, maxPixels: maxPixels);

    var width = info.width;
    var height = info.height;
    final orientation = img.decodeJpgExif(source)?.imageIfd.orientation;
    if (orientation == 5 ||
        orientation == 6 ||
        orientation == 7 ||
        orientation == 8) {
      final originalWidth = width;
      width = height;
      height = originalWidth;
    }
    _validateDimensions(width, height, maxPixels: maxPixels);
    return <int>[width, height];
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('画像を読み込めませんでした');
  }
}
'''
if text.count(old) != 1:
    raise SystemExit(f'inspect block count={text.count(old)}')
exporter.write_text(text.replace(old, new, 1), encoding='utf-8')

Path('lib/features/redaction/presentation/image_decode_policy.dart').write_text('''import 'dart:math' as math;
import 'dart:ui';

import '../models/redaction_models.dart';

class DecodeTarget {
  const DecodeTarget(this.width, this.height);

  final int width;
  final int height;
}

/// Bounds editor decoding by the physical viewport and a hard safety ceiling.
///
/// A small overscan keeps moderate zoom crisp without decoding the full source
/// image. The source aspect ratio is preserved and small images are not
/// upscaled.
DecodeTarget editorDecodeTarget({
  required PixelSize imageSize,
  required Size canvasSize,
  required double devicePixelRatio,
  double overscan = 1.5,
  int maxDimension = 4096,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    throw ArgumentError('Image dimensions must be positive');
  }
  if (maxDimension <= 0 || overscan <= 0 || !overscan.isFinite) {
    throw ArgumentError('Invalid decode policy');
  }

  final canvasWidth = canvasSize.width.isFinite
      ? math.max(1.0, canvasSize.width)
      : 1.0;
  final canvasHeight = canvasSize.height.isFinite
      ? math.max(1.0, canvasSize.height)
      : 1.0;
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final sourceWidth = imageSize.width.toDouble();
  final sourceHeight = imageSize.height.toDouble();

  final scale = math.min(
    1.0,
    math.min(
      maxDimension / math.max(sourceWidth, sourceHeight),
      math.min(
        canvasWidth * dpr * overscan / sourceWidth,
        canvasHeight * dpr * overscan / sourceHeight,
      ),
    ),
  );

  return DecodeTarget(
    math.max(1, (sourceWidth * scale).round()),
    math.max(1, (sourceHeight * scale).round()),
  );
}
''', encoding='utf-8')

main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
import_marker = "import 'features/redaction/models/redaction_models.dart';\n"
policy_import = "import 'features/redaction/presentation/image_decode_policy.dart';\n"
if policy_import not in text:
    if text.count(import_marker) != 1:
        raise SystemExit(f'main import marker count={text.count(import_marker)}')
    text = text.replace(import_marker, import_marker + policy_import, 1)
old = '''                Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Text('画像を表示できません')),
                ),
'''
new = '''                Builder(
                  builder: (context) {
                    final target = editorDecodeTarget(
                      imageSize: imageSize,
                      canvasSize: canvasSize,
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    );
                    return Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      cacheWidth: target.width,
                      cacheHeight: target.height,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Text('画像を表示できません')),
                    );
                  },
                ),
'''
if text.count(old) != 1:
    raise SystemExit(f'Image.memory block count={text.count(old)}')
main.write_text(text.replace(old, new, 1), encoding='utf-8')

Path('test/image_decode_policy_test.dart').write_text('''import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/image_decode_policy.dart';

void main() {
  group('editorDecodeTarget', () {
    test('bounds a 48MP source by the physical editor viewport', () {
      final target = editorDecodeTarget(
        imageSize: const PixelSize(8000, 6000),
        canvasSize: const Size(640, 520),
        devicePixelRatio: 3,
      );

      expect(target.width, 2880);
      expect(target.height, 2160);
      expect(target.width * target.height, lessThan(8000 * 6000));
      expect(target.width, lessThanOrEqualTo(4096));
    });

    test('does not upscale small images', () {
      final target = editorDecodeTarget(
        imageSize: const PixelSize(320, 240),
        canvasSize: const Size(640, 520),
        devicePixelRatio: 3,
      );
      expect(target.width, 320);
      expect(target.height, 240);
    });

    test('handles invalid viewport values safely', () {
      final target = editorDecodeTarget(
        imageSize: const PixelSize(8000, 6000),
        canvasSize: const Size(double.infinity, double.nan),
        devicePixelRatio: double.infinity,
      );
      expect(target.width, 2);
      expect(target.height, 2);
    });
  });

  test('lightweight inspection preserves JPEG orientation dimensions', () async {
    final source = img.encodeJpg(img.Image(width: 2, height: 3));
    final exif = img.ExifData()..imageIfd.orientation = 6;
    final orientedSource = img.injectJpgExif(source, exif);
    expect(orientedSource, isNotNull);

    final size = await const RedactionExporter().inspect(orientedSource!);
    expect(size.width, 3);
    expect(size.height, 2);
  });

  test('inspection implementation never decodes a full frame', () {
    final source = File(
      'lib/features/redaction/export/redaction_exporter.dart',
    ).readAsStringSync();
    final start = source.indexOf('List<int> _inspectImage');
    final end = source.indexOf('Uint8List _encodeRedaction', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final inspection = source.substring(start, end);
    expect(inspection, contains('startDecode'));
    expect(inspection, isNot(contains('decodeFrame')));
    expect(inspection, isNot(contains('_decodeAndOrient')));
  });
}
''', encoding='utf-8')

Path('.github/workflows/flutter-quality.yml').write_bytes(
    subprocess.check_output(['git', 'show', 'origin/main:.github/workflows/flutter-quality.yml'])
)
Path(__file__).unlink(missing_ok=True)
