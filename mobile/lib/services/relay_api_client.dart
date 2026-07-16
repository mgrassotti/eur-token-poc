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

  Future<List<Deal>> fetchDeals() async {
    final body = await _get('/deals');
    return (body['deals'] as List<dynamic>)
        .map((e) => Deal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Deal> fetchDeal(String id) async {
    final body = await _get('/deals/$id');
    return Deal.fromJson(body);
  }

  Future<Deal> createDeal({
    required int amountEurCents,
    required String periodStart,
    required String periodEnd,
  }) async {
    final body = await _post('/deals', {
      'deal': {
        'amount_eur_cents': amountEurCents,
        'period_start': periodStart,
        'period_end': periodEnd,
      },
    });
    return Deal.fromJson(body);
  }

  Future<Deal> acceptDeal(String id) async {
    final body = await _post('/deals/$id/accept', {});
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

  Future<SettlementPreview> fetchSettlement(String dealId) async {
    final body = await _get('/deals/$dealId/settlement');
    return SettlementPreview.fromJson(body);
  }

  Future<ReserveInfo> fetchReserve() async {
    final body = await _get('/reserve');
    return ReserveInfo.fromJson(body);
  }

  Future<int> syncReserve() async {
    final body = await _post('/reserve/sync', {});
    return body['balance_sats'] as int? ?? 0;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
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
