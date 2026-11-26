import 'package:flutter_test/flutter_test.dart';
import 'package:carevoice_app/main.dart';

void main() {
  testWidgets('CareVoice App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CareVoiceApp());
    expect(find.text('CareVoice'), findsAtLeastNWidgets(1));
  });
}
