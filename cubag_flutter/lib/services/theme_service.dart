import 'package:flutter/material.dart';
import '../utils/session_storage.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  static ThemeService get instance => _instance;

  factory ThemeService() => _instance;

  ThemeService._internal();

  static const String _storageKey = 'cubag_theme_mode';
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> init() async {
    try {
      final saved = await SessionStorage.instance.getString(_storageKey);
      if (saved == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (saved == 'light') {
        _themeMode = ThemeMode.light;
      } else if (saved == 'system') {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
      notifyListeners();
    } catch (_) {
      _themeMode = ThemeMode.light;
    }
  }

  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final val = mode == ThemeMode.dark
          ? 'dark'
          : mode == ThemeMode.system
          ? 'system'
          : 'light';
      await SessionStorage.instance.setString(_storageKey, val);
    } catch (_) {}
  }
}
