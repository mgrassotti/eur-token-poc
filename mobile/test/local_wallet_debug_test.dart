import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/l10n/app_localizations.dart';
import 'package:mat_mobile/screens/local_wallet_debug_screen.dart';
import 'package:mat_mobile/services/fake_wallet_service.dart';

Widget _harness(FakeWalletService wallet) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: LocalWalletDebugScreen(wallet: wallet),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty wallet shows create button', (tester) async {
    final wallet = FakeWalletService();
    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    expect(find.text('Local wallet (BDK spike)'), findsOneWidget);
    expect(find.text('Create wallet'), findsOneWidget);
    expect(find.text('Balance'), findsNothing);
  });

  testWidgets('create wallet shows receive address and balance', (tester) async {
    final wallet = FakeWalletService();
    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    // Tap create button
    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();

    expect(wallet.isInitialized, true);
    expect(find.textContaining('Receive address'), findsOneWidget);
    expect(find.textContaining('Balance'), findsOneWidget);
    expect(find.text('0 BTC (0 sats)'), findsOneWidget); // Initial balance
    expect(find.text('Recovery phrase'), findsOneWidget);
    expect(find.text('Create wallet'), findsNothing);
  });

  testWidgets('wallet with balance shows correct amount', (tester) async {
    final wallet = FakeWalletService();
    await wallet.createWallet('abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about');
    wallet.setBalance(100000000); // 1 BTC

    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    expect(find.text('1.0 BTC (100000000 sats)'), findsOneWidget);
  });

  testWidgets('delete wallet confirmation dialog', (tester) async {
    final wallet = FakeWalletService();
    await wallet.createWallet('abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about');

    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    // Tap delete button
    await tester.tap(find.text('Delete wallet'));
    await tester.pumpAndSettle();

    // Should show confirmation dialog
    expect(find.text('Delete wallet?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Wallet still exists
    expect(wallet.isInitialized, true);
    expect(find.textContaining('Receive address'), findsOneWidget);
  });

  testWidgets('delete wallet removes all data', (tester) async {
    final wallet = FakeWalletService();
    await wallet.createWallet('abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about');

    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    // Tap delete button
    await tester.tap(find.text('Delete wallet'));
    await tester.pumpAndSettle();

    // Confirm deletion
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Wallet should be deleted
    expect(wallet.isInitialized, false);
    expect(find.text('Create wallet'), findsOneWidget);
    expect(find.textContaining('Receive address'), findsNothing);
  });
}
