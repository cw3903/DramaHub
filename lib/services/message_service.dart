import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/notification_item.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'user_profile_service.dart';

/// 회원 간 쪽지 (대화 목록 + 메시지) 관리. Firestore users/{uid}/conversations, messages.
class MessageService {
  MessageService._();

  static final MessageService instance = MessageService._();

  final ValueNotifier<List<Conversation>> conversations = ValueNotifier<List<Conversation>>([]);
  final ValueNotifier<int> unreadTotal = ValueNotifier<int>(0);
  final ValueNotifier<String?> conversationUpdated = ValueNotifier<String?>(null);

  final Map<String, List<Message>> _messagesByConversation = {};
  int _idSeq = 0;
  String _nextId() => 'msg_${++_idSeq}_${DateTime.now().millisecondsSinceEpoch}';
  bool _conversationsLoaded = false;

  String get _currentUserId => AuthService.instance.currentUser.value?.uid ?? 'me';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _conversationsCol {
    final uid = _currentUserId;
    if (uid == 'me') return _firestore.collection('_').doc('_').collection('_');
    return _firestore.collection('users').doc(uid).collection('conversations');
  }

  /// Firestore에서 대화 목록 로드
  Future<void> loadIfNeeded() async {
    final uid = _currentUserId;
    if (uid == 'me') {
      conversations.value = [];
      _conversationsLoaded = true;
      return;
    }
    if (_conversationsLoaded) return;
    try {
      final snapshot = await _conversationsCol.orderBy('lastMessageAt', descending: true).get();
      final list = <Conversation>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        list.add(Conversation.fromMap(data));
      }
      conversations.value = list;
      _updateUnreadTotal();
    } catch (_) {
      conversations.value = [];
    }
    _conversationsLoaded = true;
  }

  List<Message> getMessages(String conversationId) {
    return List.from(_messagesByConversation[conversationId] ?? []);
  }

  /// Firestore에서 메시지 로드 (채팅 화면 진입 시)
  Future<void> loadMessages(String conversationId) async {
    if (_messagesByConversation.containsKey(conversationId)) return;
    final uid = _currentUserId;
    if (uid == 'me') return;
    try {
      final snapshot = await _conversationsCol
          .doc(conversationId)
          .collection('messages')
          .orderBy('sentAt')
          .get();
      final list = snapshot.docs
          .map((d) => Message.fromMap(d.data()))
          .toList();
      _messagesByConversation[conversationId] = list;
      conversationUpdated.value = conversationId;
    } catch (_) {}
  }

  void _updateUnreadTotal() {
    unreadTotal.value = conversations.value.fold<int>(0, (sum, c) => sum + c.unreadCount);
  }

  Future<void> markConversationRead(String conversationId) async {
    final list = conversations.value.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(unreadCount: 0);
    }).toList();
    conversations.value = list;
    _updateUnreadTotal();
    final uid = _currentUserId;
    if (uid != 'me') {
      try {
        await _conversationsCol.doc(conversationId).update({'unreadCount': 0});
      } catch (_) {}
    }
  }

  /// 새 대화 시작. Firestore에 저장.
  Future<Conversation> startConversation(String otherUserId, String otherUserName) async {
    final existing = conversations.value.cast<Conversation?>().firstWhere(
          (c) => c!.otherUserId == otherUserId,
          orElse: () => null,
        );
    if (existing != null) return existing;

    final uid = _currentUserId;
    String id;
    if (uid != 'me') {
      final ref = await _conversationsCol.add({
        'otherUserId': otherUserId,
        'otherUserName': otherUserName,
        'unreadCount': 0,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
      id = ref.id;
    } else {
      id = 'conv_${DateTime.now().millisecondsSinceEpoch}';
    }
    final conv = Conversation(
      id: id,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      unreadCount: 0,
    );
    conversations.value = [conv, ...conversations.value];
    _messagesByConversation[id] = [];
    return conv;
  }

  Future<void> sendMessage(String conversationId, String text) async {
    if (text.trim().isEmpty) return;

    final msg = Message(
      id: _nextId(),
      conversationId: conversationId,
      senderId: _currentUserId,
      text: text.trim(),
      sentAt: DateTime.now(),
    );

    final list = _messagesByConversation[conversationId] ?? [];
    list.add(msg);
    _messagesByConversation[conversationId] = list;

    final convList = conversations.value.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(
        lastMessageText: text.trim(),
        lastMessageAt: msg.sentAt,
      );
    }).toList();
    conversations.value = convList;
    conversationUpdated.value = conversationId;

    final uid = _currentUserId;
    if (uid != 'me') {
      try {
        await _conversationsCol.doc(conversationId).collection('messages').doc(msg.id).set(msg.toMap());
        await _conversationsCol.doc(conversationId).update({
          'lastMessageText': text.trim(),
          'lastMessageAt': Timestamp.fromDate(msg.sentAt),
        });
        // 수신자에게 쪽지 알림
        final conv = conversations.value.cast<Conversation?>().firstWhere(
          (c) => c!.id == conversationId, orElse: () => null);
        if (conv != null && conv.otherUserId.isNotEmpty) {
          final myNickname = 'u/${UserProfileService.instance.nicknameNotifier.value ?? uid}';
          await NotificationService.instance.send(
            toUid: conv.otherUserId,
            type: NotificationType.message,
            fromUser: myNickname,
            postId: '',
            postTitle: '',
            commentText: text.trim(),
          );
        }
      } catch (_) {}
    }
  }

  void _addIncomingUnread(String conversationId, String text, DateTime at) {
    final conv = conversations.value.firstWhere((c) => c.id == conversationId);
    final updated = conv.copyWith(
      lastMessageText: text,
      lastMessageAt: at,
      unreadCount: conv.unreadCount + 1,
    );
    conversations.value = conversations.value
        .map((c) => c.id == conversationId ? updated : c)
        .toList();
    _updateUnreadTotal();
  }

  /// 로그아웃 시 호출
  void clearForLogout() {
    conversations.value = [];
    unreadTotal.value = 0;
    conversationUpdated.value = null;
    _messagesByConversation.clear();
    _conversationsLoaded = false;
  }

  /// 시뮬레이션: 상대가 답장한 것처럼 추가 (데모용)
  void simulateReply(String conversationId, String text) {
    final otherUserId = conversations.value
        .cast<Conversation?>()
        .firstWhere(
          (c) => c!.id == conversationId,
          orElse: () => null,
        )
        ?.otherUserId;
    if (otherUserId == null) return;

    final msg = Message(
      id: _nextId(),
      conversationId: conversationId,
      senderId: otherUserId,
      text: text,
      sentAt: DateTime.now(),
    );
    final list = _messagesByConversation[conversationId] ?? [];
    list.add(msg);
    _messagesByConversation[conversationId] = list;

    _addIncomingUnread(conversationId, text, msg.sentAt);
    conversationUpdated.value = conversationId;
  }
}
