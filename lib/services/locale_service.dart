import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile_service.dart';

/// 앱 표시 언어 (EN/한국어/日本語/中文). 회원가입·프로필에서 선택, 전체 UI에 반영.
class LocaleService {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  static const _keyAppLocale = 'app_locale';
  static const supportedLocales = ['us', 'kr', 'jp', 'cn'];

  final ValueNotifier<String> localeNotifier = ValueNotifier<String>('us');
  bool _loaded = false;

  /// [setLocale] / [load]에서 [localeNotifier] 값을 바꾸기 **직전**에 호출.
  /// (리스너 등록 순 때문에 알림 후에 비우면 위젯이 옛 캐시를 한 프레임 읽을 수 있음)
  static final List<void Function()> _preLocaleCommitCallbacks = [];

  static void registerPreLocaleCommit(void Function() fn) {
    _preLocaleCommitCallbacks.add(fn);
  }

  static void _runPreLocaleCommitCallbacks() {
    if (_preLocaleCommitCallbacks.isEmpty) return;
    final copy = List<void Function()>.from(_preLocaleCommitCallbacks);
    for (final fn in copy) {
      try {
        fn();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('LocaleService preLocaleCommit: $e\n$st');
        }
      }
    }
  }

  /// [setLocale]에서 [localeNotifier] 갱신 **직후** 호출 (새 로케일로 서비스 재로드).
  /// [main]에서 등록 — [LocaleService]는 [ReviewService] 등을 import하지 않음.
  static final List<Future<void> Function()> _postLocaleCommitHandlers = [];

  static void registerPostLocaleCommit(Future<void> Function() fn) {
    _postLocaleCommitHandlers.add(fn);
  }

  static void _runPostLocaleCommitCallbacks() {
    if (_postLocaleCommitHandlers.isEmpty) return;
    final copy = List<Future<void> Function()>.from(_postLocaleCommitHandlers);
    for (final fn in copy) {
      unawaited(
        (() async {
          try {
            await fn();
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('LocaleService postLocaleCommit: $e\n$st');
            }
          }
        })(),
      );
    }
  }

  String get locale => localeNotifier.value;

  /// 앱 시작 시 호출. 저장된 언어 로드 (없으면 'us').
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var saved = prefs.getString(_keyAppLocale);
      // 구버전·오타: BCP-47 `ko` 등 → 앱 코드 `kr`
      if (saved != null && saved.toLowerCase() == 'ko') {
        saved = 'kr';
        await prefs.setString(_keyAppLocale, 'kr');
      }
      if (saved != null && supportedLocales.contains(saved)) {
        _runPreLocaleCommitCallbacks();
        localeNotifier.value = saved;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LocaleService load: $e');
    }
    _loaded = true;
  }

  /// 언어 변경 (회원가입 첫 화면·프로필 언어 메뉴에서 호출).
  /// 로그인 중이면 Firestore `users/{uid}.country` 및 [UserProfileService.signupCountryNotifier]도 동기화해
  /// 피드·글 작성 기준(us/kr/jp/cn)이 앱 표시 언어와 맞도록 함.
  ///
  /// **Firestore 실패해도** 로컬 저장·[localeNotifier]·메모리 상의 가입 구역은 반드시 갱신한다.
  /// (이전 구현은 Firestore 예외 시 UI 언어가 안 바뀌는 버그가 있었음.)
  Future<void> setLocale(String code) async {
    if (!supportedLocales.contains(code)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAppLocale, code);
    } catch (e) {
      if (kDebugMode) debugPrint('LocaleService setLocale prefs: $e');
    }

    _runPreLocaleCommitCallbacks();
    localeNotifier.value = code;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // 피드·새 글 country와 표시 언어를 즉시 일치 (Firestore는 그 다음 베스트 에포트)
      UserProfileService.instance.signupCountryNotifier.value = code;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'country': code}, SetOptions(merge: true));
      } catch (e) {
        if (kDebugMode) debugPrint('LocaleService setLocale Firestore: $e');
      }
    }
    _runPostLocaleCommitCallbacks();
  }
}
