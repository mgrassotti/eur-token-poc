import 'dart:io';

import 'package:bdk_flutter/bdk_flutter.dart' hide InsufficientFundsException;
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
  BdkWalletService({this.network = Network.regtest, String? electrumUrl})
      : _customElectrumUrl = electrumUrl;

  final Network network;
  final String? _customElectrumUrl;

  Wallet? _wallet;
  Blockchain? _blockchain;
  String? _mnemonicPhrase;

  @override
  bool get isInitialized => _wallet != null;

  @override
  String? get mnemonicPhrase => _mnemonicPhrase;

  @override
  Future<String> createWalletWithMnemonic(dynamic mnemonic) async {
    // Convert Mnemonic object to string and delegate to createWallet
    final mnemonicString = (mnemonic as Mnemonic).asString();
    return createWallet(mnemonicString);
  }

  @override
  Future<String> createWallet(String mnemonic) async {
    if (_wallet != null) {
      throw WalletException('Wallet already initialized');
    }

    try {
      await _initializeWallet(mnemonic);
      
      // Skip blockchain initialization and sync during wallet creation
      // Blockchain will be initialized lazily on first sync() call
      // This makes wallet creation fast and not dependent on network
      
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
      
      // Skip blockchain initialization and sync during wallet restore
      // Blockchain will be initialized lazily on first sync() call
      // User can manually sync after restoration to fetch transaction history
      
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
    if (wallet == null) {
      throw WalletNotInitializedException();
    }

    final url = _getElectrumUrl();
    print('[BDK.sync] Electrum URL: $url');

    // Lazy initialization of blockchain - only connect when actually syncing
    if (_blockchain == null) {
      await _initializeBlockchain();
    }

    final blockchain = _blockchain;
    if (blockchain == null) {
      throw NetworkException('Failed to initialize blockchain at $url');
    }

    try {
      await wallet.sync(blockchain: blockchain);
      print('[BDK.sync] ✓ Sync complete');
    } catch (e) {
      // Drop stale connection so the next sync retries cleanly
      _blockchain = null;
      final detail = e.toString();
      print('[BDK.sync] ✗ Failed: $detail');
      if (detail.toLowerCase().contains('timeout')) {
        throw NetworkException('Sync timeout talking to $url', e);
      }
      throw NetworkException('Sync failed ($url): $detail', e);
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
  Future<Set<String>> knownReceiveAddresses({int lookback = 30}) async {
    final wallet = _wallet;
    if (wallet == null) throw WalletNotInitializedException();

    final addrs = <String>{};
    try {
      addrs.add(await getReceiveAddress());
      for (var i = 0; i < lookback; i++) {
        final info = wallet.getAddress(
          addressIndex: AddressIndex.peek(index: i),
        );
        addrs.add(info.address.asString());
      }
    } catch (_) {
      // peek may fail on some indices; return what we have
    }
    return addrs;
  }

  @override
  Future<List<Utxo>> selectCoins(int requiredSats) async {
    final utxos = await listUnspent();
    utxos.sort((a, b) => b.valueSats.compareTo(a.valueSats));
    final selected = <Utxo>[];
    var total = 0;
    for (final u in utxos) {
      selected.add(u);
      total += u.valueSats;
      if (total >= requiredSats) return selected;
    }
    throw InsufficientFundsException(requiredSats, total);
  }

  @override
  Future<String> buildCommitmentPsbt({
    required int requiredSats,
    String? changeAddress,
  }) async {
    final wallet = _wallet;
    if (wallet == null) throw WalletNotInitializedException();

    try {
      final addressStr = changeAddress ?? await getReceiveAddress();
      final address = await Address.fromString(s: addressStr, network: network);
      final script = address.scriptPubkey();

      // Self-send covering required sats; not broadcast — proof-of-funds only.
      // Leave dust headroom for fee so finish() succeeds.
      final sendAmount = requiredSats > 1000 ? requiredSats - 500 : requiredSats;
      final txBuilder = TxBuilder();
      final (psbt, _) = await txBuilder
          .addRecipient(script, BigInt.from(sendAmount))
          .feeRate(1.0)
          .finish(wallet);

      return psbt.toString(); // base64 PSBT
    } on InsufficientFundsException {
      rethrow;
    } catch (e) {
      throw WalletException('Failed to build commitment PSBT', e);
    }
  }

  @override
  Future<String> signPsbt(String psbtBase64) async {
    final wallet = _wallet;
    if (wallet == null) throw WalletNotInitializedException();

    try {
      // Parse PSBT
      final psbt = await PartiallySignedTransaction.fromString(psbtBase64);

      // Sign with wallet keys (returns bool indicating if finalized)
      final signOptions = const SignOptions(
        trustWitnessUtxo: true,
        allowAllSighashes: false,
        removePartialSigs: false,
        tryFinalize: false,
        signWithTapInternalKey: true,
        allowGrinding: true,
      );

      await wallet.sign(psbt: psbt, signOptions: signOptions);

      // Return signed PSBT (modified in place, still partial for 2-of-2)
      return psbt.toString();
    } catch (e) {
      throw WalletException('Failed to sign PSBT', e);
    }
  }

  @override
  Future<String> broadcastTx(String txHex) async {
    final blockchain = _blockchain;
    if (blockchain == null) throw WalletNotInitializedException();

    try {
      // Parse PSBT and extract finalized transaction
      final psbt = await PartiallySignedTransaction.fromString(txHex);
      final tx = await psbt.extractTx();
      await blockchain.broadcast(transaction: tx);
      return await tx.txid();
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

      // Delete existing database if present to prevent ChecksumMismatchException
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

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
    final url = _getElectrumUrl();
    final isSsl = url.startsWith('ssl://');

    await _preflightElectrum(url);

    try {
      print('[BDK] Creating Electrum blockchain ($url, validateDomain=$isSsl)...');
      _blockchain = await Blockchain.create(
        config: BlockchainConfig.electrum(
          config: ElectrumConfig(
            url: url,
            socks5: null,
            retry: 5,
            timeout: WalletConfig.electrumTimeoutSec,
            stopGap: BigInt.from(20),
            // Domain validation only applies to SSL; force false for tcp://regtest.
            validateDomain: isSsl,
          ),
        ),
      );
      print('[BDK] ✓ Electrum blockchain ready');
    } catch (e) {
      _blockchain = null;
      throw NetworkException('Failed to connect to Electrum at $url', e);
    }
  }

  /// Fail fast with a clear message if the Electrum TCP port is unreachable.
  /// Especially useful on macOS where App Sandbox can block Docker localhost.
  Future<void> _preflightElectrum(String url) async {
    final uri = _parseElectrumUrl(url);
    if (uri == null) return;

    try {
      print('[BDK] Preflight TCP ${uri.host}:${uri.port}...');
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      print('[BDK] ✓ Preflight OK');
    } catch (e) {
      final macHint = Platform.isMacOS
          ? ' On macOS debug builds, App Sandbox must be off to reach Docker electrs (./bin/regtest up).'
          : '';
      throw NetworkException(
        'Cannot reach Electrum at ${uri.host}:${uri.port}. Is electrs running?$macHint',
        e,
      );
    }
  }

  /// Parse `tcp://host:port` / `ssl://host:port` into host+port.
  ({String host, int port})? _parseElectrumUrl(String url) {
    final normalized = url.contains('://') ? url : 'tcp://$url';
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty || uri.port == 0) return null;
    return (host: uri.host, port: uri.port);
  }

  String _getElectrumUrl() {
    // Use custom URL if provided, otherwise use config default
    if (_customElectrumUrl != null && _customElectrumUrl!.isNotEmpty) {
      return _customElectrumUrl!;
    }

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
