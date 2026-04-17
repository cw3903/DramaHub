import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// 숏폼에서 시청한 드라마 항목
class WatchedDramaItem {
  const WatchedDramaItem({
    required this.id,
    this.dramaId,
    this.rating,
    this.comment,
    required this.title,
    required this.subtitle,
    required this.views,
    required this.watchedAt,
    this.imageUrl,
  });

  final String id;

  /// 실제 드라마 id. 신규 저장은 분리 저장하고, 구버전 데이터는 비어 있을 수 있음.
  final String? dramaId;
  final double? rating;
  final String? comment;
  final String title;
  final String subtitle;
  final String views;
  final DateTime watchedAt;

  /// 드라마 썸네일 이미지 URL (프로필 카드 표시용)
  final String? imageUrl;

  /// 구버전(엔트리 id = 드라마 id)과 신버전(엔트리 id 분리) 모두 지원.
  String get dramaKey {
    final d = dramaId?.trim();
    if (d != null && d.isNotEmpty) return d;
    return id;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    if (dramaId != null && dramaId!.isNotEmpty) 'dramaId': dramaId,
    if (rating != null) 'rating': rating,
    if (comment != null && comment!.isNotEmpty) 'comment': comment,
    'title': title,
    'subtitle': subtitle,
    'views': views,
    'watchedAt': watchedAt.millisecondsSinceEpoch,
    if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
  };

  static WatchedDramaItem fromMap(Map<String, dynamic> map) => WatchedDramaItem(
    id: map['id'] as String? ?? '',
    dramaId: map['dramaId'] as String?,
    rating: (map['rating'] as num?)?.toDouble(),
    comment: map['comment'] as String?,
    title: map['title'] as String? ?? '',
    subtitle: map['subtitle'] as String? ?? '',
    views: map['views'] as String? ?? '0',
    watchedAt: DateTime.fromMillisecondsSinceEpoch(
      map['watchedAt'] as int? ?? 0,
      isUtc: false,
    ),
    imageUrl: map['imageUrl'] as String?,
  );
}

/// 숏폼 시청 기록 관리 (SharedPreferences 로컬 캐시 + Firestore 영구 저장, 게시글처럼 DB화)
class WatchHistoryService {
  WatchHistoryService._();

  static final WatchHistoryService instance = WatchHistoryService._();

  static const _key = 'shorts_watch_history';
  static const _maxItems = 100;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ValueNotifier<List<WatchedDramaItem>> listNotifier =
      ValueNotifier<List<WatchedDramaItem>>([]);
  bool _loaded = false;
  String? _lastUid;

  List<WatchedDramaItem> get list => listNotifier.value;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  CollectionReference<Map<String, dynamic>> get _watchCol {
    final uid = _uid;
    if (uid == null) return _firestore.collection('_').doc('_').collection('_');
    return _firestore.collection('users').doc(uid).collection('watch_history');
  }

  Future<void> _load() async {
    List<WatchedDramaItem> list = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null && json.isNotEmpty) {
        list = (jsonDecode(json) as List<dynamic>)
            .map((e) => WatchedDramaItem.fromMap(e as Map<String, dynamic>))
            .where((e) => e.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    final uid = _uid;
    if (uid != null) {
      try {
        final snapshot = await _watchCol
            .orderBy('watchedAt', descending: true)
            .limit(_maxItems)
            .get();
        final fromFirestore = snapshot.docs
            .map((d) => _itemFromFirestore(d.id, d.data()))
            .whereType<WatchedDramaItem>()
            .toList();
        for (final r in fromFirestore) {
          list.removeWhere((e) => e.id == r.id);
          list.insert(0, r);
        }
        if (list.length > _maxItems) list = list.sublist(0, _maxItems);
      } catch (e) {
        debugPrint('WatchHistoryService Firestore load: $e');
      }
    } else {
      listNotifier.value = list;
      _persist(list);
      return; // 비로그인 시 _loaded를 true로 두지 않아, 로그인 후 다시 Firestore 로드
    }
    listNotifier.value = list;
    _loaded = true;
    _lastUid = _uid;
    _persist(list);
  }

  static WatchedDramaItem? _itemFromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final watchedAt = data['watchedAt'];
    final at = watchedAt is Timestamp
        ? watchedAt.toDate()
        : DateTime.fromMillisecondsSinceEpoch(
            (watchedAt as num?)?.toInt() ?? 0,
            isUtc: false,
          );
    return WatchedDramaItem(
      id: id,
      dramaId: data['dramaId'] as String? ?? data['id'] as String?,
      rating: (data['rating'] as num?)?.toDouble(),
      comment: data['comment'] as String?,
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      views: data['views'] as String? ?? '0',
      watchedAt: at,
      imageUrl: data['imageUrl'] as String?,
    );
  }

