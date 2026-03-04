import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../services/auth_service.dart';
import 'signup_page.dart';
import 'language_select_screen.dart';
import '../app_strings.dart';
import '../services/locale_service.dart';

/// 로그인 페이지 (전체 화면 - 앱바 로그인 버튼 탭 시)
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      await AuthService.instance.signInWithEmailAndPassword(email, password);
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final s = CountryScope.of(context).strings;
      String msg = s.get('loginErrorGeneric');
      if (e is FirebaseAuthException && e.code == 'invalid-credential') {
        try {
          final methods = await AuthService.instance.fetchSignInMethodsForEmail(email);
          msg = methods.isEmpty
              ? s.get('loginErrorEmailNotRegistered')
              : s.get('loginErrorWrongPassword');
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, size: 24),
          onPressed: () => Navigator.of(context).pop(),
          color: isDark ? cs.onSurface : AppColors.darkGrey,
        ),
        title: Text(
          s.get('login'),
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? cs.onSurface : AppColors.darkGrey,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Text(
                  s.get('welcomeLogin'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: isDark ? cs.onSurface : AppColors.darkGrey,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.get('loginSubtitle'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: isDark ? cs.onSurfaceVariant : AppColors.mediumGrey,
                  ),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.notoSansKr(fontSize: 16, color: cs.onSurface),
                  decoration: InputDecoration(
                    labelText: s.get('email'),
                    hintText: 'example@email.com',
                    hintStyle: GoogleFonts.notoSansKr(color: cs.onSurfaceVariant),
                    filled: true,
                    fillColor: isDark ? cs.surfaceContainerHighest : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: isDark ? cs.outline : Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: isDark ? cs.outline : AppColors.accent, width: isDark ? 1 : 2),
                    ),
                    labelStyle: GoogleFonts.notoSansKr(color: cs.onSurfaceVariant),
                    floatingLabelStyle: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      color: isDark ? Colors.white : AppColors.accent,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return s.get('enterEmail');
                    }
                    if (!value.contains('@')) {
                      return s.get('validEmail');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.notoSansKr(fontSize: 16, color: cs.onSurface),
                  decoration: InputDecoration(
                    labelText: s.get('password'),
                    hintText: '비밀번호를 입력하세요',
                    hintStyle: GoogleFonts.notoSansKr(color: cs.onSurfaceVariant),
                    filled: true,
                    fillColor: isDark ? cs.surfaceContainerHighest : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: isDark ? cs.outline : Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: isDark ? cs.outline : AppColors.accent, width: isDark ? 1 : 2),
                    ),
                    labelStyle: GoogleFonts.notoSansKr(color: cs.onSurfaceVariant),
                    floatingLabelStyle: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      color: isDark ? Colors.white : AppColors.accent,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? LucideIcons.eye_off : LucideIcons.eye,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return s.get('enterPassword');
                    }
                    if (value.length < 6) {
                      return s.get('passwordMin');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _isLoading ? null : _onLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          s.get('login'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s.get('noAccount'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: AppColors.mediumGrey,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final title = AppStrings(LocaleService.instance.locale).get('language');
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LanguageSelectScreen(
                              title: title,
                              showCloseButton: true,
                            ),
                          ),
                        );
                        if (context.mounted && ok == true) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SignupPage()),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        s.get('signUp'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.linkBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
