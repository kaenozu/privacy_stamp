import '../models/redaction_models.dart';
import '../rules/sensitive_rules.dart';
import 'barcode_detector.dart';
import 'face_detector.dart';
import 'text_detector.dart';

class DetectionService {
  DetectionService({
    SensitiveRuleEngine? rules,
    FaceRegionDetector? faceDetector,
    TextRegionDetector? textDetector,
    CodeRegionDetector? codeDetector,
  }) : _rules = rules ?? SensitiveRuleEngine(),
       _faceDetector = faceDetector ?? const NoopFaceDetector(),
       _textDetector = textDetector ?? const NoopTextDetector(),
       _codeDetector = codeDetector ?? const NoopCodeDetector();
  final SensitiveRuleEngine _rules;
  final FaceRegionDetector _faceDetector;
  final TextRegionDetector _textDetector;
  final CodeRegionDetector _codeDetector;

  Future<List<DetectionRegion>> inspect(
    Uint8ListImageInput input, {
    bool hideAllText = false,
  }) async {
    // Platform adapters can provide real face/code/OCR regions through this contract.
    // The shared rule engine remains deterministic and never sends image bytes away.
    // Each source is isolated: a failing detector degrades to "no suggestions"
    // instead of discarding the other sources or the selected image.
    List<RecognizedTextRegion> textRegions = const [];
    try {
      textRegions = await _textDetector.detect(input);
    } catch (_) {
      textRegions = const [];
    }
    final textHits = _rules.detect(textRegions, hideAllText: hideAllText);

    List<DetectionRegion> faces = const [];
    try {
      faces = await _faceDetector.detect(input);
    } catch (_) {
      faces = const [];
    }

    List<DetectionRegion> codes = const [];
    try {
      codes = await _codeDetector.detect(input);
    } catch (_) {
      codes = const [];
    }

    return [...faces, ...codes, ...textHits];
  }
}
