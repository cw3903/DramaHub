import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/share_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bar_back_icon_button.dart';
import '../widgets/country_scope.dart';

/// 공유 설정 - 국가별 공유 메시지/앱 우선순위
class ShareSettingsPage extends StatefulWidget {
  const ShareSettingsPage({super.key});

  @override
  State<ShareSettingsPage> createState() => _ShareSettingsPageState();
}

class _ShareSettingsPageState extends State<ShareSettingsPage> {
  String? _selectedCountry;
  bool _loading = true;

  /// 미국, 한국, 중국, 일본 순
  static const _countries = [
    ('us', '미국', 'Instagram, Twitter, etc.'),
    ('kr', '한국', '카카오톡, 인스타그램 등'),
    ('cn', '중국', '微信, 微博 등'),
    ('jp', '일본', 'LINE, Twitter 등'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ShareService.instance.getPreferredShareCountry();
    setState(() {
      _selectedCountry = c ?? 'us';
      _loading = false;
    });
  }

  Future<void> _setCountry(String? country) async {
    await ShareService.instance.setPreferredShareCountry(country);
    setState(() => _selectedCountry = country);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: AppBarBackIconButton(
          iconColor: Colors.white,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.get('shareSettings'),
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '공유 메시지 지역',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '공유 시 사용할 메시지 형식과 인기 앱이 지역에 맞게 표시됩니다.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ..._countries.map((e) => _CountryTile(
                        countryCode: e.$1,
                        label: e.$2,
                        subtitle: e.$3,
                        isSelected: _selectedCountry == e.$1,
                        onTap: () => _setCountry(e.$1),
                      )),
                ],
              ),
            ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.countryCode,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String? countryCode;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent.withOpacity(0.15) : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.accent : Colors.white12,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 22,
                  color: isSelected ? AppColors.accent : Colors.grey.shade500,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: Colors.grey.shade500,
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
    );
  }
}
