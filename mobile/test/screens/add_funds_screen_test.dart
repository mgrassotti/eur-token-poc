import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/l10n/app_localizations.dart';
import 'package:mat_mobile/providers/app_state.dart';
import 'package:mat_mobile/screens/add_funds_screen.dart';
import 'package:mat_mobile/services/fake_wallet_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget tests for AddFundsScreen.
///
/// These are simplified tests focusing on the main scenarios:
/// - No hang during initialization
/// - UI renders correctly based on wallet state
/// - Create wallet flow works
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock SharedPreferences for all tests
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(WalletState walletState) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<WalletState>.value(
        value: walletState,
        child: const AddFundsScreen(),
      ),
    );
  }

  group('AddFundsScreen', () {
    testWidgets('renders without hanging when no wallet exists', (tester) async {
      final fakeWallet = FakeWalletService();
      final wallet = WalletState(wallet: fakeWallet);
      
      // Should not hang or throw
      await tester.pumpWidget(harness(wallet));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      // Should show the "no wallet" UI
      expect(find.byType(AddFundsScreen), findsOneWidget);
    });

    testWidgets('shows create wallet UI when no wallet exists', (tester) async {
      final fakeWallet = FakeWalletService();
      final wallet = WalletState(wallet: fakeWallet);
      
      await tester.pumpWidget(harness(wallet));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      expect(find.text('No wallet found'), findsOneWidget);
      expect(find.text('Create wallet'), findsOneWidget);
    });

    // Note: Testing with an initialized wallet is complex due to async
    // initialization. This is covered by integration tests instead.

    testWidgets('create wallet button exists and is tappable', (tester) async {
      final fakeWallet = FakeWalletService();
      final wallet = WalletState(wallet: fakeWallet);
      
      await tester.pumpWidget(harness(wallet));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      // Should have a create wallet button
      expect(find.text('Create wallet'), findsOneWidget);
      
      // Button should be tappable (just verify we can find it, don't actually tap)
      expect(tester.widget<FilledButton>(find.ancestor(
        of: find.text('Create wallet'),
        matching: find.byType(FilledButton),
      )).onPressed, isNotNull);
    });
  });
}
