import 'dart:convert';

import 'package:http/http.dart' as http;

import 'integration_config.dart';

/// Calls dev/test-only Rails integration endpoints (simulates admin UI).
class RailsTestBridge {
  RailsTestBridge({http.Client? client, String? apiBaseUrl})
      : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ?? IntegrationConfig.apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;

  String get _integrationBase => _apiBaseUrl.replaceFirst('/api/v1', '/api/v1/integration');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Integration-Secret': IntegrationConfig.integrationSecret,
      };

  Future<void> demoReset() async {
    final response = await _client.post(
      Uri.parse('$_integrationBase/demo_reset'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw StateError('demo_reset failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Funds an on-device BDK receive address via the admin integration path.
  Future<Map<String, dynamic>> adminFundReserve({
    required String receiveAddress,
    required String amountBtc,
  }) async {
    final response = await _client.post(
      Uri.parse('$_integrationBase/admin_fund_reserve'),
      headers: _headers,
      body: jsonEncode({
        'receive_address': receiveAddress,
        'amount_btc': amountBtc,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('admin_fund_reserve failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Test helper: fund a seeded user's reserve by email (registers UserWallet address).
  Future<int> fundUserReserve({
    required String userEmail,
    required String amountBtc,
  }) async {
    final response = await _client.post(
      Uri.parse('$_integrationBase/admin_fund_reserve'),
      headers: _headers,
      body: jsonEncode({
        'user_email': userEmail,
        'amount_btc': amountBtc,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('fundUserReserve failed (${response.statusCode}): ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['balance_sats'] as num?)?.toInt() ?? 0;
  }

  /// Sends regtest BTC to any address (on-device BDK receive address).
  Future<void> fundRegtestAddress({
    required String address,
    required String amountBtc,
  }) async {
    final response = await _client.post(
      Uri.parse('$_integrationBase/fund_regtest_address'),
      headers: _headers,
      body: jsonEncode({
        'address': address,
        'amount_btc': amountBtc,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('fund_regtest_address failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Login or create a test user.
  Future<Map<String, dynamic>> loginOrCreateUser(String email, String password) async {
    try {
      // Try login first
      final loginResponse = await _client.post(
        Uri.parse('$_apiBaseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (loginResponse.statusCode == 200) {
        return jsonDecode(loginResponse.body) as Map<String, dynamic>;
      }

      // Create user if login failed
      final signupResponse = await _client.post(
        Uri.parse('$_apiBaseUrl/auth/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'password_confirmation': password,
        }),
      );

      if (signupResponse.statusCode != 201) {
        throw StateError('Failed to create user: ${signupResponse.body}');
      }

      return jsonDecode(signupResponse.body) as Map<String, dynamic>;
    } catch (e) {
      throw StateError('Failed to login or create user: $e');
    }
  }

  /// Create a wallet for a user via API.
  Future<Map<String, dynamic>> createWalletViaApi(String authToken) async {
    final response = await _client.post(
      Uri.parse('$_apiBaseUrl/wallet/create'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    );

    if (response.statusCode != 201) {
      throw StateError('Failed to create wallet: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Get wallet balance for a user via API.
  Future<int> getBalanceViaApi(String authToken) async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/wallet/balance'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    );

    if (response.statusCode != 200) {
      throw StateError('Failed to get balance: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['balance_sats'] as int;
  }

  /// Accept a recharge request via API.
  Future<Map<String, dynamic>> acceptRequestViaApi(
    String authToken,
    String requestId,
  ) async {
    final response = await _client.post(
      Uri.parse('$_apiBaseUrl/recharge_requests/$requestId/accept'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    );

    if (response.statusCode != 200) {
      throw StateError('Failed to accept request: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
