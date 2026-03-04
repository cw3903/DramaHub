import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import '../models/drama.dart';
import '../utils/format_utils.dart';

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

  Map<String, dynamic> toMap() => {
        'id': id,
        'dramaId': dramaId,
        'dramaTitle': dramaTitle,
        'rating': rating,
        'comment': comment,
        'writtenAt': writtenAt.millisecondsSinceEpoch,
        'authorName': authorName,
        'modifiedAt': modifiedAt?.millisecondsSinceEpoch,
      };

  static MyReviewItem fromMap(Map<String, dynamic> map) {
    final modifiedMs = map['modifiedAt'] as int?;
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
      modifiedAt: modifiedMs != null ? DateTime.fromMillisecondsSinceEpoch(modifiedMs, isUtc: false) : null,
    );
  }
}

/// 리뷰 탭에서 작성한 리뷰 관리 (SharedPreferences 로컬 캐시 + Firestore 영구 저장)
class ReviewService {
  ReviewService._();

  static final ReviewService instance = ReviewService._();

  static const _key = 'my_drama_reviews';
  static const _maxItems = 200;
  static const _collection = 'drama_reviews';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ValueNotifier<List<MyReviewItem>> listNotifier =
      ValueNotifier<List<MyReviewItem>>([]);
  bool _loaded = false;

  List<MyReviewItem> get list => listNotifier.value;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  Future<void> _load() async {
    List<MyReviewItem> list = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null && json.isNotEmpty) {
        list = (jsonDecode(json) as List<dynamic>)
            .map((e) => MyReviewItem.fromMap(e as Map<String, dynamic>))
            .where((e) => e.id.isNotEmpty)
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
            .map((d) => _itemFromFirestore(d.id, d.data()))
            .whereType<MyReviewItem>()
            .toList();
        for (final r in fromFirestore) {
          list.removeWhere((e) => e.dramaId == r.dramaId);
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
    _persist(list);
  }

  static MyReviewItem? _itemFromFirestore(String id, Map<String, dynamic> data) {
    final writtenAt = data['writtenAt'];
    final modifiedAt = data['modifiedAt'];
    final written = writtenAt is Timestamp
        ? writtenAt.toDate()
        : DateTime.fromMillisecondsSinceEpoch((writtenAt as num?)?.toInt() ?? 0, isUtc: false);
    final modified = modifiedAt is Timestamp
        ? modifiedAt.toDate()
        : (modifiedAt != null ? DateTime.fromMillisecondsSinceEpoch((modifiedAt as num).toInt(), isUtc: false) : null);
    return MyReviewItem(
      id: id,
      dramaId: data['dramaId'] as String? ?? '',
      dramaTitle: data['dramaTitle'] as String? ?? '',
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      comment: data['comment'] as String? ?? '',
      writtenAt: written,
      authorName: data['authorName'] as String?,
      modifiedAt: modified,
    );
  }

  Future<void> loadIfNeeded() async {
    if (!_loaded) await _load();
  }

  /// 화면 진입 시 Firestore에서 다시 로드 (로그인 후·다른 기기에서 작성한 리뷰 반영)
  Future<void> refresh() async {
    _loaded = false;
    await _load();
  }

  /// 리뷰 추가 (같은 dramaId면 덮어쓰기). 로그인 시 Firestore에도 저장.
  Future<void> add({
    required String dramaId,
    required String dramaTitle,
    required double rating,
    required String comment,
    String? authorName,
  }) async {
    final uid = _uid;
    final id = uid != null ? '${uid}_$dramaId' : 'review-$dramaId-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    final item = MyReviewItem(
      id: id,
      dramaId: dramaId,
      dramaTitle: dramaTitle,
      rating: rating,
      comment: comment,
      writtenAt: now,
      authorName: authorName,
    );
    var list = List<MyReviewItem>.from(listNotifier.value);
    list.removeWhere((e) => e.dramaId == dramaId);
    list.insert(0, item);
    if (list.length > _maxItems) {
      list = list.sublist(0, _maxItems);
    }
    listNotifier.value = list;
    await _persist(list);

    if (uid != null) {
      try {
        await _firestore.collection(_collection).doc(id).set({
          'uid': uid,
          'dramaId': dramaId,
          'dramaTitle': dramaTitle,
          'rating': rating,
          'comment': comment,
          'writtenAt': Timestamp.fromDate(now),
          'authorName': authorName,
        });
      } catch (e) {
        debugPrint('ReviewService add Firestore: $e');
      }
    }
  }

