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

  Future<bool> login(String email, String password) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final body = await _api.login(email, password);
      user = User.fromJson(body['user'] as Map<String, dynamic>);
      loading = false;
      notifyListeners();
      return true;
    } on RelayApiException catch (e) {
      error = e.message;
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
  bool _hydrated = false;

  SettingsState() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Avoid clobbering in-session toggles if hydration loses the race.
      if (_hydrated) return;
      advancedFeatures = prefs.getBool(_advancedFeaturesKey) ?? false;
      final code = prefs.getString(_localeKey);
      if (code != null && supportedLocales.any((l) => l.languageCode == code)) {
        locale = Locale(code);
      }
      _hydrated = true;
      notifyListeners();
    } catch (_) {
      _hydrated = true;
      // Keep defaults; prefs may be unavailable until a full rebuild after adding the plugin.
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
      // Toggle still works for this session even if persistence fails.
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
      // Locale still applies for this session even if persistence fails.
    }
  }
}
