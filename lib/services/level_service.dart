import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// 회원레벨 1~30, 30레벨 = 10만점.
/// 글쓰기 완료 시 [addPoints](5), 댓글 작성 완료 시 [addPoints](1) 호출.
/// 로그인 시 Firestore users/{uid} 에 totalPoints 저장/로드.
class LevelService {
  LevelService._();
  static final LevelService instance = LevelService._();

  static const String _keyTotalPoints = 'user_total_points';
  static const int _maxLevel = 30;
  static const int _pointsForLevel30 = 100000;

  final ValueNotifier<int> totalPointsNotifier = ValueNotifier<int>(0);
  bool _loaded = false;
  String? _lastUid;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _userDoc {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return _firestore.collection('_').doc('_');
    return _firestore.collection('users').doc(uid);
  }

  int get totalPoints => totalPointsNotifier.value;

  /// 레벨 n(1~30)에 필요한 최소 누적 점수. 30레벨 = 10만점, 초반은 완만하게.
  static int pointsRequiredForLevel(int n) {
    if (n <= 1) return 0;
    if (n >= _maxLevel) return _pointsForLevel30;
    // 1~29: 10만 * (n/30)^2 로 구간 설정
    return (_pointsForLevel30 * (n * n) / (_maxLevel * _maxLevel)).round();
  }

  /// 현재 누적 점수로 레벨 계산 (1~30)
  int getLevel(int points) {
    if (points <= 0) return 1;
    for (int n = _maxLevel; n >= 1; n--) {
      if (points >= pointsRequiredForLevel(n)) return n;
    }
    return 1;
  }

  int get currentLevel => getLevel(totalPointsNotifier.value);

  Future<void> _ensureLoaded() async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (_loaded && _lastUid == uid) return;
    _lastUid = uid;
    if (uid != null) {
      try {
        final doc = await _userDoc.get();
        if (doc.exists && doc.data() != null) {
          final n = doc.data()!['totalPoints'] as num?;
          totalPointsNotifier.value = n?.toInt() ?? 0;
        } else {
          totalPointsNotifier.value = 0;
        }
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        totalPointsNotifier.value = prefs.getInt(_keyTotalPoints) ?? 0;
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      totalPointsNotifier.value = prefs.getInt(_keyTotalPoints) ?? 0;
    }
    _loaded = true;
  }

  Future<void> addPoints(int points) async {
    await _ensureLoaded();
    if (points <= 0) return;
    totalPointsNotifier.value = totalPointsNotifier.value + points;
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid != null) {
      try {
        await _userDoc.set({'totalPoints': totalPointsNotifier.value}, SetOptions(merge: true));
      } catch (_) {}
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyTotalPoints, totalPointsNotifier.value);
    }
  }

  /// 프로필 등에서 초기 로드 시 호출
  Future<void> loadIfNeeded() async {
    await _ensureLoaded();
  }

  /// 로그아웃 시 호출 (로컬 포인트 캐시도 삭제)
  Future<void> resetForLogout() async {
    totalPointsNotifier.value = 0;
    _loaded = false;
    _lastUid = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyTotalPoints);
    } catch (_) {}
  }
}
