import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../models/redaction_models.dart';

/// No platform detector available (e.g. Web). Never throws, never detects.
///
/// Keeping a no-op default preserves the local-only boundary: no bytes leave
/// the device looking for a remote inference endpoint.
class NoopFaceDetector implements FaceRegionDetector {
  const NoopFaceDetector();

  @override
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input) async =>
      const [];
}

/// On-device face detection via Google ML Kit (Android/iOS, Play Services).
///
/// - Runs fully on-device; image bytes are never uploaded by this adapter.
/// - Detection runs on a downscaled (max [maxDetectionDimension] px) oriented
///   copy, so a 40MP+ source does not blow the heap. Returned boxes are mapped
///   back through normalized coordinates, which are resolution-independent.
/// - The copy is repacked to NV21, the byte format accepted by on-device ML
///   Kit (`fromBytes` rejects BGRA on Play Services runtimes).
/// - Any failure (missing plugin on Web/desktop, missing Play Services model,
///   corrupt bytes) yields `[]`. The controller keeps the image editable and
///   surfaces a "check manually" notice instead of discarding user work.
/// - Boxes are expanded by [paddingHorizontal]/[paddingVertical] so hairline
///   and chin edges stay covered.
class MlKitFaceDetector implements FaceRegionDetector {
  MlKitFaceDetector({
    this.maxDetectionDimension = 1024,
    this.paddingHorizontal = .02,
    this.paddingVertical = .03,
  });

  final int maxDetectionDimension;
  final double paddingHorizontal;
  final double paddingVertical;

  @override
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input) async {
    if (kIsWeb) return const [];
    try {
      final prepared = await compute(_prepareNv21, <String, Object>{
        'source': Uint8List.fromList(input.bytes),
        'maxDimension': maxDetectionDimension,
      });
      if (prepared == null) return const [];
      final bytes = prepared['bytes']! as Uint8List;
      final width = prepared['width']! as int;
      final height = prepared['height']! as int;

      final mlKitInput = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );
      final detector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
      );
      try {
        final faces = await detector.processImage(mlKitInput);
        final regions = <DetectionRegion>[];
        for (var i = 0; i < faces.length; i++) {
          final box = faces[i].boundingBox;
          final normalized = NormalizedRect(
            box.left / width,
            box.top / height,
            box.width / width,
            box.height / height,
          ).clamp().padded(paddingHorizontal, paddingVertical);
          if (!normalized.hasPositiveArea) continue;
          regions.add(
            DetectionRegion(
              id: 'face-$i',
              kind: DetectionKind.face,
              normalizedRect: normalized,
              reason: '顔の候補',
              sourceDetector: 'mlkit-face',
            ),
          );
        }
        return regions;
      } finally {
        await detector.close();
      }
    } catch (_) {
      // MissingPluginException (desktop/test), model download failure,
      // corrupt input: all degrade to "no automatic suggestions".
      return const [];
    }
  }
}

/// Decode, orient, downscale, and repack as NV21 for ML Kit.
///
/// NV21 requires even dimensions; odd edges are cropped by one pixel.
/// Returns `null` when the source cannot be decoded. Runs in a background
/// isolate via [compute]; keep this a top-level function.
Map<String, Object>? _prepareNv21(Map<String, Object> payload) {
  final source = payload['source']! as Uint8List;
  final maxDimension = payload['maxDimension']! as int;
  try {
    if (source.isEmpty) return null;
    final decoded = img.decodeImage(source);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    if (oriented.width <= 0 || oriented.height <= 0) return null;

    img.Image sized = oriented;
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    if (longest > maxDimension) {
      final scale = maxDimension / longest;
      sized = img.copyResize(
        oriented,
        width: (oriented.width * scale).round().clamp(1, maxDimension),
        height: (oriented.height * scale).round().clamp(1, maxDimension),
      );
    }
    // NV21 needs even dimensions.
    var width = (sized.width ~/ 2) * 2;
    var height = (sized.height ~/ 2) * 2;
    if (width < 2 || height < 2) return null;
    if (width != sized.width || height != sized.height) {
      sized = img.copyResize(sized, width: width, height: height);
    }

    final rgba = sized.getBytes(order: img.ChannelOrder.rgba);
    final ySize = width * height;
    final nv21 = Uint8List(ySize + ySize ~/ 2);
    var yIndex = 0;
    // BT.601 integer approximation.
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        final p = (j * width + i) * 4;
        final r = rgba[p];
        final g = rgba[p + 1];
        final b = rgba[p + 2];
        nv21[yIndex++] = (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16).clamp(
          0,
          255,
        );
        if (j.isEven && i.isEven) {
          final uvIndex = ySize + (j ~/ 2) * width + i;
          nv21[uvIndex] = (((112 * r - 94 * g - 18 * b + 128) >> 8) + 128)
              .clamp(0, 255);
          nv21[uvIndex + 1] = (((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128)
              .clamp(0, 255);
        }
      }
    }
    return <String, Object>{'bytes': nv21, 'width': width, 'height': height};
  } catch (_) {
    return null;
  }
}
