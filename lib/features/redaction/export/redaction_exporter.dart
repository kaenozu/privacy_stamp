import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/redaction_models.dart';

class RedactionExporter {
  /// Encodes a new opaque PNG after baking EXIF orientation and applying masks.
  ///
  /// The source bytes and decoded source image are never mutated. Every mask
  /// must already be a finite, positive rectangle within the normalized image;
  /// invalid masks throw [FormatException] rather than being skipped/clipped.
  Uint8List encode(Uint8List source, List<Stamp> stamps) {
    if (source.isEmpty) throw const FormatException('画像データが空です');

    final decoded = _decode(source);
    if (decoded.width <= 0 || decoded.height <= 0) {
      throw const FormatException('画像サイズが0pxです');
    }

    final oriented = img.bakeOrientation(decoded);
    if (oriented.width <= 0 || oriented.height <= 0) {
      throw const FormatException('回転後の画像サイズが0pxです');
    }

    // The output is a fresh privacy boundary. Do not carry EXIF, ICC, or
    // textual/XMP metadata from the decoded input into the PNG encoder.
    oriented.exif = img.ExifData();
    oriented.iccProfile = null;
    oriented.textData = null;

    // The exporter operates in the same physical, orientation-baked image
    // space as the editor's normalized coordinates.
    final layout = ImageDisplayLayout.contain(
      imageSize: PixelSize(oriented.width, oriented.height),
      canvasSize: Size(oriented.width.toDouble(), oriented.height.toDouble()),
    );
    final masks = <(Stamp, PixelRect)>[];
    for (final stamp in stamps) {
      final pixels = layout.pixelRectFromNormalized(stamp.rect);
      masks.add((stamp, pixels));
    }

    for (final (stamp, pixels) in masks) {
      final color = switch (stamp.kind) {
        'white' => img.ColorRgb8(255, 255, 255),
        'black' => img.ColorRgb8(0, 0, 0),
        _ => throw FormatException('未対応のマスク色です: ${stamp.kind}'),
      };
      img.fillRect(
        oriented,
        x1: pixels.left,
        y1: pixels.top,
        x2: pixels.right - 1,
        y2: pixels.bottom - 1,
        color: color,
      );
    }

    final output = Uint8List.fromList(img.encodePng(oriented));
    if (output.isEmpty || img.decodePng(output) == null) {
      throw const FormatException('PNGを書き出せませんでした');
    }
    return output;
  }

  img.Image _decode(Uint8List source) {
    try {
      final decoded = img.decodeImage(source);
      if (decoded == null) throw const FormatException('画像を読み込めませんでした');
      return decoded;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('画像を読み込めませんでした: $error');
    }
  }
}
