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

class _LoginPalette {
  const _LoginPalette({
    required this.scaffoldBg,
    required this.fieldFill,
    required this.border,
    required this.text,
    required this.muted,
    required this.snackBarBg,
  });

  final Color scaffoldBg;
  final Color fieldFill;
  final Color border;
  final Color text;
  final Color muted;
  final Color snackBarBg;

  static _LoginPalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    if (isDark) {
      return _LoginPalette(
        scaffoldBg: AppColors.darkSurface,
        fieldFill: AppColors.darkSurfaceVariant,
        border: cs.outline.withValues(alpha: 0.85),
        text: AppColors.darkOnSurface,
        muted: AppColors.darkOnSurfaceVariant,
        snackBarBg: const Color(0xFF2C2C2C),
      );
    }
    return _LoginPalette(
      scaffoldBg: AppColors.surface,
      fieldFill: const Color(0xFFFAFAFA),
      border: const Color(0xFFDBDBDB),
      text: const Color(0xFF262626),
      muted: const Color(0xFF8E8E8E),
      snackBarBg: const Color(0xFF262626),
    );
  }
}

/// 로그인 탭 화면
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.onLoginSuccess});

  final VoidCallback? onLoginSuccess;

  @override
  Widget build(BuildContext context) {
    final p = _LoginPalette.of(context);
    return Scaffold(
      backgroundColor: p.scaffoldBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              child: SizedBox(
                height: constraints.maxHeight,
                width: constraints.maxWidth,
                child: LoginFormContent(onLoginSuccess: onLoginSuccess),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 로그인 폼 (프로필 탭·[LoginPage] 공통)
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

  InputDecoration _fieldDecoration(_LoginPalette p, {required String hint, Widget? suffixIcon}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.border, width: 1),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.notoSansKr(
        color: p.muted,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: p.fieldFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade600, width: 1.2),
      ),
      suffixIcon: suffixIcon,
      errorStyle: GoogleFonts.notoSansKr(fontSize: 12, color: Colors.red.shade400),
    );
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
      final p = _LoginPalette.of(context);
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
          content: Text(msg, style: GoogleFonts.notoSansKr(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: p.snackBarBg,
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
            style: GoogleFonts.notoSansKr(color: Colors.white),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _openSignUp() async {
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
    if (!mounted) return;
    if (ok == true) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const SignupPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final p = _LoginPalette.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      color: p.text,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: _fieldDecoration(p, hint: s.get('email')),
                    validator: (value) {
                      if (value == null || value.isEmpty) return s.get('enterEmail');
                      if (!value.contains('@')) return s.get('validEmail');
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      color: p.text,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: _fieldDecoration(
                      p,
                      hint: s.get('password'),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? LucideIcons.eye_off : LucideIcons.eye,
                          size: 20,
                          color: p.muted,
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
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _isLoading ? null : _onLogin,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.45),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: const StadiumBorder(),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            s.get('login'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Forgot password?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: p.muted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: Divider(color: p.border, thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          s.get('loginDividerOr'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: p.muted,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: p.border, thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: _isLoading ? null : _onGoogleLogin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: p.border, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _GoogleGlyph(palette: p),
                        const SizedBox(width: 10),
                        Text(
                          s.get('loginWithGoogle'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  Text(
                    s.get('noAccount'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: p.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _isLoading ? null : _openSignUp,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.accent, width: 1.1),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      s.get('signUp'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.palette});

  final _LoginPalette palette;

  static const double _size = 22;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.fieldFill,
        shape: BoxShape.circle,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        'G',
        style: GoogleFonts.roboto(
          fontSize: _size * 0.52,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF4285F4),
          height: 1,
        ),
      ),
    );
  }
}
