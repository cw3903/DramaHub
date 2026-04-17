import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/two_tab_segment_bar.dart';
import '../widgets/user_follow_button.dart';
import '../utils/post_board_utils.dart';
import 'post_detail_page.dart';

/// 특정 회원의 작성 글 + 댓글 (탭: Posts / Comments).
class UserPostsScreen extends StatefulWidget {
  const UserPostsScreen({
    super.key,
    required this.authorName,
    this.authorUid,
    this.initialSegment = 0,
    this.initialPosts,
    this.initialCommentItems,
  });

  /// 표시 대상 닉네임 (`u/` 있거나 없음). 글은 `u/닉네임`, 댓글 매칭은 베이스 닉네임.
  final String authorName;

  /// 설정 시 글·댓글을 `authorUid` 기준으로 로드 (닉네임과 `posts.author` 불일치 대비).
  final String? authorUid;

  /// 0: Posts, 1: Comments
  final int initialSegment;

  /// 프로필 통계 로드 시 이미 가져온 포스트 목록 — 있으면 로딩 없이 즉시 표시.
  final List<Post>? initialPosts;

  /// 프로필 통계 로드 시 이미 가져온 댓글 목록 — 있으면 로딩 없이 즉시 표시.
  final List<({Post post, PostComment comment})>? initialCommentItems;

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
    // 프로필에서 이미 로드된 데이터가 있으면 즉시 표시 (로딩 스피너 없음).
    if (widget.initialPosts != null) {
      _posts = widget.initialPosts!;
      _loading = false;
    }
    if (widget.initialCommentItems != null) {
      _commentItems = widget.initialCommentItems!;
      _loading = false;
    }
    _load(); // 최신 데이터로 백그라운드 갱신
    _resolveProfile();
  }

  String get _baseNickname {
    final a = widget.authorName.trim();
    return a.startsWith('u/') ? a.substring(2) : a;
  }

  String get _postAuthor => 'u/$_baseNickname';

  String _headerTitle(dynamic s) {
    final me = AuthService.instance.currentUser.value?.uid;
    final filterUid = widget.authorUid?.trim();
    if (filterUid != null &&
        filterUid.isNotEmpty &&
        me != null &&
        me == filterUid) {
      return s.get('userPostsListTitleSelf');
    }
    if (!_profileResolving && _isSelfProfile) {
      return s.get('userPostsListTitleSelf');
    }
    final name = _baseNickname.trim();
    if (name.isNotEmpty) {
      return s.get('userPostsListTitleOtherNamed').replaceAll('{name}', name);
    }
    return s.get('userPostsListTitleOther');
  }

  Future<void> _resolveProfile() async {
    final filterUid = widget.authorUid?.trim();
    if (filterUid != null && filterUid.isNotEmpty) {
      final me = AuthService.instance.currentUser.value?.uid;
      if (me == null) {
        if (mounted) setState(() => _profileResolving = false);
        return;
      }
      if (mounted) {
        setState(() {
          _isSelfProfile = me == filterUid;
          _targetUid = _isSelfProfile ? null : filterUid;
          _profileResolving = false;
        });
      }
      return;
    }
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
    // 초기 데이터가 없을 때만 로딩 스피너 표시. 있으면 백그라운드 갱신.
    final hasData = _posts.isNotEmpty || _commentItems.isNotEmpty;
    if (!hasData) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uidFilter = widget.authorUid?.trim();
      if (uidFilter != null && uidFilter.isNotEmpty) {
        // posts + comments 병렬 로드
        final results = await Future.wait([
          PostService.instance.getPostsByAuthorUid(uidFilter),
          PostService.instance.getCommentsByAuthorUid(uidFilter),
        ]);
        var posts = results[0] as List<Post>;
        var comments =
            results[1] as List<({Post post, PostComment comment})>;
        if (comments.isEmpty && _baseNickname.isNotEmpty) {
          comments =
              await PostService.instance.getCommentsByAuthor(_baseNickname);
        }
        if (mounted) {
          setState(() {
            _posts = posts;
            _commentItems = comments;
            _loading = false;
          });
        }
      } else {
        // posts + comments 병렬 로드
        final results = await Future.wait([
          PostService.instance.getPostsByAuthor(_postAuthor),
          PostService.instance.getCommentsByAuthor(_baseNickname),
        ]);
        if (mounted) {
          setState(() {
            _posts = results[0] as List<Post>;
            _commentItems =
                results[1] as List<({Post post, PostComment comment})>;
            _loading = false;
          });
        }
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

    final title = _headerTitle(s);

    return ListsStyleSwipeBack(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        itemCount: _posts.length,
        separatorBuilder: (context, _) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: cs.outline.withValues(alpha: isDark ? 0.30 : 0.22),
          );
        },
        itemBuilder: (context, index) {
          final post = _posts[index];
          final body = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
          final titleStyle = GoogleFonts.notoSansKr(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.8),
            height: 1.12,
          );
          final bodyStyle = GoogleFonts.notoSansKr(
            fontSize: 12.5,
            height: 1.45,
            color: cs.onSurfaceVariant.withValues(alpha: 0.88),
            fontWeight: FontWeight.w400,
          );
          final timeRowStyle = GoogleFonts.notoSansKr(
            fontSize: 11.5,
            height: 1.15,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          );
          final thumbUrl = _userPostsPreviewImageUrl(post);

          return Material(
            color: Colors.transparent,
            clipBehavior: Clip.none,
            child: InkWell(
              onTap: () async {
                final isReview = postDisplayType(post) == 'review';
                final result = await Navigator.push<PostDetailResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => isReview
                        ? PostDetailPage(
                            post: post,
                            hideBottomDramaFeed: true,
                            suppressLetterboxdCommentsSection: false,
                          )
                        : PostDetailPage(
                            post: post,
                            hideBelowLetterboxdLike: false,
                            suppressLetterboxdCommentsSection: false,
                          ),
                  ),
                );
                final updated = result?.updatedPost;
                if (updated != null && mounted) {
                  setState(() {
                    _posts =
                        _posts.map((p) => p.id == updated.id ? updated : p).toList();
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _UserPostsEllipsisText(
                                text: post.title,
                                style: titleStyle,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 2),
                              _UserPostsEllipsisText(
                                text: post.timeAgo,
                                style: timeRowStyle,
                                maxLines: 1,
                              ),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                _UserPostsEllipsisText(
                                  text: body,
                                  style: bodyStyle,
                                  maxLines: 2,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _UserPostsListThumb(imageUrl: thumbUrl, cs: cs),
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
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        itemCount: _commentItems.length,
        separatorBuilder: (context, _) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: cs.outline.withValues(alpha: isDark ? 0.30 : 0.22),
          );
        },
        itemBuilder: (context, index) {
          final item = _commentItems[index];
          final country = CountryScope.of(context).country;
          final commentBody = item.comment.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          final hasBody = commentBody.isNotEmpty;
          final titleStyle = GoogleFonts.notoSansKr(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.8),
            height: 1.12,
          );
          final bodyStyle = GoogleFonts.notoSansKr(
            fontSize: 12.5,
            height: 1.45,
            color: cs.onSurfaceVariant.withValues(alpha: 0.88),
            fontWeight: FontWeight.w400,
          );
          final timeRowStyle = GoogleFonts.notoSansKr(
            fontSize: 11.5,
            height: 1.15,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          );
          final thumbUrl = _userPostsPreviewImageUrl(item.post);

          return Material(
            color: Colors.transparent,
            clipBehavior: Clip.none,
            child: InkWell(
              onTap: () async {
                final p = item.post;
                final isReview = postDisplayType(p) == 'review';
                await Navigator.push<PostDetailResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => isReview
                        ? PostDetailPage(
                            post: p,
                            hideBottomDramaFeed: true,
                            suppressLetterboxdCommentsSection: false,
                          )
                        : PostDetailPage(
                            post: p,
                            suppressLetterboxdCommentsSection: false,
                          ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _UserPostsEllipsisText(
                            text: item.post.title,
                            style: titleStyle,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          _UserPostsEllipsisText(
                            text: item.comment.timeAgoLocalized(country),
                            style: timeRowStyle,
                            maxLines: 1,
                          ),
                          if (hasBody) ...[
                            const SizedBox(height: 3),
                            _UserPostsEllipsisText(
                              text: commentBody,
                              style: bodyStyle,
                              maxLines: 2,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _UserPostsListThumb(imageUrl: thumbUrl, cs: cs),
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

String? _userPostsPreviewImageUrl(Post post) {
  for (final raw in post.imageUrls) {
    final u = raw.trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
  }
  final v = post.videoThumbnailUrl?.trim();
  if (v != null &&
      v.isNotEmpty &&
      (v.startsWith('http://') || v.startsWith('https://'))) {
    return v;
  }
  final d = post.dramaThumbnail?.trim();
  if (d != null &&
      d.isNotEmpty &&
      (d.startsWith('http://') || d.startsWith('https://'))) {
    return d;
  }
  return null;
}

class _UserPostsEllipsisText extends StatelessWidget {
  const _UserPostsEllipsisText({
    required this.text,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  static const TextHeightBehavior _heightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        style: style,
        textAlign: TextAlign.start,
        textWidthBasis: TextWidthBasis.parent,
        textHeightBehavior: _heightBehavior,
      ),
    );
  }
}

class _UserPostsListThumb extends StatelessWidget {
  const _UserPostsListThumb({required this.imageUrl, required this.cs});

  final String? imageUrl;
  final ColorScheme cs;

  static const double thumbW = 48;

  @override
  Widget build(BuildContext context) {
    final thumbH = thumbW * 1.5;
    final u = imageUrl?.trim();
    if (u != null &&
        u.isNotEmpty &&
        (u.startsWith('http://') || u.startsWith('https://'))) {
      return SizedBox(
        width: thumbW,
        height: thumbH,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: OverflowBox(
            maxWidth: thumbW,
            maxHeight: thumbH,
            minWidth: thumbW,
            minHeight: thumbH,
            alignment: Alignment.center,
            child: CachedNetworkImage(
              imageUrl: u,
              fit: BoxFit.cover,
              width: thumbW,
              height: thumbH,
              errorWidget: (_, __, ___) => ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  LucideIcons.image,
                  size: 22,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: cs.surfaceContainerHighest,
        child: SizedBox(
          width: thumbW,
          height: thumbH,
          child: Icon(
            LucideIcons.file_text,
            size: 22,
            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}
