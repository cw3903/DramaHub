import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import 'post_detail_page.dart';

/// 특정 회원이 쓴 댓글 목록 (닉네임 탭 → 작성댓글 보기)
class UserCommentsScreen extends StatefulWidget {
  const UserCommentsScreen({super.key, required this.authorName});

  final String authorName;

  @override
  State<UserCommentsScreen> createState() => _UserCommentsScreenState();
}

class _UserCommentsScreenState extends State<UserCommentsScreen> {
  List<({Post post, PostComment comment})> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await PostService.instance.getCommentsByAuthor(widget.authorName);
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
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
          '${s.get('viewUserComments')} · ${widget.authorName}',
          style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        style: GoogleFonts.notoSansKr(color: cs.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.message_circle, size: 56, color: cs.onSurfaceVariant.withOpacity(0.4)),
                            const SizedBox(height: 16),
                            Text(
                              '${widget.authorName}님이 쓴 댓글이 없어요.',
                              style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final commentText = item.comment.text;
                          final snippet = commentText.length > 80 ? '${commentText.substring(0, 80)}...' : commentText;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                await Navigator.push<Post>(
                                  context,
                                  MaterialPageRoute(builder: (_) => PostDetailPage(post: item.post)),
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: cs.outline.withOpacity(0.12)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(LucideIcons.file_text, size: 14, color: cs.primary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            item.post.title,
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      snippet,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.comment.timeAgo,
                                      style: GoogleFonts.notoSansKr(fontSize: 12, color: AppColors.mediumGrey),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
