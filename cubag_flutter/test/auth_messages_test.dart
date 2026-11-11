import 'package:cubag_flutter/utils/auth_messages.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dio({int? status, Object? data, DioExceptionType type = DioExceptionType.badResponse}) {
  final req = RequestOptions(path: '/auth/login');
  return DioException(
    requestOptions: req,
    type: type,
    response: status == null ? null : Response(requestOptions: req, statusCode: status, data: data),
  );
}

void main() {
  group('response', () {
    test('401 never echoes the server text', () {
      expect(loginErrorFromResponse(401, {'message': 'No account for x@y.com'}), loginWrongCredentials);
    });

    test('403 shows the reason (suspended / unverified)', () {
      expect(loginErrorFromResponse(403, {'message': 'Your account has been suspended.'}),
          'Your account has been suspended.');
      expect(loginErrorFromResponse(403, null), 'Account suspended or access denied.');
    });

    test('429 lockout keeps the wait time from the server', () {
      const m = 'Too many failed sign-in attempts. Please wait 15 minutes or reset your password.';
      expect(loginErrorFromResponse(429, {'message': m}), m);
      expect(loginErrorFromResponse(429, {}), contains('Too many attempts'));
    });

    test('503 shows why (e.g. admin sign-in code email failed)', () {
      const m = 'We could not send your sign-in code. Please try again shortly.';
      expect(loginErrorFromResponse(503, {'message': m}), m);
    });

    test('other 5xx is generic, never the raw body', () {
      expect(loginErrorFromResponse(500, {'message': 'relation "members" does not exist'}), loginServerError);
      expect(loginErrorFromResponse(502, '<html>Bad gateway</html>'), loginServerError);
    });

    test('400 uses the server message, HTML bodies are ignored', () {
      expect(loginErrorFromResponse(400, {'message': 'Email or phone number and password are required'}),
          'Email or phone number and password are required');
      expect(loginErrorFromResponse(400, '<!doctype html>'), loginGeneric);
      expect(loginErrorFromResponse(400, {'message': '  '}), loginGeneric);
    });
  });

  group('exception', () {
    test('DioException with a response maps like the response', () {
      expect(loginErrorFromException(_dio(status: 401)), loginWrongCredentials);
      expect(loginErrorFromException(_dio(status: 429, data: {'message': 'Wait 15 minutes'})), 'Wait 15 minutes');
      expect(loginErrorFromException(_dio(status: 500)), loginServerError);
    });

    test('timeouts', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(loginErrorFromException(_dio(type: t)), loginTimeout);
      }
    });

    test('offline', () {
      expect(loginErrorFromException(_dio(type: DioExceptionType.connectionError)), loginOffline);
      expect(loginErrorFromException(Exception("SocketException: Failed host lookup: 'api'")), loginOffline);
    });

    test('anything else is generic', () {
      expect(loginErrorFromException(StateError('boom')), loginGeneric);
      expect(loginErrorFromException(_dio(type: DioExceptionType.cancel)), loginGeneric);
    });
  });
}
