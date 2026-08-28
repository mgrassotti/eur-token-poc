import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/models.dart';

class RelayApiException implements Exception {
  RelayApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class RelayApiClient {
  RelayApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  String? _token;

  void setToken(String? token) => _token = token;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final body = await _post('/auth/login', {'email': email, 'password': password}, auth: false);
    _token = body['token'] as String;
    return body;
  }

  Future<User> currentUser() async {
    final body = await _get('/auth/me');
    return User.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<DashboardData> fetchDashboard() async {
    final body = await _get('/dashboard');
    return DashboardData.fromJson(body);
  }

  /// Public BTC/EUR rate from Rails (no auth). Used for on-device reserve EUR display.
  Future<double?> fetchMarketRate() async {
    final body = await _get('/market_rate', auth: false);
    return (body['btc_eur_per_btc'] as num?)?.toDouble();
  }

  Future<List<Deal>> fetchDeals() async {
    final body = await _get('/deals', auth: false);
    return (body['deals'] as List<dynamic>)
        .map((e) => Deal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Deal> fetchDeal(String id) async {
    final body = await _get('/deals/$id', auth: false);
    return Deal.fromJson(body);
  }

  Future<Deal> createDeal({
    required int amountEurCents,
    required String periodStart,
    required String periodEnd,
    required String fundingAddress,
    required String commitmentPsbt,
    String? borrowerName,
  }) async {
    final body = await _post(
      '/deals',
      {
        'deal': {
          'amount_eur_cents': amountEurCents,
          'period_start': periodStart,
          'period_end': periodEnd,
          'funding_address': fundingAddress,
          'commitment_psbt': commitmentPsbt,
          if (borrowerName != null) 'borrower_name': borrowerName,
        },
      },
      auth: false,
    );
    return Deal.fromJson(body);
  }

  Future<Deal> acceptDeal(
    String id, {
    required String fundingAddress,
    required List<Map<String, dynamic>> investorInputs,
    required String investorChangeAddress,
    required String investorPayoutAddress,
    required String investorIdentityPubkey,
    String? investorName,
    List<Map<String, dynamic>>? pegInputs,
    String? pegChangeAddress,
    String? pegIdentityPubkey,
  }) async {
    final body = await _post(
      '/deals/$id/accept',
      {
        'funding_address': fundingAddress,
        if (investorName != null) 'investor_name': investorName,
        'investor_inputs': investorInputs,
        'investor_change_address': investorChangeAddress,
        'investor_payout_address': investorPayoutAddress,
        'investor_identity_pubkey': investorIdentityPubkey,
        if (pegInputs != null) 'peg_inputs': pegInputs,
        if (pegChangeAddress != null) 'peg_change_address': pegChangeAddress,
        if (pegIdentityPubkey != null) 'peg_identity_pubkey': pegIdentityPubkey,
      },
      auth: false,
    );
    return Deal.fromJson(body);
  }

  Future<Deal> submitFundingSignature({
    required String dealId,
    required String fundingAddress,
    required String signedPsbt,
  }) async {
    final body = await _post(
      '/deals/$dealId/funding_signature',
      {
        'funding_address': fundingAddress,
        'signed_psbt': signedPsbt,
      },
      auth: false,
    );
    return Deal.fromJson(body);
  }

  Future<List<User>> fetchUsers() async {
    final body = await _get('/users');
    return (body['users'] as List<dynamic>)
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TransferRecord>> fetchTransfers(String dealId) async {
    final body = await _get('/deals/$dealId/transfers');
    return (body['transfers'] as List<dynamic>)
        .map((e) => TransferRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createTransfer({
    required String dealId,
    required int toUserId,
    required int amountEurCents,
  }) async {
    await _post('/deals/$dealId/transfers', {
      'to_user_id': toUserId,
      'amount_eur_cents': amountEurCents,
    });
  }

  Future<void> sendMoney({
    required int toUserId,
    required int amountEurCents,
  }) async {
    await _post('/transfers', {
      'to_user_id': toUserId,
      'amount_eur_cents': amountEurCents,
    });
  }

  Future<ReceiveRequestInfo> createReceiveRequest({int? amountEurCents}) async {
    final body = await _post('/receive_requests', {
      if (amountEurCents != null) 'amount_eur_cents': amountEurCents,
    });
    return ReceiveRequestInfo.fromJson(body);
  }

  Future<ReceiveRequestInfo> fetchReceiveRequest(String id) async {
    final body = await _get('/receive_requests/$id');
    return ReceiveRequestInfo.fromJson(body);
  }

  Future<void> payReceiveRequest({
    required String receiveRequestId,
    int? amountEurCents,
  }) async {
    await _post('/transfers', {
      'receive_request_id': receiveRequestId,
      if (amountEurCents != null) 'amount_eur_cents': amountEurCents,
    });
  }

  Future<SettlementPreview> fetchSettlement(String dealId) async {
    final body = await _get('/deals/$dealId/settlement');
    return SettlementPreview.fromJson(body);
  }

  Future<ReserveInfo> fetchReserve() async {
    final body = await _get('/reserve');
    return ReserveInfo.fromJson(body);
  }

  /// Phase 2: Register BDK-generated receive address with server.
  Future<void> updateReserveAddress(String address) async {
    await _put('/reserve/update_address', {'receive_address': address});
  }

  Future<int> syncReserve() async {
    final body = await _post('/reserve/sync', {});
    return body['balance_sats'] as int? ?? 0;
  }

  Future<Map<String, dynamic>> _get(String path, {bool auth = true}) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(includeAuth: auth),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    bool auth = true,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(includeAuth: auth),
      body: jsonEncode(payload),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> payload, {
    bool auth = true,
  }) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(includeAuth: auth),
      body: jsonEncode(payload),
    );
    return _decode(response);
  }

  Map<String, String> _headers({bool includeAuth = true}) {
    final headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (includeAuth && _token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final detail = body['detail'] as String? ?? body['error'] as String? ?? response.body;
    throw RelayApiException(detail, statusCode: response.statusCode);
  }
}
