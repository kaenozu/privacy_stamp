import 'dart:ui';

enum DetectionKind {
  face,
  code,
  email,
  phone,
  postalCode,
  card,
  coordinate,
  labelledText,
  allText,
  statusRegion,
}

enum Certainty { automatic, review }

class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;

  Rect get rect => Rect.fromLTWH(left, top, width, height);
  NormalizedRect clamp() => NormalizedRect(
    left.clamp(0, 1),
    top.clamp(0, 1),
    width.clamp(0, 1 - left.clamp(0, 1)),
    height.clamp(0, 1 - top.clamp(0, 1)),
  );
  NormalizedRect padded(double horizontal, double vertical) => NormalizedRect(
    left - horizontal,
    top - vertical,
    width + horizontal * 2,
    height + vertical * 2,
  ).clamp();
}

class DetectionRegion {
  DetectionRegion({
    required this.id,
    required this.kind,
    required this.normalizedRect,
    this.confidence = 1,
    this.certainty = Certainty.automatic,
    this.reason = '',
    this.sourceDetector = 'local',
    this.isEnabled = true,
  });
  final String id;
  final DetectionKind kind;
  final NormalizedRect normalizedRect;
  final double confidence;
  final Certainty certainty;
  final String reason;
  final String sourceDetector;
  bool isEnabled;
}

class RecognizedTextRegion {
  const RecognizedTextRegion({
    required this.text,
    required this.normalizedRect,
    this.confidence = 1,
  });
  final String text;
  final NormalizedRect normalizedRect;
  final double confidence;
}

class Stamp {
  Stamp({
    required this.id,
    required this.rect,
    this.kind = 'black',
    this.isAutomatic = false,
  });
  final String id;
  NormalizedRect rect;
  String kind;
  final bool isAutomatic;
}

abstract interface class FaceRegionDetector {
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input);
}

abstract interface class TextRegionDetector {
  Future<List<RecognizedTextRegion>> detect(Uint8ListImageInput input);
}

abstract interface class CodeRegionDetector {
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input);
}

class Uint8ListImageInput {
  const Uint8ListImageInput(this.bytes, {this.mimeType});
  final List<int> bytes;
  final String? mimeType;
}
