import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/identity.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  String get baseUrl => _baseUrl;

  Map<String, String> get _jsonHeaders => {
    'X-User-Id': devUserId,
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Map<String, String> get _headers => {
    'X-User-Id': devUserId,
    'Accept': 'application/json',
  };

  Future<Map<String, dynamic>> getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    return _decodeOrThrow(res);
  }

  Future<void> postJson(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    final res = await _client
        .post(uri, headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    _ensure2xx(res);
  }

  Future<void> delete(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final res = await _client
        .delete(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    _ensure2xx(res);
  }

  Map<String, dynamic> _decodeOrThrow(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _extractError(res.body));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _ensure2xx(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _extractError(res.body));
    }
  }

  void close() => _client.close();

  String _extractError(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return body.isEmpty ? 'request failed' : body;
  }
}

const _defaultBaseUrl = 'http://localhost:8080';
