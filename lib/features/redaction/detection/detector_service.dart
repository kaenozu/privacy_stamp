import '../models/redaction_models.dart';
import '../rules/sensitive_rules.dart';
import 'face_detector.dart';

class DetectionService {
  DetectionService({
    SensitiveRuleEngine? rules,
    FaceRegionDetector? faceDetector,
    this._codeDetector,
  }) : _rules = rules ?? SensitiveRuleEngine(),
       _faceDetector = faceDetector ?? const NoopFaceDetector();
  final SensitiveRuleEngine _rules;
  final FaceRegionDetector _faceDetector;
  final CodeRegionDetector? _codeDetector;

  Future<List<DetectionRegion>> inspect(
    Uint8ListImageInput input, {
    bool hideAllText = false,
  }) async {
    // Platform adapters can provide real face/code/OCR regions through this contract.
    // The shared rule engine remains deterministic and never sends image bytes away.
    // Each source is isolated: a failing detector degrades to "no suggestions"
    // instead of discarding the other sources or the selected image.
    final textRegions = await _localTextDetector(input);
    final textHits = _rules.detect(textRegions, hideAllText: hideAllText);

    List<DetectionRegion> faces = const [];
    try {
      faces = await _faceDetector.detect(input);
    } catch (_) {
      faces = const [];
    }

    List<DetectionRegion> codes = const [];
    final codeDetector = _codeDetector;
    if (codeDetector != null) {
      try {
        codes = await codeDetector.detect(input);
      } catch (_) {
        codes = const [];
      }
    }

    return [...faces, ...codes, ...textHits];
  }

  Future<List<RecognizedTextRegion>> _localTextDetector(
    Uint8ListImageInput input,
  ) async => const [];
}
