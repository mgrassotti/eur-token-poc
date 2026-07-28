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
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      data = await _api.fetchDashboard();
      loading = false;
      notifyListeners();
    } on RelayApiException catch (e) {
      error = e.message;
      loading = false;
      notifyListeners();
    }
  }
}

/// Phase 2: On-device BDK wallet state (replaces relay reserve).
class WalletState extends ChangeNotifier {
  WalletState({WalletApi? wallet, String? electrumUrl})
      : _wallet = wallet ?? BdkWalletService(network: Network.regtest, electrumUrl: electrumUrl),
        _lifecycle = WalletLifecycleManager(
            wallet ?? BdkWalletService(network: Network.regtest, electrumUrl: electrumUrl)) {
    _initialize();
  }

  final WalletApi _wallet;
  final WalletLifecycleManager _lifecycle;

  String? receiveAddress;
  int balanceSats = 0;
  bool loading = false;
  bool syncing = false;
  String? error;
  String? lastSyncError; // Separate field for sync-specific errors

  bool get isInitialized => _wallet.isInitialized;
  String? get mnemonicPhrase => _wallet.mnemonicPhrase;

  Future<void> _initialize() async {
    loading = true;
    notifyListeners();

    try {
      final hasWallet = await _lifecycle.hasStoredWallet();
      if (hasWallet) {
        await _lifecycle.tryLoadWallet();
        await _refreshWalletData();
      }
    } catch (e) {
      error = 'Failed to load wallet: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Creates a new wallet with a generated 12-word mnemonic.
  Future<String?> createWallet() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final mnemonic = await Mnemonic.create(WordCount.words12);
      final address = await _lifecycle.createWallet(mnemonic.asString());

      receiveAddress = address;
      balanceSats = 0;
      loading = false;
      notifyListeners();

      return mnemonic.asString();
    } catch (e) {
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
      lastSyncError = e.message;
      error = 'Sync failed: ${e.message}';
    } catch (e) {
      lastSyncError = e.toString();
      error = 'Sync failed: $e';
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

  Future<void> _refreshWalletData() async {
    if (!_wallet.isInitialized) return;

    try {
      receiveAddress = await _wallet.getReceiveAddress();
      balanceSats = await _wallet.getBalance();
    } catch (e) {
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
