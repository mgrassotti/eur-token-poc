import 'package:shared_preferences/shared_preferences.dart';

import 'wallet_api.dart';

/// Manages wallet lifecycle and mnemonic persistence.
///
/// Wraps [WalletApi] implementation and handles:
/// - Mnemonic storage (SharedPreferences plaintext for v1)
/// - Wallet initialization on app launch
/// - Automatic sync scheduling
///
/// **Security warning:** Mnemonic is stored in plaintext. Phase 2.1 will add:
/// - Encrypted storage (iOS Keychain / Android KeyStore)
/// - Optional passphrase protection
/// - Biometric unlock
class WalletLifecycleManager {
  WalletLifecycleManager(this._wallet);

  static const _mnemonicKey = 'mat_wallet_mnemonic_v1';
  static const _hasWalletKey = 'mat_wallet_exists_v1';

  final WalletApi _wallet;

  /// Returns true if a wallet was previously created and stored.
  Future<bool> hasStoredWallet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasWalletKey) ?? false;
  }

  /// Attempts to load an existing wallet from stored mnemonic.
  ///
  /// Returns true if wallet was loaded successfully, false if no wallet stored.
  ///
  /// Throws [WalletException] if mnemonic exists but wallet load fails.
  Future<bool> tryLoadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    final mnemonic = prefs.getString(_mnemonicKey);

    if (mnemonic == null || mnemonic.isEmpty) {
      return false;
    }

    try {
      await _wallet.restoreWallet(mnemonic);
      return true;
    } catch (e) {
      // If mnemonic is corrupted, clear it
      await _clearStoredMnemonic();
      rethrow;
    }
  }

  /// Creates a new wallet with the given mnemonic and persists it.
  ///
  /// Returns the wallet's first receive address.
  ///
  /// Throws [WalletException] if wallet already exists or creation fails.
  Future<String> createWallet(String mnemonic) async {
    if (await hasStoredWallet()) {
      throw WalletException('Wallet already exists. Delete first.');
    }

    final address = await _wallet.createWallet(mnemonic);

    // Persist mnemonic
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mnemonicKey, mnemonic);
    await prefs.setBool(_hasWalletKey, true);

    return address;
  }

  /// Restores wallet from mnemonic phrase (backup recovery).
  ///
  /// Overwrites existing wallet if present.
  ///
  /// Returns the wallet's first receive address.
  Future<String> restoreWallet(String mnemonic) async {
    // Close existing wallet if any
    if (_wallet.isInitialized) {
      await _wallet.close();
    }

    final address = await _wallet.restoreWallet(mnemonic);

    // Persist mnemonic
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mnemonicKey, mnemonic);
    await prefs.setBool(_hasWalletKey, true);

    return address;
  }

  /// Deletes wallet and clears stored mnemonic.
  ///
  /// **WARNING:** This is irreversible unless user has backed up mnemonic!
  Future<void> deleteWallet() async {
    if (_wallet.isInitialized) {
      await _wallet.close();
    }
    await _clearStoredMnemonic();
  }

  /// Returns stored mnemonic for backup display.
  ///
  /// Returns null if no wallet stored.
  Future<String?> getStoredMnemonic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mnemonicKey);
  }

  Future<void> _clearStoredMnemonic() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mnemonicKey);
    await prefs.remove(_hasWalletKey);
  }
}
