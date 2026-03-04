import 'package:flutter/foundation.dart';

/// 유저 레벨 (1~30) 및 숏폼 무료 시청 혜택 관리
/// - 1~29레벨: 광고 시청 시 무료 시청 권한 1회
/// - 30레벨: 광고 시청 시 무료 시청 권한 2회
class UserLevelService {
  UserLevelService._();
  static final UserLevelService instance = UserLevelService._();

  /// 현재 유저 레벨 (1~30)
  final ValueNotifier<int> level = ValueNotifier<int>(1);

  /// 무료 숏폼 시청 가능 횟수 (광고 시청으로 충전)
  final ValueNotifier<int> freeViewCredits = ValueNotifier<int>(0);

  /// 레벨에 따른 광고 시청 시 부여되는 크레딧
  /// 1~29: 1회, 30: 2회
  int get creditsPerAd {
    final lv = level.value;
    if (lv >= 30) return 2;
    return 1;
  }

  /// 광고 시청 완료 시 호출 → 크레딧 지급
  void onAdWatched() {
    freeViewCredits.value += creditsPerAd;
  }

  /// 숏폼 1회 시청 시 호출 → 크레딧 1 소모
  bool useCredit() {
    if (freeViewCredits.value <= 0) return false;
    freeViewCredits.value--;
    return true;
  }

  /// 시청 가능 여부
  bool get canWatchShort => freeViewCredits.value > 0;

  /// 테스트용: 레벨 설정
  void setLevel(int value) {
    level.value = value.clamp(1, 30);
  }

  /// 테스트용: 크레딧 설정
  void setCredits(int value) {
    freeViewCredits.value = value.clamp(0, 999);
  }
}
