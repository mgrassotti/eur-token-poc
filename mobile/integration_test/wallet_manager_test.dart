import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mat_mobile/services/fake_wallet_service.dart';
import 'package:mat_mobile/services/wallet_lifecycle_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple integration test for WalletLifecycleManager without UI.
///
/// Tests:
/// 1. No existing wallet
/// 2. Generate and store mnemonic
/// 3. Load mnemonic (persistence)
/// 4. Delete mnemonic (cleanup)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('WalletLifecycleManager Integration', () {
    setUp(() async {
      // Clean state before each test
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    test('Complete wallet lifecycle', () async {
      print('\n========== TEST START: Wallet Manager ==========\n');

      // Use FakeWalletService for testing
      final fakeWallet = FakeWalletService();
      final manager = WalletLifecycleManager(fakeWallet);

      // ==================== PHASE 1: No Existing Wallet ====================
      print('PHASE 1: Checking for existing wallet...');
      final hasWallet = await manager.hasStoredWallet();
      expect(hasWallet, isFalse, reason: 'Should not have a stored wallet');
      print('✓ No existing wallet found');

      // ==================== PHASE 2: Generate Mnemonic ====================
      print('\nPHASE 2: Generating new mnemonic...');
      final mnemonicObj = await Mnemonic.create(WordCount.words12);
      final mnemonicStr = await mnemonicObj.asString();
      
      final words = mnemonicStr.split(' ');
      expect(words.length, 12, reason: 'Mnemonic should have 12 words');
      print('✓ Generated mnemonic with 12 words: ${words.take(3).join(' ')}...');

      // ==================== PHASE 3: Create Wallet with Mnemonic ====================
      print('\nPHASE 3: Creating wallet with mnemonic...');
      final address = await manager.createWallet(mnemonicStr);
      expect(address, isNotEmpty, reason: 'Address should not be empty');
      print('✓ Wallet created with address: $address');

      // ==================== PHASE 4: Verify Persistence ====================
      print('\nPHASE 4: Verifying wallet persistence...');
      final hasWalletAfter = await manager.hasStoredWallet();
      expect(hasWalletAfter, isTrue, reason: 'Wallet should be stored');
      
      final storedMnemonic = await manager.getStoredMnemonic();
      expect(storedMnemonic, equals(mnemonicStr), reason: 'Stored mnemonic should match');
      print('✓ Wallet and mnemonic persisted correctly');

      // ==================== PHASE 5: Delete Wallet ====================
      print('\nPHASE 5: Deleting wallet...');
      await manager.deleteWallet();
      print('✓ Wallet deleted');

      // ==================== PHASE 6: Verify Deletion ====================
      print('\nPHASE 6: Verifying deletion...');
      final hasWalletAfterDelete = await manager.hasStoredWallet();
      expect(hasWalletAfterDelete, isFalse, reason: 'Wallet should be deleted');
      
      final mnemonicAfterDelete = await manager.getStoredMnemonic();
      expect(mnemonicAfterDelete, isNull, reason: 'Mnemonic should be null after deletion');
      print('✓ Deletion verified - wallet is gone');

      print('\n========== TEST COMPLETE: All phases passed! ==========\n');
    });
  });
}
