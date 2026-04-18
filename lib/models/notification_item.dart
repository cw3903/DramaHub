import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType { comment, reply, postLike, commentLike, message }

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.fromUser,
    required this.postId,
    required this.postTitle,
    required this.createdAt,
    this.commentText,
    this.isRead = false,
    this.country,
  });

  final String id;
  final NotificationType type;
  final String fromUser;
  final String postId;
  final String postTitle;
  final String? commentText;
  final DateTime createdAt;
  final bool isRead;

  /// Firestore `country` (us/kr/jp/cn). null이면 레거시.
  final String? country;

  static NotificationType _typeFromString(String s) {
    switch (s) {
      case 'comment': return NotificationType.comment;
      case 'reply': return NotificationType.reply;
      case 'postLike': return NotificationType.postLike;
      case 'commentLike': return NotificationType.commentLike;
      case 'message': return NotificationType.message;
      default: return NotificationType.comment;
    }
  }

  static String _typeToString(NotificationType t) {
    switch (t) {
      case NotificationType.comment: return 'comment';
      case NotificationType.reply: return 'reply';
      case NotificationType.postLike: return 'postLike';
      case NotificationType.commentLike: return 'commentLike';
      case NotificationType.message: return 'message';
    }
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'type': _typeToString(type),
      'fromUser': fromUser,
      'postId': postId,
      'postTitle': postTitle,
      'isRead': isRead,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final ct = commentText?.trim();
    if (ct != null && ct.isNotEmpty) {
      m['commentText'] = ct;
    }
    if (country != null) {
      m['country'] = country;
    }
    return m;
  }

  static NotificationItem fromMap(Map<String, dynamic> map, String id) {
    final createdAt = map['createdAt'];
    return NotificationItem(
      id: id,
      type: _typeFromString(map['type'] as String? ?? 'comment'),
      fromUser: map['fromUser'] as String? ?? '',
      postId: map['postId'] as String? ?? '',
      postTitle: map['postTitle'] as String? ?? '',
      commentText: map['commentText'] as String?,
      isRead: map['isRead'] as bool? ?? false,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      country: map['country'] as String?,
    );
  }

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
    id: id,
    type: type,
    fromUser: fromUser,
    postId: postId,
    postTitle: postTitle,
    commentText: commentText,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    country: country,
  );
}
