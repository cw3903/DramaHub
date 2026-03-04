import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// IP 기반 국가 감지 + 테스트용 강제 설정
class CountryService {
  CountryService._();
  static final CountryService instance = CountryService._();

  static const _keyTestCountry = 'test_country_override';
  static const _supportedCountries = ['us', 'kr', 'cn', 'jp'];

  final ValueNotifier<String> countryNotifier = ValueNotifier<String>('us');

  /// IP로 국가 감지 (테스트 강제 설정이 있으면 무시)
  Future<void> detectCountry() async {
    final prefs = await SharedPreferences.getInstance();
    final testOverride = prefs.getString(_keyTestCountry);

    if (testOverride != null && _supportedCountries.contains(testOverride)) {
      countryNotifier.value = testOverride;
      return;
    }

    try {
      final response = await http
          .get(Uri.parse('http://ip-api.com/json/?fields=countryCode'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = (data['countryCode'] as String?)?.toLowerCase() ?? 'us';

        // 지원 국가로 매핑 (일치하지 않으면 US)
        final mapped = _mapToSupported(code);
        countryNotifier.value = mapped;
      }
    } catch (e) {
      if (kDebugMode) {
        print('CountryService: IP 감지 실패 $e');
      }
      countryNotifier.value = 'us';
    }
  }

  String _mapToSupported(String code) {
    switch (code) {
      case 'kr':
      case 'kp':
        return 'kr';
      case 'jp':
        return 'jp';
      case 'cn':
      case 'tw':
      case 'hk':
      case 'mo':
        return 'cn';
      case 'us':
      case 'gb':
      case 'au':
      case 'ca':
      default:
        return 'us';
    }
  }

  /// 테스트용: 국가 코드 강제 설정 (null이면 IP 감지로 복귀)
  Future<void> setTestCountry(String? countryCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (countryCode == null) {
      await prefs.remove(_keyTestCountry);
    } else if (_supportedCountries.contains(countryCode)) {
      await prefs.setString(_keyTestCountry, countryCode);
    }
    await detectCountry();
  }

  /// 현재 테스트 강제 설정 여부
  Future<bool> hasTestOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyTestCountry);
  }

  /// 저장된 테스트 국가 로드
  Future<void> loadSavedOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final testOverride = prefs.getString(_keyTestCountry);
    if (testOverride != null) {
      countryNotifier.value = testOverride;
    }
  }
}
