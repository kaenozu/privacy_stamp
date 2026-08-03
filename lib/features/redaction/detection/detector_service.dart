import '../models/redaction_models.dart';
import '../rules/sensitive_rules.dart';

class DetectionService {
  DetectionService({SensitiveRuleEngine? rules})
    : _rules = rules ?? SensitiveRuleEngine();
  final SensitiveRuleEngine _rules;

  Future<List<DetectionRegion>> inspect(
    Uint8ListImageInput input, {
    bool hideAllText = false,
  }) async {
    // Platform adapters can provide real face/code/OCR regions through this contract.
    // The shared rule engine remains deterministic and never sends image bytes away.
    final textRegions = await _localTextDetector(input);
    return _rules.detect(textRegions, hideAllText: hideAllText);
  }

  Future<List<RecognizedTextRegion>> _localTextDetector(
    Uint8ListImageInput input,
  ) async => const [];
}
