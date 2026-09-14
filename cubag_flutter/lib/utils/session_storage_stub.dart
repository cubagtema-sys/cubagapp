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
    final prefs = await _getPrefs();
    for (final key in prefs.getKeys()) {
      final val = prefs.get(key);
      if (val is String) {
        _memCache[key] = val;
      } else if (val is List<String>) {
        _memListCache[key] = List<String>.from(val);
      }
    }

    // Secure token migration and synchronization
    try {
      final secureToken = await _secureStorage.read(key: 'cubag_token');
      if (secureToken != null && secureToken.isNotEmpty) {
        _memCache['cubag_token'] = secureToken;
        await prefs.setString('cubag_token', secureToken);
      } else if (_memCache.containsKey('cubag_token')) {
        // Migrate legacy plain token to secure storage
        final legacyToken = _memCache['cubag_token']!;
        if (legacyToken.isNotEmpty) {
          await _secureStorage.write(key: 'cubag_token', value: legacyToken);
        }
      }
    } catch (_) {
      // Fallback gracefully to SharedPreferences if Keystore is temporarily locked
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
    final prefs = await _getPrefs();
    await prefs.setString(key, value);

    if (key == 'cubag_token') {
      try {
        await _secureStorage.write(key: 'cubag_token', value: value);
      } catch (_) {}
    }
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
      } catch (_) {}
    }

    if (_memCache.containsKey(key)) return _memCache[key];
    final prefs = await _getPrefs();
    final val = prefs.getString(key);
    if (val != null) _memCache[key] = val;
    return val;
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
