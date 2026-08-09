import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/acceptance/generate_synthetic_fixture.dart <output>',
    );
    exitCode = 64;
    return;
  }

  try {
    final bytes = await generateSyntheticHighResolutionJpeg();
    await File(arguments.single).writeAsBytes(bytes);
    stdout.writeln('Generated ${bytes.length} bytes.');
  } on Object catch (error) {
    stderr.writeln('Synthetic fixture generation failed: $error');
    exitCode = 1;
  }
}

Future<Uint8List> generateSyntheticHighResolutionJpeg() async {
  final width = 6000;
  final height = 8000;
  final pixels = width * height;

  if (pixels < 40000000) {
    throw FormatException(
      'Synthetic fixture must be at least 40MP: $pixels pixels.',
    );
  }

  final src = image.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = _pixelColor(width, height, x, y);
      src.setPixelRgba(x, y, color.r, color.g, color.b, 255);
    }
  }

  final jpeg = Uint8List.fromList(image.encodeJpg(src, quality: 95));

  final exif = image.ExifData();
  exif.imageIfd.orientation = 1;
  exif.gpsIfd.gpsLatitudeRef = 'N';
  exif.gpsIfd.gpsLatitude = 35.0;
  exif.gpsIfd.gpsLongitudeRef = 'E';
  exif.gpsIfd.gpsLongitude = 140.0;

  final withExif = image.injectJpgExif(jpeg, exif);
  if (withExif == null) {
    throw FormatException('Failed to inject EXIF into synthetic JPEG.');
  }

  return withExif;
}

_SyntheticColor _pixelColor(int width, int height, int x, int y) {
  final cornerSize = 400;
  final centerBandWidth = 120;
  final centerBandHeight = 80;

  final isTopLeft = x < cornerSize && y < cornerSize;
  final isTopRight = x >= width - cornerSize && y < cornerSize;
  final isBottomLeft = x < cornerSize && y >= height - cornerSize;
  final isBottomRight = x >= width - cornerSize && y >= height - cornerSize;

  if (isTopLeft) {
    return const _SyntheticColor(240, 60, 60);
  } else if (isTopRight) {
    return const _SyntheticColor(60, 240, 60);
  } else if (isBottomLeft) {
    return const _SyntheticColor(60, 60, 240);
  } else if (isBottomRight) {
    return const _SyntheticColor(240, 180, 40);
  }

  final centerX = width ~/ 2;
  final centerY = height ~/ 2;
  final inCenterBandX =
      x >= centerX - centerBandWidth ~/ 2 && x < centerX + centerBandWidth ~/ 2;
  final inCenterBandY =
      y >= centerY - centerBandHeight ~/ 2 &&
      y < centerY + centerBandHeight ~/ 2;

  if (inCenterBandX && inCenterBandY) {
    final dx = (x - (centerX - centerBandWidth ~/ 2)) / centerBandWidth;
    final dy = (y - (centerY - centerBandHeight ~/ 2)) / centerBandHeight;
    final r = (dx * 255).round();
    final g = (dy * 255).round();
    final b = (128 + (dx * 127)).round();
    return _SyntheticColor(r, g, b);
  }

  final horizontalGradient = (x / width * 80 + 40).round();
  final verticalGradient = (y / height * 60 + 30).round();
  return _SyntheticColor(horizontalGradient, verticalGradient, 100);
}

class _SyntheticColor {
  const _SyntheticColor(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
}
