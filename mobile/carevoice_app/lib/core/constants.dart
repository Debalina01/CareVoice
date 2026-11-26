import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiConstants {
  static const _storage = FlutterSecureStorage();
  static String? _customBaseUrl;

  /// Optional compile-time override for local testing only (--dart-define=API_BASE_URL=...)
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Production Cloud Backend hosted on Railway (available 24/7 over HTTPS)
  static const String productionCloudUrl = 'https://carevoice-api-production.up.railway.app';

  /// Default port used for URL normalization helpers
  static const String defaultLocalHostIp = '10.36.7.35';
  static const int defaultBackendPort = 5070;
  static const String defaultLocalUrl = 'http://$defaultLocalHostIp:$defaultBackendPort';

  /// Determines if a hostname/IP represents a local or private address
  static bool isLocalOrPrivateHost(String? host) {
    if (host == null || host.trim().isEmpty) return false;
    final h = host.toLowerCase().trim();
    if (h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2' || h == '::1') return true;

    final ipv4Match = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
    if (ipv4Match != null) {
      final octet1 = int.tryParse(ipv4Match.group(1) ?? '') ?? 0;
      final octet2 = int.tryParse(ipv4Match.group(2) ?? '') ?? 0;
      if (octet1 == 10) return true;
      if (octet1 == 172 && octet2 >= 16 && octet2 <= 31) return true;
      if (octet1 == 192 && octet2 == 168) return true;
      if (octet1 == 127) return true;
    }
    return false;
  }

  /// Normalizes a given URL or host input:
  /// - Strips whitespace and trailing slashes
  /// - Prepends 'http://' or 'https://' if missing
  /// - Automatically appends default port :5070 if an IP/localhost is provided without a port
  static String normalizeUrl(String? raw) {
    if (raw == null) return productionCloudUrl;
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return productionCloudUrl;

    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trim();
    }

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      final hostPart = trimmed.split('/')[0].split(':')[0];
      if (isLocalOrPrivateHost(hostPart)) {
        trimmed = 'http://$trimmed';
      } else {
        trimmed = 'https://$trimmed';
      }
    }

    try {
      final uri = Uri.parse(trimmed);
      final host = uri.host;
      final port = uri.hasPort ? uri.port : null;

      if (port == null && isLocalOrPrivateHost(host)) {
        final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
        final path = uri.path.isNotEmpty ? uri.path : '';
        return '$scheme://$host:$defaultBackendPort$path';
      }
      return trimmed;
    } catch (_) {
      return trimmed;
    }
  }

  static Future<void> loadCustomUrl() async {
    try {
      final saved = (await _storage.read(key: 'custom_api_base_url')) ?? (await _storage.read(key: 'carevoice_api_base_url'));
      if (saved != null && saved.trim().isNotEmpty) {
        final normalized = normalizeUrl(saved);
        final uri = Uri.tryParse(normalized);
        if (uri != null && !isLocalOrPrivateHost(uri.host)) {
          _customBaseUrl = normalized;
        } else {
          await _storage.delete(key: 'custom_api_base_url');
          await _storage.delete(key: 'carevoice_api_base_url');
          _customBaseUrl = null;
        }
      }
    } catch (_) {}
  }

  static Future<void> setCustomUrl(String? url) async {
    if (url != null && url.trim().isNotEmpty) {
      final normalized = normalizeUrl(url);
      _customBaseUrl = normalized;
      await _storage.write(key: 'custom_api_base_url', value: normalized);
      await _storage.write(key: 'carevoice_api_base_url', value: normalized);
    } else {
      _customBaseUrl = null;
      await _storage.delete(key: 'custom_api_base_url');
      await _storage.delete(key: 'carevoice_api_base_url');
    }
  }

  static String get baseUrl {
    if (_envApiBaseUrl.trim().isNotEmpty) {
      return normalizeUrl(_envApiBaseUrl);
    }
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return normalizeUrl(_customBaseUrl);
    }
    return productionCloudUrl;
  }
}
