import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../services/locale_service.dart';

/// 이메일 형식 검증 (xxx@yyy.zz 이상)
bool _isValidEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(trimmed);
}

/// 회원가입 시 선택하는 표시 언어 (앱 UI + 게시판 노출 기준)
enum SignupLanguage {
  us('us', 'EN', '🇺🇸'),
  kr('kr', '한국어', '🇰🇷'),
  cn('cn', '中文', '🇨🇳'),
  jp('jp', '日本語', '🇯🇵');

  const SignupLanguage(this.code, this.label, this.flag);
  final String code;
  final String label;
  final String flag;
}

/// 회원가입 페이지
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _isLoading = false;
  SignupLanguage _selectedLanguage = SignupLanguage.us;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _onSignup() async {
    if (_formKey.currentState?.validate() != true) return;

    final s = CountryScope.of(context).strings;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final nickname = _displayNameController.text.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.get('validEmail'), style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (nickname.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.get('nicknameMin'), style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final nicknameAvailable = await UserProfileService.instance.isNicknameAvailable(nickname);
      if (nicknameAvailable == null && mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('닉네임 확인에 실패했어요. 네트워크를 확인하고 다시 시도해 주세요.', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (nicknameAvailable == false && mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미 사용 중인 닉네임이에요.', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await AuthService.instance.signUpWithEmailAndPassword(email, password);
      if (!mounted) return;

      final err = await UserProfileService.instance.createUserProfileAfterSignup(nickname, email, country: _selectedLanguage.code);
      if (!mounted) return;
      await LocaleService.instance.setLocale(_selectedLanguage.code);
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err, style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$nickname님, 환영합니다!', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.accent,
          ),
        );
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      String msg = '회원가입에 실패했어요.';
      if (e.code == 'email-already-in-use') msg = '이미 사용 중인 이메일이에요.';
      else if (e.code == 'invalid-email') msg = s.get('validEmail');
      else if (e.code == 'weak-password') msg = s.get('passwordMin');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('회원가입 실패: $e', style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(LucideIcons.arrow_left, size: 24, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          s.get('signUp'),
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
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
                const SizedBox(height: 16),
                Text(
                  s.get('welcomeSignup'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.get('signupSubtitle'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                // 언어 선택 (앱 표시 언어 + 게시판 노출 기준)
                Text(
                  s.get('language'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: SignupLanguage.values.map((lang) {
                    final isSelected = _selectedLanguage == lang;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedLanguage = lang),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected ? cs.primary : cs.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? cs.primary : cs.outline,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(lang.flag, style: const TextStyle(fontSize: 24)),
                                const SizedBox(height: 4),
                                Text(
                                  lang.label,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? cs.onPrimary : cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _displayNameController,
                  decoration: _inputDecoration(
                    context,
                    labelText: s.get('nickname'),
                    hintText: s.get('nicknameHint'),
                  ),
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: (value) {
                    if (value == null || value.isEmpty) return s.get('enterNickname');
                    if (value.length < 2) return s.get('nicknameMin');
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration(
                    context,
                    labelText: s.get('email'),
                    hintText: 'example@email.com',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return s.get('enterEmail');
                    if (!_isValidEmail(value)) return s.get('validEmail');
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _inputDecoration(
                    context,
                    labelText: s.get('password'),
                    hintText: s.get('passwordHint'),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? LucideIcons.eye_off : LucideIcons.eye,
                        color: AppColors.mediumGrey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return s.get('enterPassword');
                    if (value.length < 8) return s.get('passwordMin');
                    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+\[\];\x27\\/~\x60]').hasMatch(value)) {
                      return s.get('passwordSpecial');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordConfirmController,
                  obscureText: _obscurePasswordConfirm,
                  decoration: _inputDecoration(
                    context,
                    labelText: s.get('passwordConfirm'),
                    hintText: '비밀번호를 다시 입력하세요',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePasswordConfirm ? LucideIcons.eye_off : LucideIcons.eye,
                        color: AppColors.mediumGrey,
                      ),
                      onPressed: () => setState(() => _obscurePasswordConfirm = !_obscurePasswordConfirm),
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return s.get('passwordMismatch');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _isLoading ? null : _onSignup,
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
                          s.get('signUpButton'),
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
                      s.get('hasAccount'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: AppColors.mediumGrey,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        s.get('login'),
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
