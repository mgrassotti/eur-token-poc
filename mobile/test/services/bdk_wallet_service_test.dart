import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/services/fake_wallet_service.dart';
import 'package:mat_mobile/services/wallet_api.dart';

/// Unit tests for wallet service (using FakeWalletService).
///
/// BDK native tests require integration test environment.
/// These tests verify the WalletApi contract and behavior.
void main() {
  group('FakeWalletService (unit tests)', () {
    late WalletApi wallet;

    setUp(() {
      wallet = FakeWalletService();
    });

    test('new wallet is not initialized', () {
      expect(wallet.isInitialized, isFalse);
      expect(wallet.mnemonicPhrase, isNull);
    });

    test('createWallet initializes wallet and returns address', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      
      final address = await wallet.createWallet(mnemonic);

      expect(wallet.isInitialized, isTrue);
      expect(wallet.mnemonicPhrase, equals(mnemonic));
      expect(address, startsWith('bcrt1q')); // Regtest bech32
      expect(address.length, greaterThan(40));
    });

    test('createWallet throws if wallet already initialized', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      expect(
        () => wallet.createWallet(mnemonic),
        throwsA(isA<WalletException>()),
      );
    });

    test('restoreWallet initializes wallet from mnemonic', () async {
      const mnemonic = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';
      
      final address = await wallet.restoreWallet(mnemonic);

      expect(wallet.isInitialized, isTrue);
      expect(wallet.mnemonicPhrase, equals(mnemonic));
      expect(address, isNotEmpty);
    });

    test('getReceiveAddress throws if wallet not initialized', () {
      expect(
        () => wallet.getReceiveAddress(),
        throwsA(isA<WalletNotInitializedException>()),
      );
    });

    test('getReceiveAddress returns valid address after creation', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      final address = await wallet.getReceiveAddress();

      expect(address, isNotEmpty);
      expect(address, startsWith('bcrt1q'));
    });

    test('getBalance returns zero for new wallet', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      final balance = await wallet.getBalance();

      expect(balance, equals(0));
    });

    test('sync completes without error', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      await expectLater(wallet.sync(), completes);
    });

    test('listUnspent returns empty list for new wallet', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      final utxos = await wallet.listUnspent();

      expect(utxos, isEmpty);
    });

    test('close clears wallet state', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      await wallet.close();

      expect(wallet.isInitialized, isFalse);
      expect(wallet.mnemonicPhrase, isNull);
    });
  });

  group('FakeWalletService - UTXO management', () {
    late FakeWalletService wallet;

    setUp(() async {
      wallet = FakeWalletService();
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);
    });

    test('addUtxo updates balance', () async {
      final utxo = Utxo(
        txid: 'fake-txid-1',
        vout: 0,
        valueSats: 100000,
        scriptPubKey: '',
      );

      wallet.addUtxo(utxo);

      expect(await wallet.getBalance(), equals(100000));
      expect(await wallet.listUnspent(), hasLength(1));
    });

    test('multiple UTXOs accumulate balance', () async {
      wallet.addUtxo(Utxo(txid: 'tx1', vout: 0, valueSats: 50000, scriptPubKey: ''));
      wallet.addUtxo(Utxo(txid: 'tx2', vout: 0, valueSats: 30000, scriptPubKey: ''));
      wallet.addUtxo(Utxo(txid: 'tx3', vout: 1, valueSats: 20000, scriptPubKey: ''));

      expect(await wallet.getBalance(), equals(100000));
      expect(await wallet.listUnspent(), hasLength(3));
    });

    test('removeUtxo decreases balance', () async {
      wallet.addUtxo(Utxo(txid: 'tx1', vout: 0, valueSats: 100000, scriptPubKey: ''));
      wallet.addUtxo(Utxo(txid: 'tx2', vout: 0, valueSats: 50000, scriptPubKey: ''));

      wallet.removeUtxo('tx1', 0);

      expect(await wallet.getBalance(), equals(50000));
      expect(await wallet.listUnspent(), hasLength(1));
    });

    test('clearUtxos resets balance to zero', () async {
      wallet.addUtxo(Utxo(txid: 'tx1', vout: 0, valueSats: 100000, scriptPubKey: ''));
      wallet.addUtxo(Utxo(txid: 'tx2', vout: 0, valueSats: 50000, scriptPubKey: ''));

      wallet.clearUtxos();

      expect(await wallet.getBalance(), equals(0));
      expect(await wallet.listUnspent(), isEmpty);
    });
  });

  group('WalletException hierarchy', () {
    test('WalletNotInitializedException is a WalletException', () {
      final exception = WalletNotInitializedException();
      expect(exception, isA<WalletException>());
    });

    test('InsufficientFundsException includes amounts', () {
      final exception = InsufficientFundsException(100000, 50000);
      expect(exception.required, equals(100000));
      expect(exception.available, equals(50000));
      expect(exception.toString(), contains('100000'));
      expect(exception.toString(), contains('50000'));
    });

    test('NetworkException wraps cause', () {
      final cause = Exception('Connection refused');
      final exception = NetworkException('Cannot connect', cause);
      expect(exception.cause, equals(cause));
      expect(exception.toString(), contains('Cannot connect'));
    });

    test('dlcFundPubkey is a compressed hex pubkey', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      final pubkey = wallet.dlcFundPubkey;
      expect(pubkey, isNotNull);
      expect(pubkey!.length, equals(66));
      expect(pubkey.startsWith('02') || pubkey.startsWith('03'), isTrue);
    });

    test('signDlcAdaptor returns one adaptor sig per CET', () async {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      await wallet.createWallet(mnemonic);

      final signed = await wallet.signDlcAdaptor({
        'cets': ['aa', 'bb'],
      });
      expect(signed.adaptorSigs, equals(['fake-adaptor-0', 'fake-adaptor-1']));
      expect(signed.refundSig, equals('fake-refund'));
    });
  });
}