  /// dramaId에 해당하는 내 리뷰 반환 (없으면 null)
  MyReviewItem? getByDramaId(String dramaId) {
    try {
      return listNotifier.value.firstWhere((e) => e.dramaId == dramaId);
    } catch (_) {
      return null;
    }
  }

  /// 리뷰 수정 (같은 dramaId). 로그인 시 Firestore에도 반영.
  Future<void> update({
    required String dramaId,
    required double rating,
    required String comment,
  }) async {
    final idx = listNotifier.value.indexWhere((e) => e.dramaId == dramaId);
    if (idx < 0) return;
    final old = listNotifier.value[idx];
    final now = DateTime.now();
    final item = MyReviewItem(
      id: old.id,
      dramaId: old.dramaId,
      dramaTitle: old.dramaTitle,
      rating: rating,
      comment: comment,
      writtenAt: old.writtenAt,
      authorName: old.authorName,
      modifiedAt: now,
    );
    final list = List<MyReviewItem>.from(listNotifier.value);
    list[idx] = item;
    listNotifier.value = list;
    await _persist(list);

    final uid = _uid;
    if (uid != null && (old.id.startsWith('${uid}_') || old.id.startsWith('review-'))) {
      try {
        final docId = old.id.startsWith('${uid}_') ? old.id : '${uid}_$dramaId';
        await _firestore.collection(_collection).doc(docId).set({
          'uid': uid,
          'dramaId': dramaId,
          'dramaTitle': old.dramaTitle,
          'rating': rating,
          'comment': comment,
          'writtenAt': Timestamp.fromDate(old.writtenAt),
          'authorName': old.authorName,
          'modifiedAt': Timestamp.fromDate(now),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('ReviewService update Firestore: $e');
      }
    }
  }

  /// 리뷰 삭제. 로그인 시 Firestore에서도 삭제.
  Future<void> delete(String dramaId) async {
    final uid = _uid;
    final docId = uid != null ? '${uid}_$dramaId' : null;
    final list = listNotifier.value.where((e) => e.dramaId != dramaId).toList();
    listNotifier.value = list;
    await _persist(list);

    if (docId != null) {
      try {
        await _firestore.collection(_collection).doc(docId).delete();
      } catch (e) {
        debugPrint('ReviewService delete Firestore: $e');
      }
    }
  }

  Future<void> _persist(List<MyReviewItem> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(list.map((e) => e.toMap()).toList()));
    } catch (_) {}
  }

  /// 해당 드라마의 전체 유저 리뷰 기준 평균 평점 & 리뷰 수 (상세 페이지 표시용)
  Future<({double average, int count})> getDramaRatingStats(String dramaId) async {
    if (dramaId.isEmpty) return (average: 0.0, count: 0);
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('dramaId', isEqualTo: dramaId)
          .get();
      if (snapshot.docs.isEmpty) return (average: 0.0, count: 0);
      double sum = 0;
      for (final doc in snapshot.docs) {
        final r = (doc.data()['rating'] as num?)?.toDouble() ?? 0;
        sum += r;
      }
      final count = snapshot.docs.length;
      return (average: count > 0 ? sum / count : 0.0, count: count);
    } catch (e) {
      debugPrint('ReviewService getDramaRatingStats: $e');
      return (average: 0.0, count: 0);
    }
  }

  /// 해당 드라마의 전체 리뷰 목록 (상세 페이지 평점·리뷰 섹션용)
  Future<List<DramaReview>> getDramaReviews(String dramaId) async {
    if (dramaId.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('dramaId', isEqualTo: dramaId)
          .get();
      final list = <DramaReview>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final writtenAt = d['writtenAt'];
        final at = writtenAt is Timestamp
            ? writtenAt.toDate()
            : DateTime.fromMillisecondsSinceEpoch((writtenAt as num?)?.toInt() ?? 0, isUtc: false);
        list.add(DramaReview(
          id: doc.id,
          userName: d['authorName'] as String? ?? 'u/익명',
          rating: (d['rating'] as num?)?.toDouble() ?? 0,
          comment: d['comment'] as String? ?? '',
          timeAgo: formatTimeAgo(at),
          likeCount: 0,
        ));
      }
      return list;
    } catch (e) {
      debugPrint('ReviewService getDramaReviews: $e');
      return [];
    }
  }

  int get count => listNotifier.value.length;
}
