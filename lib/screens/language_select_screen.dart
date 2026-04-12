import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// 표시 언어 4가지: EN / 한국어 / 日本語 / 中文
const Map<String, String> _localeLabels = {
  'us': 'EN',
  'kr': '한국어',
  'jp': '日本語',
  'cn': '中文',
};

/// 회원가입 첫 화면·프로필 설정에서 사용. 선택 시 저장 후 pop(true).
class LanguageSelectScreen extends StatelessWidget {
  const LanguageSelectScreen({
    super.key,
    this.title = 'Select language',
    this.showCloseButton = false,
  });

  final String title;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          title,
          style: GoogleFonts.notoSansKr(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: showCloseButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => Navigator.pop(context, false),
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final code in LocaleService.supportedLocales) ...[
                Material(
                  color: isDark ? cs.surfaceContainerHighest : (cs.surfaceContainerHighest.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      // Navigator 잠금 방지: 먼저 pop한 뒤 다음 프레임에서 언어 변경
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                        await LocaleService.instance.setLocale(code);
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                      child: Text(
                        _localeLabels[code]!,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
