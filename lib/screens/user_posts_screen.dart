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
import '../utils/format_utils.dart';
import 'post_detail_page.dart';

/// 특정 회원이 쓴 글 목록 (닉네임 탭 → 작성글 보기)
class UserPostsScreen extends StatefulWidget {
  const UserPostsScreen({super.key, required this.authorName});

  final String authorName;

  @override
  State<UserPostsScreen> createState() => _UserPostsScreenState();
}

class _UserPostsScreenState extends State<UserPostsScreen> {
  List<Post> _posts = [];
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

  String get _postAuthor =>
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
    final isSelf = myAuthor == _postAuthor;
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
      final list = await PostService.instance.getPostsByAuthor(_postAuthor);
      if (mounted) {
        setState(() {
          _posts = list;
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
          '${s.get('viewUserPosts')} · ${widget.authorName.startsWith('u/') ? widget.authorName.substring(2) : widget.authorName}',
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
                : _posts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.file_text, size: 56, color: cs.onSurfaceVariant.withOpacity(0.4)),
                            const SizedBox(height: 16),
                            Text(
                              '${widget.authorName}님이 쓴 글이 없어요.',
                              style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          final post = _posts[index];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                final updated = await Navigator.push<Post>(
                                  context,
                                  MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
                                );
                                if (updated != null && mounted) {
                                  setState(() {
                                    _posts = _posts.map((p) => p.id == updated.id ? updated : p).toList();
                                  });
                                }
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
                                    Text(
                                      post.title,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(LucideIcons.message_circle, size: 14, color: AppColors.mediumGrey),
                                        const SizedBox(width: 4),
                                        Text(
                                          formatCompactCount(post.comments),
                                          style: GoogleFonts.notoSansKr(fontSize: 12, color: AppColors.mediumGrey),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(LucideIcons.eye, size: 14, color: AppColors.mediumGrey),
                                        const SizedBox(width: 4),
                                        Text(
                                          formatCompactCount(post.views),
                                          style: GoogleFonts.notoSansKr(fontSize: 12, color: AppColors.mediumGrey),
                                        ),
                                        const Spacer(),
                                        Text(
                                          post.timeAgo,
                                          style: GoogleFonts.notoSansKr(fontSize: 12, color: AppColors.mediumGrey),
                                        ),
                                      ],
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
