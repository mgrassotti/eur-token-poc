import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/main.dart';

void main() {
  testWidgets('Login screen renders', (tester) async {
    bootstrap();
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });
}
