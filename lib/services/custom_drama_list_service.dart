import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/custom_drama_list.dart';
import 'auth_service.dart';

class CustomDramaListService {
  CustomDramaListService._();
  static final CustomDramaListService instance = CustomDramaListService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ValueNotifier<List<CustomDramaList>> listsNotifier =
      ValueNotifier<List<CustomDramaList>>([]);

  bool _loaded = false;
  String? _lastUid;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  CollectionReference<Map<String, dynamic>> get _listCol {
    final uid = _uid;
    if (uid == null) return _firestore.collection('_').doc('_').collection('_');
    return _firestore.collection('users').doc(uid).collection('custom_lists');
  }

  Future<void> loadIfNeeded({bool force = false}) async {
    final uid = _uid;
    if (uid != _lastUid) {
      _loaded = false;
      _lastUid = uid;
    }
    if (force) _loaded = false;
    if (uid == null) {
      listsNotifier.value = [];
      _loaded = true;
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
          .map((d) => CustomDramaList.fromDoc(d.id, d.data()))
          .where((e) => e.title.isNotEmpty)
          .toList();
      lists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      listsNotifier.value = lists;
    } catch (e, st) {
      debugPrint('CustomDramaListService.loadIfNeeded: $e\n$st');
      listsNotifier.value = [];
    }
    _loaded = true;
  }

  void clearForLogout() {
    listsNotifier.value = [];
    _loaded = false;
    _lastUid = null;
  }

  Future<void> createList({
    required String title,
    required String description,
    required List<String> dramaIds,
    String? coverDramaId,
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

    final cover = coverDramaId?.trim();
    final validCover =
        cover != null && cover.isNotEmpty && cleanIds.contains(cover)
            ? cover
            : null;

    final now = FieldValue.serverTimestamp();
    final ref = _listCol.doc();
    final data = <String, dynamic>{
      'title': cleanTitle,
      'description': cleanDesc,
      'dramaIds': cleanIds,
      'createdAt': now,
      'updatedAt': now,
      'likeCount': 0,
      'likedBy': <String>[],
    };
    if (validCover != null) {
      data['coverDramaId'] = validCover;
    }

    await ref.set(data);
    final nowLocal = DateTime.now();
    final inserted = CustomDramaList(
      id: ref.id,
      title: cleanTitle,
      description: cleanDesc,
      dramaIds: List<String>.from(cleanIds),
      createdAt: nowLocal,
      updatedAt: nowLocal,
      coverDramaId: validCover,
      likeCount: 0,
      likedBy: const [],
    );
    final cur = listsNotifier.value;
    listsNotifier.value = [
      inserted,
      ...cur.where((e) => e.id != inserted.id),
    ];
    // 전체 재조회는 UI를 막지 않게 백그라운드에서(타임스탬프·다른 기기 반영 동기화).
    unawaited(
      loadIfNeeded(force: true).catchError((Object e, StackTrace st) {
        debugPrint('CustomDramaListService.createList refresh: $e\n$st');
      }),
    );
  }

  /// 커스텀 리스트 문서의 좋아요 토글(본인 `users/{uid}/custom_lists`만).
  /// 성공 시 true=좋아요 적용, false=취소, 문서 없음·오류 시 null.
  Future<bool?> toggleListLike(String listId) async {
    final uid = _uid;
    if (uid == null || listId.isEmpty) return null;
    final ref = _listCol.doc(listId);
    bool? nowLiked;
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
      return null;
    }
    await loadIfNeeded(force: true);
    return nowLiked;
  }
}
