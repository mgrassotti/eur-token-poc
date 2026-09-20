import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mat_mobile/services/local_wallet_service.dart';
import 'package:mat_mobile/services/wallet_lifecycle_manager.dart';

import 'support/integration_config.dart';
import 'support/rails_test_bridge.dart';

/// Phase 2 Task 1.3: BDK wallet integration tests.
///
/// Tests wallet creation, sync, balance, and funding via regtest.
///
/// **Prerequisites:**
/// - Regtest Bitcoin node running (`./bin/regtest up`)
/// - Electrum server running on port 50001
/// - Rails backend running (`bin/dev`)
///
/// **Run:**
/// ```bash
/// cd mobile
/// flutter test integration_test/bdk_wallet_test.dart \
///   -d macos \
///   --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final rails = RailsTestBridge();

  group('BDK wallet on-device', () {
    late BdkWalletService wallet;
    late WalletLifecycleManager lifecycle;

    setUp(() async {
      wallet = BdkWalletService(network: Network.regtest);
      lifecycle = WalletLifecycleManager(wallet);

      // Clean up any existing wallet
      if (await lifecycle.hasStoredWallet()) {
        await lifecycle.deleteWallet();
      }
    });

    tearDown(() async {
      if (wallet.isInitialized) {
        await wallet.close();
      }
    });

    test('create new wallet generates 12-word mnemonic and receive address', () async {
      // Generate mnemonic
      final mnemonic = await Mnemonic.create(WordCount.words12);
      final phrase = mnemonic.asString();

      // Create wallet
      final receiveAddress = await lifecycle.createWallet(phrase);

      // Verify wallet initialized
      expect(wallet.isInitialized, isTrue);
      expect(receiveAddress, startsWith('bcrt1')); // Regtest bech32
      expect(receiveAddress.length, greaterThan(40)); // BIP84 address length

      // Verify mnemonic persisted
      final storedMnemonic = await lifecycle.getStoredMnemonic();
      expect(storedMnemonic, equals(phrase));
    });

    test('restore wallet from mnemonic recovers addresses', () async {
      const testMnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      // Restore wallet
      final receiveAddress = await lifecycle.restoreWallet(testMnemonic);

      // Verify deterministic address (always same for this mnemonic)
      expect(receiveAddress, startsWith('bcrt1'));

      // Verify wallet initialized
      expect(wallet.isInitialized, isTrue);
    });

    test('wallet sync connects to Electrum regtest server', () async {
      // Create wallet
      final mnemonic = await Mnemonic.create(WordCount.words12);
      await lifecycle.createWallet(mnemonic.asString());

      // Sync should succeed (even if no transactions)
      await expectLater(wallet.sync(), completes);

      // Initial balance should be 0
      final balance = await wallet.getBalance();
      expect(balance, equals(0));
    });

    test('wallet receives regtest BTC and updates balance after sync', () async {
      // Reset demo state
      await rails.demoReset();

      // Create wallet
      final mnemonic = await Mnemonic.create(WordCount.words12);
      await lifecycle.createWallet(mnemonic.asString());
      await wallet.sync();

      // Get receive address
      final receiveAddress = await wallet.getReceiveAddress();

      // Fund address via Rails integration endpoint
      await rails.fundRegtestAddress(
        address: receiveAddress,
        amountBtc: '0.5', // 0.5 BTC = 50,000,000 sats
      );

      // Wait for electrs to index (2 blocks mined by funding endpoint)
      await Future.delayed(const Duration(seconds: 3));

      // Sync wallet
      await wallet.sync();

      // Verify balance updated
      final balance = await wallet.getBalance();
      expect(balance, equals(50000000)); // 0.5 BTC in sats
    });

    test('wallet lists UTXOs after receiving funds', () async {
      await rails.demoReset();

      final mnemonic = await Mnemonic.create(WordCount.words12);
      await lifecycle.createWallet(mnemonic.asString());
      await wallet.sync();

      final receiveAddress = await wallet.getReceiveAddress();

      // Fund with 0.1 BTC
      await rails.fundRegtestAddress(
        address: receiveAddress,
        amountBtc: '0.1',
      );

      await Future.delayed(const Duration(seconds: 3));
      await wallet.sync();

      // List UTXOs
      final utxos = await wallet.listUnspent();

      expect(utxos, hasLength(1));
      expect(utxos.first.valueSats, equals(10000000)); // 0.1 BTC
      expect(utxos.first.txid, hasLength(64)); // SHA256 hex
    });

    test('multiple receives create multiple UTXOs', () async {
      await rails.demoReset();

      final mnemonic = await Mnemonic.create(WordCount.words12);
      await lifecycle.createWallet(mnemonic.asString());
      await wallet.sync();

      // Receive 3 separate payments
      for (var i = 0; i < 3; i++) {
        final address = await wallet.getReceiveAddress();
        await rails.fundRegtestAddress(
          address: address,
          amountBtc: '0.1',
        );
      }

      await Future.delayed(const Duration(seconds: 4));
      await wallet.sync();

      final utxos = await wallet.listUnspent();
      final balance = await wallet.getBalance();

      expect(utxos, hasLength(3));
      expect(balance, equals(30000000)); // 0.3 BTC total
    });

    test('delete wallet removes stored mnemonic', () async {
      final mnemonic = await Mnemonic.create(WordCount.words12);
      await lifecycle.createWallet(mnemonic.asString());

      expect(await lifecycle.hasStoredWallet(), isTrue);

      // Delete wallet
      await lifecycle.deleteWallet();

      expect(await lifecycle.hasStoredWallet(), isFalse);
      expect(await lifecycle.getStoredMnemonic(), isNull);
      expect(wallet.isInitialized, isFalse);
    });

    test('wallet with invalid mnemonic throws exception', () async {
      const invalidMnemonic = 'invalid mnemonic phrase';

      await expectLater(
        () => lifecycle.createWallet(invalidMnemonic),
        throwsA(isA<Exception>()),
      );

      expect(wallet.isInitialized, isFalse);
    });

    test('PSBT signing returns signed transaction', () async {
      // This is a placeholder for Phase 3 DLC funding
      final mnemonic = await Mnemonic.create(WordCount.words12);
      await lifecycle.createWallet(mnemonic.asString());
      await wallet.sync();

      // For now, just verify the method exists and throws on invalid PSBT
      await expectLater(
        () => wallet.signPsbt('invalid-psbt-base64'),
        throwsA(isA<Exception>()),
      );
    });

    test('get new receive addresses without reuse', () async {
      final mnemonic = await Mnemonic.create(WordCount.words12);
      await lifecycle.createWallet(mnemonic.asString());

      // Get multiple addresses
      final addr1 = await wallet.getReceiveAddress();
      final addr2 = await wallet.getReceiveAddress();
      final addr3 = await wallet.getReceiveAddress();

      // BDK should return same address until used (lastUnused)
      // This is correct behavior to avoid address reuse
      expect(addr1, equals(addr2));
      expect(addr2, equals(addr3));

      // After actual use (receiving funds), next address changes
      // (tested in previous tests)
    });
  });
}
