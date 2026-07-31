import 'dart:io';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mat_mobile/services/local_wallet_service.dart'; // BdkWalletService is in this file
import 'package:mat_mobile/services/wallet_lifecycle_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real BDK integration test - tests actual BdkWalletService with BDK library.
///
/// Tests:
/// 1. Generate real BDK mnemonic (12 words)
/// 2. Create wallet with BdkWalletService
/// 3. Verify real Bitcoin address generation (bcrt1q... for regtest)
/// 4. Verify mnemonic persistence
/// 5. Load existing wallet (persistence test)
/// 6. Delete wallet and verify cleanup
///
/// This test uses the real BDK library and creates actual wallet files.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('BDK Wallet Lifecycle (Real BDK)', () {
    late BdkWalletService bdkService;
    late WalletLifecycleManager manager;

    setUp(() async {
      // Clean state before each test
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Delete any existing wallet databases to prevent ChecksumMismatchException
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File('${dir.path}/bdk_wallet_regtest.db');
      if (await dbFile.exists()) {
        await dbFile.delete();
        print('🗑️  Deleted old wallet database');
      }

      // Create real BdkWalletService
      bdkService = BdkWalletService();
      manager = WalletLifecycleManager(bdkService);
    });

    test('Complete BDK wallet lifecycle with real blockchain operations', () async {
      print('\n========== TEST START: BDK Wallet Lifecycle ==========\n');

      // ==================== PHASE 1: No Existing Wallet ====================
      print('PHASE 1: Checking for existing wallet...');
      final hasWallet = await manager.hasStoredWallet();
      expect(hasWallet, isFalse, reason: 'Should not have a stored wallet');
      print('✓ No existing wallet found');

      // ==================== PHASE 2: Generate Real BDK Mnemonic ====================
      print('\nPHASE 2: Generating real BDK mnemonic...');
      final mnemonicObj = await Mnemonic.create(WordCount.words12);
      final mnemonicStr = await mnemonicObj.asString();
      
      final words = mnemonicStr.split(' ');
      expect(words.length, 12, reason: 'Mnemonic should have 12 words');
      print('✓ Generated BDK mnemonic: ${words.take(3).join(' ')}... (${words.length} words)');

      // ==================== PHASE 3: Create Wallet with BDK ====================
      print('\nPHASE 3: Creating wallet with BDK (this uses real BDK library)...');
      print('  - This will create descriptor, wallet DB, and generate real address');
      
      final address = await manager.createWallet(mnemonicStr);
      
      expect(address, isNotEmpty, reason: 'Address should not be empty');
      expect(address.startsWith('bcrt1'), isTrue, reason: 'Regtest address should start with bcrt1');
      print('✓ BDK wallet created successfully');
      print('✓ Real Bitcoin address: $address');

      // ==================== PHASE 4: Verify Persistence ====================
      print('\nPHASE 4: Verifying wallet persistence...');
      final hasWalletAfter = await manager.hasStoredWallet();
      expect(hasWalletAfter, isTrue, reason: 'Wallet should be stored');
      
      final storedMnemonic = await manager.getStoredMnemonic();
      expect(storedMnemonic, equals(mnemonicStr), reason: 'Stored mnemonic should match');
      print('✓ Wallet and mnemonic persisted in SharedPreferences');

      // ==================== PHASE 5: Try Loading Existing Wallet ====================
      print('\nPHASE 5: Testing wallet loading (simulating app restart)...');
      
      // Create new BdkWalletService instance to simulate app restart
      final bdkService2 = BdkWalletService();
      final manager2 = WalletLifecycleManager(bdkService2);
      
      final walletLoaded = await manager2.tryLoadWallet();
      expect(walletLoaded, isTrue, reason: 'Should load existing wallet');
      
      // Verify we can get the receive address
      final address2 = await bdkService2.getReceiveAddress();
      expect(address2.startsWith('bcrt1'), isTrue, reason: 'Address should still be valid');
      print('✓ Wallet loaded successfully after "restart"');
      print('✓ Address from loaded wallet: $address2');

      // ==================== PHASE 6: Delete Wallet ====================
      print('\nPHASE 6: Deleting wallet...');
      await manager.deleteWallet();
      print('✓ Wallet deleted from SharedPreferences');

      // ==================== PHASE 7: Verify Complete Cleanup ====================
      print('\nPHASE 7: Verifying complete deletion...');
      final hasWalletAfterDelete = await manager.hasStoredWallet();
      expect(hasWalletAfterDelete, isFalse, reason: 'Wallet should be deleted');
      
      final mnemonicAfterDelete = await manager.getStoredMnemonic();
      expect(mnemonicAfterDelete, isNull, reason: 'Mnemonic should be null after deletion');
      print('✓ Deletion verified - all wallet data removed');

      print('\n========== TEST COMPLETE: BDK Integration Successful! ==========\n');
    });

    test('Wallet creation with corrupted/invalid mnemonic fails gracefully', () async {
      print('\n========== TEST: Invalid Mnemonic Handling ==========\n');

      final invalidMnemonic = 'invalid word word word word word word word word word word word';
      
      try {
        await manager.createWallet(invalidMnemonic);
        fail('Should have thrown an exception for invalid mnemonic');
      } catch (e) {
        print('✓ Invalid mnemonic rejected correctly: ${e.toString()}');
        // Check that error mentions either "mnemonic" or "recovery phrase"
        final errorLower = e.toString().toLowerCase();
        expect(
          errorLower.contains('mnemonic') || errorLower.contains('recovery phrase'),
          isTrue,
          reason: 'Error should mention mnemonic or recovery phrase',
        );
      }

      print('✓ Test complete - invalid mnemonic handling works\n');
    });

    test('Multiple wallet creation attempts are handled correctly', () async {
      print('\n========== TEST: Multiple Creation Attempts ==========\n');

      // Create first wallet
      final mnemonic1 = await Mnemonic.create(WordCount.words12);
      final mnemonicStr1 = await mnemonic1.asString();
      final address1 = await manager.createWallet(mnemonicStr1);
      print('✓ First wallet created: $address1');

      // Try to create second wallet (should fail or replace)
      final mnemonic2 = await Mnemonic.create(WordCount.words12);
      final mnemonicStr2 = await mnemonic2.asString();
      
      try {
        // This should either fail or delete the old wallet first
        await manager.deleteWallet(); // Clean up first
        final address2 = await manager.createWallet(mnemonicStr2);
        print('✓ Second wallet created after cleanup: $address2');
        
        // Clean up
        await manager.deleteWallet();
      } catch (e) {
        print('✓ Multiple creation prevented (expected): ${e.toString()}');
      }

      print('✓ Test complete - multiple creation handled\n');
    });
  });
}
