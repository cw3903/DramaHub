import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Firestore `users/{uid}/following/{targetUid}` · `users/{targetUid}/followers/{uid}` + 카운터 필드.
class FollowService {
  FollowService._();
  static final FollowService instance = FollowService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 프로필 통계용: `following` 서브컬렉션 문서 수(항상 서브컬렉션과 일치).
  final ValueNotifier<int> followingCountNotifier = ValueNotifier<int>(0);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followingCountSub;

  static String _normalizeNickname(String nickname) =>
      nickname.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<String?> resolveUidByNickname(String nickname) async {
    final normalized = _normalizeNickname(nickname);
    if (normalized.isEmpty) return null;
    try {
      final doc = await _firestore.collection('nicknames').doc(normalized).get();
      if (!doc.exists) return null;
      final uid = doc.data()?['uid'] as String?;
      return uid?.isNotEmpty == true ? uid : null;
    } catch (e, st) {
      debugPrint('resolveUidByNickname: $e\n$st');
      return null;
    }
  }

  Future<FollowUserPublic?> getUserPublic(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;
      final nick = data['nickname'] as String?;
      final photo = data['profileImageUrl'] as String?;
      final colorIdx = data['avatarColorIndex'];
      final displayNick = nick != null && nick.trim().isNotEmpty ? nick.trim() : uid;
      return FollowUserPublic(
        uid: uid,
        nickname: displayNick,
        profileImageUrl: photo,
        avatarColorIndex: colorIdx is num ? colorIdx.toInt() : null,
      );
    } catch (e, st) {
      debugPrint('getUserPublic: $e\n$st');
      return null;
    }
  }

  void startFollowingCountListener(String uid) {
    _followingCountSub?.cancel();
    _followingCountSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('following')
        .snapshots()
        .listen(
      (snap) {
        followingCountNotifier.value = snap.docs.length;
      },
      onError: (e, st) {
        debugPrint('following count stream: $e\n$st');
      },
    );
  }

  void stopFollowingCountListener() {
    _followingCountSub?.cancel();
    _followingCountSub = null;
    followingCountNotifier.value = 0;
  }

  /// 프로필 통계용 일회성 조회 (다른 유저 프로필 — [followingCountNotifier]와 무관).
  /// Firestore `count()` 집계로 문서를 다운로드하지 않아 빠르고 저렴.
  Future<int> getFollowingCountOnce(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return 0;
    try {
      final agg = await _firestore
          .collection('users')
          .doc(u)
          .collection('following')
          .count()
          .get();
      return agg.count ?? 0;
    } catch (e, st) {
      debugPrint('getFollowingCountOnce: $e\n$st');
      return 0;
    }
  }

  Future<bool> isFollowing(String currentUid, String targetUid) async {
    if (currentUid.isEmpty || targetUid.isEmpty || currentUid == targetUid) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('following')
          .doc(targetUid)
          .get();
      return doc.exists;
    } catch (e, st) {
      debugPrint('isFollowing: $e\n$st');
      return false;
    }
  }

  Stream<bool> isFollowingStream(String currentUid, String targetUid) {
    if (currentUid.isEmpty || targetUid.isEmpty || currentUid == targetUid) {
      return Stream<bool>.value(false);
    }
    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(targetUid)
        .snapshots()
        .map((d) => d.exists);
  }

  /// 팔로우: 서브문서(디노멀) + `followersCount` / `followingCount` 증가.
  Future<void> followUser(String targetUid) async {
    final me = AuthService.instance.currentUser.value?.uid;
    if (me == null || me == targetUid) return;
    final results = await Future.wait([getUserPublic(me), getUserPublic(targetUid)]);
    final myPub = results[0];
    final tpPub = results[1];
    if (tpPub == null) return;

    final myRef = _firestore.collection('users').doc(me);
    final targetRef = _firestore.collection('users').doc(targetUid);
    final followingRef = myRef.collection('following').doc(targetUid);
    final followerRef = targetRef.collection('followers').doc(me);
    final ts = FieldValue.serverTimestamp();

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(followingRef);
      if (existing.exists) return;

      tx.set(followingRef, {
        'uid': targetUid,
        'nickname': tpPub.nickname,
        'photoUrl': tpPub.profileImageUrl,
        'createdAt': ts,
      });
      tx.set(followerRef, {
        'uid': me,
        'nickname': myPub?.nickname ?? 'Member',
        'photoUrl': myPub?.profileImageUrl,
        'createdAt': ts,
      });
      tx.set(targetRef, {'followersCount': FieldValue.increment(1)}, SetOptions(merge: true));
      tx.set(myRef, {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
    });
  }

  /// 언팔: 서브문서 삭제 + 카운터 감소.
  Future<void> unfollowUser(String targetUid) async {
    final me = AuthService.instance.currentUser.value?.uid;
    if (me == null) return;

    final myRef = _firestore.collection('users').doc(me);
    final targetRef = _firestore.collection('users').doc(targetUid);
    final followingRef = myRef.collection('following').doc(targetUid);
    final followerRef = targetRef.collection('followers').doc(me);

    await _firestore.runTransaction((tx) async {
      final f = await tx.get(followingRef);
      if (!f.exists) return;

      tx.delete(followingRef);
      tx.delete(followerRef);
      tx.set(targetRef, {'followersCount': FieldValue.increment(-1)}, SetOptions(merge: true));
      tx.set(myRef, {'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    });
  }
}

class FollowUserPublic {
  const FollowUserPublic({
    required this.uid,
    required this.nickname,
    this.profileImageUrl,
    this.avatarColorIndex,
  });

  final String uid;
  final String nickname;
  final String? profileImageUrl;
  final int? avatarColorIndex;
}
