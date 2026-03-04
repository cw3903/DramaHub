import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 테마 모드 저장/복원 (프로필에서 변경)
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const String _key = 'app_theme_mode';
  /// 라이트/다크만 사용. 기본은 라이트.
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v == 'dark') themeModeNotifier.value = ThemeMode.dark;
      else themeModeNotifier.value = ThemeMode.light;
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }
}
