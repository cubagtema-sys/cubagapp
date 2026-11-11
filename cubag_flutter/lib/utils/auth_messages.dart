import 'package:dio/dio.dart';

/// Maps a failed sign-in to the message shown on the login screen.
/// Pure (no app imports) so it can be unit-tested.
///
/// - 401: never echo the server text, so the screen can't reveal whether an
///   account exists.
/// - 403 / 429 / 503: the server's own message is the useful one (suspended,
///   unverified, locked out for 15 minutes, sign-in code email failed).
/// - Other 5xx: generic; the server scrubs those bodies anyway (SEC-18).
const loginWrongCredentials = 'Incorrect email or password.';
const loginServerError = 'Server error. Please try again in a few seconds.';
const loginTimeout = 'Server request timed out. Please try again.';
const loginOffline =
    'Unable to reach the server. Please check your internet connection and try again.';
const loginGeneric = 'Unable to sign in. Please try again.';

String? _serverMessage(Object? data) {
  if (data is Map && data['message'] != null) {
    final m = data['message'].toString().trim();
    return m.isEmpty ? null : m;
  }
  if (data is String && data.trim().isNotEmpty && !data.trimLeft().startsWith('<')) {
    return data.trim();
  }
  return null;
}

/// From an HTTP response the server sent.
String loginErrorFromResponse(int? status, Object? data) {
  final msg = _serverMessage(data);
  final code = status ?? 0;
  if (code == 401) return loginWrongCredentials;
  if (code == 403) return msg ?? 'Account suspended or access denied.';
  if (code == 429) return msg ?? 'Too many attempts. Please wait a few minutes and try again.';
  if (code == 503) return msg ?? loginServerError;
  if (code >= 500) return loginServerError;
  return msg ?? loginGeneric;
}

/// From an exception thrown while signing in.
String loginErrorFromException(Object error) {
  if (error is DioException) {
    final res = error.response;
    if (res != null) return loginErrorFromResponse(res.statusCode, res.data);
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return loginTimeout;
      case DioExceptionType.connectionError:
        return loginOffline;
      default:
        break;
    }
  }
  final text = error.toString().toLowerCase();
  if (text.contains('timeout')) return loginTimeout;
  if (text.contains('socketexception') || text.contains('failed host lookup') ||
      text.contains('connection refused')) {
    return loginOffline;
  }
  return loginGeneric;
}
