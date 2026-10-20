import 'package:flutter_test/flutter_test.dart';

import 'package:arduino_controller_app/main.dart';

void main() {
  testWidgets('İlk açılışta tanıtım ekranı gösterilir', (WidgetTester tester) async {
    await tester.pumpWidget(const ArduinoControllerApp(isFirstTime: true));

    expect(find.text('Hoş Geldiniz'), findsOneWidget);
    expect(find.text('İleri'), findsOneWidget);
  });
}
