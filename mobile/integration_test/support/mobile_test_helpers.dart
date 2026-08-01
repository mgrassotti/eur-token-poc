import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'integration_config.dart';

/// Clears persisted prefs and seeds a stable English locale for assertions.
Future<void> resetMobilePrefs({bool advancedFeatures = false}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setString('locale_code', 'en');
  if (advancedFeatures) {
    await prefs.setBool('advanced_features', true);
  }
}

/// Phase 2: Enter name instead of login (login saved for future: bank transfer deposits)
Future<void> loginAs(
  WidgetTester tester, {
  required String email,
  String password = IntegrationConfig.password,
}) async {
  // Extract name from email (e.g. "alice@example.com" -> "Alice")
  final name = email.split('@').first.replaceFirst(
        email[0],
        email[0].toUpperCase(),
      );

  // Check if name form is shown
  if (find.text('Welcome!').evaluate().isNotEmpty) {
    await tester.enterText(find.byType(TextField).first, name);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  expect(find.text('Overview'), findsOneWidget);
}

/// Opens Add funds via Settings (dashboard CTA is hidden once reserve > 0).
Future<void> openAddFunds(WidgetTester tester) async {
  if (find.text('Deposit funds').evaluate().isEmpty) {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
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

/// Phase 2: Clear name instead of logout (no login for now)
Future<void> logout(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('user_name');
  // Note: logout button removed from dashboard in Phase 2
  // This helper is kept for compatibility with existing tests
}

Future<void> goHome(WidgetTester tester) async {
  if (find.byTooltip('Home').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
  expect(find.text('Overview'), findsOneWidget);
}

Future<void> createAndPublishDeal(WidgetTester tester) async {
  if (find.text('Top up spending').evaluate().isEmpty) {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await tester.tap(find.text('Top up spending'));
  } else {
    await tester.tap(find.text('Top up spending'));
  }
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

Future<void> leaveSettings(WidgetTester tester) async {
  // Prefer explicit pop — pageBack() expects Cupertino back control which Material AppBar may not use.
  final settingsTitle = find.text('Settings');
  expect(settingsTitle, findsOneWidget);
  Navigator.of(tester.element(settingsTitle)).pop();
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Relies on [resetMobilePrefs] having seeded `advanced_features` before bootstrap.
Future<void> enableAdvancedFeatures(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle(const Duration(seconds: 3));
  expect(find.text('Settings'), findsOneWidget);

  // SettingsState loads prefs asynchronously after construction.
  final localWallet = find.text('Local wallet (BDK spike)');
  for (var i = 0; i < 20 && localWallet.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(localWallet, findsOneWidget);
  await leaveSettings(tester);
}

Future<void> openSettlementFromCurrentDeal(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.payments_outlined));
  await tester.pumpAndSettle(const Duration(seconds: 10));
  expect(find.text('Settlement'), findsOneWidget);
}

/// Opens Settings → Advanced → Local wallet debug (does not create a BDK wallet).
Future<void> openLocalWalletDebug(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle(const Duration(seconds: 3));
  final localWallet = find.text('Local wallet (BDK spike)');
  for (var i = 0; i < 20 && localWallet.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(localWallet, findsOneWidget);
  await tester.tap(localWallet);
  await tester.pumpAndSettle(const Duration(seconds: 5));
  expect(find.text('Local wallet (BDK spike)'), findsWidgets);
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
