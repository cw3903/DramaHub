import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../widgets/user_follow_button.dart';
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
  bool _profileResolving = true;
  bool _isSelfProfile = false;
  String? _targetUid;

  @override
  void initState() {
    super.initState();
    _load();
    _resolveProfile();
  }

  String get _authorAsPost =>
      widget.authorName.startsWith('u/') ? widget.authorName : 'u/${widget.authorName}';

  String get _baseNickname =>
      widget.authorName.startsWith('u/') ? widget.authorName.substring(2) : widget.authorName;

  Future<void> _resolveProfile() async {
    final me = AuthService.instance.currentUser.value?.uid;
    if (me == null) {
      if (mounted) setState(() => _profileResolving = false);
      return;
    }
    await UserProfileService.instance.loadIfNeeded();
    final myAuthor = await UserProfileService.instance.getAuthorForPost();
    final isSelf = myAuthor == _authorAsPost;
    if (isSelf) {
      if (mounted) {
        setState(() {
          _isSelfProfile = true;
          _targetUid = null;
          _profileResolving = false;
        });
      }
      return;
    }
    final uid = await FollowService.instance.resolveUidByNickname(_baseNickname);
    if (mounted) {
      setState(() {
        _isSelfProfile = false;
        _targetUid = uid;
        _profileResolving = false;
      });
    }
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
        actions: [
          if (!_profileResolving && !_isSelfProfile && _targetUid != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: UserFollowButton(targetUid: _targetUid!, dense: true),
              ),
            ),
        ],
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
