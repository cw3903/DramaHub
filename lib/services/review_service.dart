import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'locale_service.dart';
import '../models/drama.dart';
import '../models/post.dart';
import '../utils/format_utils.dart';
import '../utils/post_board_utils.dart';

/// 리뷰 탭(드라마 상세)에서 사용자가 작성한 리뷰
class MyReviewItem {
  const MyReviewItem({
    required this.id,
    required this.dramaId,
    required this.dramaTitle,
    required this.rating,
    required this.comment,
    required this.writtenAt,
    this.authorName,
    this.modifiedAt,
    this.feedPostId,
    this.appLocale,
  });

  final String id;
  final String dramaId;
  final String dramaTitle;
  final double rating;
  final String comment;
  final DateTime writtenAt;
  final String? authorName;

  /// 수정 시각 (null이면 미수정)
  final DateTime? modifiedAt;

  /// DramaFeed `posts` 문서 id (삭제 시 해당 글만 제거)
  final String? feedPostId;

  /// 저장 시 앱 언어(us/kr/jp/cn). null이면 레거시.
  final String? appLocale;

  Map<String, dynamic> toMap() => {
    'id': id,
    'dramaId': dramaId,
    'dramaTitle': dramaTitle,
    'rating': rating,
    'comment': comment,
    'writtenAt': writtenAt.millisecondsSinceEpoch,
    'authorName': authorName,
    'modifiedAt': modifiedAt?.millisecondsSinceEpoch,
    if (feedPostId != null) 'feedPostId': feedPostId,
    if (appLocale != null && appLocale!.trim().isNotEmpty) 'country': appLocale!.trim(),
  };

  static MyReviewItem fromMap(Map<String, dynamic> map) {
    final modifiedMs = map['modifiedAt'] as int?;
    final loc = (map['country'] as String?)?.trim();
    return MyReviewItem(
      id: map['id'] as String? ?? '',
      dramaId: map['dramaId'] as String? ?? '',
      dramaTitle: map['dramaTitle'] as String? ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      comment: map['comment'] as String? ?? '',
      writtenAt: DateTime.fromMillisecondsSinceEpoch(
        map['writtenAt'] as int? ?? 0,
        isUtc: false,
      ),
      authorName: map['authorName'] as String?,
      modifiedAt: modifiedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(modifiedMs, isUtc: false)
          : null,
      feedPostId: map['feedPostId'] as String?,
      appLocale: loc != null && loc.isNotEmpty ? loc : null,
    );
  }
}

/// 리뷰 탭에서 작성한 리뷰 관리 (SharedPreferences 로컬 캐시 + Firestore 영구 저장)
class ReviewService {
  ReviewService._();

  static final ReviewService instance = ReviewService._();

  static var _registeredPreLocaleClear = false;

  /// [main]에서 `runApp` 전에 호출 — 드라마 탭을 한 번도 열지 않아도 언어 변경 시 집계 캐시가 비워지게 함.
  static void ensurePreLocaleAggregateClearRegistered() {
    if (_registeredPreLocaleClear) return;
    _registeredPreLocaleClear = true;
    LocaleService.registerPreLocaleCommit(() {
      instance._dramaAggregateStatsCache.clear();
    });
  }

  static const _key = 'my_drama_reviews';
  static const _maxItems = 200;
  static const _collection = 'drama_reviews';

