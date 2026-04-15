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
import '../widgets/optimized_network_image.dart';
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
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

typedef _LikesFetched = ({
  List<Post> likedPosts,
  List<({Post post, PostComment comment})> likedComments,
});

class _LikesTabBodyState extends State<_LikesTabBody> {
  Future<_LikesFetched>? _dataFuture;

  /// 상대 시간 문자열에 쓴 로케(us/kr/jp/cn). 언어 변경 시 다시 불러오기 위해 추적.
  String _timeLocaleKey = '';

  String _timeLocaleForFetch(BuildContext context) {
    return CountryScope.maybeOf(context)?.country ??
        LocaleService.instance.locale;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = _timeLocaleForFetch(context);
    if (_timeLocaleKey != loc || _dataFuture == null) {
      _timeLocaleKey = loc;
      _dataFuture = _fetch(loc);
    }
  }

  Future<_LikesFetched> _fetch(String countryForTimeAgo) async {
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    if (uid.isEmpty) {
      return (
        likedPosts: <Post>[],
        likedComments: <({Post post, PostComment comment})>[],
      );
    }
    final likedPosts = await PostService.instance.getPostsLikedByUid(
      uid,
      countryForTimeAgo: countryForTimeAgo,
    );
    final likedComments = await PostService.instance.getCommentsLikedByUid(
      uid,
      countryForTimeAgo: countryForTimeAgo,
    );
    return (likedPosts: likedPosts, likedComments: likedComments);
  }

  Future<void> _onRefresh() async {
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    if (uid.isEmpty) return;
    final loc = _timeLocaleForFetch(context);
    setState(() {
      _timeLocaleKey = loc;
      _dataFuture = _fetch(loc);
    });
    await _dataFuture;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cs = widget.cs;

    return FutureBuilder<_LikesFetched>(
      future: _dataFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data;
        final all = data?.likedPosts ?? [];
        final likedComments = data?.likedComments ?? [];
        final uid = AuthService.instance.currentUser.value?.uid ?? '';
        final postsOnly = <Post>[];
        final reviewsOnly = <Post>[];
        for (final p in all) {
          // 쿼리는 likedBy 기준이지만, 탭 분류 전에 한 번 더 확인 (리뷰 탭 = 내가 좋아요한 리뷰 글만).
          if (uid.isEmpty || !p.likedBy.contains(uid)) continue;
          if (postDisplayType(p) == 'review') {
            reviewsOnly.add(p);
          } else {
            postsOnly.add(p);
          }
        }

        return TabBarView(
          controller: widget.tabController,
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
              child: _LikedCommentsList(items: likedComments, s: s, cs: cs),
            ),
          ],
        );
      },
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

/// 라이크 포스트·코멘츠 행 오른쪽 썸네일(48×72, 리뷰 탭 드라마 썸네일과 동일 비율).
class _LikedPostListThumb extends StatelessWidget {
  const _LikedPostListThumb({required this.imageUrl, required this.cs});

  final String? imageUrl;
  final ColorScheme cs;

  static const double _w = 48;
  static const double _h = 72;

  @override
  Widget build(BuildContext context) {
    final u = imageUrl?.trim();
    if (u != null &&
        u.isNotEmpty &&
        (u.startsWith('http://') || u.startsWith('https://'))) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: _w,
          height: _h,
          child: OptimizedNetworkImage(
            imageUrl: u,
            width: _w,
            height: _h,
            fit: BoxFit.cover,
            memCacheWidth: 160,
            memCacheHeight: 240,
            errorWidget: ColoredBox(
              color: cs.surfaceContainerHighest,
              child: Icon(
                LucideIcons.image,
                size: 22,
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
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
          width: _w,
          height: _h,
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
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: cs.outline.withValues(alpha: 0.12),
      ),
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
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: cs.outline.withValues(alpha: 0.12),
      ),
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
        const thumbW = 48.0;
        const thumbH = 72.0;
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: thumbW,
                      height: thumbH,
                      child: hasHttp
                          ? OptimizedNetworkImage(
                              imageUrl: thumb,
                              width: thumbW,
                              height: thumbH,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                              memCacheHeight: 240,
                              errorWidget: ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  LucideIcons.tv,
                                  size: 22,
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                            )
                          : ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                LucideIcons.tv,
                                size: 22,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                    ),
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

  final List<({Post post, PostComment comment})> items;
  final dynamic s;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
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
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: cs.outline.withValues(alpha: 0.12),
      ),
      itemBuilder: (context, index) {
        final item = items[index];
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
