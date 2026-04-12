import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import '../utils/format_utils.dart';
import 'episode_rating_service.dart';
import 'user_profile_service.dart';

/// 회차별 리뷰(댓글) 한 건
class EpisodeReviewItem {
  const EpisodeReviewItem({
    required this.id,
    required this.dramaId,
    required this.episodeNumber,
    required this.uid,
    required this.authorName,
    required this.comment,
    required this.createdAt,
    this.rating,
    this.authorPhotoUrl,
    this.authorAvatarColorIndex,
  });

  final String id;
  final String dramaId;
  final int episodeNumber;
  final String uid;
  final String authorName;
  final String comment;
  final DateTime createdAt;
  final double? rating;
  final String? authorPhotoUrl;
  final int? authorAvatarColorIndex;

  String get timeAgo => formatTimeAgo(createdAt);
}

/// 회차별 리뷰/댓글 (Firestore). 로그인 사용자만 작성·저장.
class EpisodeReviewService {
  EpisodeReviewService._();

  static final EpisodeReviewService instance = EpisodeReviewService._();

  static const _collection = 'episode_reviews';

  /// [add] 중복 시 UI에서 `strings.get(duplicateReviewMessageKey)` 로 표시
  static const duplicateReviewMessageKey = 'episodeReviewAlreadyExists';

  /// Firestore 저장 실패 시
  static const saveFailedMessageKey = 'episodeReviewSaveFailed';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// key: '${dramaId}_$episodeNumber' -> 리뷰 목록 갱신용
  final Map<String, ValueNotifier<List<EpisodeReviewItem>>> _notifiers = {};

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  ValueNotifier<List<EpisodeReviewItem>> getNotifierForEpisode(String dramaId, int episodeNumber) {
    final key = '${dramaId}_$episodeNumber';
    _notifiers[key] ??= ValueNotifier<List<EpisodeReviewItem>>([]);
    return _notifiers[key]!;
  }

  /// 특정 회차의 리뷰 목록으로 평균·참여 인원을 로컬에서 계산해 EpisodeRatingService notifier에 반영.
  void _syncAverage(String dramaId, int episodeNumber, List<EpisodeReviewItem> items) {
    final rated = items.where((r) => r.rating != null && r.rating! > 0).toList();
    final avgNotifier = EpisodeRatingService.instance.getAverageNotifierForDrama(dramaId);
    final countNotifier = EpisodeRatingService.instance.getCountNotifierForDrama(dramaId);
    final currentAvg = Map<int, double>.from(avgNotifier.value);
    final currentCount = Map<int, int>.from(countNotifier.value);
    if (rated.isEmpty) {
      currentAvg.remove(episodeNumber);
      currentCount.remove(episodeNumber);
    } else {
      final sum = rated.fold(0.0, (acc, r) => acc + r.rating!);
      currentAvg[episodeNumber] = sum / rated.length;
      // 참여 인원 = 별점을 준 서로 다른 회원 수(uid 기준)
      final participantCount = rated.map((r) => r.uid).where((u) => u.isNotEmpty).toSet().length;
      currentCount[episodeNumber] = participantCount;
    }
    avgNotifier.value = currentAvg;
    countNotifier.value = currentCount;
  }

  /// 해당 회차 리뷰 목록 로드 (Firestore). `createdAt` 오름차순(오래된 것이 위).
  Future<List<EpisodeReviewItem>> loadReviews(String dramaId, int episodeNumber) async {
    if (dramaId.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('dramaId', isEqualTo: dramaId)
          .where('episodeNumber', isEqualTo: episodeNumber)
          .orderBy('createdAt', descending: false)
          .get();
      final list = snapshot.docs
          .map((d) => _itemFromFirestore(d.id, d.data()))
          .whereType<EpisodeReviewItem>()
          .toList();
      getNotifierForEpisode(dramaId, episodeNumber).value = list;
      _syncAverage(dramaId, episodeNumber, list);
      return list;
    } catch (e) {
      debugPrint('EpisodeReviewService loadReviews: $e');
      try {
        final snapshot = await _firestore
            .collection(_collection)
            .where('dramaId', isEqualTo: dramaId)
            .get();
        var list = snapshot.docs
            .map((d) => _itemFromFirestore(d.id, d.data()))
            .whereType<EpisodeReviewItem>()
            .where((e) => e.episodeNumber == episodeNumber)
            .toList();
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        getNotifierForEpisode(dramaId, episodeNumber).value = list;
        _syncAverage(dramaId, episodeNumber, list);
        return list;
      } catch (e2) {
        debugPrint('EpisodeReviewService loadReviews fallback: $e2');
        final existing = getNotifierForEpisode(dramaId, episodeNumber).value;
        _syncAverage(dramaId, episodeNumber, existing);
        return existing;
      }
    }
  }

