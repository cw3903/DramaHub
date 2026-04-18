import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/post_service.dart';
import '../utils/post_board_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/feed_review_star_row.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/two_tab_segment_bar.dart';
import 'login_page.dart';
import 'post_detail_page.dart';

/// Letterboxd Likes — [PostService.getPostsLikedByUid]만 사용 (프로필 › 리뷰 목록과 무관).
///
/// 탭 순서: 리뷰 → 포스트 → 코멘트.
/// - **리뷰** 탭: 좋아요한 글 중 `postDisplayType == review`인 것만 (피드에서 하트/좋아요 누른 리뷰 글).
/// - **포스트** 탭: 좋아요한 글 중 `postDisplayType`이 리뷰가 **아닌** 것.
/// - **코멘트** 탭: 좋아요한 댓글 ([PostService.getCommentsLikedByUid]).
class LikesScreen extends StatefulWidget {
  const LikesScreen({super.key});

  @override
  State<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;

    final headerBg = listsStyleSubpageHeaderBackground(theme);
    final overlay = listsStyleSubpageSystemOverlay(theme, headerBg);

    return ListsStyleSubpageHorizontalSwipeBack(
      onSwipePop: () => popListsStyleSubpage(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: s.get('likes'),
            onBack: () => popListsStyleSubpage(context),
          ),
        ),
        body: ValueListenableBuilder<User?>(
          valueListenable: AuthService.instance.currentUser,
          builder: (context, user, _) {
            if (user == null) {
              return _LoginPrompt(s: s, cs: cs);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ThreeTabSegmentBar(
                  selectedIndex: _tabController.index,
                  onSelect: (i) {
                    if (_tabController.index != i) {
                      _tabController.animateTo(i);
                    }
                  },
                  labelLeft: s.get('tabLikedReviews'),
                  labelMiddle: s.get('tabLikedPosts'),
                  labelRight: s.get('comments'),
                  colorScheme: cs,
                  brightness: theme.brightness,
                ),
                Expanded(
                  child: _LikesTabBody(
                    key: ValueKey(user.uid),
                    tabController: _tabController,
                    s: s,
                    cs: cs,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}

class _LikesTabBody extends StatefulWidget {
  const _LikesTabBody({
    super.key,
    required this.tabController,
    required this.s,
    required this.cs,
  });

  final TabController tabController;
  final dynamic s;
  final ColorScheme cs;

  @override
  State<_LikesTabBody> createState() => _LikesTabBodyState();
}

class _LikesTabBodyState extends State<_LikesTabBody> {
  List<Post> _likedPosts = [];
  List<({Post post, PostComment comment})>? _likedComments;

  /// 포스트 쿼리 대기 중이고 화면에 캐시도 없을 때만 상단 바 표시.
  bool _postsLoading = false;
  int _loadGen = 0;
  String _lastKickoffLocale = '';

  String _timeLocaleForFetch(BuildContext context) {
    return CountryScope.maybeOf(context)?.country ??
        LocaleService.instance.locale;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = _timeLocaleForFetch(context);
    if (_lastKickoffLocale == loc) return;
    _lastKickoffLocale = loc;
    unawaited(_loadLikesData(loc, usePeekCache: true));
  }

  /// 포스트는 즉시 그리고, 댓글은 `getCommentsLikedByUid`(전체 글 스캔) 끝나면 탭만 갱신.
  /// 프로필에서 [PostService.cacheLikedPostsForLikesScreen]이 있으면 첫 프레임부터 목록 표시.
  Future<void> _loadLikesData(String loc, {required bool usePeekCache}) async {
    _loadGen++;
    final gen = _loadGen;
    final uid = AuthService.instance.currentUser.value?.uid ?? '';

    if (uid.isEmpty) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _likedPosts = [];
        _likedComments = [];
        _postsLoading = false;
      });
      return;
    }

    if (usePeekCache) {
      final peek = PostService.instance.peekCachedLikedPostsForLikesScreen(uid);
      if (!mounted || gen != _loadGen) return;
      if (peek != null) {
        setState(() {
          _likedPosts = List<Post>.from(peek);
          _postsLoading = false;
          _likedComments = null;
        });
      } else {
        setState(() {
          _likedPosts = [];
          _postsLoading = true;
          _likedComments = null;
        });
      }
    } else {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _postsLoading = true;
        _likedComments = null;
      });
    }

    final postsFuture = PostService.instance.getPostsLikedByUid(
      uid,
      countryForTimeAgo: loc,
      hydrateViewerVotes: false,
    );
    final commentsFuture = PostService.instance.getCommentsLikedByUid(
      uid,
      countryForTimeAgo: loc,
    );

    postsFuture.then((posts) {
      if (!mounted || gen != _loadGen) return;
      PostService.instance.cacheLikedPostsForLikesScreen(uid, posts);
      setState(() {
        _likedPosts = posts;
        _postsLoading = false;
      });
    }).catchError((_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _likedPosts = [];
        _postsLoading = false;
      });
    });

    commentsFuture.then((comments) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _likedComments = comments;
      });
    }).catchError((_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _likedComments = [];
      });
    });

    if (!usePeekCache) {
      try {
        await Future.wait([postsFuture, commentsFuture]);
      } catch (_) {}
    }
  }

  Future<void> _onRefresh() async {
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    if (uid.isEmpty) return;
    final loc = _timeLocaleForFetch(context);
    _lastKickoffLocale = loc;
    await _loadLikesData(loc, usePeekCache: false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cs = widget.cs;
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    final postsOnly = <Post>[];
    final reviewsOnly = <Post>[];
    for (final p in _likedPosts) {
      if (uid.isEmpty || !p.likedBy.contains(uid)) continue;
      if (postDisplayType(p) == 'review') {
        reviewsOnly.add(p);
      } else {
        postsOnly.add(p);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_postsLoading && _likedPosts.isEmpty)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: TabBarView(
            controller: widget.tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              RefreshIndicator(
                onRefresh: _onRefresh,
                child: _LikedReviewsList(
                  posts: reviewsOnly,
                  s: s,
                  cs: cs,
                  emptyKey: 'likesEmptyReviews',
                ),
              ),
              RefreshIndicator(
                onRefresh: _onRefresh,
                child: _LikedPostsList(
                  posts: postsOnly,
                  s: s,
                  cs: cs,
                  emptyKey: 'likesEmptyPosts',
                ),
              ),
              RefreshIndicator(
                onRefresh: _onRefresh,
                child: _LikedCommentsList(
                  items: _likedComments,
                  s: s,
                  cs: cs,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.s, required this.cs});

  final dynamic s;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.heart,
              size: 56,
              color: cs.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              s.get('likesLoginRequired'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                );
              },
              child: Text(s.get('login')),
            ),
          ],
        ),
      ),
    );
  }
}

