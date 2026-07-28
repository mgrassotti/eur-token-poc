import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../config/wallet_config.dart';
import 'wallet_api.dart';

/// BDK-based wallet service for on-device Bitcoin operations.
///
/// **Phase 2 Production Implementation:**
/// - BIP84 (native segwit) wallet
/// - Persistent SQLite database
/// - Electrum sync (regtest/testnet/mainnet)
/// - PSBT signing for DLC funding (Phase 3 ready)
///
/// **Not yet implemented:**
/// - Encrypted mnemonic storage (uses plaintext for v1 - paper backup recommended)
/// - Fee estimation (uses default)
/// - Coin control / manual UTXO selection
class BdkWalletService implements WalletApi {
  BdkWalletService({this.network = Network.regtest});

  final Network network;

  Wallet? _wallet;
  Blockchain? _blockchain;
  String? _mnemonicPhrase;

  @override
  bool get isInitialized => _wallet != null;

  @override
  String? get mnemonicPhrase => _mnemonicPhrase;

  @override
  Future<String> createWallet(String mnemonic) async {
    if (_wallet != null) {
      throw WalletException('Wallet already initialized');
    }

    try {
      await _initializeWallet(mnemonic);
      await _initializeBlockchain();
      await sync(); // Initial sync

      return await getReceiveAddress();
    } catch (e) {
      throw WalletException('Failed to create wallet', e);
    }
  }

  @override
  Future<String> restoreWallet(String mnemonic) async {
    if (_wallet != null) {
      throw WalletException('Wallet already initialized');
    }

    try {
      await _initializeWallet(mnemonic);
      await _initializeBlockchain();
      await sync(); // Full sync (may take minutes)

      return await getReceiveAddress();
    } catch (e) {
      throw WalletException('Failed to restore wallet', e);
    }
  }

  @override
  Future<String> getReceiveAddress() async {
    final wallet = _wallet;
    if (wallet == null) throw WalletNotInitializedException();

    try {
      final addressInfo = wallet.getAddress(
        addressIndex: const AddressIndex.lastUnused(),
      );
      return addressInfo.address.asString();
    } catch (e) {
      throw WalletException('Failed to get receive address', e);
    }
  }

  @override
  Future<int> getBalance() async {
    final wallet = _wallet;
    if (wallet == null) throw WalletNotInitializedException();

    try {
      final balance = await wallet.getBalance();
      return balance.total.toInt();
    } catch (e) {
      throw WalletException('Failed to get balance', e);
    }
  }

  @override
  Future<void> sync() async {
    final wallet = _wallet;
    final blockchain = _blockchain;

    if (wallet == null || blockchain == null) {
      throw WalletNotInitializedException();
    }

    try {
      await wallet.sync(blockchain: blockchain);
    } on Exception catch (e) {
      // BDK may throw various exceptions (network, timeout, etc.)
      if (e.toString().contains('timeout')) {
        throw NetworkException('Sync timeout - check network connection', e);
      } else if (e.toString().contains('connection')) {
        throw NetworkException('Cannot connect to Electrum server', e);
      } else {
        throw NetworkException('Sync failed', e);
      }
    }
  }

  @override
  Future<List<Utxo>> listUnspent() async {
    final wallet = _wallet;
    if (wallet == null) throw WalletNotInitializedException();

    try {
      final utxos = await wallet.listUnspent();
      return utxos.map((u) {
        return Utxo(
          txid: u.outpoint.txid,
          vout: u.outpoint.vout,
          valueSats: u.txout.value.toInt(),
          scriptPubKey: '', // BDK doesn't expose directly (would need descriptor)
        );
      }).toList();
    } catch (e) {
      throw WalletException('Failed to list UTXOs', e);
    }
  }

  @override
  Future<String> signPsbt(String psbtBase64) async {
    final wallet = _wallet;
    if (wallet == null) throw WalletNotInitializedException();

    try {
      // Parse PSBT
      final psbt = await PartiallySignedTransaction.fromString(psbtBase64);

      // Sign with wallet keys
      final signOptions = const SignOptions(
        trustWitnessUtxo: true,
        allowAllSighashes: false,
        removePartialSigs: false,
        tryFinalize: false,
      );

      final signed = await wallet.sign(psbt: psbt, signOptions: signOptions);

      // Return signed PSBT (still partial for 2-of-2)
      return signed.asString();
    } catch (e) {
      throw WalletException('Failed to sign PSBT', e);
    }
  }

  @override
  Future<String> broadcastTx(String txHex) async {
    final blockchain = _blockchain;
    if (blockchain == null) throw WalletNotInitializedException();

    try {
      final tx = await Transaction.fromString(txHex, network);
      await blockchain.broadcast(transaction: tx);
      return tx.txid();
    } catch (e) {
      throw WalletException('Failed to broadcast transaction', e);
    }
  }

  @override
  Future<void> close() async {
    // BDK cleanup (wallet and blockchain auto-disposed by Dart GC)
    _wallet = null;
    _blockchain = null;
    _mnemonicPhrase = null;
  }

  // Private helpers

  Future<void> _initializeWallet(String mnemonicPhrase) async {
    try {
      final mnemonic = await Mnemonic.fromString(mnemonicPhrase);
      _mnemonicPhrase = mnemonicPhrase;

      final secretKey = await DescriptorSecretKey.create(
        network: network,
        mnemonic: mnemonic,
      );

      // BIP84 descriptors (native segwit)
      final external = await Descriptor.newBip84(
        secretKey: secretKey,
        keychain: KeychainKind.externalChain,
        network: network,
      );
      final internal = await Descriptor.newBip84(
        secretKey: secretKey,
        keychain: KeychainKind.internalChain,
        network: network,
      );

      // Persistent SQLite database
      final dbPath = await _getDbPath();

      _wallet = await Wallet.create(
        descriptor: external,
        changeDescriptor: internal,
        network: network,
        databaseConfig: DatabaseConfig.sqlite(
          config: SqliteDbConfiguration(path: dbPath),
        ),
      );
    } catch (e) {
      if (e.toString().contains('mnemonic')) {
        throw InvalidMnemonicException('Invalid recovery phrase');
      }
      rethrow;
    }
  }

  Future<void> _initializeBlockchain() async {
    try {
      _blockchain = await Blockchain.create(
        config: BlockchainConfig.electrum(
          config: ElectrumConfig(
            url: _getElectrumUrl(),
            socks5: null,
            retry: 3,
            timeout: WalletConfig.electrumTimeoutSec,
            stopGap: 10,
          ),
        ),
      );
    } catch (e) {
      throw NetworkException('Failed to connect to Electrum', e);
    }
  }

  String _getElectrumUrl() {
    switch (network) {
      case Network.regtest:
        return WalletConfig.regtestElectrumUrl;
      case Network.testnet:
        return WalletConfig.testnetElectrumUrl;
      case Network.bitcoin:
        return WalletConfig.mainnetElectrumUrl;
      case Network.signet:
        return 'tcp://127.0.0.1:60601'; // Local signet
    }
  }

  Future<String> _getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/bdk_wallet_${network.name}.db';
  }
}

/// Compatibility: Retain LocalWalletService name for existing code.
///
/// Use [BdkWalletService] for new code (Phase 2 production).
@Deprecated('Use BdkWalletService instead')
typedef LocalWalletService = BdkWalletService;
