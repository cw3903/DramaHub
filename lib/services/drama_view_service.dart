import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 드라마 카드 클릭(상세 진입) 횟수 — Firestore 저장 + SharedPreferences 로컬 보정
/// (앱 재시작해도 로컬 카운트 유지 → Firestore 쓰기 실패해도 다음날 0으로 안 됨)
class DramaViewService {
  DramaViewService._();
  static final DramaViewService instance = DramaViewService._();

  static const String _collection = 'drama_views';
  static const String _dailyCollection = 'drama_view_daily';
  static const String _prefKey = 'drama_local_view_counts';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 이번 앱 세션 + SharedPreferences에서 복원한 로컬 조회수
  static final Map<String, int> _localAdds = {};
  static bool _localLoaded = false;

  String _dayKey(DateTime now) =>
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

  /// 앱 시작 시 SharedPreferences에서 로컬 카운트 복원
  Future<void> loadLocalCounts() async {
    if (_localLoaded) return;
    _localLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          _localAdds[e.key] = (e.value as num).toInt();
        }
        debugPrint('DramaViewService: 로컬 카운트 복원 ${_localAdds.length}개');
      }
    } catch (e) {
      debugPrint('DramaViewService loadLocalCounts: $e');
    }
  }

  /// 로컬 카운트를 SharedPreferences에 저장
  Future<void> _saveLocalCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(_localAdds));
    } catch (e) {
      debugPrint('DramaViewService _saveLocalCounts: $e');
    }
  }

  /// 상세 페이지 진입 시 호출: 해당 드라마 조회수 +1.
  Future<void> increment(String dramaId) async {
    if (dramaId.isEmpty) return;

    // 로컬 카운트 먼저 증가 (Firestore 실패해도 앱 내/다음 실행에서 유지)
    await loadLocalCounts();
    _localAdds[dramaId] = (_localAdds[dramaId] ?? 0) + 1;
    await _saveLocalCounts();

    // Firestore에 재시도 포함해서 쓰기
    _incrementFirestore(dramaId);
  }

  /// Firestore 쓰기 (백그라운드, 최대 3회 재시도)
  Future<void> _incrementFirestore(String dramaId) async {
    const delays = [Duration.zero, Duration(seconds: 2), Duration(seconds: 5)];
    for (var i = 0; i < delays.length; i++) {
      if (i > 0) await Future.delayed(delays[i]);
      try {
        final ref = _firestore.collection(_collection).doc(dramaId);
        await ref.set({'count': FieldValue.increment(1)}, SetOptions(merge: true));
        final dayRef = _firestore
            .collection(_dailyCollection)
            .doc(_dayKey(DateTime.now()));
        try {
          await dayRef.update({'views.$dramaId': FieldValue.increment(1)});
        } catch (e) {
          if (e.toString().contains('NOT_FOUND') || e.toString().contains('no document')) {
            await dayRef.set({'views': {dramaId: 1}}, SetOptions(merge: true));
          }
        }
        debugPrint('DramaViewService increment OK: $dramaId (attempt ${i + 1})');
        return;
      } catch (e) {
        debugPrint('DramaViewService increment FAIL attempt ${i + 1}: $e');
      }
    }
  }

  /// 특정 드라마 조회수. Firestore 값과 로컬 추가분 중 큰 쪽 사용.
  Future<int> getViewCount(String dramaId) async {
    if (dramaId.isEmpty) return 0;
    await loadLocalCounts();
    int fromServer = 0;
    try {
      final snap = await _firestore.collection(_collection).doc(dramaId).get();
      fromServer = (snap.data()?['count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('DramaViewService getViewCount ERROR: $e');
    }
    final local = _localAdds[dramaId] ?? 0;
    return fromServer > local ? fromServer : local;
  }

  /// 드라마별 조회수 맵. Firestore 값과 로컬 중 큰 값 사용.
  Future<Map<String, int>> getAllViewCounts() async {
    await loadLocalCounts();
    final map = <String, int>{};
    try {
      final snapshot = await _firestore.collection(_collection).get();
      for (final doc in snapshot.docs) {
        final count = (doc.data()['count'] as num?)?.toInt() ?? 0;
        map[doc.id] = count;
      }
    } catch (e) {
      debugPrint('DramaViewService getAllViewCounts ERROR: $e');
    }
    // 로컬이 서버보다 크면 로컬로 덮어쓰기 (Firestore 쓰기 지연/실패 보정)
    for (final e in _localAdds.entries) {
      final current = map[e.key] ?? 0;
      if (e.value > current) map[e.key] = e.value;
    }
    if (map.isEmpty) {
      debugPrint('DramaViewService: getAllViewCounts 결과 0개 — Firestore drama_views 컬렉션이 비어있거나 쓰기 규칙 미배포 가능성');
    }
    return map;
  }

  /// 지난 7일(오늘 포함) 조회수 합산. 리뷰 탭 인기순 정렬용.
  Future<Map<String, int>> getViewCountsLast7Days() async {
    await loadLocalCounts();
    final map = <String, int>{};
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      final docId = _dayKey(d);
      try {
        final snap = await _firestore
            .collection(_dailyCollection)
            .doc(docId)
            .get();
        final data = snap.data()?['views'];
        if (data is Map) {
          for (final e in data.entries) {
            if (e.value is num) {
              final id = e.key.toString();
              map[id] = (map[id] ?? 0) + (e.value as num).toInt();
            }
          }
        }
      } catch (e) {
        debugPrint('DramaViewService getViewCountsLast7Days doc $docId: $e');
      }
    }
    // 7일 합산도 로컬 보정 (세션 내 진입분 반영)
    for (final e in _localAdds.entries) {
      final current = map[e.key] ?? 0;
      if (e.value > current) map[e.key] = e.value;
    }
    return map;
  }
}