String? _likedPostPreviewImageUrl(Post post) {
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

/// Row › Expanded › Column 안에서도 가로 폭이 고정되어 `…` 말줄임이 적용되게 함.
class _LikesListEllipsisText extends StatelessWidget {
  const _LikesListEllipsisText({
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

/// 라이크 포스트·코멘츠·리뷰 행 오른쪽 썸네일(2:3).
class _LikedPostListThumb extends StatelessWidget {
  const _LikedPostListThumb({
    required this.imageUrl,
    required this.cs,
    this.errorIcon = LucideIcons.image,
    this.emptyIcon = LucideIcons.file_text,
  });

  final String? imageUrl;
  final ColorScheme cs;
  final IconData errorIcon;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    const double thumbW = 48;
    final double thumbH = thumbW * 1.5;
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
            minWidth: thumbW,
            maxWidth: thumbW,
            minHeight: thumbH,
            maxHeight: thumbH,
            alignment: Alignment.center,
            child: CachedNetworkImage(
              imageUrl: u,
              fit: BoxFit.cover,
              width: thumbW,
              height: thumbH,
              errorWidget: (_, __, ___) => ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  errorIcon,
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
            emptyIcon,
            size: 22,
            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _LikedPostsList extends StatelessWidget {
  const _LikedPostsList({
    required this.posts,
    required this.s,
    required this.cs,
    required this.emptyKey,
  });

  final List<Post> posts;
  final dynamic s;
  final ColorScheme cs;
  final String emptyKey;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  s.get(emptyKey),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      itemCount: posts.length,
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
      itemBuilder: (context, i) {
        final post = posts[i];
        final body = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        final titleAlpha = 0.8;
        final titleStyle = GoogleFonts.notoSansKr(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: cs.onSurface.withValues(alpha: titleAlpha.clamp(0.0, 1.0)),
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
        final thumbUrl = _likedPostPreviewImageUrl(post);

        return Material(
          color: Colors.transparent,
          clipBehavior: Clip.none,
          child: InkWell(
            onTap: () {
              Navigator.push<void>(
                context,
                CupertinoPageRoute<void>(
                  builder: (_) => PostDetailPage(post: post),
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
                        _LikesListEllipsisText(
                          text: post.title,
                          style: titleStyle,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        _LikesListEllipsisText(
                          text: post.timeAgo,
                          style: timeRowStyle,
                          maxLines: 1,
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _LikesListEllipsisText(
                            text: body,
                            style: bodyStyle,
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _LikedPostListThumb(imageUrl: thumbUrl, cs: cs),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 좋아요한 **리뷰 게시글**만 (`_LikesTabBody`에서 `likedBy`·`postDisplayType` 검증 후 전달).
/// 레이아웃만 프로필 › 리뷰 목록과 유사할 뿐, 데이터는 [ReviewService] / 내 리뷰와 무관.
class _LikedReviewsList extends StatelessWidget {
  const _LikedReviewsList({
    required this.posts,
    required this.s,
    required this.cs,
    required this.emptyKey,
  });

  final List<Post> posts;
  final dynamic s;
  final ColorScheme cs;
  final String emptyKey;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  s.get(emptyKey),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      itemCount: posts.length,
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
      itemBuilder: (context, i) {
        final post = posts[i];
        final thumb = post.dramaThumbnail?.trim();
        final hasHttp =
            thumb != null &&
            (thumb.startsWith('http://') || thumb.startsWith('https://'));
        final title = post.dramaTitle?.trim().isNotEmpty == true
            ? post.dramaTitle!.trim()
            : post.title;
        final rating = post.rating;
        final body = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        final titleAlpha = 0.8;
        final titleStyle = GoogleFonts.notoSansKr(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: cs.onSurface.withValues(alpha: titleAlpha.clamp(0.0, 1.0)),
          height: 1.12,
        );
        final bodyStyle = GoogleFonts.notoSansKr(
          fontSize: 12.5,
          height: 1.45,
          color: cs.onSurfaceVariant.withValues(alpha: 0.88),
          fontWeight: FontWeight.w400,
        );

        // 홈 DramaFeed Letterboxd와 동일 — [FeedReviewRatingStars], layoutThumbWidth 62.
        final Widget starBlock = (rating != null && rating > 0)
            ? FeedReviewRatingStars(rating: rating, layoutThumbWidth: 62)
            : Text(
                '—',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              );

        return Material(
          color: Colors.transparent,
          clipBehavior: Clip.none,
          child: InkWell(
            onTap: () {
              Navigator.push<void>(
                context,
                CupertinoPageRoute<void>(
                  builder: (_) => PostDetailPage(
                    post: post,
                    hideBottomDramaFeed: true,
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
                        _LikesListEllipsisText(
                          text: title,
                          style: titleStyle,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: starBlock,
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _LikesListEllipsisText(
                            text: body,
                            style: bodyStyle,
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _LikedPostListThumb(
                    imageUrl: hasHttp ? thumb : null,
                    cs: cs,
                    errorIcon: LucideIcons.tv,
                    emptyIcon: LucideIcons.tv,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LikedCommentsList extends StatelessWidget {
  const _LikedCommentsList({
    required this.items,
    required this.s,
    required this.cs,
  });

  /// null: 아직 로딩 중(포스트는 이미 표시 가능).
  final List<({Post post, PostComment comment})>? items;
  final dynamic s;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (items == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    }
    final rows = items!;
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  s.get('likesEmptyComments'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      itemCount: rows.length,
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
        final item = rows[index];
        final country = CountryScope.of(context).country;
        final commentBody = item.comment.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final hasBody = commentBody.isNotEmpty;
        const titleAlpha = 0.8;
        final titleStyle = GoogleFonts.notoSansKr(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: cs.onSurface.withValues(alpha: titleAlpha.clamp(0.0, 1.0)),
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
        final thumbUrl = _likedPostPreviewImageUrl(item.post);

        return Material(
          color: Colors.transparent,
          clipBehavior: Clip.none,
          child: InkWell(
            onTap: () {
              Navigator.push<void>(
                context,
                CupertinoPageRoute<void>(
                  builder: (_) => PostDetailPage(post: item.post),
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
                        _LikesListEllipsisText(
                          text: item.post.title,
                          style: titleStyle,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        _LikesListEllipsisText(
                          text: item.comment.timeAgoLocalized(country),
                          style: timeRowStyle,
                          maxLines: 1,
                        ),
                        if (hasBody) ...[
                          const SizedBox(height: 3),
                          _LikesListEllipsisText(
                            text: commentBody,
                            style: bodyStyle,
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _LikedPostListThumb(imageUrl: thumbUrl, cs: cs),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
