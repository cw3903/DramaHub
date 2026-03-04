import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

/// 회차별 별점 저장 (Firestore). 로그인 사용자만 영구 저장.
class EpisodeRatingService {
  EpisodeRatingService._();

  static final EpisodeRatingService instance = EpisodeRatingService._();

  static const _collection = 'episode_ratings';
  static const _reviewsCollection = 'episode_reviews';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// dramaId -> (episodeNumber -> 내 별점). 로드 후 UI 갱신용.
  final Map<String, ValueNotifier<Map<int, double>>> _notifiers = {};
  /// dramaId -> (episodeNumber -> 회원들 평균 별점). 표시용.
  final Map<String, ValueNotifier<Map<int, double>>> _averageNotifiers = {};
  /// dramaId -> (episodeNumber -> 참여 인원 수). 표시용.
  final Map<String, ValueNotifier<Map<int, int>>> _countNotifiers = {};

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  /// 해당 드라마의 내 회차별 별점 갱신용. 없으면 생성 후 반환.
  ValueNotifier<Map<int, double>> getNotifierForDrama(String dramaId) {
    _notifiers[dramaId] ??= ValueNotifier<Map<int, double>>({});
    return _notifiers[dramaId]!;
  }

  /// 해당 드라마의 회차별 평균 별점 갱신용. 없으면 생성 후 반환.
  ValueNotifier<Map<int, double>> getAverageNotifierForDrama(String dramaId) {
    _averageNotifiers[dramaId] ??= ValueNotifier<Map<int, double>>({});
    return _averageNotifiers[dramaId]!;
  }

  /// 해당 드라마의 회차별 참여 인원 수(평점 준 사람 수). 없으면 생성 후 반환.
  ValueNotifier<Map<int, int>> getCountNotifierForDrama(String dramaId) {
    _countNotifiers[dramaId] ??= ValueNotifier<Map<int, int>>({});
    return _countNotifiers[dramaId]!;
  }

