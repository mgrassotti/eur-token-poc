import 'wallet_api.dart';

/// Mock wallet implementation for testing without BDK native dependencies.
///
/// Use this in unit tests where `bdk_flutter` cannot run (pure Dart `flutter test`).
/// Integration tests on simulators should use [BdkWalletService].
///
/// Example:
/// ```dart
/// test('wallet creation', () async {
///   final wallet = FakeWalletService();
///   await wallet.createWallet('abandon abandon...');
///   expect(wallet.isInitialized, true);
/// });
/// ```
class FakeWalletService implements WalletApi {
  String? _mnemonicPhrase;
  String? _receiveAddress;
  int _balance = 0;
  final Map<String, Utxo> _utxos = {};
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  String? get mnemonicPhrase => _mnemonicPhrase;

  @override
  Future<String> createWalletWithMnemonic(dynamic mnemonic) async {
    if (_initialized) {
      throw WalletException('Wallet already initialized');
    }

    await Future.delayed(const Duration(milliseconds: 100)); // Simulate work

    // For FakeWalletService, convert mnemonic to string
    _mnemonicPhrase = mnemonic.toString();
    _receiveAddress = _generateFakeAddress();
    _initialized = true;

    return _receiveAddress!;
  }

  @override
  Future<String> createWallet(String mnemonic) async {
    if (_initialized) {
      throw WalletException('Wallet already initialized');
    }

    await Future.delayed(const Duration(milliseconds: 100)); // Simulate work

    _mnemonicPhrase = mnemonic;
    _receiveAddress = _generateFakeAddress();
    _initialized = true;

    return _receiveAddress!;
  }

  @override
  Future<String> restoreWallet(String mnemonic) async {
    if (_initialized) {
      throw WalletException('Wallet already initialized');
    }

    await Future.delayed(const Duration(milliseconds: 200)); // Simulate sync

    _mnemonicPhrase = mnemonic;
    _receiveAddress = _generateFakeAddress();
    _initialized = true;

    return _receiveAddress!;
  }

  @override
  Future<String> getReceiveAddress() async {
    if (!_initialized) throw WalletNotInitializedException();
    return _receiveAddress ?? _generateFakeAddress();
  }

  @override
  Future<int> getBalance() async {
    if (!_initialized) throw WalletNotInitializedException();
    return _balance;
  }

  @override
  Future<void> sync() async {
    if (!_initialized) throw WalletNotInitializedException();
    await Future.delayed(const Duration(milliseconds: 50)); // Simulate network
  }

  @override
  Future<List<Utxo>> listUnspent() async {
    if (!_initialized) throw WalletNotInitializedException();
    return _utxos.values.toList();
  }

  @override
  Future<String> signPsbt(String psbtBase64) async {
    if (!_initialized) throw WalletNotInitializedException();
    await Future.delayed(const Duration(milliseconds: 20)); // Simulate signing

    // Return same PSBT with fake signature appended
    return '$psbtBase64-SIGNED';
  }

  @override
  Future<String> broadcastTx(String txHex) async {
    if (!_initialized) throw WalletNotInitializedException();
    await Future.delayed(const Duration(milliseconds: 50)); // Simulate broadcast

    // Return fake txid
    return 'fake-txid-${txHex.hashCode.toRadixString(16)}';
  }

  @override
  Future<void> close() async {
    _initialized = false;
    _mnemonicPhrase = null;
    _receiveAddress = null;
    _balance = 0;
    _utxos.clear();
  }

  // Test helpers

  /// Manually set balance for testing.
  void setBalance(int sats) {
    _balance = sats;
  }

  /// Manually add UTXO for testing.
  void addUtxo(Utxo utxo) {
    _utxos['${utxo.txid}:${utxo.vout}'] = utxo;
    _balance += utxo.valueSats;
  }

  /// Remove UTXO (simulate spending).
  void removeUtxo(String txid, int vout) {
    final key = '$txid:$vout';
    final utxo = _utxos.remove(key);
    if (utxo != null) {
      _balance -= utxo.valueSats;
    }
  }

  /// Clear all UTXOs.
  void clearUtxos() {
    _utxos.clear();
    _balance = 0;
  }

  /// Generate fake Bitcoin address for testing.
  String _generateFakeAddress() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final hexStr = random.toRadixString(16).padRight(40, '0');
    return 'bcrt1qfake${hexStr.substring(0, 36)}';
  }
}
