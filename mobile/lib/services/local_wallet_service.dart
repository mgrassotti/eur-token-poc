import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Narrow API for the local-wallet debug screen (allows fakes in widget tests).
///
/// Native BDK (`bdk_flutter`) cannot run under plain `flutter test` — use a fake
/// [LocalWalletApi] there. Integration tests on a simulator may call the real
/// [LocalWalletService], but wallet create/load can still be flaky without
/// platform plugins linked correctly.
abstract class LocalWalletApi {
  Future<bool> tryLoad();
  Future<String> create();
  Future<String> receiveAddress();
}

/// Phase 2 spike: local BDK wallet (mnemonic + receive address).
///
/// Not production-ready: mnemonic is stored in SharedPreferences plaintext,
/// uses an in-memory DB, and does not sync to Esplora yet.
///
/// TODO(phase2): encrypted seed backup, sqlite wallet DB, Esplora sync,
/// PSBT signing for DLC funding, replace relay deposit address path.
class LocalWalletService implements LocalWalletApi {
  LocalWalletService({this.network = Network.testnet});

  static const _mnemonicKey = 'mat_local_wallet_mnemonic_v1';

  final Network network;

  Wallet? _wallet;
  String? _mnemonicPhrase;

  bool get isLoaded => _wallet != null;
  String? get mnemonicPhrase => _mnemonicPhrase;

  /// Load an existing mnemonic from prefs, or return null if none stored.
  @override
  Future<bool> tryLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final phrase = prefs.getString(_mnemonicKey);
    if (phrase == null || phrase.isEmpty) return false;
    await _openFromMnemonic(phrase);
    return true;
  }

  /// Create a new 12-word wallet and persist the mnemonic (debug only).
  @override
  Future<String> create() async {
    final mnemonic = await Mnemonic.create(WordCount.words12);
    final phrase = mnemonic.asString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mnemonicKey, phrase);
    await _openFromMnemonic(phrase);
    return phrase;
  }

  /// Next unused receive address (BIP84 external).
  @override
  Future<String> receiveAddress() async {
    final wallet = _wallet;
    if (wallet == null) {
      throw StateError('Wallet not loaded — call tryLoad() or create() first');
    }
    final info = wallet.getAddress(addressIndex: const AddressIndex.increase());
    return info.address.toString();
  }

  Future<void> _openFromMnemonic(String phrase) async {
    final mnemonic = await Mnemonic.fromString(phrase);
    final secretKey = await DescriptorSecretKey.create(
      network: network,
      mnemonic: mnemonic,
    );
    final descriptor = await Descriptor.newBip84(
      secretKey: secretKey,
      network: network,
      keychain: KeychainKind.externalChain,
    );
    _wallet = await Wallet.create(
      descriptor: descriptor,
      network: network,
      databaseConfig: const DatabaseConfig.memory(),
    );
    _mnemonicPhrase = phrase;
  }
}
