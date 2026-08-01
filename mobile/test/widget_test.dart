import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/main.dart';

void main() {
  testWidgets('Name form screen renders on first launch', (tester) async {
    bootstrap();
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
