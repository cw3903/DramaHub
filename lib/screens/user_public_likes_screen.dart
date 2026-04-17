import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../utils/post_board_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/feed_review_star_row.dart' show FeedReviewRatingStars;
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/two_tab_segment_bar.dart' show ThreeTabSegmentBar;
import 'post_detail_page.dart';

/// [FutureBuilder]용 — 레코드 typedef는 핫 리로드 시 이전 Future와 타입이 어긋날 수 있음.
class _PublicLikesFetchedData {
  const _PublicLikesFetchedData({
    required this.posts,
    required this.likedComments,
  });

  final List<Post> posts;
  final List<({Post post, PostComment comment})> likedComments;
}

/// 타 유저의 좋아요 목록 (읽기 전용).
class UserPublicLikesScreen extends StatefulWidget {
  const UserPublicLikesScreen({
    super.key,
    required this.uid,
    this.ownerDisplayName,
  });

  final String uid;
  final String? ownerDisplayName;

  @override
  State<UserPublicLikesScreen> createState() => _UserPublicLikesScreenState();
}

class _UserPublicLikesScreenState extends State<UserPublicLikesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Future<_PublicLikesFetchedData>? _future;
  String _localeKey = '';
  String? _lastFetchedUid;

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = CountryScope.maybeOf(context)?.country ?? '';
    final uid = widget.uid;
    if (_localeKey != loc || _lastFetchedUid != uid || _future == null) {
      _localeKey = loc;
      _lastFetchedUid = uid;
      _future = _fetch(loc);
    }
  }

  Future<_PublicLikesFetchedData> _fetch(String country) async {
    final uid = widget.uid;
    final posts = await PostService.instance.getPostsLikedByUid(
      uid,
      countryForTimeAgo: country,
    );
    final likedComments = await PostService.instance.getCommentsLikedByUid(
      uid,
      countryForTimeAgo: country,
    );
    return _PublicLikesFetchedData(posts: posts, likedComments: likedComments);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  String _headerTitle(dynamic s) {
    final name = widget.ownerDisplayName?.trim() ?? '';
    if (name.isNotEmpty) {
      return s.get('likesTitleWithName').replaceAll('{name}', name);
    }
    return s.get('likes');
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headerBg = listsStyleSubpageHeaderBackground(theme);

    return ListsStyleSwipeBack(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: listsStyleSubpageSystemOverlay(theme, headerBg),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: _headerTitle(s),
            onBack: () => popListsStyleSubpage(context),
          ),
        ),
        body: FutureBuilder<_PublicLikesFetchedData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data?.posts ?? [];
            final likedComments = snap.data?.likedComments ?? [];
            final viewedUid = widget.uid;
            final reviewsOnly = <Post>[];
            final postsOnly = <Post>[];
            for (final p in all) {
              if (viewedUid.isEmpty || !p.likedBy.contains(viewedUid)) continue;
              if (postDisplayType(p) == 'review') {
                reviewsOnly.add(p);
              } else {
                postsOnly.add(p);
              }
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
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _PostList(
                        posts: reviewsOnly,
                        emptyKey: 'likesEmptyReviews',
                        s: s,
                        cs: cs,
                        reviewsTab: true,
                      ),
                      _PostList(
                        posts: postsOnly,
                        emptyKey: 'likesEmptyPosts',
                        s: s,
                        cs: cs,
                        reviewsTab: false,
                      ),
                      _PublicLikedCommentsList(
                        items: likedComments,
                        s: s,
                        cs: cs,
                      ),
                    ],
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

class _PostList extends StatelessWidget {
  const _PostList({
    required this.posts,
    required this.emptyKey,
    required this.s,
    required this.cs,
    required this.reviewsTab,
  });

  final List<Post> posts;
  final String emptyKey;
  final dynamic s;
  final ColorScheme cs;
  final bool reviewsTab;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.heart,
                size: 56,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                s.get(emptyKey) as String,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
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
      itemBuilder: (ctx, i) => _PostRow(
        post: posts[i],
        cs: cs,
        reviewsTab: reviewsTab,
      ),
    );
  }
}

/// [likes_screen.dart] `_LikesListEllipsisText`와 동일 — Expanded 안에서 말줄임.
class _PublicLikesEllipsisText extends StatelessWidget {
  const _PublicLikesEllipsisText({
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

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.cs,
    required this.reviewsTab,
  });

  final Post post;
  final ColorScheme cs;
  final bool reviewsTab;

  @override
  Widget build(BuildContext context) {
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

    if (reviewsTab) {
      return _buildReviewRow(context, titleStyle, bodyStyle);
    }
    return _buildPostRow(context, titleStyle, bodyStyle, timeRowStyle);
  }

  Widget _buildReviewRow(
    BuildContext context,
    TextStyle titleStyle,
    TextStyle bodyStyle,
  ) {
    final thumb = post.dramaThumbnail?.trim();
    final hasHttp = thumb != null &&
        (thumb.startsWith('http://') || thumb.startsWith('https://'));
    final title = post.dramaTitle?.trim().isNotEmpty == true
        ? post.dramaTitle!.trim()
        : post.title;
    final rating = post.rating;
    final body = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

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
                    _PublicLikesEllipsisText(
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
                      _PublicLikesEllipsisText(
                        text: body,
                        style: bodyStyle,
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PublicLikesListThumb(
                imageUrl: hasHttp ? thumb : null,
                cs: cs,
                emptyIcon: LucideIcons.tv,
                errorIcon: LucideIcons.tv,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostRow(
    BuildContext context,
    TextStyle titleStyle,
    TextStyle bodyStyle,
    TextStyle timeRowStyle,
  ) {
    final body = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
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
                    _PublicLikesEllipsisText(
                      text: post.title,
                      style: titleStyle,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    _PublicLikesEllipsisText(
                      text: post.timeAgo,
                      style: timeRowStyle,
                      maxLines: 1,
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _PublicLikesEllipsisText(
                        text: body,
                        style: bodyStyle,
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PublicLikesListThumb(
                imageUrl: thumbUrl,
                cs: cs,
                emptyIcon: LucideIcons.file_text,
                errorIcon: LucideIcons.image,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _likedPostPreviewImageUrl(Post post) {
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
}

/// 리스트 행 썸네일 2:3 — [user_posts_screen] `_UserPostsListThumb`와 동일 패턴.
class _PublicLikesListThumb extends StatelessWidget {
  const _PublicLikesListThumb({
    required this.cs,
    required this.imageUrl,
    required this.emptyIcon,
    required this.errorIcon,
  });

  final ColorScheme cs;
  final String? imageUrl;
  final IconData emptyIcon;
  final IconData errorIcon;

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

/// [likes_screen.dart] `_LikedCommentsList`와 동일 레이아웃·썸네일 플레이스홀더.
class _PublicLikedCommentsList extends StatelessWidget {
  const _PublicLikedCommentsList({
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
                  s.get('likesEmptyComments') as String,
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
        final thumbUrl = _PostRow._likedPostPreviewImageUrl(item.post);

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
                        _PublicLikesEllipsisText(
                          text: item.post.title,
                          style: titleStyle,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        _PublicLikesEllipsisText(
                          text: item.comment.timeAgoLocalized(country),
                          style: timeRowStyle,
                          maxLines: 1,
                        ),
                        if (hasBody) ...[
                          const SizedBox(height: 3),
                          _PublicLikesEllipsisText(
                            text: commentBody,
                            style: bodyStyle,
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _PublicLikesListThumb(
                    imageUrl: thumbUrl,
                    cs: cs,
                    emptyIcon: LucideIcons.file_text,
                    errorIcon: LucideIcons.image,
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
