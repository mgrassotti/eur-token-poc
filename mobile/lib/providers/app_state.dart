import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/relay_api_client.dart';

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

class SettingsState extends ChangeNotifier {
  static const _advancedFeaturesKey = 'advanced_features';
  static const _localeKey = 'locale_code';

  static const supportedLocales = [
    Locale('en'),
    Locale('it'),
  ];

  bool advancedFeatures = false;
  Locale locale = const Locale('en');

  SettingsState() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      advancedFeatures = prefs.getBool(_advancedFeaturesKey) ?? false;
      final code = prefs.getString(_localeKey);
      if (code != null && supportedLocales.any((l) => l.languageCode == code)) {
        locale = Locale(code);
      }
      notifyListeners();
    } catch (_) {
      // Keep defaults; prefs may be unavailable until a full rebuild after adding the plugin.
    }
  }

  Future<void> setAdvancedFeatures(bool enabled) async {
    advancedFeatures = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_advancedFeaturesKey, enabled);
    } catch (_) {
      // Toggle still works for this session even if persistence fails.
    }
  }

  Future<void> setLocale(Locale value) async {
    if (!supportedLocales.any((l) => l.languageCode == value.languageCode)) return;
    locale = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeKey, value.languageCode);
    } catch (_) {
      // Locale still applies for this session even if persistence fails.
    }
  }
}
