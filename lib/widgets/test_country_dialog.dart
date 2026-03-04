import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/country_service.dart';
import '../theme/app_theme.dart';

/// 테스트용 국가 강제 설정 다이얼로그
class TestCountryDialog extends StatelessWidget {
  const TestCountryDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => const TestCountryDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryService.instance;
    return AlertDialog(
      title: Text(
        '테스트: 국가 설정',
        style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '접속 시 표시할 언어를 선택하세요.\nIP 감지 시 자동으로 설정됩니다.',
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: AppColors.mediumGrey,
            ),
          ),
          const SizedBox(height: 16),
          _CountryOption(
            code: 'us',
            label: 'US (English)',
            onTap: () => s.setTestCountry('us').then((_) => Navigator.pop(context)),
          ),
          _CountryOption(
            code: 'kr',
            label: '한국 (한국어)',
            onTap: () => s.setTestCountry('kr').then((_) => Navigator.pop(context)),
          ),
          _CountryOption(
            code: 'cn',
            label: '中国 (中文)',
            onTap: () => s.setTestCountry('cn').then((_) => Navigator.pop(context)),
          ),
          _CountryOption(
            code: 'jp',
            label: '日本 (日本語)',
            onTap: () => s.setTestCountry('jp').then((_) => Navigator.pop(context)),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'IP 자동 감지로 복귀',
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: AppColors.linkBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () => s.setTestCountry(null).then((_) => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}

class _CountryOption extends StatelessWidget {
  const _CountryOption({
    required this.code,
    required this.label,
    required this.onTap,
  });

  final String code;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: GoogleFonts.notoSansKr(fontSize: 15)),
      onTap: onTap,
    );
  }
}