  static EpisodeReviewItem? _itemFromFirestore(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    final at = createdAt is Timestamp
        ? createdAt.toDate()
        : DateTime.fromMillisecondsSinceEpoch((createdAt as num?)?.toInt() ?? 0, isUtc: false);
    final colorIdx = data['authorAvatarColorIndex'];
    return EpisodeReviewItem(
      id: id,
      dramaId: data['dramaId'] as String? ?? '',
      episodeNumber: data['episodeNumber'] as int? ?? 0,
      uid: data['uid'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '회원',
      comment: data['comment'] as String? ?? '',
      createdAt: at,
      rating: (data['rating'] as num?)?.toDouble(),
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      authorAvatarColorIndex: colorIdx is num ? colorIdx.toInt() : null,
    );
  }

  /// 새 리뷰 등록. 문서 id는 자동 생성, `uid`는 필드로만 저장.
  /// 같은 회차에 동일 `uid` 문서가 이미 있으면 [duplicateReviewMessageKey] 반환 (덮어쓰기 없음).
  /// 성공 시 null 반환.
  Future<String?> add({
    required String dramaId,
    required int episodeNumber,
    required String comment,
    double? rating,
  }) async {
    if (dramaId.isEmpty || comment.trim().isEmpty) return null;
    final uid = _uid;
    final notifier = getNotifierForEpisode(dramaId, episodeNumber);
    final trimmed = comment.trim();

    if (uid != null) {
      try {
        final dup = await _firestore
            .collection(_collection)
            .where('dramaId', isEqualTo: dramaId)
            .where('episodeNumber', isEqualTo: episodeNumber)
            .where('uid', isEqualTo: uid)
            .limit(1)
            .get();
        if (dup.docs.isNotEmpty) {
          return duplicateReviewMessageKey;
        }
      } catch (e) {
        debugPrint('EpisodeReviewService add duplicate check: $e');
        // 인덱스 미배포 등으로 쿼리 실패 시에는 저장 단계까지 진행
      }
    }

    final authorName = uid != null
        ? await UserProfileService.instance.getAuthorBaseName()
        : (UserProfileService.instance.nicknameNotifier.value?.trim() ?? '회원');
    final authorPhotoUrl = UserProfileService.instance.profileImageUrlNotifier.value;
    final authorAvatarColorIndex = UserProfileService.instance.avatarColorNotifier.value;
    final now = DateTime.now();

    if (uid == null) {
      final docId = 'local_${dramaId}_${episodeNumber}_${now.millisecondsSinceEpoch}';
      final newItem = EpisodeReviewItem(
        id: docId,
        dramaId: dramaId,
        episodeNumber: episodeNumber,
        uid: '',
        authorName: authorName,
        comment: trimmed,
        createdAt: now,
        rating: rating,
        authorPhotoUrl: authorPhotoUrl,
        authorAvatarColorIndex: authorAvatarColorIndex,
      );
      notifier.value = [...notifier.value, newItem];
      _syncAverage(dramaId, episodeNumber, notifier.value);
      return null;
    }

    try {
      await _firestore.collection(_collection).add({
        'uid': uid,
        'dramaId': dramaId,
        'episodeNumber': episodeNumber,
        'authorName': authorName,
        'comment': trimmed,
        'rating': rating,
        'createdAt': FieldValue.serverTimestamp(),
        'authorPhotoUrl': authorPhotoUrl,
        'authorAvatarColorIndex': authorAvatarColorIndex,
      });
      await loadReviews(dramaId, episodeNumber);
      if (rating != null && rating > 0) {
        await EpisodeRatingService.instance.setRating(
          dramaId: dramaId,
          episodeNumber: episodeNumber,
          rating: rating.toDouble(),
        );
        await EpisodeRatingService.instance.loadEpisodeAverageRatings(dramaId);
      }
      return null;
    } catch (e) {
      debugPrint('EpisodeReviewService add: $e');
      return saveFailedMessageKey;
    }
  }

  /// 특정 댓글 수정 (id로 문서 지정)
  Future<void> update({
    required String id,
    required String dramaId,
    required int episodeNumber,
    required String comment,
    double? rating,
  }) async {
    if (id.isEmpty || dramaId.isEmpty || comment.trim().isEmpty) return;
    final uid = _uid;
    final authorName = uid != null
        ? await UserProfileService.instance.getAuthorBaseName()
        : (UserProfileService.instance.nicknameNotifier.value?.trim() ?? '회원');
    final authorPhotoUrl = UserProfileService.instance.profileImageUrlNotifier.value;
    final authorAvatarColorIndex = UserProfileService.instance.avatarColorNotifier.value;
    final trimmed = comment.trim();
    if (uid != null) {
      try {
        await _firestore.collection(_collection).doc(id).set({
          'uid': uid,
          'dramaId': dramaId,
          'episodeNumber': episodeNumber,
          'authorName': authorName,
          'comment': trimmed,
          'rating': rating,
          'authorPhotoUrl': authorPhotoUrl,
          'authorAvatarColorIndex': authorAvatarColorIndex,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await loadReviews(dramaId, episodeNumber);
        if (rating != null && rating > 0) {
          await EpisodeRatingService.instance.setRating(
            dramaId: dramaId,
            episodeNumber: episodeNumber,
            rating: rating.toDouble(),
          );
          await EpisodeRatingService.instance.loadEpisodeAverageRatings(dramaId);
        }
      } catch (e) {
        debugPrint('EpisodeReviewService update: $e');
      }
    }
  }

  /// 댓글 삭제 (문서 id로 삭제). 삭제 후 회차 평균 별점 갱신.
  Future<void> deleteById(String dramaId, int episodeNumber, String reviewId) async {
    final notifier = getNotifierForEpisode(dramaId, episodeNumber);
    notifier.value = notifier.value.where((e) => e.id != reviewId).toList();
    _syncAverage(dramaId, episodeNumber, notifier.value);
    try {
      await _firestore.collection(_collection).doc(reviewId).delete();
    } catch (e) {
      debugPrint('EpisodeReviewService deleteById: $e');
    }
  }
}
