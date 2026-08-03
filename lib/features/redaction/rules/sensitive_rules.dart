import '../models/redaction_models.dart';

class SensitiveRuleEngine {
  static final _email = RegExp(r'\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b');
  static final _phone = RegExp(
    r'(?<!\d)(?:\+81[- ]?\d{1,4}[- ]?\d{1,4}[- ]?\d{3,4}|0\d{1,4}[- ]?\d{1,4}[- ]?\d{3,4}|0120[- ]?\d{2,4}[- ]?\d{3,4})(?!\d)',
  );
  static final _postal = RegExp(r'(?<!\d)〒?\d{3}[- ]?\d{4}(?!\d)');
  static final _coordinate = RegExp(
    r'(?<!\d)([-+]?\d{1,3}\.\d{3,})\s*[,/ ]\s*([-+]?\d{1,3}\.\d{3,})(?!\d)',
  );
  static final _digits = RegExp(r'(?<!\d)\d{13,19}(?!\d)');
  static final _labels = RegExp(
    r'(氏名|名前|お名前|宛名|住所|配送先|送付先|お届け先|口座番号|会員番号|顧客番号|注文番号|予約番号|受付番号|追跡番号)\s*[:：]?\s*(\S+)',
  );

  List<DetectionRegion> detect(
    Iterable<RecognizedTextRegion> regions, {
    bool hideAllText = false,
  }) {
    final output = <DetectionRegion>[];
    var index = 0;
    for (final region in regions) {
      final text = region.text.trim();
      if (text.isEmpty) {
        continue;
      }
      if (hideAllText) {
        output.add(
          _region(index++, DetectionKind.allText, region, '強力モード: OCR文字領域'),
        );
        continue;
      }
      void add(
        DetectionKind kind,
        String reason, {
        Certainty certainty = Certainty.automatic,
      }) => output.add(
        _region(index++, kind, region, reason, certainty: certainty),
      );
      if (_email.hasMatch(text)) {
        add(DetectionKind.email, 'メールアドレス');
      }
      if (_phone.hasMatch(text)) {
        add(DetectionKind.phone, '電話番号');
      }
      if (_postal.hasMatch(text)) {
        add(DetectionKind.postalCode, '郵便番号', certainty: Certainty.review);
      }
      final coordinate = _coordinate.firstMatch(text);
      if (coordinate != null &&
          _validCoordinate(
            double.tryParse(coordinate.group(1)!),
            double.tryParse(coordinate.group(2)!),
          )) {
        add(DetectionKind.coordinate, '緯度・経度');
      }
      for (final match in _digits.allMatches(text)) {
        if (_passesLuhn(match.group(0)!)) {
          add(DetectionKind.card, 'カード番号候補');
        }
      }
      if (_labels.hasMatch(text)) {
        add(
          DetectionKind.labelledText,
          'センシティブラベルに続く値',
          certainty: Certainty.review,
        );
      }
    }
    return output;
  }

  bool _validCoordinate(double? a, double? b) =>
      a != null && b != null && a.abs() <= 90 && b.abs() <= 180;
  bool _passesLuhn(String value) {
    var sum = 0;
    var alternate = false;
    for (var i = value.length - 1; i >= 0; i--) {
      var n = int.parse(value[i]);
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  DetectionRegion _region(
    int index,
    DetectionKind kind,
    RecognizedTextRegion source,
    String reason, {
    Certainty certainty = Certainty.automatic,
  }) => DetectionRegion(
    id: 'text-$index',
    kind: kind,
    normalizedRect: source.normalizedRect.padded(.012, .018),
    confidence: source.confidence,
    certainty: certainty,
    reason: reason,
    sourceDetector: 'ocr-rules',
  );
}
