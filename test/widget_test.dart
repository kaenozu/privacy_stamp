import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/main.dart';

void main() {
  testWidgets('shows local-only image picker landing screen', (tester) async {
    await tester.pumpWidget(const PrivacyStampApp());
    expect(find.text('画像を選ぶ'), findsOneWidget);
    expect(find.textContaining('端末・ブラウザー内'), findsOneWidget);
  });
}
