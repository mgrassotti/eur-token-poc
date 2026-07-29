/// Abstract interface for Bitcoin wallet operations.
///
/// Enables testing with mock implementations ([FakeWalletService]) and supports
/// multiple backends (BDK on-device, or future server-backed relay wallets).
///
/// Phase 2 target: Replace all Rails L1 wallet dependencies with BDK.
abstract class WalletApi {
  /// Creates a new wallet from a Mnemonic object.
  ///
  /// - Accepts a BDK Mnemonic object (avoids string conversion issues)
  /// - Derives BIP84 descriptors (native segwit)
  /// - Initializes wallet database
  /// - Returns the first receive address
  ///
  /// Throws [WalletException] if mnemonic invalid or wallet already exists.
  Future<String> createWalletWithMnemonic(dynamic mnemonic);

  /// Creates a new wallet from a mnemonic phrase.
  ///
  /// - Generates or accepts a 12/24-word BIP39 mnemonic
  /// - Derives BIP84 descriptors (native segwit)
  /// - Initializes wallet database
  /// - Returns the first receive address
  ///
  /// Throws [WalletException] if mnemonic invalid or wallet already exists.
  Future<String> createWallet(String mnemonic);

  /// Restores wallet from existing mnemonic phrase.
  ///
  /// - Validates BIP39 mnemonic
  /// - Performs full blockchain sync (may take minutes)
  /// - Returns the first receive address
  ///
  /// Throws [WalletException] if mnemonic invalid or sync fails.
  Future<String> restoreWallet(String mnemonic);

  /// Returns the next unused receive address (BIP84 external chain).
  ///
  /// Uses BDK's `AddressIndex.lastUnused()` to avoid address reuse.
  ///
  /// Throws [WalletException] if wallet not initialized.
  Future<String> getReceiveAddress();

  /// Returns total balance in satoshis (confirmed + unconfirmed).
  ///
  /// Throws [WalletException] if wallet not initialized.
  Future<int> getBalance();

  /// Syncs wallet state with blockchain via Electrum/Esplora.
  ///
  /// - Fetches new transactions
  /// - Updates UTXO set
  /// - May take 5-30 seconds on first sync
  ///
  /// Throws [WalletException] if network error or wallet not initialized.
  Future<void> sync();

  /// Lists all unspent transaction outputs (UTXOs).
  ///
  /// Used for coin selection when funding DLC contracts (Phase 3).
  ///
  /// Throws [WalletException] if wallet not initialized.
  Future<List<Utxo>> listUnspent();

  /// Signs a Partially Signed Bitcoin Transaction (PSBT).
  ///
  /// - Parses PSBT base64
  /// - Signs all inputs that belong to this wallet
  /// - Returns partially signed PSBT (for 2-of-2 multisig)
  ///
  /// Used for DLC funding transaction signing (Phase 3).
  ///
  /// Throws [WalletException] if PSBT invalid or wallet not initialized.
  Future<String> signPsbt(String psbtBase64);

  /// Broadcasts a fully signed transaction to the Bitcoin network.
  ///
  /// Returns the transaction ID (txid).
  ///
  /// Throws [WalletException] if transaction invalid or broadcast fails.
  Future<String> broadcastTx(String txHex);

  /// Closes wallet and cleans up resources.
  ///
  /// Should be called when switching wallets or app closing.
  Future<void> close();

  /// Returns true if wallet is loaded and ready for operations.
  bool get isInitialized;

  /// Returns the wallet's mnemonic phrase (for backup display).
  ///
  /// Returns null if wallet not initialized or mnemonic not accessible.
  /// WARNING: Exposing mnemonic is security-sensitive.
  String? get mnemonicPhrase;
}

/// UTXO (Unspent Transaction Output) representation.
///
/// Used for coin selection when funding DLC contracts.
class Utxo {
  final String txid;
  final int vout;
  final int valueSats;
  final String scriptPubKey;

  Utxo({
    required this.txid,
    required this.vout,
    required this.valueSats,
    required this.scriptPubKey,
  });

  @override
  String toString() => 'Utxo($txid:$vout, $valueSats sats)';
}

/// Base exception for wallet operations.
class WalletException implements Exception {
  final String message;
  final Object? cause;

  WalletException(this.message, [this.cause]);

  @override
  String toString() => 'WalletException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Wallet not initialized (call createWallet or restoreWallet first).
class WalletNotInitializedException extends WalletException {
  WalletNotInitializedException() : super('Wallet not initialized');
}

/// Insufficient balance for operation.
class InsufficientFundsException extends WalletException {
  final int required;
  final int available;

  InsufficientFundsException(this.required, this.available)
      : super('Insufficient funds: need $required sats, have $available sats');
}

/// Network/sync error.
class NetworkException extends WalletException {
  NetworkException(String message, [Object? cause]) : super(message, cause);
}

/// Invalid mnemonic phrase.
class InvalidMnemonicException extends WalletException {
  InvalidMnemonicException([String message = 'Invalid mnemonic phrase']) : super(message);
}