  /// 해당 드라마의 내 회차별 별점 로드. 로그인 시 Firestore, 비로그인 시 빈 맵.
  Future<Map<int, double>> getMyRatingsForDrama(String dramaId) async {
    final uid = _uid;
    if (dramaId.isEmpty) return {};
    if (uid == null) {
      _notifiers[dramaId] ??= ValueNotifier<Map<int, double>>({});
      return {};
    }
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('uid', isEqualTo: uid)
          .where('dramaId', isEqualTo: dramaId)
          .get();
      final map = <int, double>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ep = data['episodeNumber'] as int?;
        final r = (data['rating'] as num?)?.toDouble();
        if (ep != null && r != null) map[ep] = r;
      }
      _notifiers[dramaId] ??= ValueNotifier<Map<int, double>>({});
      _notifiers[dramaId]!.value = Map.from(map);
      return map;
    } catch (e) {
      debugPrint('EpisodeRatingService getMyRatingsForDrama: $e');
      _notifiers[dramaId] ??= ValueNotifier<Map<int, double>>({});
      return _notifiers[dramaId]!.value;
    }
  }

  /// 회차 별점 저장 (0.5 ~ 5.0). 로그인 시에만 Firestore에 저장. 저장 후 해당 드라마 평균 갱신.
  Future<void> setRating({
    required String dramaId,
    required int episodeNumber,
    required double rating,
  }) async {
    final uid = _uid;
    final clamped = rating.clamp(0.5, 5.0);
    _notifiers[dramaId] ??= ValueNotifier<Map<int, double>>({});
    final prev = Map<int, double>.from(_notifiers[dramaId]!.value);
    prev[episodeNumber] = clamped;
    _notifiers[dramaId]!.value = prev;

    if (uid != null && dramaId.isNotEmpty) {
      try {
        final docId = '${uid}_${dramaId}_$episodeNumber';
        await _firestore.collection(_collection).doc(docId).set({
          'uid': uid,
          'dramaId': dramaId,
          'episodeNumber': episodeNumber,
          'rating': clamped,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await loadEpisodeAverageRatings(dramaId);
      } catch (e) {
        debugPrint('EpisodeRatingService setRating: $e');
      }
    }
  }

  /// 해당 드라마 회차별 평균 별점 로드.
  /// episode_ratings + episode_reviews를 각각 독립적으로 쿼리해 합산.
  /// 한 쪽 컬렉션에 오류가 나도 다른 쪽 데이터로 평균 계산.
  Future<Map<int, double>> loadEpisodeAverageRatings(String dramaId) async {
    if (dramaId.isEmpty) return {};

    final sumByEp = <int, double>{};
    final countByEp = <int, int>{};
    final uidSetByEp = <int, Set<String>>{};

    void addRating(int ep, String uid, double r) {
      if (ep <= 0 || r <= 0) return;
      sumByEp[ep] = (sumByEp[ep] ?? 0) + r;
      countByEp[ep] = (countByEp[ep] ?? 0) + 1;
      uidSetByEp[ep] ??= {};
      if (uid.isNotEmpty) uidSetByEp[ep]!.add(uid);
    }

    // episode_ratings 컬렉션
    try {
      final ratingsSnap = await _firestore
          .collection(_collection)
          .where('dramaId', isEqualTo: dramaId)
          .get();
      for (final doc in ratingsSnap.docs) {
        final data = doc.data();
        final epNum = data['episodeNumber'];
        final ep = epNum is int ? epNum : (epNum is num ? epNum.toInt() : null);
        final r = (data['rating'] as num?)?.toDouble();
        final u = data['uid'] as String? ?? '';
        if (ep != null && r != null && r > 0) addRating(ep, u, r);
      }
    } catch (e) {
      debugPrint('EpisodeRatingService episode_ratings query error: $e');
    }

    // episode_reviews 컬렉션 (rating 필드)
    try {
      final reviewsSnap = await _firestore
          .collection(_reviewsCollection)
          .where('dramaId', isEqualTo: dramaId)
          .get();
      for (final doc in reviewsSnap.docs) {
        final data = doc.data();
        final epNum = data['episodeNumber'];
        final ep = epNum is int ? epNum : (epNum is num ? epNum.toInt() : null);
        final r = (data['rating'] as num?)?.toDouble();
        final u = data['uid'] as String? ?? '';
        if (ep != null && r != null && r > 0) addRating(ep, u, r);
      }
    } catch (e) {
      debugPrint('EpisodeRatingService episode_reviews query error: $e');
    }

    if (sumByEp.isEmpty) {
      return getAverageNotifierForDrama(dramaId).value;
    }

    final avg = <int, double>{};
    for (final e in sumByEp.keys) {
      final n = countByEp[e] ?? 0;
      if (n > 0) avg[e] = sumByEp[e]! / n;
    }
    final mergedAvg = Map<int, double>.from(getAverageNotifierForDrama(dramaId).value)..addAll(avg);
    getAverageNotifierForDrama(dramaId).value = mergedAvg;

    final participantCount = <int, int>{};
    for (final e in uidSetByEp.keys) {
      participantCount[e] = uidSetByEp[e]!.length;
    }
    final mergedCount = Map<int, int>.from(getCountNotifierForDrama(dramaId).value)..addAll(participantCount);
    getCountNotifierForDrama(dramaId).value = mergedCount;

    return mergedAvg;
  }

  /// 외부(EpisodeReviewService 등)에서 로컬 리뷰 목록으로 평균을 직접 갱신할 때 사용.
  void updateAverageForEpisode(String dramaId, int episodeNumber, double? avg) {
    final notifier = getAverageNotifierForDrama(dramaId);
    final current = Map<int, double>.from(notifier.value);
    if (avg == null || avg <= 0) {
      current.remove(episodeNumber);
    } else {
      current[episodeNumber] = avg;
    }
    notifier.value = current;
  }

  /// 특정 회차 내 별점만 반환 (캐시 기준). 없으면 null.
  double? getMyRating(String dramaId, int episodeNumber) {
    return _notifiers[dramaId]?.value[episodeNumber];
  }
}
