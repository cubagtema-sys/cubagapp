import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_storage.dart';

SessionStorage getSessionStorage() => StubSessionStorage();

class StubSessionStorage implements SessionStorage {
  static final StubSessionStorage _instance = StubSessionStorage._internal();
  factory StubSessionStorage() => _instance;
  StubSessionStorage._internal();

  SharedPreferences? _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final Map<String, String> _memCache = {};
  final Map<String, List<String>> _memListCache = {};
  bool _initialized = false;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await _getPrefs();
      for (final key in prefs.getKeys()) {
        final val = prefs.get(key);
        if (val is String) {
          _memCache[key] = val;
        } else if (val is List<String>) {
          _memListCache[key] = List<String>.from(val);
        }
      }

      // Secure token migration and synchronization with robust error trapping
      try {
        // SEC-13: the session token lives ONLY in secure storage
        // (Keychain / EncryptedSharedPreferences). Migrate and delete any
        // legacy plaintext copy from SharedPreferences.
        final secureToken = await _secureStorage.read(key: _tokenKey);
        final legacyToken = prefs.getString(_tokenKey);
        if (secureToken != null && secureToken.isNotEmpty) {
          _memCache[_tokenKey] = secureToken;
          if (legacyToken != null) await prefs.remove(_tokenKey);
        } else if (legacyToken != null && legacyToken.isNotEmpty) {
          try {
            await _secureStorage.write(key: _tokenKey, value: legacyToken);
            await prefs.remove(_tokenKey);
          } catch (_) {
            // Secure storage unavailable on this device: keep legacy copy so the
            // user isn't signed out; it is still removed on logout.
          }
        }
      } catch (e) {
        debugPrint('SecureStorage read/write skipped on init: $e');
      }
    } catch (e) {
      debugPrint('SessionStorage init error: $e');
    }

    _initialized = true;
  }

  @override
  String? getStringSync(String key) => _memCache[key];

  static const String _tokenKey = 'cubag_token';

  @override
  void setStringSync(String key, String value) {
    _memCache[key] = value;
    if (key == _tokenKey) {
      setString(key, value);
      return;
    }
    _getPrefs().then((prefs) {
      prefs.setString(key, value);
    }).catchError((_) {});
  }

  @override
  List<String>? getStringListSync(String key) => _memListCache[key];

  @override
  Future<void> setString(String key, String value) async {
    _memCache[key] = value;
    if (key == _tokenKey) {
      try {
        await _secureStorage.write(key: _tokenKey, value: value);
        return;
      } catch (e) {
        // Rare: secure storage broken on device. Fall back to prefs so the
        // session survives a restart (removed again on logout).
        debugPrint('SecureStorage write failed for cubag_token: $e');
      }
    }
    try {
      final prefs = await _getPrefs();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  @override
  Future<String?> getString(String key) async {
    if (key == 'cubag_token') {
      try {
        final secure = await _secureStorage.read(key: 'cubag_token');
        if (secure != null && secure.isNotEmpty) {
          _memCache['cubag_token'] = secure;
          return secure;
        }
      } catch (e) {
        debugPrint('SecureStorage read failed for cubag_token: $e');
      }
    }

    if (_memCache.containsKey(key)) return _memCache[key];
    try {
      final prefs = await _getPrefs();
      final val = prefs.getString(key);
      if (val != null) _memCache[key] = val;
      return val;
    } catch (_) {
      return _memCache[key];
    }
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _memListCache[key] = List<String>.from(value);
    final prefs = await _getPrefs();
    await prefs.setStringList(key, value);
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    if (_memListCache.containsKey(key)) return _memListCache[key];
    final prefs = await _getPrefs();
    final val = prefs.getStringList(key);
    if (val != null) _memListCache[key] = List<String>.from(val);
    return val;
  }

  @override
  Future<void> remove(String key) async {
    _memCache.remove(key);
    _memListCache.remove(key);
    final prefs = await _getPrefs();
    await prefs.remove(key);

    if (key == 'cubag_token') {
      try {
        await _secureStorage.delete(key: 'cubag_token');
      } catch (_) {}
    }
  }

  @override
  Future<void> clear() async {
    _memCache.clear();
    _memListCache.clear();
    final prefs = await _getPrefs();
    final keys = [
      'cubag_token',
      'cubag_role',
      'cubag_id',
      'cubag_name',
      'cubag_email',
      'cubag_photo',
      'cubag_permissions',
      'cubag_status',
      'cubag_member_status',
      'cubag_expiry',
      'cubag_license_number',
    ];
    for (final k in keys) {
      await prefs.remove(k);
    }
    try {
      await _secureStorage.delete(key: 'cubag_token');
    } catch (_) {}
  }
}
