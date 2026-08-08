import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/rules/sensitive_rules.dart';

void main() {
  final engine = SensitiveRuleEngine();
  RecognizedTextRegion text(String value) => RecognizedTextRegion(
    text: value,
    normalizedRect: const NormalizedRect(.1, .1, .5, .1),
  );

  test('detects email and Japanese phone without hiding unrelated prices', () {
    final result = engine.detect([
      text('連絡先 test@example.com 090-1234-5678 価格 1280円'),
    ]);
    expect(
      result.map((r) => r.kind),
      containsAll([DetectionKind.email, DetectionKind.phone]),
    );
    expect(result.where((r) => r.kind == DetectionKind.card), isEmpty);
  });
  test('detects postal code as review candidate', () {
    final result = engine.detect([text('〒100-0001')]);
    expect(result.single.kind, DetectionKind.postalCode);
    expect(result.single.certainty, Certainty.review);
  });
  test('only detects Luhn-valid card candidates', () {
    expect(
      engine.detect([text('4111111111111111')]).single.kind,
      DetectionKind.card,
    );
    expect(engine.detect([text('4111111111111112')]), isEmpty);
  });
  test('detects Luhn-valid card candidates with spaces or hyphens', () {
    for (final value in [
      '4111 1111 1111 1111',
      '4111-1111-1111-1111',
    ]) {
      final result = engine.detect([text(value)]);
      expect(result.single.kind, DetectionKind.card, reason: value);
    }
  });
  test('rejects separated card candidates with invalid length or Luhn', () {
    expect(engine.detect([text('4111 1111 1111')]), isEmpty);
    expect(engine.detect([text('4111 1111 1111 1112')]), isEmpty);
    expect(engine.detect([text('4111 1111 1111 1111 1111')]), isEmpty);
  });
  test('detects valid coordinates and rejects out of range values', () {
    expect(
      engine.detect([text('35.681236, 139.767125')]).single.kind,
      DetectionKind.coordinate,
    );
    expect(engine.detect([text('95.681236, 139.767125')]), isEmpty);
  });
  test('strong mode hides every OCR region', () {
    final result = engine.detect([text('普通の文章')], hideAllText: true);
    expect(result.single.kind, DetectionKind.allText);
  });
}
