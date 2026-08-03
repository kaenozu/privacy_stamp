import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/redaction_models.dart';

class RedactionExporter {
  Uint8List encode(
    Uint8List source,
    List<Stamp> stamps, {
    img.ImageFormat format = img.ImageFormat.png,
  }) {
    final decoded = img.decodeImage(source);
    if (decoded == null) throw const FormatException('画像を読み込めませんでした');
    final oriented = img.bakeOrientation(decoded);
    for (final stamp in stamps.where(
      (s) => s.rect.width > 0 && s.rect.height > 0,
    )) {
      final r = stamp.rect.clamp();
      final left = (r.left * oriented.width).round();
      final top = (r.top * oriented.height).round();
      final right = ((r.left + r.width) * oriented.width).round().clamp(
        left + 1,
        oriented.width,
      );
      final bottom = ((r.top + r.height) * oriented.height).round().clamp(
        top + 1,
        oriented.height,
      );
      final color = stamp.kind == 'white'
          ? img.ColorRgb8(255, 255, 255)
          : img.ColorRgb8(0, 0, 0);
      img.fillRect(
        oriented,
        x1: left,
        y1: top,
        x2: right - 1,
        y2: bottom - 1,
        color: color,
      );
    }
    return Uint8List.fromList(img.encodePng(oriented));
  }
}
