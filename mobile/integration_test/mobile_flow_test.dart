import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mat_mobile/main.dart' as app;

import 'support/integration_config.dart';
import 'support/mobile_test_helpers.dart';
import 'support/rails_test_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final rails = RailsTestBridge();

  group('MAT mobile integration', () {
    testWidgets('login shows dashboard overview', (tester) async {
      app.bootstrap(apiBaseUrl: IntegrationConfig.apiBaseUrl);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await loginAs(tester, email: IntegrationConfig.bobEmail);

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Deposit funds'), findsOneWidget);
    });

    testWidgets('add funds shows regtest receive address', (tester) async {
      app.bootstrap(apiBaseUrl: IntegrationConfig.apiBaseUrl);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await loginAs(tester, email: IntegrationConfig.bobEmail);
      await openAddFunds(tester);

      expect(find.text('Copy address'), findsOneWidget);
      expect(find.textContaining('bcrt1'), findsOneWidget);
    });

    testWidgets('alice funds reserve via admin after copying address', (tester) async {
      await rails.demoReset();

      app.bootstrap(apiBaseUrl: IntegrationConfig.apiBaseUrl);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await loginAs(tester, email: IntegrationConfig.aliceEmail);
      await openAddFunds(tester);

      expect(find.text('Balance: 0 sats'), findsOneWidget);

      final address = await copyReceiveAddress(tester);

      await rails.adminFundReserve(
        userEmail: IntegrationConfig.aliceEmail,
        receiveAddress: address,
        amountBtc: IntegrationConfig.fundAmountBtc,
      );

      await tester.tap(find.text('Sync balance'));
      await tester.pumpAndSettle(const Duration(seconds: 8));

      expect(find.text('Reserve updated: ${IntegrationConfig.fundAmountSats} sats'), findsOneWidget);
      expect(find.text('Balance: ${IntegrationConfig.fundAmountSats} sats'), findsOneWidget);
    });

    testWidgets('alice sends eurt to claude after bob accepts deal', (tester) async {
      await rails.demoReset();
      await rails.fundUserReserve(
        userEmail: IntegrationConfig.aliceEmail,
        amountBtc: IntegrationConfig.aliceDepositBtc,
      );
      await rails.fundUserReserve(
        userEmail: IntegrationConfig.bobEmail,
        amountBtc: IntegrationConfig.bobDepositBtc,
      );

      app.bootstrap(apiBaseUrl: IntegrationConfig.apiBaseUrl);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Alice creates a €1000 deal
      await loginAs(tester, email: IntegrationConfig.aliceEmail);
      await createAndPublishDeal(tester);
      await goHome(tester);
      await logout(tester);

      // Bob accepts the pending offer
      await loginAs(tester, email: IntegrationConfig.bobEmail);
      await enableAdvancedFeatures(tester);
      await openDealListTile(tester, '· pending');
      await acceptCurrentDeal(tester);
      await goHome(tester);
      await logout(tester);

      // Alice sends €500 EURT to Claude
      await loginAs(tester, email: IntegrationConfig.aliceEmail);
      await openSendMoney(tester);
      await sendMoneyTo(
        tester,
        recipientName: 'Claude',
        amountEur: IntegrationConfig.transferAmountEur,
      );

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Spending / Savings'), findsOneWidget);
    });

    testWidgets('dashboard lists investable deals for hodler', (tester) async {
      app.bootstrap(apiBaseUrl: IntegrationConfig.apiBaseUrl);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await loginAs(tester, email: IntegrationConfig.bobEmail);
      await enableAdvancedFeatures(tester);

      expect(find.text('Open to invest'), findsOneWidget);
    });
  });
}
