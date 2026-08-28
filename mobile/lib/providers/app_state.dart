import 'dart:async';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/local_wallet_service.dart';
import '../services/relay_api_client.dart';
import '../services/wallet_api.dart';
import '../services/wallet_lifecycle_manager.dart';

class AuthState extends ChangeNotifier {
  AuthState(this._api);

  final RelayApiClient _api;
  User? user;
  bool loading = false;
  String? error;

  bool get isLoggedIn => user != null;

  /// Login timeout duration (15 seconds).
  /// Adjust this value if your network or server typically takes longer to respond.
  /// After timeout, the login button will be re-enabled and an error shown.
  static const _loginTimeout = Duration(seconds: 15);

  Future<bool> login(String email, String password) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final body = await _api.login(email, password).timeout(
        _loginTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Connection timeout. Please check your network and try again.',
            _loginTimeout,
          );
        },
      );
      user = User.fromJson(body['user'] as Map<String, dynamic>);
      loading = false;
      notifyListeners();
      return true;
    } on TimeoutException catch (e) {
      error = e.message ?? 'Connection timeout. Please try again.';
      loading = false;
      notifyListeners();
      return false;
    } on RelayApiException catch (e) {
      error = e.message;
      loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      error = 'Connection error. Please check if the server is running.';
      loading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    user = null;
    _api.setToken(null);
    notifyListeners();
  }
}

class DashboardState extends ChangeNotifier {
  DashboardState(this._api);

  final RelayApiClient _api;
  DashboardData? data;
  double? marketRateEur;
  List<Deal> openDeals = const [];
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      data = await _api.fetchDashboard();
      marketRateEur = data?.marketRateEur ?? marketRateEur;
      loading = false;
      notifyListeners();
    } on RelayApiException catch (e) {
      error = e.message;
      loading = false;
      notifyListeners();
    }
  }

  /// Phase 2: Fetch public BTC/EUR rate without login for reserve EUR display.
  Future<void> refreshMarketRate() async {
    try {
      marketRateEur = await _api.fetchMarketRate();
      error = null;
      notifyListeners();
    } on RelayApiException catch (e) {
      // Keep last known rate; surface error lightly
      error = e.message;
      notifyListeners();
    }
  }

  /// Public marketplace list (no auth).
  Future<void> refreshOpenDeals() async {
    try {
      openDeals = await _api.fetchDeals();
      notifyListeners();
    } on RelayApiException catch (e) {
      error = e.message;
      notifyListeners();
    }
  }
}

/// Phase 2: On-device BDK wallet state (replaces relay reserve).
class WalletState extends ChangeNotifier {
  // Factory constructor to ensure _wallet and _lifecycle use the SAME instance
  factory WalletState({WalletApi? wallet, String? electrumUrl, RelayApiClient? api}) {
    final walletInstance = wallet ?? BdkWalletService(network: Network.regtest, electrumUrl: electrumUrl);
    return WalletState._internal(walletInstance, WalletLifecycleManager(walletInstance), api);
  }

  WalletState._internal(this._wallet, this._lifecycle, this._api) {
    // Delay initialization to avoid blocking UI during construction
    Future.microtask(() => _initialize());
  }

  final WalletApi _wallet;
  final WalletLifecycleManager _lifecycle;
  final RelayApiClient? _api;

  String? receiveAddress;
  int balanceSats = 0;
  bool loading = false;
  bool syncing = false;
  String? error;
  String? lastSyncError; // Separate field for sync-specific errors

  bool get isInitialized => _wallet.isInitialized;
  String? get mnemonicPhrase => _wallet.mnemonicPhrase;

  Future<void> _initialize() async {
    print('[WalletState] Starting initialization...');
    loading = true;
    notifyListeners();

    try {
      print('[WalletState] Checking for stored wallet...');
      final hasWallet = await _lifecycle.hasStoredWallet();
      print('[WalletState] Has stored wallet: $hasWallet');
      
      if (hasWallet) {
        print('[WalletState] Loading existing wallet...');
        await _lifecycle.tryLoadWallet();
        print('[WalletState] ✓ tryLoadWallet() completed, refreshing data...');
        await _refreshWalletData();
        print('[WalletState] ✓ Wallet loaded successfully');
        print('[WalletState]   - Address: $receiveAddress');
        print('[WalletState]   - Balance: $balanceSats sats');
        print('[WalletState]   - Initialized: ${_wallet.isInitialized}');
      } else {
        print('[WalletState] No existing wallet found');
      }
    } catch (e) {
      print('[WalletState] Initialization error: $e');
      error = 'Failed to load wallet: $e';
    } finally {
      loading = false;
      print('[WalletState] Initialization complete. Loading: $loading, Error: $error');
      notifyListeners();
    }
  }

