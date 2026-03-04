import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/share_service.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../screens/share_settings_page.dart';

/// 공유 바텀시트 - 링크 복사, 앱 공유, 설정
class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.title,
    this.type = 'drama',
  });

  final String title;
  final String type; // 'short', 'drama', 'post'

  static Future<void> show(
    BuildContext context, {
    required String title,
    String type = 'drama',
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(title: title, type: type),
    );
  }

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  String _country = 'us';

  @override
  void initState() {
    super.initState();
    ShareService.instance.getPreferredShareCountry().then((c) {
      if (mounted && c != null) setState(() => _country = c);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _country = CountryScope.maybeOf(context)?.country ?? _country;
  }

  ShareContent get _content => ShareService.instance.buildContent(
        country: _country,
        title: widget.title,
        type: widget.type,
      );

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.get('share'),
            style: GoogleFonts.notoSansKr(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          // 링크 복사
          _ShareOptionTile(
            icon: LucideIcons.link,
            label: s.get('copyLink'),
            onTap: () async {
              await ShareService.instance.copyLink(_content);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(s.get('linkCopied'), style: GoogleFonts.notoSansKr()),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.accent,
                  ),
                );
              }
              HapticFeedback.lightImpact();
            },
          ),
          const SizedBox(height: 12),
          // 앱으로 공유
          _ShareOptionTile(
            icon: LucideIcons.share_2,
            label: s.get('shareToApps'),
            onTap: () async {
              HapticFeedback.lightImpact();
              await ShareService.instance.share(_content);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          // 공유 설정
          _ShareOptionTile(
            icon: LucideIcons.settings,
            label: s.get('shareSettings'),
            onTap: () {
              HapticFeedback.lightImpact();
              final navigator = Navigator.of(context);
              Navigator.pop(context);
              navigator.push(
                CupertinoPageRoute(builder: (_) => const ShareSettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: AppColors.accent),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.chevron_right, size: 20, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
