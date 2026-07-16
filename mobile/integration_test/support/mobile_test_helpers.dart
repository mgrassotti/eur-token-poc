import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_config.dart';

Future<void> loginAs(
  WidgetTester tester, {
  required String email,
  String password = IntegrationConfig.password,
}) async {
  expect(find.text('Log in'), findsOneWidget);

  await tester.enterText(find.byType(TextField).first, email);
  await tester.enterText(find.byType(TextField).last, password);
  await tester.tap(find.text('Log in'));
  await tester.pumpAndSettle(const Duration(seconds: 5));

  expect(find.text('Overview'), findsOneWidget);
}

Future<void> openAddFunds(WidgetTester tester) async {
  await tester.tap(find.text('Deposit funds'));
  await tester.pumpAndSettle(const Duration(seconds: 5));
  expect(find.text('Add funds'), findsOneWidget);
}

Future<String> readReceiveAddress(WidgetTester tester) async {
  final addressFinder = find.byType(SelectableText);
  expect(addressFinder, findsOneWidget);
  final widget = tester.widget<SelectableText>(addressFinder);
  return widget.data!;
}

Future<String> copyReceiveAddress(WidgetTester tester) async {
  final address = await readReceiveAddress(tester);
  await tester.tap(find.text('Copy address'));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final clipboard = await Clipboard.getData('text/plain');
  expect(clipboard?.text, address);
  expect(find.text('Address copied'), findsOneWidget);
  return address;
}

Future<void> logout(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.logout));
  await tester.pumpAndSettle(const Duration(seconds: 5));
  expect(find.text('Log in'), findsOneWidget);
}

Future<void> goHome(WidgetTester tester) async {
  if (find.byTooltip('Home').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
  expect(find.text('Overview'), findsOneWidget);
}

Future<void> createAndPublishDeal(WidgetTester tester) async {
  await tester.tap(find.text('Top up spending'));
  await tester.pumpAndSettle(const Duration(seconds: 3));
  expect(find.text('Top up spending/savings account'), findsOneWidget);

  await tester.tap(find.text('Top up'));
  await tester.pumpAndSettle(const Duration(seconds: 20));

  expect(find.text('Overview'), findsOneWidget);
}

Future<void> openDealListTile(WidgetTester tester, String label) async {
  await tester.tap(find.textContaining(label));
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

Future<void> acceptCurrentDeal(WidgetTester tester) async {
  await tester.tap(find.text('Accept & activate'));
  await tester.pumpAndSettle(const Duration(seconds: 120));
  expect(find.text('ACTIVE'), findsOneWidget);
}

Future<void> enableAdvancedFeatures(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle(const Duration(seconds: 3));
  final toggle = find.byType(Switch);
  if (toggle.evaluate().isNotEmpty) {
    final switchWidget = tester.widget<Switch>(toggle);
    if (!switchWidget.value) {
      await tester.tap(toggle);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  }
  await tester.pageBack();
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

Future<void> openSendMoney(WidgetTester tester) async {
  await tester.tap(find.text('Send money'));
  await tester.pumpAndSettle(const Duration(seconds: 5));
  expect(find.textContaining('Available:'), findsOneWidget);
}

Future<void> sendMoneyTo(
  WidgetTester tester, {
  required String recipientName,
  required String amountEur,
}) async {
  await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField));
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await tester.tap(find.text(recipientName).last);
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final amountField = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Amount (EUR)',
  );
  await tester.enterText(amountField, amountEur);

  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle(const Duration(seconds: 60));

  expect(find.textContaining('Sent €'), findsOneWidget);
}
