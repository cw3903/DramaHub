import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 표시 언어 (EN/한국어/日本語/中文). 회원가입·프로필에서 선택, 전체 UI에 반영.
class LocaleService {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  static const _keyAppLocale = 'app_locale';
  static const supportedLocales = ['us', 'kr', 'jp', 'cn'];

  final ValueNotifier<String> localeNotifier = ValueNotifier<String>('us');
  bool _loaded = false;

  String get locale => localeNotifier.value;

  /// 앱 시작 시 호출. 저장된 언어 로드 (없으면 'us').
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_keyAppLocale);
      if (saved != null && supportedLocales.contains(saved)) {
        localeNotifier.value = saved;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LocaleService load: $e');
    }
    _loaded = true;
  }

  /// 언어 변경 (회원가입 첫 화면·프로필 언어 메뉴에서 호출).
  Future<void> setLocale(String code) async {
    if (!supportedLocales.contains(code)) return;
    localeNotifier.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAppLocale, code);
    } catch (e) {
      if (kDebugMode) debugPrint('LocaleService setLocale: $e');
    }
  }
}