  Future<void> _persist(List<WatchedDramaItem> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(list.map((e) => e.toMap()).toList()),
      );
    } catch (_) {}
  }

  Future<void> loadIfNeeded() async {
    final uid = _uid;
    // UID가 바뀌면 이전 사용자 데이터를 즉시 클리어하고 재로드
    if (uid != _lastUid) await clearForLogout();
    if (!_loaded) await _load();
  }

  /// 로그아웃 또는 계정 전환 시 호출 — 메모리·로컬 캐시 완전 초기화.
  Future<void> clearForLogout() async {
    listNotifier.value = [];
    _loaded = false;
    _lastUid = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// 화면 진입 시 Firestore/로컬에서 최신 데이터 다시 로드
  Future<void> refresh() async {
    _loaded = false;
    await _load();
  }

  /// 타 유저 다이어리 목록 조회.
  Future<List<WatchedDramaItem>> fetchForUid(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return [];
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection('users')
            .doc(u)
            .collection('watch_history')
            .orderBy('watchedAt', descending: true)
            .get();
      } catch (_) {
        snap = await _firestore
            .collection('users')
            .doc(u)
            .collection('watch_history')
            .get();
      }
      final items = snap.docs
          .map((d) => _itemFromFirestore(d.id, d.data()))
          .whereType<WatchedDramaItem>()
          .where((e) => e.id.isNotEmpty)
          .toList();
      items.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
      return items;
    } catch (e, st) {
      debugPrint('WatchHistoryService.fetchForUid: $e\n$st');
      return [];
    }
  }

  /// 타 유저 프로필 메뉴 카운트용. Firestore `count()` 집계 사용.
  Future<int> countWatchHistoryForUid(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return 0;
    try {
      final agg = await _firestore
          .collection('users')
          .doc(u)
          .collection('watch_history')
          .count()
          .get();
      return agg.count ?? 0;
    } catch (e, st) {
      debugPrint('WatchHistoryService.countWatchHistoryForUid: $e\n$st');
      return 0;
    }
  }

  /// 숏폼 시청 시 호출. 같은 작품이라도 저장할 때마다 새 다이어리 엔트리를 쌓는다.
  Future<void> add({
    required String id,
    required String title,
    String subtitle = '',
    String views = '0',
    String? imageUrl,
    double? rating,
    String? comment,
  }) async {
    final now = DateTime.now();
    final dramaId = id.trim();
    if (dramaId.isEmpty) return;
    final entryId = '${dramaId}_${now.microsecondsSinceEpoch}';
    final item = WatchedDramaItem(
      id: entryId,
      dramaId: dramaId,
      rating: rating,
      comment: comment?.trim(),
      title: title,
      subtitle: subtitle,
      views: views,
      watchedAt: now,
      imageUrl: imageUrl,
    );
    var list = List<WatchedDramaItem>.from(listNotifier.value);
    list.insert(0, item);
    if (list.length > _maxItems) {
      list = list.sublist(0, _maxItems);
    }
    listNotifier.value = list;
    await _persist(list);

    final uid = _uid;
    if (uid != null) {
      _watchCol
          .doc(entryId)
          .set({
            'id': dramaId,
            'dramaId': dramaId,
            if (rating != null) 'rating': rating,
            if (comment != null && comment.trim().isNotEmpty)
              'comment': comment.trim(),
            'title': title,
            'subtitle': subtitle,
            'views': views,
            'watchedAt': Timestamp.fromDate(now),
            if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
          })
          .timeout(const Duration(seconds: 8))
          .catchError((e) {
            debugPrint('WatchHistoryService add Firestore: $e');
          });
    }
  }

  bool isWatched(String id) {
    return listNotifier.value.any((e) => e.dramaKey == id);
  }

  Future<void> remove(String id) async {
    final list = List<WatchedDramaItem>.from(listNotifier.value);
    list.removeWhere((e) => e.id == id);
    listNotifier.value = list;
    await _persist(list);
    final uid = _uid;
    if (uid != null) {
      await _watchCol.doc(id).delete().catchError((e) {
        debugPrint('WatchHistoryService remove: $e');
      });
    }
  }
}
