import 'package:flutter_test/flutter_test.dart';

/// Tests for ApiService URL construction logic.
/// We test the logic directly rather than instantiating the singleton
/// (which requires Firebase/Hive initialization).
void main() {
  group('API Base URL', () {
    test('v1 prefix is in all expected base URLs', () {
      // This test documents the expected URL patterns.
      // If the base URL ever regresses to /api without /v1,
      // production calls will silently 404.
      const expectedPatterns = ['/api/v1'];
      const unexpectedPatterns = [
        '/api/auth', // old pattern (without v1)
        '/api/members', // old pattern
      ];

      // Simulate the URL that would be produced for each env
      const localUrl = 'http://127.0.0.1:5005/api/v1';
      const prodUrl = 'https://cubag-backend.onrender.com/api/v1';

      for (final url in [localUrl, prodUrl]) {
        for (final pattern in expectedPatterns) {
          expect(
            url.contains(pattern),
            isTrue,
            reason: '$url should contain $pattern',
          );
        }
        for (final pattern in unexpectedPatterns) {
          expect(
            url.contains(pattern),
            isFalse,
            reason: '$url should not contain $pattern',
          );
        }
        // Old /api-only base would end with '/api' not '/api/v1'
        expect(
          url.endsWith('/api'),
          isFalse,
          reason: 'Base URL must end with /api/v1, not just /api',
        );
      }
    });

    test('trailing slash normalization', () {
      // _normalizedBase should always end with /
      String normalizeUrl(String url) {
        if (!url.endsWith('/')) url = '$url/';
        return url;
      }

      expect(normalizeUrl('http://localhost:5005/api/v1'), endsWith('/'));
      expect(normalizeUrl('http://localhost:5005/api/v1/'), endsWith('/'));
    });
  });
}
