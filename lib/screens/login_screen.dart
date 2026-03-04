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

/// 로그인 탭 화면 - 로그인 폼 표시
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.onLoginSuccess});

  final VoidCallback? onLoginSuccess;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: LoginFormContent(onLoginSuccess: onLoginSuccess),
      ),
    );
  }
}

/// 로그인 폼 (탭에서 사용 - 로그인 페이지와 동일한 폼)
class LoginFormContent extends StatefulWidget {
  const LoginFormContent({super.key, this.onLoginSuccess});

  final VoidCallback? onLoginSuccess;

  @override
  State<LoginFormContent> createState() => _LoginFormContentState();
}

class _LoginFormContentState extends State<LoginFormContent> {
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
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signInWithEmailAndPassword(email, password);
      if (!mounted) return;
      setState(() => _isLoading = false);
      widget.onLoginSuccess?.call();
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

  Future<void> _onGoogleLogin() async {
    final s = CountryScope.of(context).strings;
    setState(() => _isLoading = true);
    try {
      final user = await AuthService.instance.signInWithGoogle();
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (user != null) {
        widget.onLoginSuccess?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${s.get('loginPreparing')}: $e',
            style: GoogleFonts.notoSansKr(),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
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
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text(
            s.get('welcomeLogin'),
            style: GoogleFonts.notoSansKr(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.get('loginSubtitle'),
            style: GoogleFonts.notoSansKr(
              fontSize: 15,
              color: cs.onSurfaceVariant,
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
              if (value == null || value.isEmpty) return s.get('enterEmail');
              if (!value.contains('@')) return s.get('validEmail');
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
              if (value == null || value.isEmpty) return s.get('enterPassword');
              if (value.length < 6) return s.get('passwordMin');
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
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _onGoogleLogin,
            icon: Icon(Icons.g_mobiledata, size: 24, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              s.get('loginWithGoogle'),
              style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}
