import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'services/watch_history_service.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/country_service.dart';
import 'services/level_service.dart';
import 'services/saved_service.dart';
import 'services/watchlist_service.dart';
import 'services/user_profile_service.dart';
import 'services/message_service.dart';
import 'services/notification_service.dart';
import 'services/post_service.dart';
import 'services/theme_service.dart';
import 'services/locale_service.dart';
import 'services/review_service.dart';
import 'services/drama_view_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/country_scope.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart' show redditTheme, redditDarkTheme;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // LocaleService.load / setLocale 직전 콜백 — 드라마 탭 미방문 시에도 등록되도록 최대한 이른 시점
  ReviewService.ensurePreLocaleAggregateClearRegistered();
  LocaleService.registerPostLocaleCommit(() async {
    // 동시 실행 대신 순차 실행 + 각각 독립 에러 처리
    // Firestore 채널 과부하 방지
    Future.microtask(() async {
      try {
        await ReviewService.instance.refresh();
      } catch (e) {
        debugPrint('ReviewService refresh: $e');
      }
      try {
        await WatchHistoryService.instance.refresh();
      } catch (e) {
        debugPrint('WatchHistoryService refresh: $e');
      }
    });
  });
  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  // 세션 복원 먼저 (다른 서비스들이 auth 상태에 의존)
  await AuthService.instance.restoreSession();
  // 앱 첫 프레임 전 필수 초기화만 대기 (느린 Firestore·쪽지 등은 runApp 뒤 백그라운드)
  await Future.wait([
    CountryService.instance.loadSavedOverride(),
    LevelService.instance.loadIfNeeded(),
    ThemeService.instance.load(),
    LocaleService.instance.load(),
    NotificationService.instance.init(),
  ]);
  CountryService.instance.detectCountry();
  runApp(const DramaHubApp());
  unawaited(SavedService.instance.loadIfNeeded());
  unawaited(WatchlistService.instance.loadIfNeeded());
  unawaited(UserProfileService.instance.loadIfNeeded());
  unawaited(MessageService.instance.loadIfNeeded());
  unawaited(DramaViewService.instance.loadLocalCounts());
  // 댓글 createdAt 일회성 마이그레이션 — runApp 이후 백그라운드에서 실행
  SharedPreferences.getInstance().then((prefs) {
    if (prefs.getBool('comment_createdAt_migrated') != true) {
      PostService.instance.migrateCommentCreatedAt().then((_) {
        prefs.setBool('comment_createdAt_migrated', true);
      });
    }
  });
}

class DramaHubApp extends StatefulWidget {
  const DramaHubApp({super.key});

  @override
  State<DramaHubApp> createState() => _DramaHubAppState();
}

class _DramaHubAppState extends State<DramaHubApp> {
  @override
  void initState() {
    super.initState();
    LocaleService.instance.localeNotifier.addListener(_onLocaleChanged);
    ThemeService.instance.themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    LocaleService.instance.localeNotifier.removeListener(_onLocaleChanged);
    ThemeService.instance.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onLocaleChanged() => setState(() {});
  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final locale = LocaleService.instance.locale;
    final themeMode = ThemeService.instance.themeModeNotifier.value;
    return CountryScope(
      country: locale,
      child: MaterialApp(
        title: 'DramaHub',
        debugShowCheckedModeBanner: false,
        theme: redditTheme,
        darkTheme: redditDarkTheme,
        themeMode: themeMode,
        themeAnimationDuration: Duration.zero,
        home: const MainScreen(),
      ),
    );
  }
}
