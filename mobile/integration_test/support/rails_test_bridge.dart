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

  Future<int> adminFundReserve({
    required String userEmail,
    required String receiveAddress,
    required String amountBtc,
  }) async {
    final response = await _client.post(
      Uri.parse('$_integrationBase/admin_fund_reserve'),
      headers: _headers,
      body: jsonEncode({
        'user_email': userEmail,
        'receive_address': receiveAddress,
        'amount_btc': amountBtc,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('admin_fund_reserve failed (${response.statusCode}): ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['balance_sats'] as int;
  }

  /// Funds a user's reserve on regtest (admin path, no pasted address).
  Future<int> fundUserReserve({
    required String userEmail,
    required String amountBtc,
  }) {
    return adminFundReserve(userEmail: userEmail, receiveAddress: '', amountBtc: amountBtc);
  }
}
