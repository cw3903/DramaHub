import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// 숏폼에서 시청한 드라마 항목
class WatchedDramaItem {
  const WatchedDramaItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.views,
    required this.watchedAt,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String views;
  final DateTime watchedAt;
  /// 드라마 썸네일 이미지 URL (프로필 카드 표시용)
  final String? imageUrl;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'views': views,
        'watchedAt': watchedAt.millisecondsSinceEpoch,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      };

  static WatchedDramaItem fromMap(Map<String, dynamic> map) => WatchedDramaItem(
        id: map['id'] as String? ?? '',
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
    _persist(list);
  }

  static WatchedDramaItem? _itemFromFirestore(String id, Map<String, dynamic> data) {
    final watchedAt = data['watchedAt'];
    final at = watchedAt is Timestamp
        ? watchedAt.toDate()
        : DateTime.fromMillisecondsSinceEpoch((watchedAt as num?)?.toInt() ?? 0, isUtc: false);
    return WatchedDramaItem(
      id: id,
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
      await prefs.setString(_key, jsonEncode(list.map((e) => e.toMap()).toList()));
    } catch (_) {}
  }

  Future<void> loadIfNeeded() async {
    if (!_loaded) await _load();
  }

  /// 화면 진입 시 Firestore/로컬에서 최신 데이터 다시 로드
  Future<void> refresh() async {
    _loaded = false;
    await _load();
  }

  /// 숏폼 시청 시 호출 (중복 시 최신으로 갱신). 로그인 시 Firestore에도 저장.
  Future<void> add({
    required String id,
    required String title,
    String subtitle = '',
    String views = '0',
    String? imageUrl,
  }) async {
    final now = DateTime.now();
    final item = WatchedDramaItem(
      id: id,
      title: title,
      subtitle: subtitle,
      views: views,
      watchedAt: now,
      imageUrl: imageUrl,
    );
    var list = List<WatchedDramaItem>.from(listNotifier.value);
    list.removeWhere((e) => e.id == id);
    list.insert(0, item);
    if (list.length > _maxItems) {
      list = list.sublist(0, _maxItems);
    }
    listNotifier.value = list;
    await _persist(list);

    final uid = _uid;
    if (uid != null) {
      _watchCol.doc(id).set({
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'views': views,
        'watchedAt': Timestamp.fromDate(now),
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      }).timeout(const Duration(seconds: 8)).catchError((e) {
        debugPrint('WatchHistoryService add Firestore: $e');
      });
    }
  }

  bool isWatched(String id) {
    return listNotifier.value.any((e) => e.id == id);
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
