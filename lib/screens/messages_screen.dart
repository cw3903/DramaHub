import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/message.dart';
import '../services/message_service.dart';
import '../widgets/country_scope.dart';
import 'message_thread_screen.dart';

/// 쪽지 목록 (대화 목록)
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.get('messages'),
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<List<Conversation>>(
        valueListenable: MessageService.instance.conversations,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.message_circle,
                      size: 72,
                      color: cs.onSurfaceVariant.withOpacity(0.4),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      s.get('noConversations'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.get('noConversationsHint'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: () => _showNewMessageDialog(context),
                      icon: const Icon(LucideIcons.pencil, size: 20),
                      label: Text(s.get('newMessage')),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final conv = list[index];
              final preview = conv.lastMessageText ?? '';
              final timeStr = conv.lastMessageAt != null
                  ? _formatTime(conv.lastMessageAt!)
                  : '';

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    MessageService.instance.markConversationRead(conv.id);
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => MessageThreadScreen(
                          conversationId: conv.id,
                          otherUserName: conv.otherUserName,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: cs.surfaceContainerHighest,
                          child: Text(
                            conv.otherUserName.isNotEmpty
                                ? conv.otherUserName.substring(0, 1).toUpperCase()
                                : '?',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conv.otherUserName,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 16,
                                        fontWeight: conv.unreadCount > 0
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: cs.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (timeStr.isNotEmpty)
                                    Text(
                                      timeStr,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                              if (preview.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  preview,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 14,
                                    color: cs.onSurfaceVariant,
                                    fontWeight: conv.unreadCount > 0
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (conv.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${conv.unreadCount}',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(
                          LucideIcons.chevron_right,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: ValueListenableBuilder<List<Conversation>>(
        valueListenable: MessageService.instance.conversations,
        builder: (context, list, _) {
          if (list.isEmpty) return const SizedBox.shrink();
          return FloatingActionButton(
            onPressed: () => _showNewMessageDialog(context),
            child: const Icon(LucideIcons.pencil),
          );
        },
      ),
    );
  }

  void _showNewMessageDialog(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final nicknameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.get('newMessage'), style: const TextStyle(fontFamily: 'NotoSansKR')),
        content: TextField(
            controller: nicknameController,
            decoration: InputDecoration(
              labelText: s.get('recipientNickname'),
              hintText: s.get('recipientNicknameHint'),
              border: const OutlineInputBorder(),
            ),
          autofocus: true,
          textCapitalization: TextCapitalization.none,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final name = nicknameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final conv = await MessageService.instance.startConversation(
                'user_${name.hashCode}',
                name,
              );
              if (!context.mounted) return;
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => MessageThreadScreen(
                    conversationId: conv.id,
                    otherUserName: conv.otherUserName,
                  ),
                ),
              );
            },
            child: Text(s.get('send')),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inDays > 0) return '${diff.inDays}일 전';
    if (diff.inHours > 0) return '${diff.inHours}시간 전';
    if (diff.inMinutes > 0) return '${diff.inMinutes}분 전';
    return '방금';
  }
}
