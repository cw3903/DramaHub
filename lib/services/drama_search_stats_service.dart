import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 인기 검색 순위 기간
enum SearchStatsPeriod {
  /// 지난 24시간 (현재 시각 기준)
  day,
  /// 지난 7일 (현재 시각 기준)
  week,
  month,
  year,
}

/// 검색 페이지 인기 순위: 검색 + 클릭 복합 점수.
/// Today = 지난 24시간(1시간 버킷). Week = 지난 7일(일 단위 버킷). Month/Year = 캘린더.
class DramaSearchStatsService {
  DramaSearchStatsService._();

  static final DramaSearchStatsService instance = DramaSearchStatsService._();

  /// hour_2026030314, day_20260303, month_202503, year_2025
  static const String _collection = 'drama_search_stats';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _hourKey(DateTime now) =>
      'hour_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}';

  String _dayKey(DateTime now) =>
      'day_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

  String _monthKey(DateTime now) =>
      'month_${now.year}${now.month.toString().padLeft(2, '0')}';

  String _yearKey(DateTime now) => 'year_${now.year}';

  /// Today: 지난 24개 hour 문서 id
  List<String> _last24HourDocIds(DateTime now) {
    final ids = <String>[];
    for (var i = 0; i < 24; i++) {
      ids.add(_hourKey(now.subtract(Duration(hours: i))));
    }
    return ids;
  }

  /// Week: 지난 7일 day 문서 id (오늘 포함 7개)
  List<String> _last7DayDocIds(DateTime now) {
    final ids = <String>[];
    for (var i = 0; i < 7; i++) {
      ids.add(_dayKey(now.subtract(Duration(days: i))));
    }
    return ids;
  }

  /// 쓰기: hour(Today) + day(Week용) + month + year
  List<String> _writeDocIds(DateTime now) {
    return [_hourKey(now), _dayKey(now), _monthKey(now), _yearKey(now)];
  }

  /// 클릭 시: hour + day + month + year 문서에 +1
  Future<void> incrementClick(String dramaId) async {
    if (dramaId.isEmpty) return;
    final now = DateTime.now();
    for (final docId in _writeDocIds(now)) {
      try {
        final ref = _firestore.collection(_collection).doc(docId);
        await ref.update({'clicks.$dramaId': FieldValue.increment(1)});
      } catch (e) {
        if (e.toString().contains('NOT_FOUND') || e.toString().contains('no document')) {
          final ref = _firestore.collection(_collection).doc(docId);
          await ref.set({'clicks': {dramaId: 1}, 'searches': {}}, SetOptions(merge: true));
        } else {
          debugPrint('DramaSearchStatsService incrementClick ERROR: $e');
        }
      }
    }
    debugPrint('DramaSearchStatsService incrementClick: $dramaId');
  }

  /// 검색 제출 시: 결과 상위 드라마 id들에 대해 hour + day + month + year에 검색 +1
  Future<void> incrementSearch(List<String> dramaIds) async {
    if (dramaIds.isEmpty) return;
    final now = DateTime.now();
    final ids = dramaIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    for (final docId in _writeDocIds(now)) {
      try {
        final ref = _firestore.collection(_collection).doc(docId);
        final updates = <String, dynamic>{};
        for (final id in ids) {
          updates['searches.$id'] = FieldValue.increment(1);
        }
        await ref.update(updates);
      } catch (e) {
        if (e.toString().contains('NOT_FOUND') || e.toString().contains('no document')) {
          final ref = _firestore.collection(_collection).doc(docId);
          final searches = <String, dynamic>{};
          for (final id in ids) {
            searches[id] = 1;
          }
          await ref.set({'clicks': {}, 'searches': searches}, SetOptions(merge: true));
        } else {
          debugPrint('DramaSearchStatsService incrementSearch ERROR: $e');
        }
      }
    }
    debugPrint('DramaSearchStatsService incrementSearch: ${ids.length} dramas');
  }

  /// 한 문서에서 클릭/검색 맵 파싱 후 scores에 합산
  void _mergeDocInto(Map<String, int> clicks, Map<String, int> searches, Map<String, dynamic>? data) {
    if (data == null) return;
    final c = data['clicks'] is Map ? data['clicks'] as Map<String, dynamic> : <String, dynamic>{};
    final s = data['searches'] is Map ? data['searches'] as Map<String, dynamic> : <String, dynamic>{};
    for (final e in c.entries) {
      if (e.value is num) clicks[e.key] = (clicks[e.key] ?? 0) + (e.value as num).toInt();
    }
    for (final e in s.entries) {
      if (e.value is num) searches[e.key] = (searches[e.key] ?? 0) + (e.value as num).toInt();
    }
  }

  /// 복합 점수 = 검색*1 + 클릭*2. Today=지난 24시간 병합, 나머지=해당 1문서.
  Future<List<String>> getTopDramaIds(
    SearchStatsPeriod period,
    int limit, {
    bool fromServer = false,
  }) async {
    try {
      final now = DateTime.now();
      final getOpt = fromServer ? const GetOptions(source: Source.server) : null;

      if (period == SearchStatsPeriod.day) {
        final ids = _last24HourDocIds(now);
        final clicks = <String, int>{};
        final searches = <String, int>{};
        for (final id in ids) {
          final snap = getOpt != null
              ? await _firestore.collection(_collection).doc(id).get(getOpt)
              : await _firestore.collection(_collection).doc(id).get();
          _mergeDocInto(clicks, searches, snap.data());
        }
        final allIds = <String>{...clicks.keys, ...searches.keys};
        final scores = <String, int>{};
        for (final id in allIds) {
          scores[id] = (searches[id] ?? 0) * 1 + (clicks[id] ?? 0) * 2;
        }
        final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return sorted.take(limit).map((e) => e.key).toList();
      }

      if (period == SearchStatsPeriod.week) {
        final ids = _last7DayDocIds(now);
        final clicks = <String, int>{};
        final searches = <String, int>{};
        for (final id in ids) {
          final snap = getOpt != null
              ? await _firestore.collection(_collection).doc(id).get(getOpt)
              : await _firestore.collection(_collection).doc(id).get();
          _mergeDocInto(clicks, searches, snap.data());
        }
        final allIds = <String>{...clicks.keys, ...searches.keys};
        final scores = <String, int>{};
        for (final id in allIds) {
          scores[id] = (searches[id] ?? 0) * 1 + (clicks[id] ?? 0) * 2;
        }
        final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return sorted.take(limit).map((e) => e.key).toList();
      }

      // month / year: 1문서
      final docId = period == SearchStatsPeriod.month ? _monthKey(now) : _yearKey(now);
      final ref = _firestore.collection(_collection).doc(docId);
      final snap = getOpt != null ? await ref.get(getOpt) : await ref.get();
      final data = snap.data();
      if (data == null) return [];

      final clicks = data['clicks'] is Map ? data['clicks'] as Map<String, dynamic> : <String, dynamic>{};
      final searches = data['searches'] is Map ? data['searches'] as Map<String, dynamic> : <String, dynamic>{};
      final allIds = <String>{...clicks.keys, ...searches.keys};
      final scores = <String, int>{};
      for (final id in allIds) {
        final c = (clicks[id] is num) ? (clicks[id] as num).toInt() : 0;
        final s = (searches[id] is num) ? (searches[id] as num).toInt() : 0;
        scores[id] = s * 1 + c * 2;
      }
      final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(limit).map((e) => e.key).toList();
    } catch (e) {
      debugPrint('DramaSearchStatsService getTopDramaIds ERROR: $e');
      return [];
    }
  }
}
