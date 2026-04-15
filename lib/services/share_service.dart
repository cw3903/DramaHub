import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'locale_service.dart';

/// 공유 대상 (국가별 인기 앱 표시용)
enum ShareTarget {
  copyLink,
  nativeShare,
}

/// 국가별 공유 메시지 형식 + 설정
class ShareService {
  ShareService._();
  static final instance = ShareService._();

  static const _prefShareCountry = 'share_preferred_country';

  /// 공유할 콘텐츠 생성
  ShareContent buildContent({
    required String country,
    String? title,
    String? type, // 'short', 'drama', 'post'
  }) {
    final baseUrl = 'https://dramahub.app';
    final path = type == 'post' ? '/community' : '/watch';
    final link = '$baseUrl$path';
    final t = title ?? 'DramaHub 콘텐츠';

    switch (country) {
      case 'kr':
        return ShareContent(
          text: '$t\n\n$link',
          subject: 'DramaHub에서 함께 보기',
        );
      case 'cn':
        return ShareContent(
          text: '$t\n\n$link',
          subject: '在DramaHub一起观看',
        );
      case 'jp':
        return ShareContent(
          text: '$t\n\n$link',
          subject: 'DramaHubで一緒に視聴',
        );
      default:
        return ShareContent(
          text: '$t\n\n$link',
          subject: 'Watch together on DramaHub',
        );
    }
  }

  /// 링크 복사
  Future<void> copyLink(ShareContent content) async {
    await Clipboard.setData(ClipboardData(text: content.text));
  }

  /// 네이티브 공유 시트 열기
  Future<void> share(ShareContent content) async {
    await Share.share(
      content.text,
      subject: content.subject,
    );
  }

  /// 앱 표시 언어(us/kr/jp/cn)와 동일한 코드 — 공유 문구·제목에 사용.
  Future<String?> getPreferredShareCountry() async {
    await LocaleService.instance.load();
    final c = LocaleService.instance.locale;
    return LocaleService.supportedLocales.contains(c) ? c : 'us';
  }

  /// 로그아웃 시 호출 (구버전 로컬 공유 국가 프리퍼런스 제거)
  Future<void> clearForLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefShareCountry);
    } catch (_) {}
  }
}

class ShareContent {
  ShareContent({required this.text, this.subject});
  final String text;
  final String? subject;
}
