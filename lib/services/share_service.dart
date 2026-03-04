import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _userDoc {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return _firestore.collection('_').doc('_');
    return _firestore.collection('users').doc(uid);
  }

  /// 설정된 공유용 국가 코드 (null이면 앱 기본 사용). 로그인 시 Firestore 동기화.
  Future<String?> getPreferredShareCountry() async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid != null) {
      try {
        final doc = await _userDoc.get();
        if (doc.exists && doc.data() != null) {
          final c = doc.data()!['preferredShareCountry'] as String?;
          if (c != null) return c;
        }
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefShareCountry);
  }

  Future<void> setPreferredShareCountry(String? country) async {
    final prefs = await SharedPreferences.getInstance();
    if (country == null) {
      await prefs.remove(_prefShareCountry);
    } else {
      await prefs.setString(_prefShareCountry, country);
    }
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid != null) {
      try {
        await _userDoc.set({'preferredShareCountry': country}, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// 로그아웃 시 호출 (로컬 공유 설정 삭제)
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
