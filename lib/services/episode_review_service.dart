import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../utils/format_utils.dart';
import 'auth_service.dart';
import 'episode_rating_service.dart';
import 'locale_service.dart';
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
    this.appLocale,
    this.likedUids = const [],
    this.replyCount = 0,
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

  /// Firestore `country` (us/kr/jp/cn). null이면 레거시.
  final String? appLocale;

  /// 좋아요 누른 uid 목록 (`arrayUnion` / `arrayRemove`).
  final List<String> likedUids;

  /// `thread` 서브컬렉션 댓글·대댓글 개수 (문서 필드 `replyCount`).
  final int replyCount;

  String get timeAgo => formatTimeAgo(createdAt, LocaleService.instance.locale);

  int get likeCount => likedUids.length;

  bool likedByUid(String? uid) =>
      uid != null && uid.isNotEmpty && likedUids.contains(uid);

  EpisodeReviewItem copyWith({
    List<String>? likedUids,
    int? replyCount,
  }) {
    return EpisodeReviewItem(
      id: id,
      dramaId: dramaId,
      episodeNumber: episodeNumber,
      uid: uid,
      authorName: authorName,
      comment: comment,
      createdAt: createdAt,
      rating: rating,
      authorPhotoUrl: authorPhotoUrl,
      authorAvatarColorIndex: authorAvatarColorIndex,
      appLocale: appLocale,
      likedUids: likedUids ?? this.likedUids,
      replyCount: replyCount ?? this.replyCount,
    );
  }
}

/// 에피소드 리뷰 아래 스레드 댓글·대댓글 (`episode_reviews/{id}/thread`).
class EpisodeReviewThreadItem {
  const EpisodeReviewThreadItem({
    required this.id,
    required this.uid,
    required this.authorName,
    required this.comment,
    required this.createdAt,
    this.parentCommentId,
  });

  final String id;
  final String uid;
  final String authorName;
  final String comment;
  final DateTime createdAt;
  /// null이면 리뷰에 대한 직접 댓글, 있으면 해당 댓글의 대댓글.
  final String? parentCommentId;

  String get timeAgo => formatTimeAgo(createdAt, LocaleService.instance.locale);
}

/// 회차별 리뷰/댓글 (Firestore). 로그인 사용자만 작성·저장.
class EpisodeReviewService {
  EpisodeReviewService._();

  static final EpisodeReviewService instance = EpisodeReviewService._();

  static const _collection = 'episode_reviews';
  static const _threadSubcollection = 'thread';

  /// [add] 중복 시 UI에서 `strings.get(duplicateReviewMessageKey)` 로 표시
  static const duplicateReviewMessageKey = 'episodeReviewAlreadyExists';

  /// Firestore 저장 실패 시
  static const saveFailedMessageKey = 'episodeReviewSaveFailed';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// key: '${dramaId}_$episodeNumber' -> 리뷰 목록 갱신용
  final Map<String, ValueNotifier<List<EpisodeReviewItem>>> _notifiers = {};

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  static bool _docVisibleInCurrentLocale(Map<String, dynamic> data) =>
      Post.userScopedFirestoreDocVisibleForLocale(
        data,
        LocaleService.instance.locale,
      );

