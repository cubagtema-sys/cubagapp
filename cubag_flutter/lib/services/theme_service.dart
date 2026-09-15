import 'package:flutter/material.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  static ThemeService get instance => _instance;

  factory ThemeService() => _instance;

  ThemeService._internal();

  ThemeMode get themeMode => ThemeMode.light;
  bool get isDark => false;

  Future<void> init() async {}
  Future<void> toggleTheme() async {}
  Future<void> setThemeMode(ThemeMode mode) async {}
}
