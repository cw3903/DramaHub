import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/country_service.dart';
import 'services/level_service.dart';
import 'services/saved_service.dart';
import 'services/user_profile_service.dart';
import 'services/message_service.dart';
import 'services/notification_service.dart';
import 'services/post_service.dart';
import 'services/theme_service.dart';
import 'services/locale_service.dart';
import 'services/drama_view_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/country_scope.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart' show redditTheme, redditDarkTheme;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  // 세션 복원 먼저 (다른 서비스들이 auth 상태에 의존)
  await AuthService.instance.restoreSession();
  // 의존성 없는 초기화는 병렬 실행
  await Future.wait([
    CountryService.instance.loadSavedOverride(),
    LevelService.instance.loadIfNeeded(),
    SavedService.instance.loadIfNeeded(),
    UserProfileService.instance.loadIfNeeded(),
    MessageService.instance.loadIfNeeded(),
    NotificationService.instance.init(),
    ThemeService.instance.load(),
    LocaleService.instance.load(),
    DramaViewService.instance.loadLocalCounts(),
  ]);
  // Country 감지는 loadSavedOverride 완료 후
  CountryService.instance.detectCountry();
  runApp(const DramaHubApp());
  // 댓글 createdAt 일회성 마이그레이션 — runApp 이후 백그라운드에서 실행
  SharedPreferences.getInstance().then((prefs) {
    if (prefs.getBool('comment_createdAt_migrated') != true) {
      PostService.instance.migrateCommentCreatedAt().then((_) {
        prefs.setBool('comment_createdAt_migrated', true);
      });
    }
  });
}

class DramaHubApp extends StatelessWidget {
  const DramaHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LocaleService.instance.localeNotifier,
      builder: (context, locale, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService.instance.themeModeNotifier,
          builder: (context, themeMode, __) {
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
          },
        );
      },
    );
  }
}
