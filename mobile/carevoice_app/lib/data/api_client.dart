import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _storage = FlutterSecureStorage();

  Future<String?> getAccessToken() => _storage.read(key: 'accessToken');

  Future<bool> hasJwtToken() async {
    final token = await getAccessToken();
    return token != null && token.split('.').length == 3;
  }

  Future<Map<String, String>> authHeaders({bool jsonContent = true}) async {
    final token = await getAccessToken();
    final headers = <String, String>{};
    if (jsonContent) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri uri(String path, [Map<String, String>? queryParameters]) {
    final base = ApiConstants.baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final parsed = Uri.parse('$base$cleanPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return parsed;
    }
    return parsed.replace(queryParameters: queryParameters);
  }

  Future<http.Response> sendWithRefresh(Future<http.Response> Function() requestFn) async {
    var response = await requestFn();
    if (response.statusCode == 401) {
      final refreshed = await tryRefreshToken();
      if (refreshed) {
        response = await requestFn();
      }
    }
    return response;
  }

  Future<bool> tryRefreshToken() async {
    try {
      final accessToken = await _storage.read(key: 'accessToken');
      final refreshToken = await _storage.read(key: 'refreshToken');
      if (accessToken == null || refreshToken == null) return false;
      if (accessToken.split('.').length != 3) return false;

      final res = await http
          .post(
            uri('/api/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'accessToken': accessToken,
              'refreshToken': refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final newAccess = data['accessToken']?.toString();
        final newRefresh = data['refreshToken']?.toString();
        if (newAccess != null && newAccess.isNotEmpty) {
          await _storage.write(key: 'accessToken', value: newAccess);
          if (newRefresh != null && newRefresh.isNotEmpty) {
            await _storage.write(key: 'refreshToken', value: newRefresh);
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static String friendlyError(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
    final raw = error.toString().replaceAll('Exception: ', '').trim();
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('clientexception')) {
      return 'Unable to reach CareVoice right now. Please check your internet connection and try again.';
    }
    if (lower.contains('timeoutexception') || lower.contains('timed out')) {
      return 'The connection took too long. Please check your internet connection and try again.';
    }
    if (raw.isEmpty) return fallback;
    return raw;
  }
}
