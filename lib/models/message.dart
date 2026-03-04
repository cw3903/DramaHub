import 'package:cloud_firestore/cloud_firestore.dart';

/// 쪽지 대화 요약 (목록용)
class Conversation {
  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    this.lastMessageText,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final String otherUserId;
  final String otherUserName;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final int unreadCount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'otherUserId': otherUserId,
      'otherUserName': otherUserName,
      'lastMessageText': lastMessageText,
      'lastMessageAt': lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
      'unreadCount': unreadCount,
    };
  }

  static Conversation fromMap(Map<String, dynamic> map) {
    final t = map['lastMessageAt'];
    DateTime? at;
    if (t is Timestamp) at = t.toDate();
    return Conversation(
      id: map['id'] as String? ?? '',
      otherUserId: map['otherUserId'] as String? ?? '',
      otherUserName: map['otherUserName'] as String? ?? '',
      lastMessageText: map['lastMessageText'] as String?,
      lastMessageAt: at,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  Conversation copyWith({
    String? id,
    String? otherUserId,
    String? otherUserName,
    String? lastMessageText,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return Conversation(
      id: id ?? this.id,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUserName: otherUserName ?? this.otherUserName,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

/// 쪽지 한 통
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime sentAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'text': text,
      'sentAt': Timestamp.fromDate(sentAt),
    };
  }

  static Message fromMap(Map<String, dynamic> map) {
    final t = map['sentAt'];
    DateTime at = DateTime.now();
    if (t is Timestamp) at = t.toDate();
    return Message(
      id: map['id'] as String? ?? '',
      conversationId: map['conversationId'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      text: map['text'] as String? ?? '',
      sentAt: at,
    );
  }
}
