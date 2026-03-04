import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../widgets/country_scope.dart';

/// 쪽지 대화 스레드 (채팅 UI)
class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
  });

  final String conversationId;
  final String otherUserName;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String _myId = AuthService.instance.currentUser.value?.uid ?? 'me';

  @override
  void initState() {
    super.initState();
    MessageService.instance.markConversationRead(widget.conversationId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    MessageService.instance.sendMessage(widget.conversationId, text);
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.otherUserName,
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<String?>(
              valueListenable: MessageService.instance.conversationUpdated,
              builder: (context, updatedId, _) {
                final messages = MessageService.instance.getMessages(widget.conversationId);
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      s.get('noConversationsHint'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == _myId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment:
                            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe)
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: cs.surfaceContainerHighest,
                              child: Text(
                                widget.otherUserName.isNotEmpty
                                    ? widget.otherUserName.substring(0, 1).toUpperCase()
                                    : '?',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          if (!isMe) const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.text,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 15,
                                      color: isMe
                                          ? cs.onPrimaryContainer
                                          : cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(msg.sentAt),
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 11,
                                      color: (isMe
                                              ? cs.onPrimaryContainer
                                              : cs.onSurfaceVariant)
                                          .withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isMe) const SizedBox(width: 8),
                          if (isMe)
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: cs.primary,
                              child: Icon(
                                LucideIcons.user,
                                size: 18,
                                color: cs.onPrimary,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outline.withOpacity(0.2))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: s.get('typeMessage'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(LucideIcons.send, size: 22),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime at) {
    final h = at.hour;
    final m = at.minute;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