  static String? _trimOrNull(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  /// `dramaId`별 전체 리뷰 평균·개수 — 상세 [getDramaRatingStats]·[prefetchDramaRatingStats]로 채움.
  final Map<String, ({double average, int count})> _dramaAggregateStatsCache =
      {};

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ValueNotifier<List<MyReviewItem>> listNotifier =
      ValueNotifier<List<MyReviewItem>>([]);
  bool _loaded = false;
  String? _lastUid;
  String? _lastLocaleForFilter;

  bool _myReviewVisibleInLocale(MyReviewItem e) {
    final m = <String, dynamic>{};
    if (e.appLocale != null && e.appLocale!.trim().isNotEmpty) {
      m['country'] = e.appLocale!.trim();
    }
    return Post.documentVisibleInCountryFeed(m, LocaleService.instance.locale);
  }

  bool _firestoreReviewDocVisible(Map<String, dynamic> data) =>
      Post.documentVisibleInCountryFeed(data, LocaleService.instance.locale);

  /// [delete]로 DramaFeed `posts`에서 리뷰 글이 지워졌을 때 +1. [consumeLastDeletedFeedPostIds]로 id 목록 소비.
  final ValueNotifier<int> reviewFeedPostsDeletedTick = ValueNotifier(0);
  List<String> _lastDeletedFeedPostIds = [];

  /// [reviewFeedPostsDeletedTick] 직후 호출: 방금 삭제된 posts 문서 id (없으면 빈 목록).
  List<String> consumeLastDeletedFeedPostIds() {
    final out = List<String>.from(_lastDeletedFeedPostIds);
    _lastDeletedFeedPostIds = [];
    return out;
  }

  List<MyReviewItem> get list => listNotifier.value;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  Future<void> _load() async {
    final loc = LocaleService.instance.locale;
    List<MyReviewItem> list = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null && json.isNotEmpty) {
        list = (jsonDecode(json) as List<dynamic>)
            .map((e) => MyReviewItem.fromMap(e as Map<String, dynamic>))
            .where((e) => e.id.isNotEmpty)
            .where(_myReviewVisibleInLocale)
            .toList();
      }
    } catch (_) {}

