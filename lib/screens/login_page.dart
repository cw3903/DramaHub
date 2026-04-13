import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import 'login_screen.dart';

/// 전체 화면 로그인 (모달 푸시) — [LoginScreen]과 동일한 폼·테마.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : AppColors.surface;
    final fg = isDark ? AppColors.darkOnSurface : AppColors.darkGrey;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, size: 24),
          onPressed: () => Navigator.of(context).pop(),
          color: fg,
        ),
        title: Text(
          s.get('login'),
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              child: SizedBox(
                height: constraints.maxHeight,
                width: constraints.maxWidth,
                child: LoginFormContent(
                  onLoginSuccess: () {
                    if (context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
