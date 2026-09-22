import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../utils/session_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/router.dart';
import 'auth_service.dart';
import '../utils/app_logger.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;

  static String get _base {
    // ── 0. Saved custom API URL (set dynamically by user) ───────────────────
    try {
      final customUrl = SessionStorage.instance.getStringSync('custom_api_url');
      if (customUrl != null && customUrl.trim().isNotEmpty) {
        return customUrl.trim();
      }
    } catch (_) {}

    // ── 1. Build-time override (highest priority) ───────────────────────────
    // Pass --dart-define=API_URL=https://... to override everything.
    const overrideUrl = String.fromEnvironment('API_URL');
    if (overrideUrl.isNotEmpty) {
      return overrideUrl;
    }

    // ── 2. Explicit production build override ──────────────────────────────
    const productionUrl = String.fromEnvironment('PRODUCTION_API_URL');
    if (productionUrl.isNotEmpty) {
      return productionUrl;
    }

    // ── 3. Web — always derive from the page origin ────────────────────────
    if (kIsWeb) {
      final scheme = Uri.base.scheme.isNotEmpty ? Uri.base.scheme : 'http';
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      final portStr = Uri.base.hasPort ? ':${Uri.base.port}' : '';
      return '$scheme://$host$portStr/api/v1';
    }

    // ── 4. Android & iOS — connects to host machine IP on local Wi-Fi / physical devices ─
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      return 'http://192.168.4.127:5005/api/v1';
    }

    // ── 5. macOS / Windows / Linux ─────────────────────────────────────────
    return 'http://127.0.0.1:5005/api/v1';
  }

  static String get activeHost {
    try {
      final uri = Uri.parse(_instance._dio.options.baseUrl);
      final portStr = uri.hasPort ? ':${uri.port}' : '';
      if (uri.host.isNotEmpty && uri.host != '10.0.2.2' && uri.host != '127.0.0.1' && uri.host != 'localhost') {
        return '${uri.host}$portStr';
      }
    } catch (_) {}
    return '192.168.4.127:5005';
  }

  /// Updates the active baseUrl at runtime and saves it to local storage.
  static Future<void> updateBaseUrl(String newUrl) async {
    String clean = newUrl.trim();
    if (clean.isEmpty) return;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    if (!clean.endsWith('/')) clean = '$clean/';
    if (!clean.contains('/api/v1/')) {
      clean = '${clean}api/v1/';
    }
    _instance._dio.options.baseUrl = clean;
    await SessionStorage.instance.setString('custom_api_url', clean);
    debugPrint('[ApiService] Updated active baseUrl to $clean');
  }

  /// Tests connectivity to a given server URL or the current active baseUrl.
  static Future<bool> testConnection([String? testUrl]) async {
    try {
      String base = (testUrl != null && testUrl.trim().isNotEmpty)
          ? testUrl.trim()
          : baseUrl;
      if (!base.startsWith('http://') && !base.startsWith('https://')) {
        base = 'http://$base';
      }
      final rootUrl = base.replaceFirst(RegExp(r'/api/v1/?$'), '').replaceAll(RegExp(r'/+$'), '');
      final pingUrl = '$rootUrl/api/ping';
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final res = await dio.get(pingUrl);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] testConnection error: $e');
      return false;
    }
  }

  static String get _normalizedBase {
    String url = _base.trim();
    // Ensure trailing slash
    if (!url.endsWith('/')) url = '$url/';
    return url;
  }

  static String get baseUrl {
    try {
      final cur = _instance._dio.options.baseUrl;
      if (cur.isNotEmpty) return cur;
    } catch (_) {}
    return _normalizedBase;
  }
  String get instanceBaseUrl => _dio.options.baseUrl;

  /// Resolves relative image paths and converts localhost/127.0.0.1 URLs
  /// to active host on physical devices.
  static String resolveImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return '';
    String url = rawUrl.trim();
    final currentHost = activeHost;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      for (final h in [
        'localhost:5005',
        '127.0.0.1:5005',
        '10.0.2.2:5005',
      ]) {
        if (url.contains(h)) {
          url = url.replaceFirst(h, currentHost);
        }
      }
      return url;
    }
    final serverBase = baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
    final cleanPath = url.startsWith('/') ? url : '/$url';
    return '$serverBase$cleanPath';
  }

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _normalizedBase,
        connectTimeout: const Duration(
          seconds: 15,
        ), // Allow time for emulator virtual network setup
        receiveTimeout: const Duration(
          seconds: 30,
        ), // Allow time for slow DB queries / password hashing
        sendTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token =
              SessionStorage.instance.getStringSync('cubag_token') ??
              await SessionStorage.instance.getString('cubag_token');
          if (token != null &&
              token.isNotEmpty &&
              !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await AuthService().logout();
            final currentLoc =
                appRouter.routerDelegate.currentConfiguration.uri.path;
            if (currentLoc != '/' &&
                currentLoc != '/login' &&
                currentLoc != '/register' &&
                !currentLoc.startsWith('/verify-member/')) {
              appRouter.go('/login');
            }
            return handler.next(error);
          }

          // Automatic Retry Logic for Network Drops
          if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.unknown) {
            final requestOptions = error.requestOptions;
            int retryCount = requestOptions.extra['retryCount'] ?? 0;

            if (retryCount < 2) {
              requestOptions.extra['retryCount'] = retryCount + 1;
              await Future.delayed(
                Duration(milliseconds: 600 * (retryCount + 1)),
              );
              try {
                final response = await _dio.fetch(requestOptions);
                return handler.resolve(response);
              } catch (e) {
                // Fall through to handler.next
              }
            }
          }

          return handler.next(error);
        },
      ),
    );
  }

  String _path(String p) => p.startsWith('/') ? p.substring(1) : p;

  Future<Response<dynamic>> get(String path, {Options? options}) =>
      _dio.get(_path(path), options: options);

  static Options rawResponseOptions() =>
      Options(responseType: ResponseType.plain);

  Future<Response<dynamic>> post(String path, {dynamic data}) => _dio.post(
    _path(path),
    data: data,
    // Accept 4xx client errors as valid responses so callers can
    // inspect the status code (e.g. 409 LICENSE_ACTIVE) instead of
    // catching a DioException with the body stripped.
    options: Options(
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  Future<Response<dynamic>> put(String path, {dynamic data}) =>
      _dio.put(_path(path), data: data);

  Future<Response<dynamic>> patch(String path, {dynamic data}) =>
      _dio.patch(_path(path), data: data);

  Future<Response<dynamic>> delete(String path) => _dio.delete(_path(path));

  Future<Response<dynamic>> upload(String path, FormData data) => _dio.post(
    _path(path),
    data: data,
    options: Options(
      contentType: 'multipart/form-data',
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  Future<dynamic> fetchData(String path) async {
    try {
      final res = await _dio.get(_path(path));
      return res.data;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> postPublic(String path, dynamic data) async {
    try {
      final res = await _dio.post(
        _path(path),
        data: data,
        options: Options(headers: {'Authorization': ''}),
      );
      return res.data;
    } catch (e, st) {
      AppLogger.error('api_service_postPublic', e, st);
      rethrow;
    }
  }

  static Completer<Box>? _boxCompleter;

  static Future<Box?> _getCacheBox() async {
    if (kIsWeb) return null;
    try {
      if (Hive.isBoxOpen('api_cache')) {
        return Hive.box('api_cache');
      }
      if (_boxCompleter != null) {
        return _boxCompleter!.future;
      }
      _boxCompleter = Completer<Box>();
      final box = await Hive.openBox('api_cache');
      if (!_boxCompleter!.isCompleted) _boxCompleter!.complete(box);
      return box;
    } catch (e, st) {
      AppLogger.error('api_service', e, st);
      if (_boxCompleter != null && !_boxCompleter!.isCompleted) {
        _boxCompleter!.completeError(e);
      }
      _boxCompleter = null;
      return null;
    }
  }

  static Future<void> deleteCacheKey(String key) async {
    if (kIsWeb) return;
    try {
      final box = await _getCacheBox();
      if (box != null) {
        await box.delete(key);
      }
    } catch (e, st) {
      AppLogger.error('api_service_deleteKey', e, st);
    }
  }

  static Dio? _publicDioInstance;

  static Dio get _publicDio {
    _publicDioInstance ??= Dio(
      BaseOptions(
        baseUrl: _normalizedBase,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    return _publicDioInstance!;
  }

  static Future<void> deleteCacheKeysMatching(String pattern) async {
    if (kIsWeb) return;
    try {
      final box = await _getCacheBox();
      if (box != null) {
        final keysToRemove = box.keys
            .where((k) => k.toString().contains(pattern))
            .toList();
        if (keysToRemove.isNotEmpty) {
          await box.deleteAll(keysToRemove);
        }
      }
    } catch (e, st) {
      AppLogger.error('api_service_deleteKeysMatching', e, st);
    }
  }

  static Future<void> clearAllCaches() async {
    if (kIsWeb) return;
    try {
      final box = await _getCacheBox();
      if (box != null) {
        await box.clear();
      }
    } catch (e, st) {
      AppLogger.error('api_service_clearAllCaches', e, st);
    }
  }

  Future<void> fetchDataWithCache(
    String path,
    Function(dynamic data, bool isCached, {bool hasError}) onData,
  ) async {
    final cacheKey = 'cache_v1_${_path(path)}';

    if (kIsWeb) {
      try {
        final res = await _dio.get(_path(path));
        onData(res.data, false, hasError: false);
      } catch (e) {
        onData(null, false, hasError: true);
      }
      return;
    }

    Box? box;
    try {
      box = await _getCacheBox();
    } catch (e, st) {
      AppLogger.error('api_service', e, st);
    }

    if (box == null) {
      try {
        final res = await _dio.get(_path(path));
        onData(res.data, false, hasError: false);
      } catch (e) {
        onData(null, false, hasError: true);
      }
      return;
    }

    try {
      final cachedStr = box.get(cacheKey);
      if (cachedStr != null) {
        final decoded = jsonDecode(cachedStr);
        try {
          onData(decoded, true, hasError: false);
        } catch (e, st) {
          AppLogger.error('api_service_onData_cached', e, st);
        }
      }
    } catch (e, st) {
      AppLogger.error('api_service', e, st);
    }

    try {
      final res = await _dio.get(_path(path));
      final freshData = res.data;
      if (freshData != null) {
        try {
          box.put(cacheKey, jsonEncode(freshData));
        } catch (e, st) {
          AppLogger.error('api_service', e, st);
        }
      }
      try {
        onData(freshData, false, hasError: false);
      } catch (e, st) {
        AppLogger.error('api_service_onData_fresh', e, st);
      }
    } catch (e) {
      debugPrint('[API Error] $path: $e');
      try {
        onData(null, false, hasError: true);
      } catch (e, st) {
        AppLogger.error('api_service_onData_error', e, st);
      }
    }
  }

  final Map<String, Future<dynamic>> _inFlightPublicGets = {};

  Future<dynamic> getPublic(String path) async {
    final cleanPath = _path(path);
    if (_inFlightPublicGets.containsKey(cleanPath)) {
      return _inFlightPublicGets[cleanPath];
    }

    final future = () async {
      try {
        final separator = cleanPath.contains('?') ? '&' : '?';
        final bustPath = '$cleanPath${separator}_t=${DateTime.now().millisecondsSinceEpoch}';
        final res = await _publicDio.get(
          bustPath,
          options: Options(
            headers: {
              'Cache-Control': 'no-cache, no-store, must-revalidate',
              'Pragma': 'no-cache',
              'Expires': '0',
            },
          ),
        );
        return res.data;
      } catch (e) {
        debugPrint('getPublic error for path $cleanPath: $e');
        return null;
      } finally {
        _inFlightPublicGets.remove(cleanPath);
      }
    }();

    _inFlightPublicGets[cleanPath] = future;
    return future;
  }

  Future<dynamic> postData(String path, dynamic data) async {
    try {
      final res = await _dio.post(_path(path), data: data);
      return res.data;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> putData(String path, dynamic data) async {
    try {
      final res = await _dio.put(_path(path), data: data);
      return res.data;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> patchData(String path, dynamic data) async {
    try {
      final res = await _dio.patch(_path(path), data: data);
      return res.data;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> deleteData(String path) async {
    try {
      final res = await _dio.delete(_path(path));
      return res.data;
    } catch (_) {
      return null;
    }
  }

  static List<dynamic> ensureList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) return decoded;
        if (decoded is Map) return _findListInMap(decoded);
      } catch (e, st) {
        AppLogger.error('api_service', e, st);
      }
    }
    if (data is Map) {
      return _findListInMap(data);
    }
    return [];
  }

  static List<dynamic> _findListInMap(Map data) {
    if (data.containsKey('data') && data['data'] is List) return data['data'];
    if (data.containsKey('items') && data['items'] is List) {
      return data['items'];
    }
    if (data.containsKey('results') && data['results'] is List) {
      return data['results'];
    }
    for (var v in data.values) {
      if (v is List) return v;
    }
    return [];
  }
}
