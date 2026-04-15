import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/two_tab_segment_bar.dart';
import '../widgets/user_follow_button.dart';
import '../utils/format_utils.dart';
import 'post_detail_page.dart';

/// 특정 회원의 작성 글 + 댓글 (탭: Posts / Comments).
class UserPostsScreen extends StatefulWidget {
  const UserPostsScreen({
    super.key,
    required this.authorName,
    this.initialSegment = 0,
  });

  /// 표시 대상 닉네임 (`u/` 있거나 없음). 글은 `u/닉네임`, 댓글 매칭은 베이스 닉네임.
  final String authorName;

  /// 0: Posts, 1: Comments
  final int initialSegment;

  @override
  State<UserPostsScreen> createState() => _UserPostsScreenState();
}

class _UserPostsScreenState extends State<UserPostsScreen> {
  List<Post> _posts = [];
  List<({Post post, PostComment comment})> _commentItems = [];
  bool _loading = true;
  String? _error;
  bool _profileResolving = true;
  bool _isSelfProfile = false;
  String? _targetUid;
  late int _segment;

  @override
  void initState() {
    super.initState();
    _segment = widget.initialSegment.clamp(0, 1);
    _load();
    _resolveProfile();
  }

  String get _baseNickname {
    final a = widget.authorName.trim();
    return a.startsWith('u/') ? a.substring(2) : a;
  }

  String get _postAuthor => 'u/$_baseNickname';

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
      final posts = await PostService.instance.getPostsByAuthor(_postAuthor);
      final comments =
          await PostService.instance.getCommentsByAuthor(_baseNickname);
      if (mounted) {
        setState(() {
          _posts = posts;
          _commentItems = comments;
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
    final brightness = theme.brightness;

    final headerBg = listsStyleSubpageHeaderBackground(theme);
    final trailing = (!_profileResolving && !_isSelfProfile && _targetUid != null)
        ? UserFollowButton(targetUid: _targetUid!, dense: true)
        : null;

    final title = !_profileResolving && _isSelfProfile
        ? s.get('userPostsListTitleSelf')
        : s.get('userPostsListTitleOther');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: listsStyleSubpageSystemOverlay(theme, headerBg),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: title,
            onBack: () => popListsStyleSubpage(context),
            trailing: trailing,
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.25,
                        ),
                        Text(
                          _error!,
                          style: GoogleFonts.notoSansKr(color: cs.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TwoTabSegmentBar(
                        selectedIndex: _segment,
                        onSelect: (i) => setState(() => _segment = i),
                        labelLeft: s.get('userPostsTabPosts'),
                        labelRight: s.get('comments'),
                        colorScheme: cs,
                        brightness: brightness,
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _segment,
                          children: [
                            _buildPostsTab(context, s, cs),
                            _buildCommentsTab(context, s, cs),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildPostsTab(BuildContext context, dynamic s, ColorScheme cs) {
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Icon(
              LucideIcons.file_text,
              size: 56,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                s.get('userPostsEmptyPosts').replaceAll('{name}', _baseNickname),
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final result = await Navigator.push<PostDetailResult>(
                  context,
                  MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
                );
                final updated = result?.updatedPost;
                if (updated != null && mounted) {
                  setState(() {
                    _posts =
                        _posts.map((p) => p.id == updated.id ? updated : p).toList();
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
                  border: Border.all(
                    color: cs.outline.withValues(alpha: 0.12),
                  ),
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
                        Icon(LucideIcons.message_circle,
                            size: 14, color: AppColors.mediumGrey),
                        const SizedBox(width: 4),
                        Text(
                          formatCompactCount(post.comments),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: AppColors.mediumGrey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(LucideIcons.eye, size: 14, color: AppColors.mediumGrey),
                        const SizedBox(width: 4),
                        Text(
                          formatCompactCount(post.views),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: AppColors.mediumGrey,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          post.timeAgo,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: AppColors.mediumGrey,
                          ),
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
    );
  }

  Widget _buildCommentsTab(BuildContext context, dynamic s, ColorScheme cs) {
    if (_commentItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Icon(
              LucideIcons.message_circle,
              size: 56,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                s.get('userPostsEmptyComments')
                    .replaceAll('{name}', _baseNickname),
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: _commentItems.length,
        itemBuilder: (context, index) {
          final item = _commentItems[index];
          final commentText = item.comment.text;
          final snippet = commentText.length > 80
              ? '${commentText.substring(0, 80)}...'
              : commentText;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await Navigator.push<PostDetailResult>(
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
                  border: Border.all(
                    color: cs.outline.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.post.title,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: AppColors.mediumGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
