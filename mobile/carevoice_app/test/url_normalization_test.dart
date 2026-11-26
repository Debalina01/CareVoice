import 'package:flutter_test/flutter_test.dart';
import 'package:carevoice_app/core/constants.dart';

void main() {
  group('ApiConstants URL Normalization Tests', () {
    test('Default fallback for null and empty input', () {
      expect(ApiConstants.normalizeUrl(null), ApiConstants.productionCloudUrl);
      expect(ApiConstants.normalizeUrl(''), ApiConstants.productionCloudUrl);
      expect(ApiConstants.normalizeUrl('   '), ApiConstants.productionCloudUrl);
    });

    test('Local IP addresses without port auto-append :5070 and http scheme', () {
      expect(ApiConstants.normalizeUrl('10.36.7.35'), 'http://10.36.7.35:5070');
      expect(ApiConstants.normalizeUrl('http://10.36.7.35'), 'http://10.36.7.35:5070');
      expect(ApiConstants.normalizeUrl('http://10.36.7.35/'), 'http://10.36.7.35:5070');
      expect(ApiConstants.normalizeUrl('http://192.168.1.100'), 'http://192.168.1.100:5070');
      expect(ApiConstants.normalizeUrl('10.0.0.5'), 'http://10.0.0.5:5070');
    });

    test('Local IP addresses with existing port preserve port', () {
      expect(ApiConstants.normalizeUrl('http://10.36.7.35:5070'), 'http://10.36.7.35:5070');
      expect(ApiConstants.normalizeUrl('http://10.36.7.35:5070/'), 'http://10.36.7.35:5070');
      expect(ApiConstants.normalizeUrl('10.36.7.35:8080'), 'http://10.36.7.35:8080');
    });

    test('Localhost and Android emulator IP handling', () {
      expect(ApiConstants.normalizeUrl('localhost'), 'http://localhost:5070');
      expect(ApiConstants.normalizeUrl('http://localhost'), 'http://localhost:5070');
      expect(ApiConstants.normalizeUrl('127.0.0.1'), 'http://127.0.0.1:5070');
      expect(ApiConstants.normalizeUrl('10.0.2.2'), 'http://10.0.2.2:5070');
    });

    test('Public domain URL handling', () {
      expect(
        ApiConstants.normalizeUrl('https://carevoice.example.com'),
        'https://carevoice.example.com',
      );
      expect(
        ApiConstants.normalizeUrl('https://carevoice.example.com/'),
        'https://carevoice.example.com',
      );
    });

    test('isLocalOrPrivateHost detection', () {
      expect(ApiConstants.isLocalOrPrivateHost('10.36.7.35'), isTrue);
      expect(ApiConstants.isLocalOrPrivateHost('192.168.1.1'), isTrue);
      expect(ApiConstants.isLocalOrPrivateHost('10.0.2.2'), isTrue);
      expect(ApiConstants.isLocalOrPrivateHost('127.0.0.1'), isTrue);
      expect(ApiConstants.isLocalOrPrivateHost('localhost'), isTrue);
      expect(ApiConstants.isLocalOrPrivateHost('google.com'), isFalse);
    });
  });
}
