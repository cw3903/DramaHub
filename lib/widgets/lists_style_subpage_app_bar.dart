import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// 서브페이지 뒤로가기: 빈 스택·연속 pop에 안전하게 [Navigator.maybePop] 사용.
///
/// 제스처/빌드 직후 바로 [maybePop]하면 Navigator가 `_debugLocked`인 채로 assert가 날 수 있어
/// 한 프레임 끝까지 기다린 뒤 실행합니다 ([DramaSearchScreen._popSelf]와 동일).
void popListsStyleSubpage(BuildContext context, [Object? result]) {
  unawaited(_popListsStyleSubpageAsync(context, result));
}

Future<void> _popListsStyleSubpageAsync(
  BuildContext context,
  Object? result,
) async {
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  final nav = Navigator.maybeOf(context);
  if (nav == null || !nav.canPop()) return;
  await nav.maybePop(result);
}

/// [ListsScreen] 상단과 동일 — 툴바 높이·좌우 슬롯 폭·`<`·가운데 제목
const double kListsStyleSubpageToolbarHeight = 46;
const double kListsStyleSubpageSideSlotWidth = 108;

/// Lists 본문 카드·제목과 동일한 왼쪽 여백 (`lists_screen` horizontal 16).
const double kListsStyleSubpageLeadingEdgeInset = 16;

Color listsStyleSubpageHeaderBackground(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return isDark ? Colors.black : theme.scaffoldBackgroundColor;
}

Color listsStyleSubpageBarForeground(ThemeData theme, ColorScheme cs) {
  return theme.brightness == Brightness.dark ? Colors.white : cs.onSurface;
}

Color listsStyleSubpageLeadingMuted(ThemeData theme, ColorScheme cs) {
  final isDark = theme.brightness == Brightness.dark;
  return isDark
      ? Colors.white.withValues(alpha: 0.52)
      : cs.onSurface.withValues(alpha: 0.55);
}

SystemUiOverlayStyle listsStyleSubpageSystemOverlay(
  ThemeData theme,
  Color headerBarBg,
) {
  final isDark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: headerBarBg,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );
}

/// [ListsScreen]·워치리스트 헤더 trailing 공통 — 24×24 다크 칩 + 흰색 십자.
class ListsStyleSubpageHeaderAddButton extends StatelessWidget {
  const ListsStyleSubpageHeaderAddButton({super.key, required this.onTap});

  final VoidCallback onTap;

  static const double _chip = 24;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Ink(
          width: _chip,
          height: _chip,
          decoration: BoxDecoration(
            color: const Color(0xFF2C3440),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Center(
            child: SizedBox(
              width: 10,
              height: 10,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 8,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 1.5,
                      height: 8,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists / List 상세와 동일한 상단 바(상태바 색 + SafeArea + 46px 행, 선택 시 [bottom]).
class ListsStyleSubpageHeaderBar extends StatelessWidget {
  const ListsStyleSubpageHeaderBar({
    super.key,
    required this.title,
    required this.onBack,
    this.leadingLabel,
    this.trailing,
    this.bottom,
    this.backgroundColor,
    this.titleColor,
    this.leadingMutedColor,
  });

  final String title;
  final VoidCallback onBack;
  /// `<` 오른쪽에 붙는 짧은 라벨(닉네임 등). 없으면 화살표만.
  final String? leadingLabel;
  /// 오른쪽 [kListsStyleSubpageSideSlotWidth] 안에 배치. 화면 끝 여백은 leading과 동일([kListsStyleSubpageLeadingEdgeInset]).
  final Widget? trailing;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  /// null이면 [listsStyleSubpageBarForeground] 기준
  final Color? titleColor;
  /// null이면 [listsStyleSubpageLeadingMuted] 기준
  final Color? leadingMutedColor;

  static Size preferredSizeOf(
    BuildContext context, {
    PreferredSizeWidget? bottom,
  }) {
    final top = MediaQuery.paddingOf(context).top;
    final bh = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(top + kListsStyleSubpageToolbarHeight + bh);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headerBg = backgroundColor ?? listsStyleSubpageHeaderBackground(theme);
    final barFg = titleColor ?? listsStyleSubpageBarForeground(theme, cs);
    final leadingMuted =
        leadingMutedColor ?? listsStyleSubpageLeadingMuted(theme, cs);
    final label = leadingLabel?.trim() ?? '';

    return Material(
      color: headerBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: kListsStyleSubpageToolbarHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: kListsStyleSubpageSideSlotWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: kListsStyleSubpageLeadingEdgeInset,
                        right: 4,
                      ),
                      child: SizedBox(
                        height: kListsStyleSubpageToolbarHeight,
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: onBack,
                          behavior: HitTestBehavior.opaque,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 14,
                                  color: leadingMuted,
                                ),
                                if (label.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.start,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        height: 1.1,
                                        fontWeight: FontWeight.w500,
                                        color: leadingMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          color: barFg,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: kListsStyleSubpageSideSlotWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 4,
                          right: kListsStyleSubpageLeadingEdgeInset,
                        ),
                        child: trailing ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}
