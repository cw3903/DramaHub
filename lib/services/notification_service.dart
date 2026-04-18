import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_item.dart';
import 'auth_service.dart';

/// 알림 관리 서비스. Firestore users/{uid}/notifications 컬렉션 사용.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final ValueNotifier<List<NotificationItem>> notifications = ValueNotifier([]);
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSubscription;
  StreamSubscription<User?>? _authSubscription;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('notifications');
  }

  void _bindNotificationsQuery(String uid) {
    _notifSubscription?.cancel();
    _notifSubscription = null;
    notifications.value = [];
    unreadCount.value = 0;
    if (uid.isEmpty) return;
    _notifSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
      (snapshot) {
        final list = snapshot.docs
            .map((d) => NotificationItem.fromMap(d.data(), d.id))
            .toList();
        notifications.value = list;
        unreadCount.value = list.where((n) => !n.isRead).length;
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('notifications snapshot: $e\n$st');
        }
      },
    );
  }

  /// 앱 시작 시 1회 호출. 로그인/로그아웃 시마다 인박스 스트림을 다시 붙임.
  Future<void> init() async {
    await _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        _notifSubscription?.cancel();
        _notifSubscription = null;
        notifications.value = [];
        unreadCount.value = 0;
        final uid = user?.uid;
        if (uid != null && uid.isNotEmpty) {
          _bindNotificationsQuery(uid);
        }
      },
    );
  }

  /// [raw]이 Firebase uid 형태가 아니면 nicknames로 uid 해석 (구글/오타 대비).
  Future<String?> _normalizeRecipientUid(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final looksLikeUid =
        t.length >= 20 && t.length <= 128 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(t);
    if (looksLikeUid) return t;
    return getUidByNickname(t);
  }

  /// 알림 저장 (수신자 uid 기준으로 저장)
  Future<void> send({
    required String toUid,
    required NotificationType type,
    required String fromUser,
    required String postId,
    required String postTitle,
    String? commentText,
  }) async {
    final recipient = await _normalizeRecipientUid(toUid);
    if (recipient == null || recipient.isEmpty) return;
    final senderUid = FirebaseAuth.instance.currentUser?.uid.trim();
    // 자기 자신한테는 알림 안 보냄 (수신자 uid == 현재 로그인 uid)
    if (senderUid != null && senderUid == recipient) return;
    try {
      await _firestore
          .collection('users')
          .doc(recipient)
          .collection('notifications')
          .add(NotificationItem(
            id: '',
            type: type,
            fromUser: fromUser,
            postId: postId,
            postTitle: postTitle,
            commentText: commentText,
            createdAt: DateTime.now(),
          ).toMap());
    } catch (e, st) {
      developer.log(
        '알림 전송 실패 to=$recipient type=$type: $e',
        name: 'NotificationService',
        error: e,
        stackTrace: st,
      );
      debugPrint('알림 전송 실패: $e');
    }
  }

  /// 알림 전체 읽음 처리
  Future<void> markAllRead() async {
    final col = _col;
    if (col == null) return;
    final unread = notifications.value.where((n) => !n.isRead).toList();
    for (final n in unread) {
      col.doc(n.id).update({'isRead': true}).catchError((_) {});
    }
    notifications.value = notifications.value.map((n) => n.copyWith(isRead: true)).toList();
    unreadCount.value = 0;
  }

  /// 알림 하나 읽음 처리
  Future<void> markRead(String notificationId) async {
    final col = _col;
    if (col == null) return;
    await col.doc(notificationId).update({'isRead': true}).catchError((_) {});
    notifications.value = notifications.value
        .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
        .toList();
    unreadCount.value = notifications.value.where((n) => !n.isRead).length;
  }

  /// 닉네임으로 uid 조회 (nicknames 컬렉션)
  Future<String?> getUidByNickname(String nickname) async {
    if (nickname.isEmpty) return null;
    final normalized = nickname.startsWith('u/') ? nickname.substring(2) : nickname;
    try {
      final doc = await _firestore
          .collection('nicknames')
          .doc(normalized.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ''))
          .get();
      return doc.data()?['uid'] as String?;
    } catch (_) {
      return null;
    }
  }

  void reset() {
    _notifSubscription?.cancel();
    _notifSubscription = null;
    notifications.value = [];
    unreadCount.value = 0;
  }
}