    final uid = _uid;
    if (uid != null) {
      try {
        final snapshot = await _firestore
            .collection(_collection)
            .where('uid', isEqualTo: uid)
            .get();
        final fromFirestore = snapshot.docs
            .where((d) => _firestoreReviewDocVisible(d.data()))
            .map((d) => _itemFromFirestore(d.id, d.data()))
            .whereType<MyReviewItem>()
            .toList();
        for (final r in fromFirestore) {
          list.removeWhere((e) => e.id == r.id);
          list.insert(0, r);
        }
        if (list.length > _maxItems) list = list.sublist(0, _maxItems);
      } catch (e) {
        debugPrint('ReviewService Firestore load: $e');
      }
    } else {
      // 비로그인 상태에서 로드한 경우 다음에 로그인되면 다시 로드되도록 _loaded를 true로 두지 않음
      listNotifier.value = list;
      _persist(list);
      return;
    }
    listNotifier.value = list;
    _loaded = true;
    _lastUid = _uid;
    _lastLocaleForFilter = loc;
    _persist(list);
  }

  static MyReviewItem? _itemFromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final writtenAt = data['writtenAt'];
    final modifiedAt = data['modifiedAt'];
    final written = writtenAt is Timestamp
        ? writtenAt.toDate()
        : DateTime.fromMillisecondsSinceEpoch(
            (writtenAt as num?)?.toInt() ?? 0,
            isUtc: false,
          );
    final modified = modifiedAt is Timestamp
        ? modifiedAt.toDate()
        : (modifiedAt != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (modifiedAt as num).toInt(),
                  isUtc: false,
                )
              : null);
    final loc = (data['country'] as String?)?.trim();
    return MyReviewItem(
      id: id,
      dramaId: data['dramaId'] as String? ?? '',
      dramaTitle: data['dramaTitle'] as String? ?? '',
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      comment: data['comment'] as String? ?? '',
      writtenAt: written,
      authorName: data['authorName'] as String?,
      modifiedAt: modified,
      feedPostId: data['feedPostId'] as String?,
      appLocale: loc != null && loc.isNotEmpty ? loc : null,
    );
  }

  Future<void> loadIfNeeded() async {
    final uid = _uid;
    // UID가 바뀌면 이전 사용자 데이터를 즉시 클리어하고 재로드
    if (uid != _lastUid) await clearForLogout();
    if (_lastLocaleForFilter != null &&
        _lastLocaleForFilter != LocaleService.instance.locale) {
      _loaded = false;
    }
    if (!_loaded) await _load();
  }

  /// 타 유저 프로필·Recent activity용. [drama_reviews]에서 `uid` 일치 문서만.
  Future<List<MyReviewItem>> fetchReviewsForUserUid(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('uid', isEqualTo: u)
          .get();
      final loc = LocaleService.instance.locale;
      final list = snapshot.docs
          .where((d) => Post.documentVisibleInCountryFeed(d.data(), loc))
          .map((d) => _itemFromFirestore(d.id, d.data()))
          .whereType<MyReviewItem>()
          .toList();
      list.sort((a, b) {
        final tb = b.modifiedAt ?? b.writtenAt;
        final ta = a.modifiedAt ?? a.writtenAt;
        return tb.compareTo(ta);
      });
      return list;
    } catch (e, st) {
      debugPrint('fetchReviewsForUserUid: $e\n$st');
      return [];
    }
  }

  /// 화면 진입 시 Firestore에서 다시 로드 (로그인 후·다른 기기에서 작성한 리뷰 반영)
  Future<void> refresh() async {
    _loaded = false;
    await _load();
  }

  String _newReviewDocId(String? uid, String dramaId) {
    if (uid == null) {
      return 'review-$dramaId-${DateTime.now().millisecondsSinceEpoch}';
    }
    final salt = Random().nextInt(1 << 30);
    return '${uid}_${dramaId}_${DateTime.now().millisecondsSinceEpoch}_$salt';
  }

  /// 리뷰 추가. 같은 작품에 여러 건 가능. 로그인 시 Firestore `drama_reviews/{id}` 저장.
  /// [documentId]·[feedPostId]는 피드 글과 1:1 맞출 때 사용.
  Future<String> add({
    required String dramaId,
    required String dramaTitle,
    required double rating,
    required String comment,
    String? authorName,
    String? documentId,
    String? feedPostId,
    String? authorPhotoUrl,
    String? appLocale,
  }) async {
    final uid = _uid;
    final id = (documentId != null && documentId.isNotEmpty)
        ? documentId
        : _newReviewDocId(uid, dramaId);
    final now = DateTime.now();
    final loc = (appLocale != null && appLocale.trim().isNotEmpty)
        ? appLocale.trim()
        : LocaleService.instance.locale;
    final item = MyReviewItem(
      id: id,
      dramaId: dramaId,
      dramaTitle: dramaTitle,
      rating: rating,
      comment: comment,
      writtenAt: now,
      authorName: authorName,
      feedPostId: feedPostId,
      appLocale: loc,
    );
    var list = List<MyReviewItem>.from(listNotifier.value);
    list.removeWhere((e) => e.id == id);
    list.insert(0, item);
    if (list.length > _maxItems) {
      list = list.sublist(0, _maxItems);
    }
    listNotifier.value = list;
    await _persist(list);

    if (uid != null) {
      try {
        final data = <String, dynamic>{
          'uid': uid,
          'dramaId': dramaId,
          'dramaTitle': dramaTitle,
          'rating': rating,
          'comment': comment,
          'writtenAt': Timestamp.fromDate(now),
          'authorName': authorName,
          'country': loc,
        };
        if (feedPostId != null && feedPostId.isNotEmpty) {
          data['feedPostId'] = feedPostId;
        }
        final ap = authorPhotoUrl?.trim();
        if (ap != null && ap.isNotEmpty) {
          data['authorPhotoUrl'] = ap;
        }
        await _firestore.collection(_collection).doc(id).set(data);
      } catch (e) {
        debugPrint('ReviewService add Firestore: $e');
      }
    }
    _invalidateDramaAggregateStats(dramaId);
    unawaited(prefetchDramaRatingStats([dramaId]));
    return id;
  }

  MyReviewItem? getById(String id) {
    if (id.isEmpty) return null;
    try {
      return listNotifier.value.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// dramaId에 해당하는 **가장 최근** 내 리뷰 (목록·별점 표시용). 없으면 null.
  MyReviewItem? getByDramaId(String dramaId) {
    final matches = listNotifier.value
        .where((e) => e.dramaId == dramaId)
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final tb = b.modifiedAt ?? b.writtenAt;
      final ta = a.modifiedAt ?? a.writtenAt;
      return tb.compareTo(ta);
    });
    return matches.first;
  }

  /// 리뷰 수정. 로그인 시 Firestore `drama_reviews/{id}` 반영.
  Future<void> updateById({
    required String id,
    required double rating,
    required String comment,
    /// 피드 동기화 등: 게시글 `country`로 덮어쓸 때만 지정. null이면 [old.appLocale] 유지.
    String? countryOverride,
  }) async {
    final idx = listNotifier.value.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final old = listNotifier.value[idx];
    final now = DateTime.now();
    final loc = (countryOverride != null && countryOverride.trim().isNotEmpty)
        ? countryOverride.trim()
        : ((old.appLocale != null && old.appLocale!.trim().isNotEmpty)
              ? old.appLocale!.trim()
              : LocaleService.instance.locale);
    final item = MyReviewItem(
      id: old.id,
      dramaId: old.dramaId,
      dramaTitle: old.dramaTitle,
      rating: rating,
      comment: comment,
      writtenAt: old.writtenAt,
      authorName: old.authorName,
      modifiedAt: now,
      feedPostId: old.feedPostId,
      appLocale: loc,
    );
    final list = List<MyReviewItem>.from(listNotifier.value);
    list[idx] = item;
    listNotifier.value = list;
    await _persist(list);

    final uid = _uid;
    if (uid != null) {
      try {
        final data = <String, dynamic>{
          'uid': uid,
          'dramaId': old.dramaId,
          'dramaTitle': old.dramaTitle,
          'rating': rating,
          'comment': comment,
          'writtenAt': Timestamp.fromDate(old.writtenAt),
          'authorName': old.authorName,
          'modifiedAt': Timestamp.fromDate(now),
          'country': loc,
        };
        if (old.feedPostId != null && old.feedPostId!.isNotEmpty) {
          data['feedPostId'] = old.feedPostId;
        }
        await _firestore
            .collection(_collection)
            .doc(id)
            .set(data, SetOptions(merge: true));
      } catch (e) {
        debugPrint('ReviewService update Firestore: $e');
      }
    }
    _invalidateDramaAggregateStats(old.dramaId);
    unawaited(prefetchDramaRatingStats([old.dramaId]));
  }

  /// DramaFeed 글 id를 리뷰 문서에 연결 (신규 리뷰 저장 직후).
  Future<void> setFeedPostId({
    required String reviewId,
    required String feedPostId,
  }) async {
    await loadIfNeeded();
    final idx = listNotifier.value.indexWhere((e) => e.id == reviewId);
    if (idx < 0) return;
    final old = listNotifier.value[idx];
    final loc = (old.appLocale != null && old.appLocale!.trim().isNotEmpty)
        ? old.appLocale!.trim()
        : LocaleService.instance.locale;
    final item = MyReviewItem(
      id: old.id,
      dramaId: old.dramaId,
      dramaTitle: old.dramaTitle,
      rating: old.rating,
      comment: old.comment,
      writtenAt: old.writtenAt,
      authorName: old.authorName,
      modifiedAt: old.modifiedAt,
      feedPostId: feedPostId,
      appLocale: loc,
    );
    final list = List<MyReviewItem>.from(listNotifier.value);
    list[idx] = item;
    listNotifier.value = list;
    await _persist(list);
    final uid = _uid;
    if (uid != null) {
      try {
        await _firestore.collection(_collection).doc(reviewId).set({
          'feedPostId': feedPostId,
          'country': loc,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('ReviewService setFeedPostId: $e');
      }
    }
  }

  /// 리뷰 한 건 삭제. 연결된 피드 글이 있으면 해당 글만 삭제.
  Future<void> deleteById(String id) async {
    if (id.isEmpty) return;
    final uid = _uid;
    MyReviewItem? found;
    for (final e in listNotifier.value) {
      if (e.id == id) {
        found = e;
        break;
      }
    }
    if (found == null) return;
    final list = listNotifier.value.where((e) => e.id != id).toList();
    listNotifier.value = list;
    await _persist(list);

    if (uid == null) return;

    try {
      await _firestore.collection(_collection).doc(id).delete();
    } catch (e) {
      debugPrint('ReviewService delete Firestore: $e');
    }
    _invalidateDramaAggregateStats(found.dramaId);
    unawaited(prefetchDramaRatingStats([found.dramaId]));

    final removedIds = <String>[];
    final fp = found.feedPostId?.trim();
    if (fp != null && fp.isNotEmpty) {
      try {
        await _firestore.collection('posts').doc(fp).delete();
        removedIds.add(fp);
      } catch (e, st) {
        debugPrint('ReviewService delete linked post: $e\n$st');
      }
    } else {
      removedIds.addAll(
        await _deleteLinkedFeedReviewPosts(dramaId: found.dramaId, uid: uid),
      );
    }
    if (removedIds.isNotEmpty) {
      _lastDeletedFeedPostIds = removedIds;
      reviewFeedPostsDeletedTick.value++;
    }
  }

  /// 같은 유저가 같은 드라마에 올린 DramaFeed 리뷰 글(`posts`, type=review) 삭제. 삭제된 문서 id 목록.
  Future<List<String>> _deleteLinkedFeedReviewPosts({
    required String dramaId,
    required String uid,
  }) async {
    if (dramaId.isEmpty) return [];
    try {
      final snap = await _firestore
          .collection('posts')
          .where('authorUid', isEqualTo: uid)
          .where('dramaId', isEqualTo: dramaId)
          .get();
      final toDelete = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in snap.docs) {
        final type = (doc.data()['type'] as String?)?.trim().toLowerCase();
        if (type == 'review') {
          toDelete.add(doc);
        }
      }
      if (toDelete.isEmpty) return [];
      const chunk = 400;
      final ids = <String>[];
      for (var i = 0; i < toDelete.length; i += chunk) {
        final batch = _firestore.batch();
        final end = (i + chunk) > toDelete.length ? toDelete.length : i + chunk;
        final slice = toDelete.sublist(i, end);
        for (final doc in slice) {
          batch.delete(doc.reference);
          ids.add(doc.id);
        }
        await batch.commit();
      }
      return ids;
    } catch (e, st) {
      debugPrint('ReviewService _deleteLinkedFeedReviewPosts: $e\n$st');
      return [];
    }
  }

  /// 로그아웃 또는 계정 전환 시 호출 — 메모리·로컬 캐시 완전 초기화.
  Future<void> clearForLogout() async {
    listNotifier.value = [];
    _loaded = false;
    _lastUid = null;
    _lastLocaleForFilter = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  Future<void> _persist(List<MyReviewItem> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(list.map((e) => e.toMap()).toList()),
      );
    } catch (_) {}
  }

  /// DramaFeed `posts`에 저장된 리뷰 글을 드라마 상세의 리뷰 탭(`drama_reviews`)과 맞춤.
  /// [PostService.addPost] / [PostService.updatePost] 성공 후 호출.
  Future<void> syncDramaReviewFromFeedPost(Post post) async {
    if (postDisplayType(post) != 'review') return;
    final dramaId = post.dramaId?.trim() ?? '';
    if (dramaId.isEmpty) return;
    final rating = post.rating ?? 0;
    final comment = (post.body ?? '').trim();
    if (comment.isNotEmpty && rating <= 0) return;
    final dramaTitle = (post.dramaTitle?.trim().isNotEmpty == true)
        ? post.dramaTitle!.trim()
        : post.title.trim();
    var authorName = post.author.startsWith('u/')
        ? post.author.substring(2)
        : post.author;
    if (authorName.isEmpty) authorName = '익명';

    await loadIfNeeded();
    final postId = post.id.trim();
    if (postId.isEmpty) return;
    var existing = getById(postId);

    // WriteReviewSheet이 ReviewService.add()로 먼저 저장한 경우 — postId 대신
    // dramaId가 일치하고 feedPostId가 없는 미연결 리뷰가 있으면 그것을 연결하고 종료.
    if (existing == null) {
      final unlinked = listNotifier.value
          .where(
            (e) =>
                e.dramaId == dramaId &&
                (e.feedPostId == null || e.feedPostId!.trim().isEmpty),
          )
          .toList();
      if (unlinked.isNotEmpty) {
        final target = unlinked.first;
        await updateById(
          id: target.id,
          rating: rating,
          comment: comment,
          countryOverride: post.country,
        );
        await setFeedPostId(reviewId: target.id, feedPostId: postId);
        return;
      }
    }

    if (existing != null) {
      await updateById(
        id: postId,
        rating: rating,
        comment: comment,
        countryOverride: post.country,
      );
      final cur = getById(postId);
      if (cur != null && (cur.feedPostId == null || cur.feedPostId!.isEmpty)) {
        await setFeedPostId(reviewId: postId, feedPostId: postId);
      }
    } else {
      await add(
        dramaId: dramaId,
        dramaTitle: dramaTitle.isNotEmpty ? dramaTitle : dramaId,
        rating: rating,
        comment: comment,
        authorName: authorName,
        documentId: postId,
        feedPostId: postId,
        authorPhotoUrl: post.authorPhotoUrl,
        appLocale: post.country,
      );
    }
  }

  void _putDramaAggregateStats(String dramaId, double average, int count) {
    final id = dramaId.trim();
    if (id.isEmpty) return;
    _dramaAggregateStatsCache[id] = (average: average, count: count);
  }

  void _invalidateDramaAggregateStats(String dramaId) {
    final id = dramaId.trim();
    if (id.isEmpty) return;
    _dramaAggregateStatsCache.remove(id);
  }

  /// 그리드·검색 카드: Firestore 집계 후 캐시가 있으면 그 구역 기준.
  /// [count]가 0이면(해당 구역에 보이는 리뷰 없음) **0**을 반환해 카탈로그 별점으로 덮어쓰지 않음.
  /// 캐시 미적재 시에만 [catalogRating].
  double ratingForListCard(String dramaId, {required double catalogRating}) {
    final id = dramaId.trim();
    if (id.isEmpty) return catalogRating;
    final c = _dramaAggregateStatsCache[id];
    if (c == null) return catalogRating;
    if (c.count <= 0) return 0.0;
    return c.average;
  }

  /// [prefetchDramaRatingStats] 등으로 채워진 집계 캐시 — 네트워크 없이 동기 조회.
  ({double average, int count})? peekDramaAggregateStats(String dramaId) {
    final id = dramaId.trim();
    if (id.isEmpty) return null;
    return _dramaAggregateStatsCache[id];
  }

  /// 최대 10개씩 `whereIn`으로 배치 조회 후 [_dramaAggregateStatsCache] 갱신.
  Future<void> prefetchDramaRatingStats(Iterable<String> dramaIds) async {
    final unique = dramaIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final missing = unique
        .where((id) => !_dramaAggregateStatsCache.containsKey(id))
        .toList();
    if (missing.isEmpty) return;
    const chunk = 10;
    for (var i = 0; i < missing.length; i += chunk) {
      final end = (i + chunk > missing.length) ? missing.length : i + chunk;
      final part = missing.sublist(i, end);
      try {
        final snap = await _firestore
            .collection(_collection)
            .where('dramaId', whereIn: part)
            .get();
        final sumBy = <String, double>{};
        final cntBy = <String, int>{};
        for (final doc in snap.docs) {
          final d = doc.data();
          if (!_firestoreReviewDocVisible(d)) continue;
          final did = (d['dramaId'] as String?)?.trim() ?? '';
          final r = (d['rating'] as num?)?.toDouble() ?? 0;
          if (did.isEmpty || r <= 0) continue;
          sumBy[did] = (sumBy[did] ?? 0) + r;
          cntBy[did] = (cntBy[did] ?? 0) + 1;
        }
        for (final id in part) {
          final c = cntBy[id] ?? 0;
          _putDramaAggregateStats(id, c > 0 ? (sumBy[id] ?? 0) / c : 0.0, c);
        }
      } catch (e, st) {
        debugPrint('ReviewService.prefetchDramaRatingStats: $e\n$st');
        for (final id in part) {
          if (!_dramaAggregateStatsCache.containsKey(id)) {
            _putDramaAggregateStats(id, 0.0, 0);
          }
        }
      }
    }
  }

  /// 해당 드라마의 전체 유저 리뷰 기준 평균 평점 & 리뷰 수 (상세 페이지 표시용)
  Future<({double average, int count})> getDramaRatingStats(
    String dramaId,
  ) async {
    final id = dramaId.trim();
    if (id.isEmpty) return (average: 0.0, count: 0);
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('dramaId', isEqualTo: id)
          .get();
      if (snapshot.docs.isEmpty) {
        const r = (average: 0.0, count: 0);
        _putDramaAggregateStats(id, r.average, r.count);
        return r;
      }
      double sum = 0;
      var count = 0;
      for (final doc in snapshot.docs) {
        final d = doc.data();
        if (!_firestoreReviewDocVisible(d)) continue;
        final r = (d['rating'] as num?)?.toDouble() ?? 0;
        if (r <= 0) continue;
        sum += r;
        count++;
      }
      final r = (average: count > 0 ? sum / count : 0.0, count: count);
      _putDramaAggregateStats(id, r.average, r.count);
      return r;
    } catch (e) {
      debugPrint('ReviewService getDramaRatingStats: $e');
      const r = (average: 0.0, count: 0);
      _putDramaAggregateStats(id, r.average, r.count);
      return r;
    }
  }

  /// 상세 페이지 등: `drama_reviews`를 **한 번만** 읽어 평균·개수·목록을 함께 반환.
  /// [getDramaRatingStats] + [getDramaReviews]를 각각 호출하면 동일 컬렉션을 두 번 읽어 병목이 됨.
  Future<({double average, int count, List<DramaReview> reviews})>
  getDramaReviewDetailBundle(String dramaId, {String? country}) async {
    final id = dramaId.trim();
    if (id.isEmpty) {
      return (average: 0.0, count: 0, reviews: <DramaReview>[]);
    }
    try {
      final loc = (country != null && country.trim().isNotEmpty)
          ? country.trim().toLowerCase()
          : LocaleService.instance.locale.trim().toLowerCase();
      final snapshot = await _firestore
          .collection(_collection)
          .where('dramaId', isEqualTo: id)
          .get();
      if (snapshot.docs.isEmpty) {
        const r = (average: 0.0, count: 0);
        _putDramaAggregateStats(id, r.average, r.count);
        return (average: r.average, count: r.count, reviews: <DramaReview>[]);
      }
      final list = <DramaReview>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        if (!Post.documentVisibleInCountryFeed(d, loc)) continue;
        final writtenAt = d['writtenAt'];
        final at = writtenAt is Timestamp
            ? writtenAt.toDate()
            : DateTime.fromMillisecondsSinceEpoch(
                (writtenAt as num?)?.toInt() ?? 0,
                isUtc: false,
              );
        final ctry = (d['country'] as String?)?.trim();
        list.add(
          DramaReview(
            id: doc.id,
            userName: d['authorName'] as String? ?? 'u/익명',
            rating: (d['rating'] as num?)?.toDouble() ?? 0,
            comment: d['comment'] as String? ?? '',
            timeAgo: formatTimeAgo(at, loc),
            likeCount:
                (d['likeCount'] as num?)?.toInt() ??
                (d['likes'] as num?)?.toInt() ??
                0,
            writtenAt: at,
            authorPhotoUrl: d['authorPhotoUrl'] as String?,
            authorUid: d['uid'] as String?,
            feedPostId: _trimOrNull(d['feedPostId'] as String?),
            appLocale: ctry != null && ctry.isNotEmpty ? ctry : null,
          ),
        );
      }
      list.sort((a, b) {
        final tb = b.writtenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final ta = a.writtenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      double sum = 0;
      var ratingCount = 0;
      for (final r in list) {
        if (r.rating <= 0) continue;
        sum += r.rating;
        ratingCount++;
      }
      final avg = ratingCount > 0 ? sum / ratingCount : 0.0;
      _putDramaAggregateStats(id, avg, ratingCount);
      return (average: avg, count: ratingCount, reviews: list);
    } catch (e) {
      debugPrint('ReviewService getDramaReviewDetailBundle: $e');
      const r = (average: 0.0, count: 0);
      _putDramaAggregateStats(id, r.average, r.count);
      return (average: r.average, count: r.count, reviews: <DramaReview>[]);
    }
  }

  /// 해당 드라마의 전체 리뷰 목록 (상세 페이지 평점·리뷰 섹션용)
  /// [country]: `us`/`kr`/`jp`/`cn` — 상대 시각 문자열([formatTimeAgo])에 사용.
  Future<List<DramaReview>> getDramaReviews(
    String dramaId, {
    String? country,
  }) async {
    if (dramaId.isEmpty) return [];
    try {
      final bundle = await getDramaReviewDetailBundle(
        dramaId,
        country: country,
      );
      return bundle.reviews;
    } catch (e) {
      debugPrint('ReviewService getDramaReviews: $e');
      return [];
    }
  }

  int get count => listNotifier.value.length;
}
