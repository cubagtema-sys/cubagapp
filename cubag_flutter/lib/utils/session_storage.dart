import 'session_storage_stub.dart'
    if (dart.library.html) 'session_storage_web.dart';

abstract class SessionStorage {
  static SessionStorage get instance => getSessionStorage();

  Future<void> init();
  String? getStringSync(String key);
  List<String>? getStringListSync(String key);

  Future<void> setString(String key, String value);
  Future<String?> getString(String key);
  Future<void> setStringList(String key, List<String> value);
  Future<List<String>?> getStringList(String key);
  Future<void> remove(String key);
  Future<void> clear();
}
