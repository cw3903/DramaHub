import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/custom_drama_list.dart';
import '../models/post.dart';
import 'auth_service.dart';
import 'locale_service.dart';

class CustomDramaListService {
  CustomDramaListService._();
  static final CustomDramaListService instance = CustomDramaListService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ValueNotifier<List<CustomDramaList>> listsNotifier =
      ValueNotifier<List<CustomDramaList>>([]);

  bool _loaded = false;
  String? _lastUid;
  String? _lastLocaleForFilter;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  CollectionReference<Map<String, dynamic>> get _listCol {
    final uid = _uid;
    if (uid == null) return _firestore.collection('_').doc('_').collection('_');
    return _firestore.collection('users').doc(uid).collection('custom_lists');
  }

  Future<void> loadIfNeeded({bool force = false}) async {
    final uid = _uid;
    final loc = LocaleService.instance.locale;
    if (uid != _lastUid) {
      _loaded = false;
      _lastUid = uid;
    }
    if (_lastLocaleForFilter != null && _lastLocaleForFilter != loc) {
      _loaded = false;
    }
    if (force) _loaded = false;
    if (uid == null) {
      listsNotifier.value = [];
      _loaded = true;
      _lastLocaleForFilter = loc;
      return;
    }
    if (_loaded) return;

    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _listCol.orderBy('updatedAt', descending: true).get();
      } catch (_) {
        snapshot = await _listCol.get();
      }
      final lists = snapshot.docs
          .where(
            (d) => Post.documentVisibleInCountryFeed(d.data(), loc),
          )
          .map((d) => CustomDramaList.fromDoc(d.id, d.data()))
          .where((e) => e.title.trim().isNotEmpty && e.dramaIds.isNotEmpty)
          .toList();
      lists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      listsNotifier.value = lists;
    } catch (e, st) {
      debugPrint('CustomDramaListService.loadIfNeeded: $e\n$st');
      listsNotifier.value = [];
    }
    _loaded = true;
    _lastLocaleForFilter = loc;
  }

  void clearForLogout() {
    listsNotifier.value = [];
    _loaded = false;
    _lastUid = null;
    _lastLocaleForFilter = null;
  }

  /// 갤러리 표지 업로드. Storage 규칙상 `posts/` 경로 사용.
  Future<String?> uploadListCoverImage(Uint8List bytes) async {
    final uid = _uid;
    if (uid == null || bytes.isEmpty) return null;
    try {
      final name =
          'list_cover_${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('posts').child(name);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e, st) {
      debugPrint('CustomDramaListService.uploadListCoverImage: $e\n$st');
      return null;
    }
  }

  Future<void> createList({
    required String title,
    required String description,
    required List<String> dramaIds,
    String? coverDramaId,
    String? coverImageUrl,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final cleanTitle = title.trim();
    final cleanDesc = description.trim();
    final cleanIds = dramaIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .take(20)
        .toList();
    if (cleanTitle.isEmpty || cleanIds.isEmpty) return;

    final rawImg = coverImageUrl?.trim();
    final validImg =
        rawImg != null &&
            rawImg.isNotEmpty &&
            (rawImg.startsWith('http://') || rawImg.startsWith('https://'))
        ? rawImg
        : null;

    final cover = coverDramaId?.trim();
    final validCover =
        cover != null && cover.isNotEmpty && cleanIds.contains(cover)
        ? cover
        : null;

    final now = FieldValue.serverTimestamp();
    final ref = _listCol.doc();
    final loc = LocaleService.instance.locale;
    final data = <String, dynamic>{
      'title': cleanTitle,
      'description': cleanDesc,
      'dramaIds': cleanIds,
      'createdAt': now,
      'updatedAt': now,
      'likeCount': 0,
      'likedBy': <String>[],
      'country': loc,
    };
    if (validImg != null) {
      data['coverImageUrl'] = validImg;
    } else if (validCover != null) {
      data['coverDramaId'] = validCover;
    }

    // Optimistic local update first so UI responds instantly.
    final nowLocal = DateTime.now();
    final inserted = CustomDramaList(
      id: ref.id,
      title: cleanTitle,
      description: cleanDesc,
      dramaIds: List<String>.from(cleanIds),
      createdAt: nowLocal,
      updatedAt: nowLocal,
      coverDramaId: validImg != null ? null : validCover,
      coverImageUrl: validImg,
      likeCount: 0,
      likedBy: const [],
      appLocale: loc,
    );
    final cur = listsNotifier.value;
    listsNotifier.value = [inserted, ...cur.where((e) => e.id != inserted.id)];
    // Firestore write + re-fetch run fully in background.
    unawaited(
      ref
          .set(data)
          .then((_) {
            return loadIfNeeded(force: true);
          })
          .catchError((Object e, StackTrace st) {
            debugPrint('CustomDramaListService.createList: $e\n$st');
          }),
    );
  }

  /// 리스트 삭제. 성공 시 true.
  Future<bool> deleteList(String listId) async {
    final uid = _uid;
    if (uid == null || listId.trim().isEmpty) return false;
    try {
      await _listCol.doc(listId).delete();
      listsNotifier.value = listsNotifier.value
          .where((e) => e.id != listId)
          .toList();
      unawaited(
        loadIfNeeded(force: true).catchError((Object e, StackTrace st) {
          debugPrint('CustomDramaListService.deleteList refresh: $e\n$st');
        }),
      );
      return true;
    } catch (e, st) {
      debugPrint('CustomDramaListService.deleteList: $e\n$st');
      return false;
    }
  }

  /// 리스트 수정(제목·설명·드라마·표지). [clearAllCovers] true면 표지 필드 둘 다 제거.
  Future<bool> updateList({
    required String listId,
    required String title,
    required String description,
    required List<String> dramaIds,
    String? coverDramaId,
    String? coverImageUrl,
    bool clearAllCovers = false,
  }) async {
    final uid = _uid;
    if (uid == null || listId.trim().isEmpty) return false;
    final cleanTitle = title.trim();
    final cleanDesc = description.trim();
    final cleanIds = dramaIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .take(20)
        .toList();
    if (cleanTitle.isEmpty || cleanIds.isEmpty) return false;

    final rawImg = coverImageUrl?.trim();
    final validImg =
        rawImg != null &&
            rawImg.isNotEmpty &&
            (rawImg.startsWith('http://') || rawImg.startsWith('https://'))
        ? rawImg
        : null;

    final cover = coverDramaId?.trim();
    final validCover =
        cover != null && cover.isNotEmpty && cleanIds.contains(cover)
        ? cover
        : null;

    final loc = LocaleService.instance.locale;
    final update = <String, dynamic>{
      'title': cleanTitle,
      'description': cleanDesc,
      'dramaIds': cleanIds,
      'updatedAt': FieldValue.serverTimestamp(),
      'country': loc,
    };

    if (clearAllCovers) {
      update['coverImageUrl'] = FieldValue.delete();
      update['coverDramaId'] = FieldValue.delete();
    } else if (validImg != null) {
      update['coverImageUrl'] = validImg;
      update['coverDramaId'] = FieldValue.delete();
    } else if (validCover != null) {
      update['coverDramaId'] = validCover;
      update['coverImageUrl'] = FieldValue.delete();
    }

    // Optimistic local update so UI responds instantly.
    final nowLocal = DateTime.now();
    final prev = listsNotifier.value;
    final updated = prev.map((e) {
      if (e.id != listId) return e;
      return CustomDramaList(
        id: e.id,
        title: cleanTitle,
        description: cleanDesc,
        dramaIds: List<String>.from(cleanIds),
        createdAt: e.createdAt,
        updatedAt: nowLocal,
        coverDramaId: clearAllCovers
            ? null
            : (validImg != null ? null : (validCover ?? e.coverDramaId)),
        coverImageUrl: clearAllCovers ? null : (validImg ?? e.coverImageUrl),
        likeCount: e.likeCount,
        likedBy: e.likedBy,
        appLocale: e.appLocale ?? loc,
      );
    }).toList();
    listsNotifier.value = updated;

    // Firestore write + re-fetch in background.
    unawaited(
      _listCol
          .doc(listId)
          .update(update)
          .then((_) {
            return loadIfNeeded(force: true);
          })
          .catchError((Object e, StackTrace st) {
            debugPrint('CustomDramaListService.updateList: $e\n$st');
            // Rollback on failure.
            listsNotifier.value = prev;
          }),
    );
    return true;
  }

  /// 타 유저 커스텀 리스트 목록 조회.
  Future<List<CustomDramaList>> fetchListsForUid(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return [];
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection('users')
            .doc(u)
            .collection('custom_lists')
            .orderBy('updatedAt', descending: true)
            .get();
      } catch (_) {
        snap = await _firestore
            .collection('users')
            .doc(u)
            .collection('custom_lists')
            .get();
      }
      final loc = LocaleService.instance.locale;
      return snap.docs
          .where((d) => Post.documentVisibleInCountryFeed(d.data(), loc))
          .map((d) => CustomDramaList.fromDoc(d.id, d.data()))
          .where((e) => e.title.trim().isNotEmpty && e.dramaIds.isNotEmpty)
          .toList();
    } catch (e, st) {
      debugPrint('CustomDramaListService.fetchListsForUid: $e\n$st');
      return [];
    }
  }

  /// 커스텀 리스트 문서의 좋아요 토글(본인 `users/{uid}/custom_lists`만).
  /// 성공 시 true=좋아요 적용, false=취소, 문서 없음·오류 시 null.
  /// 타 유저 프로필 메뉴 카운트용. Firestore `count()` 집계 사용.
  Future<int> countListsForUid(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return 0;
    try {
      final agg = await _firestore
          .collection('users')
          .doc(u)
          .collection('custom_lists')
          .count()
          .get();
      return agg.count ?? 0;
    } catch (e, st) {
      debugPrint('CustomDramaListService.countListsForUid: $e\n$st');
      return 0;
    }
  }

  Future<bool?> toggleListLike(String listId) async {
    final uid = _uid;
    if (uid == null || listId.isEmpty) return null;
    final ref = _listCol.doc(listId);
    bool? nowLiked;
    // 낙관적 업데이트: 탭 즉시 UI 반영
    final before = List<CustomDramaList>.from(listsNotifier.value);
    final idx = before.indexWhere((e) => e.id == listId);
    if (idx >= 0) {
      final cur = before[idx];
      final already = cur.likedBy.contains(uid);
      final nextLikedBy = already
          ? cur.likedBy.where((e) => e != uid).toList()
          : [...cur.likedBy, uid];
      final nextCount = already
          ? (cur.likeCount - 1).clamp(0, 1 << 30)
          : cur.likeCount + 1;
      final updated = CustomDramaList(
        id: cur.id,
        title: cur.title,
        description: cur.description,
        dramaIds: cur.dramaIds,
        createdAt: cur.createdAt,
        updatedAt: cur.updatedAt,
        coverDramaId: cur.coverDramaId,
        coverImageUrl: cur.coverImageUrl,
        likedBy: nextLikedBy,
        likeCount: nextCount,
        appLocale: cur.appLocale,
      );
      final optimistic = List<CustomDramaList>.from(before);
      optimistic[idx] = updated;
      listsNotifier.value = optimistic;
      nowLiked = !already;
    }
    try {
      await _firestore.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        if (!snap.exists) {
          nowLiked = null;
          return;
        }
        final data = snap.data()!;
        final likedBy = List<String>.from(
          (data['likedBy'] as List<dynamic>?)?.map((e) => e.toString()) ?? [],
        );
        if (likedBy.contains(uid)) {
          transaction.update(ref, <String, dynamic>{
            'likedBy': FieldValue.arrayRemove([uid]),
            'likeCount': FieldValue.increment(-1),
          });
          nowLiked = false;
        } else {
          transaction.update(ref, <String, dynamic>{
            'likedBy': FieldValue.arrayUnion([uid]),
            'likeCount': FieldValue.increment(1),
          });
          nowLiked = true;
        }
      });
    } catch (e, st) {
      debugPrint('CustomDramaListService.toggleListLike: $e\n$st');
      // 롤백
      listsNotifier.value = before;
      return null;
    }
    // 서버 값 동기화는 백그라운드로
    unawaited(
      loadIfNeeded(force: true).catchError((Object e, StackTrace st) {
        debugPrint('CustomDramaListService.toggleListLike refresh: $e\n$st');
      }),
    );
    return nowLiked;
  }
}
