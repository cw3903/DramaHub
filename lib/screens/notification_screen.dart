import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/notification_item.dart';
import '../services/notification_service.dart';
import '../utils/format_utils.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.comment: return LucideIcons.message_circle;
      case NotificationType.reply: return LucideIcons.corner_down_right;
      case NotificationType.postLike: return LucideIcons.thumbs_up;
      case NotificationType.commentLike: return LucideIcons.thumbs_up;
      case NotificationType.message: return LucideIcons.mail;
    }
  }

  Color _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.comment: return const Color(0xFF4CAF50);
      case NotificationType.reply: return const Color(0xFF2196F3);
      case NotificationType.postLike: return const Color(0xFFFF6B35);
      case NotificationType.commentLike: return const Color(0xFFFF9800);
      case NotificationType.message: return const Color(0xFF9C27B0);
    }
  }

  String _labelForType(NotificationType type, String fromUser) {
    final name = fromUser.startsWith('u/') ? fromUser.substring(2) : fromUser;
    switch (type) {
      case NotificationType.comment: return '$name님이 내 글에 댓글을 달았어요';
      case NotificationType.reply: return '$name님이 내 댓글에 답글을 달았어요';
      case NotificationType.postLike: return '$name님이 내 글을 좋아해요';
      case NotificationType.commentLike: return '$name님이 내 댓글을 좋아해요';
      case NotificationType.message: return '$name님이 쪽지를 보냈어요';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '알림',
          style: GoogleFonts.notoSansKr(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => NotificationService.instance.markAllRead(),
            child: Text('모두 읽음', style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<NotificationItem>>(
        valueListenable: NotificationService.instance.notifications,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.bell, size: 56, color: cs.onSurfaceVariant.withOpacity(0.35)),
                  const SizedBox(height: 16),
                  Text('알림이 없어요', style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant)),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: cs.outline.withOpacity(0.08)),
            itemBuilder: (context, i) {
              final n = list[i];
              final color = _colorForType(n.type);
              return InkWell(
                onTap: () => NotificationService.instance.markRead(n.id),
                child: Container(
                  color: n.isRead ? null : color.withOpacity(0.05),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                        child: Icon(_iconForType(n.type), size: 18, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _labelForType(n.type, n.fromUser),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            if (n.postTitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                n.postTitle,
                                style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (n.commentText != null && n.commentText!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '"${n.commentText}"',
                                style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              formatTimeAgo(n.createdAt),
                              style: GoogleFonts.notoSansKr(fontSize: 11, color: cs.onSurfaceVariant.withOpacity(0.6)),
                            ),
                          ],
                        ),
                      ),
                      if (!n.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
