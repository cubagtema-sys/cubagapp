// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'session_storage.dart';
import '../utils/app_logger.dart';

SessionStorage getSessionStorage() => WebSessionStorage();

class WebSessionStorage implements SessionStorage {
  static final WebSessionStorage _instance = WebSessionStorage._internal();
  factory WebSessionStorage() => _instance;
  WebSessionStorage._internal();

  final Map<String, String> _memCache = {};
  final Map<String, List<String>> _memListCache = {};
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    try {
      final keys = html.window.sessionStorage.keys;
      for (final key in keys) {
        final val = html.window.sessionStorage[key];
        if (val != null) {
          _memCache[key] = val;
          try {
            final decoded = jsonDecode(val);
            if (decoded is List) {
              _memListCache[key] = List<String>.from(decoded);
            }
          } catch (_) {}
        }
      }
    } catch (e, st) {
      AppLogger.error('session_storage_web_init', e, st);
    }
    _initialized = true;
  }

  @override
  String? getStringSync(String key) => _memCache[key];

  @override
  List<String>? getStringListSync(String key) => _memListCache[key];

  @override
  Future<void> setString(String key, String value) async {
    _memCache[key] = value;
    try {
      html.window.sessionStorage[key] = value;
    } catch (e, st) {
      AppLogger.error('session_storage_web_setString', e, st);
    }
  }

  @override
  Future<String?> getString(String key) async {
    if (_memCache.containsKey(key)) return _memCache[key];
    try {
      final val = html.window.sessionStorage[key];
      if (val != null) _memCache[key] = val;
      return val;
    } catch (e, st) {
      AppLogger.error('session_storage_web_getString', e, st);
      return null;
    }
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _memListCache[key] = List<String>.from(value);
    final encoded = jsonEncode(value);
    _memCache[key] = encoded;
    try {
      html.window.sessionStorage[key] = encoded;
    } catch (e, st) {
      AppLogger.error('session_storage_web_setStringList', e, st);
    }
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    if (_memListCache.containsKey(key)) return _memListCache[key];
    try {
      final val = html.window.sessionStorage[key];
      if (val == null) return null;
      final decoded = jsonDecode(val);
      if (decoded is List) {
        final list = List<String>.from(decoded);
        _memListCache[key] = list;
        return list;
      }
    } catch (e, st) {
      AppLogger.error('session_storage_web_getStringList', e, st);
    }
    return null;
  }

  @override
  Future<void> remove(String key) async {
    _memCache.remove(key);
    _memListCache.remove(key);
    try {
      html.window.sessionStorage.remove(key);
    } catch (e, st) {
      AppLogger.error('session_storage_web_remove', e, st);
    }
  }

  @override
  Future<void> clear() async {
    _memCache.clear();
    _memListCache.clear();
    try {
      html.window.sessionStorage.clear();
    } catch (e, st) {
      AppLogger.error('session_storage_web_clear', e, st);
    }
  }
}
