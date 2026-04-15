import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// DramaHub - 모던 컬러 팔레트 (라이트/다크 공통 브랜드 색)
class AppColors {
  static const Color accent = Color(0xFFFF4500);
  static const Color ratingStar = Color(0xFFFFB020);
  static const Color redditOrange = accent;
  static const Color darkGrey = Color(0xFF1A1A1A);
  static const Color mediumGrey = Color(0xFF6B6B6B);
  static const Color lightGrey = Color(0xFFF5F5F5);
  /// 게시판(인기글/자유/질문) 리스트 배경색. community_screen·BlindRefreshIndicator에서 공통 사용.
  static const Color communityBoardBackground = Color(0xFFF7F7F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color linkBlue = Color(0xFF0A84FF);

  /// 다크 모드용
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkSurfaceVariant = Color(0xFF1E1E1E);
  static const Color darkOnSurface = Color(0xFFE5E5E5);
  static const Color darkOnSurfaceVariant = Color(0xFFB0B0B0);

  /// Community 홈 탭 상단(DramaFeed) AppBar 배경과 동일 — 글 상세 상단 바 등에서 재사용
  static Color homeHeaderBarBackground(ThemeData theme) {
    final pageBg = theme.scaffoldBackgroundColor;
    if (theme.brightness == Brightness.dark) {
      return Color.lerp(Colors.black, pageBg, 0.45) ?? const Color(0xFF0A0A0A);
    }
    return pageBg;
  }
}

/// 모던 테마
ThemeData get redditTheme {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.linkBlue,
      surface: Colors.white,
      onSurface: AppColors.darkGrey,
      surfaceContainerHighest: AppColors.lightGrey,
      outline: Colors.grey.shade200,
    ),
    scaffoldBackgroundColor: AppColors.surface,
    fontFamily: GoogleFonts.notoSansKr().fontFamily,
    textTheme: GoogleFonts.notoSansKrTextTheme().copyWith(
      titleLarge: GoogleFonts.notoSansKr(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkGrey,
      ),
      bodyLarge: GoogleFonts.notoSansKr(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.darkGrey,
      ),
      bodyMedium: GoogleFonts.notoSansKr(
        fontSize: 14,
        color: AppColors.mediumGrey,
      ),
      labelLarge: GoogleFonts.notoSansKr(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.mediumGrey,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.darkGrey,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.darkGrey,
      unselectedLabelColor: AppColors.mediumGrey,
      indicatorColor: AppColors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: GoogleFonts.notoSansKr(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.notoSansKr(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.mediumGrey,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.notoSansKr(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkGrey,
      ),
      contentTextStyle: GoogleFonts.notoSansKr(
        fontSize: 14,
        color: AppColors.mediumGrey,
      ),
    ),
  );
}

/// 다크 모드 테마
ThemeData get redditDarkTheme {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.linkBlue,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkOnSurface,
      onSurfaceVariant: AppColors.darkOnSurfaceVariant,
      surfaceContainerHighest: AppColors.darkSurfaceVariant,
      outline: const Color(0xFF3A3A3A),
    ),
    scaffoldBackgroundColor: AppColors.darkSurface,
    fontFamily: GoogleFonts.notoSansKr().fontFamily,
    textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme).copyWith(
      titleLarge: GoogleFonts.notoSansKr(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkOnSurface,
      ),
      bodyLarge: GoogleFonts.notoSansKr(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.darkOnSurface,
      ),
      bodyMedium: GoogleFonts.notoSansKr(
        fontSize: 14,
        color: AppColors.darkOnSurfaceVariant,
      ),
      labelLarge: GoogleFonts.notoSansKr(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.darkOnSurfaceVariant,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkOnSurface,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.darkOnSurface,
      unselectedLabelColor: AppColors.darkOnSurfaceVariant,
      indicatorColor: AppColors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: GoogleFonts.notoSansKr(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.notoSansKr(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurfaceVariant,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.darkOnSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurfaceVariant,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkSurfaceVariant,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.notoSansKr(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkOnSurface,
      ),
      contentTextStyle: GoogleFonts.notoSansKr(
        fontSize: 14,
        color: AppColors.darkOnSurfaceVariant,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSurfaceVariant,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