  /// 해당 드라마 회차 캐시만 비움 (언어 전환 등).
  void clearNotifiersForDrama(String dramaId) {
    final id = dramaId.trim();
    if (id.isEmpty) return;
    final prefix = '${id}_';
    final keys = _notifiers.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _notifiers.remove(k);
    }
  }

  void clearAllEpisodeNotifiers() {
    for (final n in _notifiers.values) {
      n.value = [];
    }
    _notifiers.clear();
  }

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
          .where((d) => _docVisibleInCurrentLocale(d.data()))
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
            .where((d) => _docVisibleInCurrentLocale(d.data()))
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

  static DateTime _readTimestamp(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: false);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: false);
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: false);
  }

  static EpisodeReviewItem? _itemFromFirestore(String id, Map<String, dynamic> data) {
    var at = _readTimestamp(data, 'createdAt');
    if (at.millisecondsSinceEpoch == 0) {
      at = _readTimestamp(data, 'updatedAt');
    }
    final colorIdx = data['authorAvatarColorIndex'];
    final loc = (data['country'] as String?)?.trim();
    final likedRaw = data['likedUids'];
    final likedUids = <String>[];
    if (likedRaw is List) {
      for (final e in likedRaw) {
        if (e is String && e.trim().isNotEmpty) likedUids.add(e.trim());
      }
    }
    final rc = data['replyCount'];
    final replyCount = rc is num ? rc.toInt() : int.tryParse('$rc') ?? 0;
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
      appLocale: loc != null && loc.isNotEmpty ? loc : null,
      likedUids: likedUids,
      replyCount: replyCount,
    );
  }

  static String _threadStrField(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  static EpisodeReviewThreadItem? _threadItemFromDoc(String id, Map<String, dynamic> data) {
    var at = _readTimestamp(data, 'createdAt');
    if (at.millisecondsSinceEpoch == 0) {
      at = _readTimestamp(data, 'updatedAt');
    }
    if (at.millisecondsSinceEpoch == 0) {
      // `serverTimestamp()` 확정 전 로컬 스냅샷에서는 `createdAt`이 비어 0으로 올 수 있음.
      // 이때 null을 반환하면 방금 쓴 댓글이 목록에서 빠져 "저장 안 됨"처럼 보인다.
      at = DateTime.now();
    }
    final parent = data['parentCommentId'];
    String? parentId;
    if (parent is DocumentReference) {
      final t = parent.id.trim();
      if (t.isNotEmpty) parentId = t;
    } else if (parent is String) {
      final t = parent.trim();
      if (t.isNotEmpty) parentId = t;
    } else if (parent != null) {
      final t = parent.toString().trim();
      if (t.isNotEmpty) parentId = t;
    }
    return EpisodeReviewThreadItem(
      id: id,
      uid: _threadStrField(data, 'uid'),
      authorName: _threadStrField(data, 'authorName'),
      comment: _threadStrField(data, 'comment'),
      createdAt: at,
      parentCommentId: parentId,
    );
  }

  static List<EpisodeReviewThreadItem> _parseThreadSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final items = <EpisodeReviewThreadItem>[];
    for (final d in snap.docs) {
      try {
        final item = _threadItemFromDoc(d.id, d.data());
        if (item != null) items.add(item);
      } catch (e, st) {
        debugPrint('EpisodeReviewService thread doc ${d.id}: $e\n$st');
      }
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  /// 리뷰 스레드 실시간 스트림 (작성순).
  ///
  /// Firestore `snapshots()` 오류·문서 파싱 예외는 [StreamBuilder.hasError]로 흘러가지 않게
  /// 빈 목록으로 삼키고 로그만 남긴다(기존 UI가 `episodeReviewSaveFailed`로 오해 표시).
  ///
  /// [StreamController]로 감싸 `onCancel`에서 `close()`하면 구독 해제와 트리 비활성화가
  /// 겹칠 때 `InheritedElement._dependents.isEmpty` assert가 날 수 있어, 변환기만 쓴다.
  Stream<List<EpisodeReviewThreadItem>> watchThread(String reviewId) {
    final rid = reviewId.trim();
    if (rid.isEmpty) return const Stream.empty();
    return _firestore
        .collection(_collection)
        .doc(rid)
        .collection(_threadSubcollection)
        .snapshots()
        .transform<List<EpisodeReviewThreadItem>>(
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              List<EpisodeReviewThreadItem>>.fromHandlers(
            handleData: (snap, sink) {
              try {
                sink.add(_parseThreadSnapshot(snap));
              } catch (e, st) {
                debugPrint('EpisodeReviewService watchThread parse: $e\n$st');
                sink.add(const []);
              }
            },
            handleError: (Object e, StackTrace st, sink) {
              debugPrint('EpisodeReviewService watchThread listen: $e\n$st');
              sink.add(const []);
            },
          ),
        );
  }

  /// 스레드에 댓글·대댓글 추가. [parentCommentId]가 있으면 해당 댓글에 대한 답글.
  ///
  /// 반환 `(에러 키, null)` 실패, `(null, 추가된 항목)` 성공, `(null, null)`은 본문 비어 호출용.
  /// 스레드는 [FieldValue.serverTimestamp] 대신 **클라이언트 [Timestamp]**를 쓴다.
  /// `serverTimestamp` + `parentCommentId` 조합에서 규칙/캐시·파싱 타이밍 이슈로 답글만
  /// 실패하거나 목록에 안 보이는 사례가 있어 피드 답글과 동일하게 즉시 읽을 수 있게 한다.
  Future<(String?, EpisodeReviewThreadItem?)> addThreadComment({
    required String reviewId,
    required String dramaId,
    required int episodeNumber,
    required String text,
    String? parentCommentId,
  }) async {
    final uid = _uid;
    if (uid == null) return ('loginRequired', null);
    final trimmed = text.trim();
    if (trimmed.isEmpty) return (null, null);
    final rid = reviewId.trim();
    if (rid.isEmpty) return (saveFailedMessageKey, null);
    if (rid.startsWith('local_')) return (saveFailedMessageKey, null);

    final loc = Post.normalizeFeedCountry(LocaleService.instance.locale);
    final authorName = await UserProfileService.instance.getAuthorBaseName();
    final rawPhoto = UserProfileService.instance.profileImageUrlNotifier.value?.trim();
    final photoUrl =
        (rawPhoto != null && rawPhoto.startsWith('http')) ? rawPhoto : null;

    String? parent = parentCommentId?.trim();
    if (parent != null && parent.isEmpty) parent = null;
    // thread/{parentId} 가 아니라 에피 리뷰 문서 id와 동일하면 exists 규칙 등에서 답글만 거절될 수 있음.
    if (parent != null && parent == rid) {
      debugPrint(
        'EpisodeReviewService addThreadComment: parentCommentId equals review doc id, ignored',
      );
      parent = null;
    }

    final createdAtLocal = DateTime.now();
    final createdAtTs = Timestamp.fromDate(createdAtLocal.toUtc());

    final payload = <String, dynamic>{};
    if (parent != null) {
      payload['parentCommentId'] = parent;
    }
    payload.addAll({
      'uid': uid,
      'authorName': authorName,
      'comment': trimmed,
      'createdAt': createdAtTs,
      'country': loc,
    });
    if (photoUrl != null) {
      payload['authorPhotoUrl'] = photoUrl;
    }

    late final String newDocId;
    try {
      final ref = await _firestore
          .collection(_collection)
          .doc(rid)
          .collection(_threadSubcollection)
          .add(payload);
      newDocId = ref.id;
    } catch (e, st) {
      if (e is FirebaseException) {
        debugPrint(
          'EpisodeReviewService addThreadComment thread add: '
          '${e.code} ${e.message}',
        );
      }
      debugPrint('EpisodeReviewService addThreadComment thread add: $e\n$st');
      return (saveFailedMessageKey, null);
    }

    try {
      await _firestore.collection(_collection).doc(rid).update({
        'replyCount': FieldValue.increment(1),
      });
    } catch (e, st) {
      debugPrint(
        'EpisodeReviewService addThreadComment replyCount update (non-fatal): $e\n$st',
      );
    }

    await loadReviews(dramaId, episodeNumber);

    final added = EpisodeReviewThreadItem(
      id: newDocId,
      uid: uid,
      authorName: authorName,
      comment: trimmed,
      createdAt: createdAtLocal,
      parentCommentId: parent,
    );
    return (null, added);
  }

  /// 좋아요 토글 (로그인 필요).
  /// 목록은 즉시 낙관 반영 후 Firestore만 갱신한다. 전체 [loadReviews] 호출 없음(지연·병목 제거).
  Future<String?> toggleEpisodeReviewLike({
    required String reviewId,
    required String dramaId,
    required int episodeNumber,
  }) async {
    final uid = _uid;
    if (uid == null) return 'loginRequired';
    if (reviewId.startsWith('local_')) return null;
    final notifier = getNotifierForEpisode(dramaId, episodeNumber);
    final before = List<EpisodeReviewItem>.from(notifier.value);
    final idx = before.indexWhere((r) => r.id == reviewId);
    if (idx < 0) {
      return _toggleEpisodeReviewLikeReloadPath(reviewId, dramaId, episodeNumber);
    }
    final item = before[idx];
    final liked = item.likedByUid(uid);
    final nextLikes = List<String>.from(item.likedUids);
    if (liked) {
      nextLikes.removeWhere((x) => x == uid);
    } else if (!nextLikes.contains(uid)) {
      nextLikes.add(uid);
    }
    final optimistic = List<EpisodeReviewItem>.from(before);
    optimistic[idx] = item.copyWith(likedUids: nextLikes);
    notifier.value = optimistic;

    try {
      final ref = _firestore.collection(_collection).doc(reviewId);
      if (liked) {
        await ref.update({'likedUids': FieldValue.arrayRemove([uid])});
      } else {
        await ref.update({'likedUids': FieldValue.arrayUnion([uid])});
      }
      return null;
    } catch (e) {
      debugPrint('EpisodeReviewService toggleEpisodeReviewLike: $e');
      notifier.value = before;
      return saveFailedMessageKey;
    }
  }

  /// 캐시에 없을 때만: 기존처럼 읽기·쓰기 후 전체 로드.
  Future<String?> _toggleEpisodeReviewLikeReloadPath(
    String reviewId,
    String dramaId,
    int episodeNumber,
  ) async {
    final uid = _uid;
    if (uid == null) return 'loginRequired';
    try {
      final ref = _firestore.collection(_collection).doc(reviewId);
      final snap = await ref.get();
      if (!snap.exists) return saveFailedMessageKey;
      final data = snap.data() ?? {};
      final likes = List<String>.from(
        (data['likedUids'] as List?)?.map((e) => e.toString()) ?? [],
      );
      final liked = likes.contains(uid);
      if (liked) {
        await ref.update({'likedUids': FieldValue.arrayRemove([uid])});
      } else {
        await ref.update({'likedUids': FieldValue.arrayUnion([uid])});
      }
      await loadReviews(dramaId, episodeNumber);
      return null;
    } catch (e) {
      debugPrint('EpisodeReviewService _toggleEpisodeReviewLikeReloadPath: $e');
      return saveFailedMessageKey;
    }
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
    if (uid == null) return 'loginRequired';
    final trimmed = comment.trim();
    final loc = LocaleService.instance.locale;

    try {
      final dup = await _firestore
          .collection(_collection)
          .where('dramaId', isEqualTo: dramaId)
          .where('episodeNumber', isEqualTo: episodeNumber)
          .get();
      for (final d in dup.docs) {
        if ((d.data()['uid'] as String?) != uid) continue;
        if (_docVisibleInCurrentLocale(d.data())) {
          return duplicateReviewMessageKey;
        }
      }
    } catch (e) {
      debugPrint('EpisodeReviewService add duplicate check: $e');
    }

    final authorName = await UserProfileService.instance.getAuthorBaseName();
    final authorPhotoUrl = UserProfileService.instance.profileImageUrlNotifier.value;
    final authorAvatarColorIndex = UserProfileService.instance.avatarColorNotifier.value;

    try {
      await _firestore.collection(_collection).add({
        'uid': uid,
        'dramaId': dramaId,
        'episodeNumber': episodeNumber,
        'authorName': authorName,
        'comment': trimmed,
        'rating': rating,
        'country': loc,
        'createdAt': FieldValue.serverTimestamp(),
        'authorPhotoUrl': authorPhotoUrl,
        'authorAvatarColorIndex': authorAvatarColorIndex,
        'likedUids': <String>[],
        'replyCount': 0,
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
        final snap = await _firestore.collection(_collection).doc(id).get();
        final prev = snap.data();
        final prevCountry = (prev?['country'] as String?)?.trim();
        final countryToWrite =
            (prevCountry != null && prevCountry.isNotEmpty)
                ? prevCountry
                : LocaleService.instance.locale;
        await _firestore.collection(_collection).doc(id).set({
          'uid': uid,
          'dramaId': dramaId,
          'episodeNumber': episodeNumber,
          'authorName': authorName,
          'comment': trimmed,
          'rating': rating,
          'country': countryToWrite,
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
    if (reviewId.startsWith('local_')) return;
    try {
      final threadRef =
          _firestore.collection(_collection).doc(reviewId).collection(_threadSubcollection);
      const chunk = 400;
      while (true) {
        final snap = await threadRef.limit(chunk).get();
        if (snap.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
      await _firestore.collection(_collection).doc(reviewId).delete();
    } catch (e) {
      debugPrint('EpisodeReviewService deleteById: $e');
    }
  }
}