  /// Creates a new wallet with a generated 12-word mnemonic.
  Future<String?> createWallet() async {
    print('[WalletState.createWallet] Starting...');
    loading = true;
    error = null;
    notifyListeners();

    try {
      print('[WalletState.createWallet] Generating mnemonic...');
      final mnemonic = await Mnemonic.create(WordCount.words12);
      final mnemonicString = mnemonic.asString();
      print('[WalletState.createWallet] Mnemonic generated: ${mnemonicString.split(' ').take(3).join(' ')}...');
      print('[WalletState.createWallet] Creating wallet with string mnemonic (no blockchain init)...');
      
      // Use string-based createWallet which skips blockchain initialization
      // Blockchain will be lazily initialized on first sync()
      final address = await _lifecycle.createWallet(mnemonicString);
      print('[WalletState.createWallet] ✓ Wallet created with address: $address');

      print('[WalletState.createWallet] Setting receive address...');
      receiveAddress = address;
      balanceSats = 0;

      // Phase 2: Register address with server so admin can fund
      if (_api != null) {
        try {
          print('[WalletState.createWallet] Registering address with server...');
          await _api.updateReserveAddress(address);
          print('[WalletState.createWallet] ✓ Address registered with server');
        } catch (e) {
          print('[WalletState.createWallet] Warning: Failed to register address with server: $e');
          // Don't fail wallet creation if server registration fails
          // User can still use the wallet, just admin funding won't work until they register manually
        }
      }
      
      print('[WalletState.createWallet] Setting loading=false and notifying listeners...');
      loading = false;
      notifyListeners();
      
      print('[WalletState.createWallet] ✓ Complete! Returning mnemonic string');
      return mnemonicString;
    } catch (e) {
      print('[WalletState.createWallet] ✗ Error: $e');
      error = 'Failed to create wallet: $e';
      loading = false;
      notifyListeners();
      return null;
    }
  }

  /// Restores wallet from a mnemonic phrase.
  Future<bool> restoreWallet(String mnemonic) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _lifecycle.restoreWallet(mnemonic);
      await _refreshWalletData();

      loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Failed to restore wallet: $e';
      loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Syncs wallet with blockchain and updates balance.
  Future<void> sync() async {
    if (!_wallet.isInitialized) {
      error = 'Wallet not initialized';
      notifyListeners();
      return;
    }

    syncing = true;
    error = null;
    lastSyncError = null;
    notifyListeners();

    try {
      await _wallet.sync();
      await _refreshWalletData();
    } on NetworkException catch (e) {
      // Include cause so macOS sandbox / connection errors are visible in the UI
      lastSyncError = e.cause != null ? '${e.message} (${e.cause})' : e.message;
      error = 'Sync failed: ${e.message}';
      print('[WalletState.sync] ✗ $lastSyncError');
    } catch (e) {
      lastSyncError = e.toString();
      error = 'Sync failed: $e';
      print('[WalletState.sync] ✗ $lastSyncError');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Deletes wallet and clears all data.
  Future<void> deleteWallet() async {
    loading = true;
    notifyListeners();

    try {
      await _lifecycle.deleteWallet();

      receiveAddress = null;
      balanceSats = 0;
      error = null;
      loading = false;
      notifyListeners();
    } catch (e) {
      error = 'Failed to delete wallet: $e';
      loading = false;
      notifyListeners();
    }
  }

  Future<String> buildCommitmentPsbt({required int requiredSats}) {
    return _wallet.buildCommitmentPsbt(
      requiredSats: requiredSats,
      changeAddress: receiveAddress,
    );
  }

  Future<List<Utxo>> selectCoins(int requiredSats) => _wallet.selectCoins(requiredSats);

  Future<String> signPsbt(String psbtBase64) => _wallet.signPsbt(psbtBase64);

  Future<List<Utxo>> listUnspent() => _wallet.listUnspent();

  Future<String> nextChangeAddress() => _wallet.getReceiveAddress();

  Future<Set<String>> knownReceiveAddresses() async {
    if (!_wallet.isInitialized) {
      return {
        if (receiveAddress != null) receiveAddress!,
      };
    }
    return _wallet.knownReceiveAddresses();
  }

  /// True if [address] was derived by this wallet (current or recent receive).
  Future<bool> ownsAddress(String? address) async {
    if (address == null || address.isEmpty) return false;
    if (address == receiveAddress) return true;
    if (!_wallet.isInitialized) return false;
    final known = await knownReceiveAddresses();
    return known.contains(address);
  }

  bool ownsAddressSync(String? address, Set<String> known) {
    if (address == null || address.isEmpty) return false;
    return address == receiveAddress || known.contains(address);
  }

  Future<void> _refreshWalletData() async {
    print('[WalletState._refreshWalletData] Checking initialization...');
    if (!_wallet.isInitialized) {
      print('[WalletState._refreshWalletData] Wallet not initialized, skipping');
      return;
    }

    try {
      print('[WalletState._refreshWalletData] Getting receive address...');
      receiveAddress = await _wallet.getReceiveAddress();
      print('[WalletState._refreshWalletData] ✓ Address: $receiveAddress');
      
      print('[WalletState._refreshWalletData] Getting balance...');
      balanceSats = await _wallet.getBalance();
      print('[WalletState._refreshWalletData] ✓ Balance: $balanceSats sats');
    } catch (e) {
      print('[WalletState._refreshWalletData] Error: $e');
      error = 'Failed to refresh wallet data: $e';
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_wallet.isInitialized) {
      _wallet.close();
    }
    super.dispose();
  }
}

class NameState extends ChangeNotifier {
  static const _nameKey = 'user_name';

  String? _name;
  bool _hydrated = false;

  String? get name => _name;
  bool get hasName => _name != null && _name!.isNotEmpty;

  NameState() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hydrated) return;
      _name = prefs.getString(_nameKey);
      _hydrated = true;
      notifyListeners();
    } catch (_) {
      _hydrated = true;
    }
  }

  Future<void> setName(String name) async {
    _hydrated = true;
    _name = name;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, name);
    } catch (_) {
    }
  }

  Future<void> clearName() async {
    _hydrated = true;
    _name = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_nameKey);
    } catch (_) {
    }
  }
}

class SettingsState extends ChangeNotifier {
  static const _advancedFeaturesKey = 'advanced_features';
  static const _localeKey = 'locale_code';
  static const _electrumUrlKey = 'electrum_url';

  static const supportedLocales = [
    Locale('en'),
    Locale('it'),
  ];

  bool advancedFeatures = false;
  Locale locale = const Locale('en');
  String? electrumUrl; // null = use default from WalletConfig
  bool _hydrated = false;

  SettingsState() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hydrated) return;
      advancedFeatures = prefs.getBool(_advancedFeaturesKey) ?? false;
      electrumUrl = prefs.getString(_electrumUrlKey); // null = default
      final code = prefs.getString(_localeKey);
      if (code != null && supportedLocales.any((l) => l.languageCode == code)) {
        locale = Locale(code);
      }
      _hydrated = true;
      notifyListeners();
    } catch (_) {
      _hydrated = true;
    }
  }

  Future<void> setAdvancedFeatures(bool enabled) async {
    _hydrated = true;
    advancedFeatures = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_advancedFeaturesKey, enabled);
    } catch (_) {
    }
  }

  Future<void> setLocale(Locale value) async {
    if (!supportedLocales.any((l) => l.languageCode == value.languageCode)) return;
    _hydrated = true;
    locale = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeKey, value.languageCode);
    } catch (_) {
    }
  }

  Future<void> setElectrumUrl(String? url) async {
    _hydrated = true;
    electrumUrl = url;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (url == null || url.isEmpty) {
        await prefs.remove(_electrumUrlKey);
      } else {
        await prefs.setString(_electrumUrlKey, url);
      }
    } catch (_) {
    }
  }

  String getElectrumUrlOrDefault() {
    if (electrumUrl != null && electrumUrl!.isNotEmpty) {
      return electrumUrl!;
    }
    // Default: local regtest
    return 'tcp://127.0.0.1:50001';
  }
}
