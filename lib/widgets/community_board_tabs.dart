import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_profile_avatar_size.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/feed_review_post_card.dart';
import '../widgets/feed_review_letterboxd_tile.dart';
import '../widgets/feed_inline_action_colors.dart';
import '../widgets/review_card_tap_highlight.dart';
import '../widgets/blind_refresh_indicator.dart';
import '../widgets/optimized_network_image.dart';
import '../screens/community_search_page.dart';
import '../screens/drama_detail_page.dart';
import '../screens/drama_watchers_screen.dart';
import '../screens/drama_reviews_list_screen.dart';
import '../screens/login_page.dart';
import '../services/drama_list_service.dart';
import '../models/drama.dart';
import 'talk_ask_feed_list_row.dart';

const int _postsPerPage = 20;

/// 리뷰 인라인 댓글 렌더링용 flatten 엔트리(depth 보존)
/// depth 0: 루트 댓글, depth 1+: 대댓글
class _InlineReviewCommentEntry {
  const _InlineReviewCommentEntry({required this.comment, required this.depth});

  final PostComment comment;
  final int depth;
}

/// 하단 네비 바만 겹치지 않을 정도의 여백 (과한 빈 공간 방지)
double _listBottomPadding(BuildContext context) =>
    48 + MediaQuery.of(context).padding.bottom;

enum PostSearchScope { titleAndBody, title, body, comment, nickname }

const List<PostSearchScope> postSearchScopeOrder = [
  PostSearchScope.titleAndBody,
  PostSearchScope.title,
  PostSearchScope.body,
  PostSearchScope.comment,
  PostSearchScope.nickname,
];

String postSearchScopeLabel(PostSearchScope s, BuildContext context) {
  final str = CountryScope.of(context).strings;
  switch (s) {
    case PostSearchScope.titleAndBody:
      return str.get('searchScopeTitleAndBody');
    case PostSearchScope.title:
      return str.get('searchScopeTitle');
    case PostSearchScope.body:
      return str.get('searchScopeBody');
    case PostSearchScope.comment:
      return str.get('searchScopeComment');
    case PostSearchScope.nickname:
      return str.get('searchScopeNickname');
  }
}

bool commentContainsQuery(PostComment c, String q) {
  if (c.text.toLowerCase().contains(q)) return true;
  return c.replies.any((r) => commentContainsQuery(r, q));
}

/// 레이아웃은 [visual]과 동일, 터치만 [outsets]만큼 확장. 스플래시/하이라이트 없음.
/// [top] 확장은 금지(본문·별점 행으로 히트가 넘어가 하트만 먹는 현상 방지).
Widget reviewInlineActionHitTarget({
  required VoidCallback onTap,
  required Widget visual,
  EdgeInsets outsets = const EdgeInsets.fromLTRB(18, 0, 18, 8),
}) {
  return Stack(
    clipBehavior: Clip.none,
    fit: StackFit.passthrough,
    alignment: Alignment.center,
    children: [
      Positioned(
        left: -outsets.left,
        top: -outsets.top,
        right: -outsets.right,
        bottom: -outsets.bottom,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: const SizedBox.expand(),
        ),
      ),
      IgnorePointer(child: visual),
    ],
  );
}

/// 인기글 탭 - 홈탭/글상세 공통
class PopularPostsTab extends StatefulWidget {
  const PopularPostsTab({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.onRefresh,
    this.error,
    this.currentUserAuthor,
    this.onPostUpdated,
    this.onPostDeleted,
    this.onPostTap,
    this.onUserBlocked,
    this.enablePullToRefresh = true,
    this.shrinkWrap = false,
    this.useReviewLayout = false,
    this.listTabLabel,

    /// [useReviewLayout]이 true일 때만 적용. 커뮤니티 홈 Reviews 탭 Letterboxd 스타일.
    this.useLetterboxdReviewLayout = false,

    /// true면 피드 내 검색·페이지네이션 숨기고 [feedScrollController]로 무한 스크롤
    this.useSimpleFeedLayout = false,
    this.feedScrollController,
    this.feedLoadingMore = false,
    this.feedHasMore = true,
    this.reviewLetterboxdInlineFeed = false,
    this.feedAuthorAvatarSize,
  });

  final List<Post> posts;
  final bool isLoading;
  final String? error;
  final String? currentUserAuthor;
  final Future<void> Function() onRefresh;

  /// 글상세 DramaFeed 섹션에서는 false로 설정
  final bool enablePullToRefresh;

  /// 글상세에서 상위 스크롤과 연동하려면 true (중첩 스크롤 방지)
  final bool shrinkWrap;
  final void Function(Post)? onPostUpdated;
  final void Function(Post)? onPostDeleted;
  final void Function(Post)? onPostTap;
  final VoidCallback? onUserBlocked;

  /// true면 리뷰 전용 카드·빈 화면 문구
  final bool useReviewLayout;

  /// Feed 카드에 넘기는 탭 이름 (저장/공유 등). null이면 리뷰 레이아웃일 때 tabReviews, 아니면 tabHot
  final String? listTabLabel;

  /// true면 `type == 'review'` 게시글을 구분선 리스트(Letterboxd 스타일)로 표시
  final bool useLetterboxdReviewLayout;
  final bool useSimpleFeedLayout;
  final ScrollController? feedScrollController;
  final bool feedLoadingMore;
  final bool feedHasMore;
  final bool reviewLetterboxdInlineFeed;

  /// 글 상세 DramaFeed: 피드 카드 작성자 아바타 직경. null이면 카드 기본.
  final double? feedAuthorAvatarSize;

  @override
  State<PopularPostsTab> createState() => _PopularPostsTabState();
}

class _PopularPostsTabState extends State<PopularPostsTab> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageInputController = TextEditingController();
  final GlobalKey _filterKey = GlobalKey();
  int _currentPage = 0;
  String _searchQuery = '';
  bool _showPageInput = false;
  PostSearchScope _searchScope = PostSearchScope.titleAndBody;
  Timer? _debounce;

  // 필터 캐시
  List<Post>? _cachedFiltered;
  List<Post>? _lastPosts;
  String? _lastSearchQuery;
  PostSearchScope? _lastSearchScope;

  /// 낙관적 업데이트용 로컬 재정의 맵. 키: post.id, 값: 낙관적 Post.
  /// 부모 setState로 같은 리스트 인스턴스 요소만 교체될 때 캐시 문제를 우회.
  final Map<String, Post> _localOverrides = {};
  Map<String, Post>? _postsCache;
  List<Post>? _postsCacheSource;

  final Set<String> _inlineLikeBusy = {};
  final Set<String> _inlineCommentSubmitting = {};

  /// 리뷰 본문 탭 시 아래에 댓글 목록 펼침(Letterboxd 인라인 피드).
  final Set<String> _expandedReviewComments = {};
  final Map<String, TextEditingController> _inlineCommentControllers = {};
  final Map<String, FocusNode> _inlineCommentFocusNodes = {};

  /// 인라인 댓글 좋아요 상태: postId → commentId → (liked, count)
  final Map<String, Map<String, ({bool liked, int count})>>
  _inlineCommentLikeState = {};

  /// 인라인 댓글 답글 대상: postId → commentId
  final Map<String, String?> _inlineReplyingToCommentId = {};

  /// 인라인 댓글 답글 대상 객체: postId → PostComment
  final Map<String, PostComment?> _inlineReplyingToComment = {};
  /// 인라인 댓글 답글 펼침 상태: postId → 펼친 parent comment ids
  final Map<String, Set<String>> _inlineExpandedReplyThreads = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
  }

  void _onSearchTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(PopularPostsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 부모가 widget.posts 리스트를 제자리(in-place) 수정한 경우 identical() 체크가
    // 캐시를 재구성하지 않아 stale 데이터가 반환되는 버그를 방지.
    // 위젯이 갱신될 때마다 무효화해 항상 최신 목록으로 재구성한다.
    _postsCacheSource = null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _inlineCommentControllers.values) {
      c.dispose();
    }
    _inlineCommentControllers.clear();
    for (final n in _inlineCommentFocusNodes.values) {
      n.dispose();
    }
    _inlineCommentFocusNodes.clear();
    _searchController.dispose();
    _pageInputController.dispose();
    super.dispose();
  }

  Map<String, Post> get _postsById {
    // 포스트 리스트가 바뀐 경우에만 캐시 재구성
    if (!identical(_postsCacheSource, widget.posts)) {
      _postsCacheSource = widget.posts;
      _postsCache = {for (final p in widget.posts) p.id: p};
    }
    return _postsCache!;
  }

  /// 낙관적 재정의 우선, 그 다음 캐시된 맵, 없으면 [p] 그대로.
  Post _latestPost(Post p) => _localOverrides[p.id] ?? _postsById[p.id] ?? p;

  Future<void> _refreshPostForComments(String postId) async {
    final locale = CountryScope.maybeOf(context)?.country;
    final fresh = await PostService.instance.getPost(postId, locale);
    if (!mounted) return;
    if (fresh != null) widget.onPostUpdated?.call(fresh);
  }

  Future<void> _inlineToggleLike(Post post) async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return;

    // 현재 상태(낙관적 재정의 포함)에서 최신 Post 가져오기.
    final p = _latestPost(post);
    final liked = p.likedBy.contains(uid);
    final currentVote = liked ? 1 : (p.dislikedBy.contains(uid) ? -1 : 0);

    // 낙관적 업데이트 — 네트워크 응답 전에 즉시 반영.
    final newLikedBy = List<String>.from(p.likedBy);
    if (!liked) {
      if (!newLikedBy.contains(uid)) newLikedBy.add(uid);
    } else {
      newLikedBy.remove(uid);
    }
    final likeVoteDelta = !liked ? (p.dislikedBy.contains(uid) ? 2 : 1) : -1;
    var nextLikeCount = p.likeCount;
    var nextDislikeCount = p.dislikeCount;
    if (!liked) {
      if (p.dislikedBy.contains(uid))
        nextDislikeCount = (nextDislikeCount - 1).clamp(0, 999999);
      nextLikeCount += 1;
    } else {
      nextLikeCount = (nextLikeCount - 1).clamp(0, 999999);
    }
    final optimistic = p.copyWith(
      votes: p.votes + likeVoteDelta,
      likedBy: newLikedBy,
      dislikedBy: !liked
          ? p.dislikedBy.where((u) => u != uid).toList()
          : p.dislikedBy,
      likeCount: nextLikeCount,
      dislikeCount: nextDislikeCount,
    );
    // 로컬 재정의에 먼저 저장해 다음 탭이 최신 낙관 상태를 즉시 참조.
    _localOverrides[p.id] = optimistic;
    widget.onPostUpdated?.call(optimistic);

    // 이전 요청이 아직 진행 중이면 Firestore 호출 중복 방지만 하고 UI는 이미 업데이트.
    if (_inlineLikeBusy.contains(p.id)) return;
    _inlineLikeBusy.add(p.id);

    // 마지막 낙관 상태를 실제로 서버에 반영(연속 탭 시 마지막 상태만 전송).
    await Future.delayed(Duration.zero); // microtask 경계: 연속 탭 배칭.
    if (!mounted) {
      _inlineLikeBusy.remove(p.id);
      return;
    }
    // 가장 최근 낙관 상태를 다시 참조해 서버로 전송.
    final latest = _localOverrides[p.id] ?? optimistic;
    final latestLiked = latest.likedBy.contains(uid);
    final latestVote = latestLiked
        ? 1
        : (latest.dislikedBy.contains(uid) ? -1 : 0);

    final ok = await PostService.instance.togglePostLike(
      p.id,
      currentVoteState: latestVote,
      postAuthorUid: p.authorUid,
      postTitle: p.title,
    );
    _inlineLikeBusy.remove(p.id);
    if (!mounted) return;
    if (ok == null) {
      // 실패 시 서버에서 최신 상태 복원.
      _localOverrides.remove(p.id);
      final loc = CountryScope.maybeOf(context)?.country;
      final re = await PostService.instance.getPost(p.id, loc);
      if (re != null && mounted) widget.onPostUpdated?.call(re);
    } else {
      // 성공 시 로컬 재정의 제거(부모 상태가 곧 업데이트됨).
      _localOverrides.remove(p.id);
    }
  }

  /// 인라인 댓글 좋아요 토글 (낙관적 업데이트)
  Future<void> _toggleInlineCommentLike(Post post, PostComment comment) async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    final postId = post.id;
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    final map = _inlineCommentLikeState.putIfAbsent(postId, () => {});
    final cur = map[comment.id];
    final wasLiked = cur?.liked ?? comment.likedBy.contains(uid);
    final prevCount = cur?.count ?? comment.votes;
    setState(() {
      map[comment.id] = (
        liked: !wasLiked,
        count: wasLiked ? (prevCount - 1).clamp(0, 99999) : prevCount + 1,
      );
    });
    final updated = await PostService.instance.toggleCommentLike(
      postId,
      comment.id,
    );
    if (!mounted) return;
    if (updated != null) {
      _localOverrides[postId] = updated;
      final fresh = PostService.findCommentById(
        updated.commentsList,
        comment.id,
      );
      if (fresh != null && mounted) {
        setState(() {
          map[comment.id] = (
            liked: fresh.likedBy.contains(uid),
            count: fresh.votes,
          );
        });
      }
    }
  }

  FocusNode _inlineComposerFocus(String postId) =>
      _inlineCommentFocusNodes.putIfAbsent(postId, FocusNode.new);

  /// 인라인 댓글 답글 시작
  void _startInlineReply(Post post, PostComment comment) {
    final id = post.id;
    _inlineCommentControllers.putIfAbsent(id, TextEditingController.new);
    _inlineComposerFocus(id);
    setState(() {
      _inlineReplyingToCommentId[id] = comment.id;
      _inlineReplyingToComment[id] = comment;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineCommentFocusNodes[id]?.requestFocus();
    });
  }

  Future<void> _submitInlineComment(
    Post post, {
    BuildContext? successPopContext,
  }) async {
    final id = post.id;
    final ctrl = _inlineCommentControllers[id];
    if (ctrl == null) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    if (_inlineCommentSubmitting.contains(id)) return;
    setState(() => _inlineCommentSubmitting.add(id));
    final s = CountryScope.of(context).strings;
    final author = await UserProfileService.instance.getAuthorBaseName();
    if (!mounted) return;
    final p = _latestPost(post);
    final ctry = p.country?.trim().isNotEmpty == true
        ? p.country!.trim()
        : LocaleService.instance.locale;
    final newComment = PostComment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: author,
      timeAgo: s.get('timeAgoJustNow'),
      text: text,
      votes: 0,
      replies: const [],
      authorPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
      authorAvatarColorIndex:
          UserProfileService.instance.avatarColorNotifier.value,
      createdAtDate: DateTime.now(),
      authorUid: AuthService.instance.currentUser.value?.uid,
      country: Post.normalizeFeedCountry(ctry),
    );

    final parentId = _inlineReplyingToCommentId[id];
    String? err;
    List<PostComment> newComments;
    int newCount;

    if (parentId != null && parentId.isNotEmpty) {
      err = await PostService.instance.addReply(id, parentId, newComment);
      if (!mounted) return;
      if (err != null) {
        setState(() => _inlineCommentSubmitting.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err, style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final parent = PostService.findCommentById(p.commentsList, parentId);
      if (parent != null) {
        final updated = PostComment(
          id: parent.id,
          author: parent.author,
          timeAgo: parent.timeAgo,
          text: parent.text,
          votes: parent.votes,
          replies: [...parent.replies, newComment],
          likedBy: parent.likedBy,
          dislikedBy: parent.dislikedBy,
          authorPhotoUrl: parent.authorPhotoUrl,
          authorAvatarColorIndex: parent.authorAvatarColorIndex,
          createdAtDate: parent.createdAtDate,
          imageUrl: parent.imageUrl,
          authorUid: parent.authorUid,
          country: parent.country,
        );
        newComments = PostService.replaceCommentById(
          p.commentsList,
          parentId,
          updated,
        );
      } else {
        newComments = p.commentsList;
      }
      newCount = p.comments + 1;
    } else {
      err = await PostService.instance.addComment(id, p, newComment);
      if (!mounted) return;
      if (err != null) {
        setState(() => _inlineCommentSubmitting.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err, style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      newComments = [...p.commentsList, newComment];
      newCount = (p.commentsList.length + 1 > p.comments)
          ? p.commentsList.length + 1
          : p.comments + 1;
    }

    // 낙관적 업데이트: 서버 응답 전에 즉시 댓글 반영
    final optimisticPost = p.copyWith(
      commentsList: newComments,
      comments: newCount,
    );
    _localOverrides[id] = optimisticPost;
    setState(() {
      _inlineCommentSubmitting.remove(id);
      _inlineReplyingToCommentId.remove(id);
      _inlineReplyingToComment.remove(id);
    });
    widget.onPostUpdated?.call(optimisticPost);

    ctrl.clear();
    if (successPopContext != null && successPopContext.mounted) {
      Navigator.of(successPopContext).pop();
    }

    // 백그라운드에서 서버 동기화 (UI 블로킹 없음)
    unawaited(_reconcileAfterComment(id, newComment.id));
  }

  Future<void> _reconcileAfterComment(
    String postId,
    String newCommentId,
  ) async {
    final locale = CountryScope.maybeOf(context)?.country;

    // 최대 3번 재시도 (0s → 2s → 4s)
    for (final delay in [
      Duration.zero,
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]) {
      if (delay != Duration.zero) {
        await Future.delayed(delay);
      }
      if (!mounted) return;
      final fresh = await PostService.instance.getPost(postId, locale);
      if (!mounted) return;
      if (fresh == null) continue;
      final serverHasComment =
          PostService.findCommentById(fresh.commentsList, newCommentId) != null;
      if (serverHasComment) {
        // 서버에 반영됐으면 로컬 오버라이드 제거.
        // _postsCacheSource도 null로 초기화해 _postsById가 최신 widget.posts로
        // 재구성되도록 강제한 뒤 부모에 전파.
        setState(() {
          _localOverrides.remove(postId);
          _postsCacheSource = null;
        });
        widget.onPostUpdated?.call(fresh);
        return;
      }
      // 아직 전파 안 됐으면 다음 재시도 대기
    }
    // 모든 재시도 실패 → 낙관적 상태 유지 (댓글이 화면에서 사라지지 않음)
  }

  void _openCommunitySearchForTag(BuildContext context, Post post, String raw) {
    final q = raw.trim();
    if (q.isEmpty) return;
    final dramaId = post.dramaId?.trim();
    if (dramaId == null || dramaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '연결된 드라마가 없어 태그 페이지를 열 수 없어요',
            style: GoogleFonts.notoSansKr(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CommunitySearchPage(
          initialQuery: q,
          reviewDramaId: dramaId,
          reviewDramaPosterUrl: post.dramaThumbnail?.trim(),
        ),
      ),
    );
  }

  /// 피드 리뷰 타일 — 제목·썸네일 탭 시 드라마 상세 페이지로 이동.
  Future<void> _openDramaDetailFromPost(BuildContext context, Post post) async {
    await DramaListService.instance.loadFromAsset();
    if (!context.mounted) return;
    final locale = CountryScope.maybeOf(context)?.country;
    final dramaId = post.dramaId?.trim() ?? '';
    DramaItem? fromList;
    for (final e in DramaListService.instance.list) {
      if (dramaId.isNotEmpty && e.id == dramaId) {
        fromList = e;
        break;
      }
    }
    final item =
        fromList ??
        DramaItem(
          id: dramaId.isNotEmpty ? dramaId : 'review_${post.id}',
          title: (post.dramaTitle?.trim().isNotEmpty == true)
              ? post.dramaTitle!.trim()
              : post.title.trim(),
          subtitle: '',
          views: '0',
          rating: post.rating ?? 0,
          imageUrl: post.dramaThumbnail?.trim(),
        );
    if (!context.mounted) return;
    await DramaDetailPage.openFromItem(context, item, country: locale);
  }

  /// 피드 리뷰 타일 — 별점 탭 시 드라마 상세 > 리뷰 페이지로 이동.
  Future<void> _openDramaWatchersFromPost(
    BuildContext context,
    Post post,
  ) async {
    await DramaListService.instance.loadFromAsset();
    if (!context.mounted) return;
    final locale = CountryScope.maybeOf(context)?.country;
    final dramaId = post.dramaId?.trim() ?? '';
    if (dramaId.isEmpty) {
      await _openDramaDetailFromPost(context, post);
      return;
    }
    final displayTitle = DramaListService.instance.getDisplayTitle(
      dramaId,
      locale,
    );
    final fallbackTitle = displayTitle.isNotEmpty
        ? displayTitle
        : (post.dramaTitle?.trim().isNotEmpty == true
              ? post.dramaTitle!.trim()
              : post.title.trim());
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(
        builder: (_) =>
            DramaReviewsListScreen(dramaId: dramaId, dramaTitle: fallbackTitle),
      ),
    );
  }

  void _toggleReviewBodyComments(Post post) {
    final id = post.id;
    final wasOpen = _expandedReviewComments.contains(id);
    setState(() {
      if (wasOpen) {
        _expandedReviewComments.remove(id);
      } else {
        // 여러 리뷰의 댓글을 동시에 펼칠 수 있게 유지
        _expandedReviewComments.add(id);
        _inlineCommentControllers.putIfAbsent(id, TextEditingController.new);
      }
    });
    if (!wasOpen) _refreshPostForComments(id);
  }

  void _flattenCommentsInto(
    List<PostComment> roots,
    List<_InlineReviewCommentEntry> out, {
    required Set<String> expandedParentIds,
    int depth = 0,
  }) {
    for (final c in roots) {
      out.add(_InlineReviewCommentEntry(comment: c, depth: depth));
      if (c.replies.isNotEmpty && expandedParentIds.contains(c.id)) {
        _flattenCommentsInto(
          c.replies,
          out,
          expandedParentIds: expandedParentIds,
          depth: depth + 1,
        );
      }
    }
  }

  Widget _buildInlineCommentAvatar(PostComment c, double size) {
    final rawUrl = c.authorPhotoUrl?.trim();
    final colorIdx = c.authorAvatarColorIndex ?? c.author.hashCode;
    Widget fallback() {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: UserProfileService.bgColorFromIndex(colorIdx),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            Icons.person,
            size: size * 0.56,
            color: UserProfileService.iconColorFromIndex(colorIdx),
          ),
        ),
      );
    }

    if (rawUrl != null && rawUrl.isNotEmpty) {
      return ClipOval(
        child: OptimizedNetworkImage.avatar(
          imageUrl: rawUrl,
          size: size,
          errorWidget: fallback(),
        ),
      );
    }
    return fallback();
  }

  Widget _buildFlatCommentRow(
    _InlineReviewCommentEntry entry,
    ColorScheme cs,
    Post post, {
    required bool showLeadingReplyIcon,
  }) {
    final c = entry.comment;
    final isReply = entry.depth > 0;
    const avatarSize = kAppUnifiedProfileAvatarSize;
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    final likeMap = _inlineCommentLikeState[post.id];
    final likeState = likeMap?[c.id];
    final isLiked = likeState?.liked ?? c.likedBy.contains(uid);
    final likeCount = likeState?.count ?? c.votes;

    // ── 톡/에스크와 동일한 색상·스타일 ──────────────────────────────────
    final metaColor = cs.onSurface.withValues(alpha: 0.44);
    final bodyFontSize = isReply ? 12.0 : 13.0;
    final bodyTextStyle = GoogleFonts.notoSansKr(
      fontSize: bodyFontSize,
      color: cs.onSurface,
      height: 1.38,
    );
    const talkAskBodyTextHeightBehavior = TextHeightBehavior(
      applyHeightToLastDescent: false,
    );
    final replyStyle = appUnifiedNicknameStyle(
      cs,
    ).copyWith(
      fontWeight: FontWeight.w500,
      color: cs.onSurface.withValues(alpha: 0.30),
      height: 1.2,
    );
    final countStyle = appUnifiedNicknameStyle(cs).copyWith(
      fontWeight: FontWeight.w500,
      color: isLiked ? Colors.redAccent : metaColor,
      height: 1.2,
    );

    // ── 상수 (톡/에스크와 동일) ──────────────────────────────────────────
    const talkAskLikeColW = 40.0;
    const talkAskLikeCountDownNudge = 1.0;
    const talkAskBodyVisualUpNudge = 1.5;
    const heartIconSize = 16.0;
    const heartVPad = 4.0;
    const heartBlockH = heartVPad + heartIconSize + heartVPad;
    const gapNameToBody = 1.0;
    const bodyMicroUpPx = 1.0;
    const gapTalkAskNameBodyReply = gapNameToBody - bodyMicroUpPx;
    const replyArrowW = 18.0; // 14px 아이콘 + 4px gap

    Widget heartWidget() {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_toggleInlineCommentLike(post, c)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: heartVPad),
          child: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            size: heartIconSize,
            color: isLiked ? Colors.redAccent : metaColor,
          ),
        ),
      );
    }

    final commentBody = LayoutBuilder(
      builder: (ctx, cons) {
        final innerMaxW = cons.maxWidth;
        final textColumnMaxW =
            (innerMaxW -
                    avatarSize -
                    8 -
                    talkAskLikeColW -
                    ((isReply || showLeadingReplyIcon) ? replyArrowW : 0.0))
                .clamp(1.0, 9999.0);
        final textScaler = MediaQuery.textScalerOf(ctx);
        final textDir = Directionality.of(ctx);

        final authorLineStyle = appUnifiedNicknameStyle(cs);
        final authorText = c.author.startsWith('u/')
            ? c.author.substring(2)
            : c.author;

        final tpAuthorLine = TextPainter(
          text: TextSpan(
            text: authorText.isEmpty ? ' ' : authorText,
            style: authorLineStyle,
          ),
          textDirection: textDir,
          maxLines: 1,
          textScaler: textScaler,
        )..layout(maxWidth: textColumnMaxW);
        final nameBlockH = tpAuthorLine.height;

        final tpReply = TextPainter(
          text: TextSpan(text: 'Reply', style: replyStyle),
          textDirection: textDir,
          maxLines: 1,
          textScaler: textScaler,
        )..layout();
        final replyRowH = math.max(tpReply.height + 2.0, 18.0);

        final tpCountSlot = TextPainter(
          text: TextSpan(
            text: '0',
            style: appUnifiedNicknameStyle(cs).copyWith(
              fontWeight: FontWeight.w500,
              color: metaColor,
              height: 1.2,
            ),
          ),
          textDirection: textDir,
          maxLines: 1,
          textScaler: textScaler,
        )..layout();
        final countSlotH = tpCountSlot.height;

        final yBodyTop = nameBlockH + gapTalkAskNameBodyReply;
        final hasText = c.text.trim().isNotEmpty;

        double bodyH = 0;
        List<LineMetrics>? bodyLineMetrics;
        if (hasText) {
          final tpBody = TextPainter(
            text: TextSpan(text: c.text, style: bodyTextStyle),
            textDirection: textDir,
            maxLines: null,
            textScaler: textScaler,
            textHeightBehavior: talkAskBodyTextHeightBehavior,
          )..layout(maxWidth: textColumnMaxW);
          bodyH = tpBody.height;
          bodyLineMetrics = tpBody.computeLineMetrics();
        }

        double countH = countSlotH;
        if (likeCount > 0) {
          final tpC = TextPainter(
            text: TextSpan(
              text: formatCompactCount(likeCount),
              style: countStyle,
            ),
            textDirection: textDir,
            maxLines: 1,
            textScaler: textScaler,
          )..layout();
          countH = math.max(countSlotH, tpC.height);
        }

        final double heartTop;
        final double countTop;
        final double replyRowTop;

        if (hasText && bodyH > 0 && bodyLineMetrics != null) {
          final lines = bodyLineMetrics;
          if (lines.length >= 2) {
            final h0 = lines[0].height;
            final h1 = lines[1].height;
            heartTop = yBodyTop + h0 / 2 - heartBlockH / 2;
            countTop =
                yBodyTop + h0 + h1 / 2 - countH / 2 + talkAskLikeCountDownNudge;
            replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
          } else {
            replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
            heartTop = yBodyTop + bodyH / 2 - heartBlockH / 2;
            final countCenterY = replyRowTop + replyRowH / 2;
            final ct = countCenterY - countH / 2 + talkAskLikeCountDownNudge;
            final min = replyRowTop;
            final max = replyRowTop + replyRowH - countH;
            countTop = max >= min ? ct.clamp(min, max) : min;
          }
        } else {
          replyRowTop = hasText
              ? yBodyTop + bodyH + gapTalkAskNameBodyReply
              : yBodyTop;
          heartTop = yBodyTop + replyRowH / 2 - heartBlockH / 2;
          final countCenterY = replyRowTop + replyRowH / 2;
          final ct = countCenterY - countH / 2 + talkAskLikeCountDownNudge;
          final min = replyRowTop;
          final max = replyRowTop + replyRowH - countH;
          countTop = max >= min ? ct.clamp(min, max) : min;
        }

        final contentBottom = math.max(
          hasText ? yBodyTop + bodyH + gapTalkAskNameBodyReply : replyRowTop,
          replyRowTop + replyRowH,
        );
        var stackH = math.max(
          contentBottom,
          math.max(heartTop + heartBlockH, countTop + countH),
        );
        stackH = math.max(stackH, avatarSize.toDouble());

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isReply || showLeadingReplyIcon) ...[
              Padding(
                padding: EdgeInsets.only(
                  left: showLeadingReplyIcon && !isReply ? 2 : 0,
                  top: 2,
                ),
                child: Transform.rotate(
                  angle: math.pi,
                  child: Icon(LucideIcons.reply, size: 14, color: metaColor),
                ),
              ),
              const SizedBox(width: 4),
            ],
            _buildInlineCommentAvatar(c, avatarSize),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: stackH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 닉네임
                    Positioned(
                      left: 0,
                      right: talkAskLikeColW,
                      top: 0,
                      child: Transform.translate(
                        offset: const Offset(0, -1.5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                authorText,
                                style: authorLineStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 댓글 본문
                    if (hasText)
                      Positioned(
                        left: 0,
                        right: talkAskLikeColW,
                        top: yBodyTop,
                        child: Transform.translate(
                          offset: const Offset(0, -talkAskBodyVisualUpNudge),
                          child: Text(
                            c.text,
                            style: bodyTextStyle,
                            textHeightBehavior: talkAskBodyTextHeightBehavior,
                          ),
                        ),
                      ),
                    // Reply 버튼
                    Positioned(
                      left: 0,
                      right: talkAskLikeColW,
                      top: replyRowTop,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _startInlineReply(post, c),
                        child: Text('Reply', style: replyStyle),
                      ),
                    ),
                    // 하트 아이콘
                    Positioned(
                      right: 0,
                      top: heartTop,
                      width: talkAskLikeColW,
                      height: heartBlockH,
                      child: Center(child: heartWidget()),
                    ),
                    // 하트 숫자
                    Positioned(
                      right: 0,
                      top: countTop,
                      width: talkAskLikeColW,
                      height: countH,
                      child: Center(
                        child: likeCount > 0
                            ? Text(
                                formatCompactCount(likeCount),
                                textAlign: TextAlign.center,
                                style: countStyle,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!isReply) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 20, 0, 8),
        child: commentBody,
      );
    }
    final nestedReplyLeft = 50.0 + ((entry.depth - 1) * 10.0);
    return Padding(
      padding: EdgeInsets.only(left: nestedReplyLeft, top: 12),
      child: commentBody,
    );
  }

  /// 본문 탭 펼침: 댓글 있으면 목록 + 입력줄, 없으면 입력줄만(오버레이와 동일 입력 UI).
  Widget _buildReviewExpandedInlineCommentSection(
    BuildContext context,
    Post post,
    ColorScheme cs,
  ) {
    final id = post.id;
    _inlineCommentControllers.putIfAbsent(id, TextEditingController.new);
    final ctrl = _inlineCommentControllers[id]!;
    final p = _latestPost(post);
    final expandedReplyParents = _inlineExpandedReplyThreads.putIfAbsent(
      id,
      () => <String>{},
    );
    final flat = <_InlineReviewCommentEntry>[];
    _flattenCommentsInto(
      p.commentsList,
      flat,
      expandedParentIds: expandedReplyParents,
    );
    final hasComments = flat.isNotEmpty;

    final replyingComment = _inlineReplyingToComment[id];

    final commentWidgets = <Widget>[];
    final stack = <({int depth, PostComment comment, int flatIndex})>[];
    for (var i = 0; i < flat.length; i++) {
      final entry = flat[i];
      final comment = entry.comment;
      const showLeadingReplyIcon = true;
      while (stack.isNotEmpty && stack.last.depth >= entry.depth) {
        stack.removeLast();
      }
      stack.add((depth: entry.depth, comment: comment, flatIndex: i));

      final hasReplies = comment.replies.isNotEmpty;
      final isExpanded = expandedReplyParents.contains(comment.id);
      final row = _buildFlatCommentRow(
        entry,
        cs,
        p,
        showLeadingReplyIcon: showLeadingReplyIcon,
      );
      commentWidgets.add(row);

      double toggleLeftFor(int depth, bool hasArrow) {
        final rowLeft = depth == 0 ? 40.0 : 50.0 + ((depth - 1) * 10.0);
        return rowLeft +
            (hasArrow ? 18.0 : 0.0) +
            kAppUnifiedProfileAvatarSize +
            8.0;
      }

      if (hasReplies && !isExpanded) {
        final hasArrow = entry.depth > 0 || showLeadingReplyIcon;
        final toggleLeft = toggleLeftFor(entry.depth, hasArrow);
        final repliesN = comment.replies.length;
        final label = repliesN == 1 ? 'reply' : 'replies';
        final metaColor = cs.onSurface.withValues(alpha: 0.44);
        commentWidgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(toggleLeft, 0, 0, 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => expandedReplyParents.add(comment.id)),
              child: Text.rich(
                TextSpan(
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    color: metaColor,
                    height: 1.25,
                  ),
                  children: [
                    const TextSpan(text: '— '),
                    TextSpan(
                      text: 'View $repliesN more $label',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: metaColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final nextDepth = i + 1 < flat.length ? flat[i + 1].depth : -1;
      for (var j = stack.length - 1; j >= 0; j--) {
        final parent = stack[j];
        if (parent.depth < nextDepth) break;
        final parentComment = parent.comment;
        final parentExpanded = expandedReplyParents.contains(parentComment.id);
        if (!parentExpanded || parentComment.replies.isEmpty) continue;
        const parentHasArrow = true;
        final toggleLeft = toggleLeftFor(parent.depth, parentHasArrow);
        final label = parentComment.replies.length == 1 ? 'reply' : 'replies';
        final metaColor = cs.onSurface.withValues(alpha: 0.44);
        commentWidgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(toggleLeft, 0, 0, 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(
                () => expandedReplyParents.remove(parentComment.id),
              ),
              child: Text.rich(
                TextSpan(
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    color: metaColor,
                    height: 1.25,
                  ),
                  children: [
                    const TextSpan(text: '— '),
                    TextSpan(
                      text: 'Hide $label',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: metaColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return ColoredBox(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasComments)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: commentWidgets,
              ),
            ),
          // 답글 중 배너
          if (replyingComment != null)
            _InlineReplyingToBanner(
              comment: replyingComment,
              cs: cs,
              onCancel: () => setState(() {
                _inlineReplyingToCommentId.remove(id);
                _inlineReplyingToComment.remove(id);
              }),
            ),
          _ReviewFeedInlineComposer(
            controller: ctrl,
            focusNode: _inlineComposerFocus(id),
            isSubmitting: _inlineCommentSubmitting.contains(id),
            autofocus: !hasComments,
            onSend: () => _submitInlineComment(post, successPopContext: null),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewInlineActionBar(Post post, ColorScheme cs, dynamic s) {
    final p = _latestPost(post);
    final uid = AuthService.instance.currentUser.value?.uid;
    final liked = uid != null && p.likedBy.contains(uid);
    const iconSize = 13.0;
    final actionFg = feedInlineActionMutedForeground(cs);
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ReviewCardSuppressParentTap(
          child: reviewInlineActionHitTarget(
            onTap: () => _inlineToggleLike(post),
            visual: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    size: iconSize,
                    color: liked ? Colors.redAccent : actionFg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(p.likeCount),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      color: actionFg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        ReviewCardSuppressParentTap(
          child: reviewInlineActionHitTarget(
            onTap: () => _toggleReviewBodyComments(post),
            visual: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.message_circle,
                    size: iconSize,
                    color: actionFg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(p.comments),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      color: actionFg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _submitSearch() => setState(
    () => _searchQuery = _searchController.text.trim().toLowerCase(),
  );

  bool _postMatchesQuery(Post p, String q) {
    final title = p.title.toLowerCase();
    final body = (p.body ?? '').toLowerCase();
    final author =
        (p.author.startsWith('u/') ? p.author.substring(2) : p.author)
            .toLowerCase();
    switch (_searchScope) {
      case PostSearchScope.titleAndBody:
        if (title.contains(q) || body.contains(q)) return true;
        for (final t in p.tags) {
          if (t.toLowerCase().contains(q)) return true;
        }
        return false;
      case PostSearchScope.title:
        return title.contains(q);
      case PostSearchScope.body:
        return body.contains(q);
      case PostSearchScope.comment:
        return p.commentsList.any((c) => commentContainsQuery(c, q));
      case PostSearchScope.nickname:
        return author.contains(q);
    }
  }

  List<Post> get _filteredPosts {
    if (_cachedFiltered != null &&
        identical(_lastPosts, widget.posts) &&
        _lastSearchQuery == _searchQuery &&
        _lastSearchScope == _searchScope) {
      return _cachedFiltered!;
    }
    var list = widget.posts.toList()
      ..sort((a, b) {
        final aT = a.popularAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = b.popularAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bT.compareTo(aT);
      });
    if (_searchQuery.isNotEmpty)
      list = list.where((p) => _postMatchesQuery(p, _searchQuery)).toList();
    _cachedFiltered = list;
    _lastPosts = widget.posts;
    _lastSearchQuery = _searchQuery;
    _lastSearchScope = _searchScope;
    return list;
  }

  List<Post> get _paginatedPosts {
    final f = _filteredPosts;
    final start = _currentPage * _postsPerPage;
    if (start >= f.length) return [];
    return f.sublist(start, (start + _postsPerPage).clamp(0, f.length));
  }

  int get _totalPages {
    final len = _filteredPosts.length;
    if (len == 0) return 0;
    return (len / _postsPerPage).ceil();
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(
              LucideIcons.search,
              size: 17,
              color: cs.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: CountryScope.of(context).strings.get('search'),
                hintStyle: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                  fontWeight: FontWeight.w400,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: cs.onSurface,
              ),
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: cs.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
            ),
          Container(
            width: 1,
            height: 22,
            color: cs.onSurface.withOpacity(0.08),
          ),
          GestureDetector(
            key: _filterKey,
            onTap: () async {
              final RenderBox btn =
                  _filterKey.currentContext!.findRenderObject() as RenderBox;
              final Offset btnOffset = btn.localToGlobal(Offset.zero);
              final Size screenSize = MediaQuery.of(context).size;
              final selected = await showMenu<PostSearchScope>(
                context: context,
                position: RelativeRect.fromRect(
                  Rect.fromLTWH(
                    btnOffset.dx,
                    btnOffset.dy,
                    btn.size.width,
                    btn.size.height,
                  ),
                  Offset.zero & screenSize,
                ),
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                items: postSearchScopeOrder.map((scope) {
                  final isSelected = scope == _searchScope;
                  return PopupMenuItem<PostSearchScope>(
                    value: scope,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        Text(
                          postSearchScopeLabel(scope, context),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        if (isSelected) ...[
                          const Spacer(),
                          Icon(
                            LucideIcons.check,
                            size: 14,
                            color: cs.onSurface,
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
              if (selected != null && mounted)
                setState(() => _searchScope = selected);
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    postSearchScopeLabel(_searchScope, context),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    LucideIcons.chevron_down,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalPagination(
    ColorScheme cs,
    int totalPages,
    int totalCount,
  ) {
    if (totalCount == 0 || totalPages == 0) return const SizedBox.shrink();
    final c = _currentPage;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: c > 0
                ? () => setState(() {
                    _currentPage = c - 1;
                    _showPageInput = false;
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                LucideIcons.chevron_left,
                size: 22,
                color: c > 0
                    ? cs.onSurface.withOpacity(0.75)
                    : cs.onSurface.withOpacity(0.18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() {
              _showPageInput = !_showPageInput;
              if (_showPageInput) _pageInputController.clear();
            }),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showPageInput
                  ? Container(
                      key: const ValueKey('input'),
                      width: 80,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? cs.outline
                              : const Color(0xFFFF6B35),
                          width: Theme.of(context).brightness == Brightness.dark
                              ? 1
                              : 1.2,
                        ),
                      ),
                      child: Center(
                        child: TextField(
                          controller: _pageInputController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: '페이지',
                            hintStyle: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            color: cs.onSurface,
                          ),
                          onSubmitted: (val) {
                            final n = int.tryParse(val);
                            if (n != null && n >= 1 && n <= totalPages)
                              setState(() {
                                _currentPage = n - 1;
                                _showPageInput = false;
                              });
                            else
                              setState(() => _showPageInput = false);
                          },
                        ),
                      ),
                    )
                  : Container(
                      key: const ValueKey('label'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${c + 1} / $totalPages',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: c < totalPages - 1
                ? () => setState(() {
                    _currentPage = c + 1;
                    _showPageInput = false;
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                LucideIcons.chevron_right,
                size: 22,
                color: c < totalPages - 1
                    ? cs.onSurface.withOpacity(0.75)
                    : cs.onSurface.withOpacity(0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapRefresh(Widget child) {
    if (widget.enablePullToRefresh) {
      return BlindRefreshIndicator(
        onRefresh: widget.onRefresh,
        spinnerOffsetDown: 17.0,
        child: child,
      );
    }
    return child;
  }

  /// 커뮤니티 홈: 검색·페이지네이션 없이 무한 스크롤 전용
  Widget _buildSimplePopularFeed(
    BuildContext context,
    ColorScheme cs,
    List<Post> posts,
    bool isLoading,
    String? error,
    Future<void> Function() onRefresh,
    String? currentUserAuthor,
    void Function(Post)? onPostUpdated,
    void Function(Post)? onPostDeleted,
  ) {
    final s = CountryScope.of(context).strings;
    if (isLoading && posts.isEmpty) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && posts.isEmpty) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.cloud_off,
              size: 56,
              color: cs.error.withOpacity(0.6),
            ),
            const SizedBox(height: 20),
            Text(
              '글을 불러오지 못했어요',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: cs.error,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onRefresh,
              child: Text(
                '다시 시도',
                style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary),
              ),
            ),
          ],
        ),
      );
    }
    if (posts.isEmpty) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.star,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 24),
            Text(
              s.get('reviewsTabEmpty'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    final tabName =
        widget.listTabLabel ??
        (widget.useReviewLayout ? s.get('tabReviews') : s.get('tabHot'));
    bool isTypedReview(Post p) => p.type?.trim().toLowerCase() == 'review';
    final useLb = widget.useReviewLayout && widget.useLetterboxdReviewLayout;
    final footerCount = (widget.feedLoadingMore && widget.feedHasMore) ? 1 : 0;
    final listView = ListView.builder(
      controller: widget.feedScrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 900,
      itemCount: posts.length + footerCount + 1,
      itemBuilder: (context, index) {
        if (index < posts.length) {
          final post = posts[index];
          if (useLb && isTypedReview(post)) {
            final inline = widget.reviewLetterboxdInlineFeed;
            return RepaintBoundary(
              key: ValueKey('lb_${post.id}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.outline.withValues(alpha: 0.26),
                    ),
                  FeedReviewLetterboxdTile(
                    post: post,
                    onTap: (!inline && widget.onPostTap != null)
                        ? () => widget.onPostTap!(post)
                        : null,
                    thumbTrailingActions: inline
                        ? _buildReviewInlineActionBar(post, cs, s)
                        : null,
                    onDramaTap: () => _openDramaDetailFromPost(context, post),
                    onReviewBodyTap: inline
                        ? () => _toggleReviewBodyComments(post)
                        : null,
                    onRatingTap: () =>
                        _openDramaWatchersFromPost(context, post),
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    authorAvatarSize: widget.feedAuthorAvatarSize,
                    onTagTap: (tag) =>
                        _openCommunitySearchForTag(context, post, tag),
                  ),
                  if (inline && _expandedReviewComments.contains(post.id))
                    KeyedSubtree(
                      key: ValueKey('rv_inline_comments_${post.id}'),
                      child: _buildReviewExpandedInlineCommentSection(
                        context,
                        post,
                        cs,
                      ),
                    ),
                ],
              ),
            );
          }
          return RepaintBoundary(
            child: widget.useReviewLayout
                ? FeedReviewPostCard(
                    key: ValueKey('rv_${post.id}'),
                    post: post,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    tabName: tabName,
                    onTap: widget.onPostTap != null
                        ? () => widget.onPostTap!(post)
                        : null,
                    onUserBlocked: widget.onUserBlocked,
                  )
                : FeedPostCard(
                    key: ValueKey(post.id),
                    post: post,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    tabName: tabName,
                    onTap: widget.onPostTap != null
                        ? () => widget.onPostTap!(post)
                        : null,
                    onUserBlocked: widget.onUserBlocked,
                    authorAvatarSize: widget.feedAuthorAvatarSize,
                  ),
          );
        }
        if (footerCount == 1 && index == posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            ),
          );
        }
        return SizedBox(
          height: widget.shrinkWrap ? 24 : _listBottomPadding(context),
        );
      },
    );
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.deferToChild,
      child: _wrapRefresh(listView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    final posts = widget.posts;
    final isLoading = widget.isLoading;
    final error = widget.error;
    final onRefresh = widget.onRefresh;
    final currentUserAuthor = widget.currentUserAuthor;
    final onPostUpdated = widget.onPostUpdated;
    final onPostDeleted = widget.onPostDeleted;

    if (widget.useSimpleFeedLayout) {
      return _buildSimplePopularFeed(
        context,
        cs,
        posts,
        isLoading,
        error,
        onRefresh,
        currentUserAuthor,
        onPostUpdated,
        onPostDeleted,
      );
    }

    if (isLoading) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: [
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.cloud_off,
              size: 56,
              color: cs.error.withOpacity(0.6),
            ),
            const SizedBox(height: 20),
            Text(
              '글을 불러오지 못했어요',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: cs.error,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onRefresh,
              child: Text(
                '다시 시도',
                style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary),
              ),
            ),
          ],
        ),
      );
    }
    if (posts.isEmpty) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.star,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 24),
            Text(
              s.get('reviewsTabEmpty'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredPosts;
    final start = _currentPage * _postsPerPage;
    final paginated = start >= filtered.length
        ? <Post>[]
        : filtered.sublist(
            start,
            (start + _postsPerPage).clamp(0, filtered.length),
          );
    final totalPages = filtered.isEmpty
        ? 0
        : (filtered.length / _postsPerPage).ceil();
    if (_currentPage >= totalPages && _currentPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          setState(() => _currentPage = (totalPages - 1).clamp(0, 999999));
      });
    }

    final tabName =
        widget.listTabLabel ??
        (widget.useReviewLayout ? s.get('tabReviews') : s.get('tabHot'));
    bool isTypedReview(Post p) => p.type?.trim().toLowerCase() == 'review';

    final listView = ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 900,
      itemCount: paginated.length + 4,
      itemBuilder: (context, index) {
        if (index < paginated.length) {
          final post = paginated[index];
          final useLb =
              widget.useReviewLayout && widget.useLetterboxdReviewLayout;
          if (useLb && isTypedReview(post)) {
            final inline = widget.reviewLetterboxdInlineFeed;
            return RepaintBoundary(
              key: ValueKey('lb_${post.id}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.outline.withValues(alpha: 0.26),
                    ),
                  FeedReviewLetterboxdTile(
                    post: post,
                    onTap: (!inline && widget.onPostTap != null)
                        ? () => widget.onPostTap!(post)
                        : null,
                    thumbTrailingActions: inline
                        ? _buildReviewInlineActionBar(post, cs, s)
                        : null,
                    onDramaTap: () => _openDramaDetailFromPost(context, post),
                    onReviewBodyTap: inline
                        ? () => _toggleReviewBodyComments(post)
                        : null,
                    onRatingTap: () =>
                        _openDramaWatchersFromPost(context, post),
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    authorAvatarSize: widget.feedAuthorAvatarSize,
                    onTagTap: (tag) =>
                        _openCommunitySearchForTag(context, post, tag),
                  ),
                  if (inline && _expandedReviewComments.contains(post.id))
                    KeyedSubtree(
                      key: ValueKey('rv_inline_comments_${post.id}'),
                      child: _buildReviewExpandedInlineCommentSection(
                        context,
                        post,
                        cs,
                      ),
                    ),
                ],
              ),
            );
          }
          return RepaintBoundary(
            child: widget.useReviewLayout
                ? FeedReviewPostCard(
                    key: ValueKey('rv_${post.id}'),
                    post: post,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    tabName: tabName,
                    onTap: widget.onPostTap != null
                        ? () => widget.onPostTap!(post)
                        : null,
                    onUserBlocked: widget.onUserBlocked,
                  )
                : FeedPostCard(
                    key: ValueKey(post.id),
                    post: post,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    tabName: tabName,
                    onTap: widget.onPostTap != null
                        ? () => widget.onPostTap!(post)
                        : null,
                    onUserBlocked: widget.onUserBlocked,
                    authorAvatarSize: widget.feedAuthorAvatarSize,
                  ),
          );
        }
        if (index == paginated.length) return const SizedBox(height: 16);
        if (index == paginated.length + 1)
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildSearchBar(cs),
          );
        if (index == paginated.length + 2)
          return _buildMinimalPagination(cs, totalPages, filtered.length);
        return SizedBox(
          height: widget.shrinkWrap ? 24 : _listBottomPadding(context),
        );
      },
    );
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_showPageInput) setState(() => _showPageInput = false);
      },
      behavior: HitTestBehavior.deferToChild,
      child: _wrapRefresh(listView),
    );
  }
}

/// 리뷰 Letterboxd 인라인 펼침 하단: 피드에 붙는 댓글 입력(오버레이 하단바와 동일 스타일).
class _ReviewFeedInlineComposer extends StatelessWidget {
  _ReviewFeedInlineComposer({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.autofocus,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final bool autofocus;
  final Future<void> Function() onSend;

  static const Color _sendBlue = Color(0xFF0A84FF);

  Widget _defaultAvatar(int colorIdx, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UserProfileService.bgColorFromIndex(colorIdx),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.person,
          size: size * 0.55,
          color: UserProfileService.iconColorFromIndex(colorIdx),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sendLabel =
        CountryScope.maybeOf(context)?.strings.get('replySubmit') ?? '';

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            UserProfileService.instance.profileImageUrlNotifier,
            UserProfileService.instance.avatarColorNotifier,
            controller,
          ]),
          builder: (context, _) {
            final rawUrl =
                UserProfileService.instance.profileImageUrlNotifier.value;
            final url = rawUrl?.trim();
            final colorIdx =
                UserProfileService.instance.avatarColorNotifier.value ?? 0;
            const avatarSize = kAppUnifiedProfileAvatarSize;
            final Widget avatar = (url != null && url.isNotEmpty)
                ? ClipOval(
                    child: OptimizedNetworkImage.avatar(
                      imageUrl: url,
                      size: avatarSize,
                      errorWidget: _defaultAvatar(colorIdx, avatarSize),
                    ),
                  )
                : _defaultAvatar(colorIdx, avatarSize);
            final canSend = !isSubmitting && controller.text.trim().isNotEmpty;
            final sendBg = canSend
                ? _sendBlue
                : cs.onSurface.withValues(alpha: 0.22);
            final sendIconColor = canSend
                ? Colors.white
                : cs.onSurface.withValues(alpha: 0.38);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                avatar,
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    minLines: 1,
                    maxLines: 6,
                    style: GoogleFonts.notoSansKr(fontSize: 14, height: 1.32),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.brightness == Brightness.dark
                          ? cs.surfaceContainerHigh
                          : cs.surface,
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.28),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.28),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.45),
                        ),
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
                        child: Material(
                          color: sendBg,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: (!canSend || isSubmitting)
                                ? null
                                : () {
                                    unawaited(onSend());
                                  },
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: Center(
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        Icons.arrow_upward,
                                        color: sendIconColor,
                                        size: 17,
                                        semanticLabel: sendLabel,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 36,
                      ),
                    ),
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

/// Reviews 인라인: 키보드 위 댓글 입력(딤 배경 + 왼쪽 프로필 + 캡슐 필드 + 필드 안 파란 원형 전송).
class _ReviewCommentComposerOverlay extends StatefulWidget {
  const _ReviewCommentComposerOverlay({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final Future<void> Function(BuildContext overlayContext) onSend;

  @override
  State<_ReviewCommentComposerOverlay> createState() =>
      _ReviewCommentComposerOverlayState();
}

class _ReviewCommentComposerOverlayState
    extends State<_ReviewCommentComposerOverlay> {
  bool _sending = false;

  static const Color _sendBlue = Color(0xFF0A84FF);

  void _onControllerText() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerText);
    super.dispose();
  }

  Widget _defaultAvatar(int colorIdx, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UserProfileService.bgColorFromIndex(colorIdx),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.person,
          size: size * 0.55,
          color: UserProfileService.iconColorFromIndex(colorIdx),
        ),
      ),
    );
  }

  Future<void> _onTapSend(BuildContext overlayContext) async {
    if (_sending || widget.controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(overlayContext);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final sendLabel =
        CountryScope.maybeOf(context)?.strings.get('replySubmit') ?? '';

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              },
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.48)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Material(
                color: theme.scaffoldBackgroundColor,
                elevation: 20,
                shadowColor: Colors.black54,
                child: SafeArea(
                  top: false,
                  maintainBottomViewPadding: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        UserProfileService.instance.profileImageUrlNotifier,
                        UserProfileService.instance.avatarColorNotifier,
                        widget.controller,
                      ]),
                      builder: (context, _) {
                        final rawUrl = UserProfileService
                            .instance
                            .profileImageUrlNotifier
                            .value;
                        final url = rawUrl?.trim();
                        final colorIdx =
                            UserProfileService
                                .instance
                                .avatarColorNotifier
                                .value ??
                            0;
                        const avatarSize = kAppUnifiedProfileAvatarSize;
                        final Widget avatar = (url != null && url.isNotEmpty)
                            ? ClipOval(
                                child: OptimizedNetworkImage.avatar(
                                  imageUrl: url,
                                  size: avatarSize,
                                  errorWidget: _defaultAvatar(
                                    colorIdx,
                                    avatarSize,
                                  ),
                                ),
                              )
                            : _defaultAvatar(colorIdx, avatarSize);
                        final canSend =
                            !_sending &&
                            widget.controller.text.trim().isNotEmpty;
                        final sendBg = canSend
                            ? _sendBlue
                            : cs.onSurface.withValues(alpha: 0.22);
                        final sendIconColor = canSend
                            ? Colors.white
                            : cs.onSurface.withValues(alpha: 0.38);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            avatar,
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: widget.controller,
                                autofocus: true,
                                minLines: 1,
                                maxLines: 6,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  height: 1.32,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: theme.brightness == Brightness.dark
                                      ? cs.surfaceContainerHigh
                                      : cs.surface,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    14,
                                    8,
                                    4,
                                    8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(22),
                                    borderSide: BorderSide(
                                      color: cs.outline.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(22),
                                    borderSide: BorderSide(
                                      color: cs.outline.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(22),
                                    borderSide: BorderSide(
                                      color: cs.outline.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      4,
                                      4,
                                      4,
                                    ),
                                    child: Material(
                                      color: sendBg,
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: (!canSend || _sending)
                                            ? null
                                            : () => _onTapSend(context),
                                        child: SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: Center(
                                            child: _sending
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : Icon(
                                                    Icons.arrow_upward,
                                                    color: sendIconColor,
                                                    size: 17,
                                                    semanticLabel: sendLabel,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  suffixIconConstraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 36,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 자유게시판 탭 - 홈탭/글상세 공통
class FreeBoardTab extends StatefulWidget {
  const FreeBoardTab({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.onRefresh,
    this.error,
    this.currentUserAuthor,
    this.onPostUpdated,
    this.onPostDeleted,
    this.onPostTap,
    this.onUserBlocked,
    this.enablePullToRefresh = true,
    this.shrinkWrap = false,
    this.useSimpleFeedLayout = false,
    this.feedScrollController,
    this.feedLoadingMore = false,
    this.feedHasMore = true,
    this.feedAuthorAvatarSize,
    this.useCardFeedLayout = false,
  });

  final List<Post> posts;
  final bool isLoading;
  final String? error;
  final String? currentUserAuthor;
  final Future<void> Function() onRefresh;
  final bool enablePullToRefresh;
  final bool shrinkWrap;
  final void Function(Post)? onPostUpdated;
  final void Function(Post)? onPostDeleted;
  final void Function(Post)? onPostTap;
  final VoidCallback? onUserBlocked;
  final bool useSimpleFeedLayout;
  final ScrollController? feedScrollController;
  final bool feedLoadingMore;
  final bool feedHasMore;
  final double? feedAuthorAvatarSize;

  /// false(기본): 구분선 리스트. true: 카드.
  final bool useCardFeedLayout;

  @override
  State<FreeBoardTab> createState() => _FreeBoardTabState();
}

class _FreeBoardTabState extends State<FreeBoardTab> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageInputController = TextEditingController();
  final GlobalKey _filterKey = GlobalKey();
  int _currentPage = 0;
  String _searchQuery = '';
  bool _showPageInput = false;
  PostSearchScope _searchScope = PostSearchScope.titleAndBody;
  Timer? _debounce;

  // 필터 캐시
  List<Post>? _cachedFiltered;
  List<Post>? _lastPosts;
  String? _lastSearchQuery;
  PostSearchScope? _lastSearchScope;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
  }

  void _onSearchTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _pageInputController.dispose();
    super.dispose();
  }

  void _submitSearch() => setState(
    () => _searchQuery = _searchController.text.trim().toLowerCase(),
  );

  bool _postMatchesQuery(Post p, String q) {
    final title = p.title.toLowerCase();
    final body = (p.body ?? '').toLowerCase();
    final author =
        (p.author.startsWith('u/') ? p.author.substring(2) : p.author)
            .toLowerCase();
    switch (_searchScope) {
      case PostSearchScope.titleAndBody:
        if (title.contains(q) || body.contains(q)) return true;
        for (final t in p.tags) {
          if (t.toLowerCase().contains(q)) return true;
        }
        return false;
      case PostSearchScope.title:
        return title.contains(q);
      case PostSearchScope.body:
        return body.contains(q);
      case PostSearchScope.comment:
        return p.commentsList.any((c) => commentContainsQuery(c, q));
      case PostSearchScope.nickname:
        return author.contains(q);
    }
  }

  List<Post> get _filteredPosts {
    if (_cachedFiltered != null &&
        identical(_lastPosts, widget.posts) &&
        _lastSearchQuery == _searchQuery &&
        _lastSearchScope == _searchScope) {
      return _cachedFiltered!;
    }
    var list = widget.posts;
    if (_searchQuery.isNotEmpty)
      list = list.where((p) => _postMatchesQuery(p, _searchQuery)).toList();
    _cachedFiltered = list;
    _lastPosts = widget.posts;
    _lastSearchQuery = _searchQuery;
    _lastSearchScope = _searchScope;
    return list;
  }

  List<Post> get _paginatedPosts {
    final f = _filteredPosts;
    final start = _currentPage * _postsPerPage;
    if (start >= f.length) return [];
    return f.sublist(start, (start + _postsPerPage).clamp(0, f.length));
  }

  int get _totalPages {
    final len = _filteredPosts.length;
    if (len == 0) return 0;
    return (len / _postsPerPage).ceil();
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(
              LucideIcons.search,
              size: 17,
              color: cs.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: CountryScope.of(context).strings.get('search'),
                hintStyle: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                  fontWeight: FontWeight.w400,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: cs.onSurface,
              ),
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: cs.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
            ),
          Container(
            width: 1,
            height: 22,
            color: cs.onSurface.withOpacity(0.08),
          ),
          GestureDetector(
            key: _filterKey,
            onTap: () async {
              final RenderBox btn =
                  _filterKey.currentContext!.findRenderObject() as RenderBox;
              final Offset btnOffset = btn.localToGlobal(Offset.zero);
              final Size screenSize = MediaQuery.of(context).size;
              final selected = await showMenu<PostSearchScope>(
                context: context,
                position: RelativeRect.fromRect(
                  Rect.fromLTWH(
                    btnOffset.dx,
                    btnOffset.dy,
                    btn.size.width,
                    btn.size.height,
                  ),
                  Offset.zero & screenSize,
                ),
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                items: postSearchScopeOrder.map((scope) {
                  final isSelected = scope == _searchScope;
                  return PopupMenuItem<PostSearchScope>(
                    value: scope,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        Text(
                          postSearchScopeLabel(scope, context),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        if (isSelected) ...[
                          const Spacer(),
                          Icon(
                            LucideIcons.check,
                            size: 14,
                            color: cs.onSurface,
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
              if (selected != null && mounted)
                setState(() => _searchScope = selected);
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    postSearchScopeLabel(_searchScope, context),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    LucideIcons.chevron_down,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalPagination(
    ColorScheme cs,
    int totalPages,
    int totalCount,
  ) {
    if (totalCount == 0 || totalPages == 0) return const SizedBox.shrink();
    final c = _currentPage;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: c > 0
                ? () => setState(() {
                    _currentPage = c - 1;
                    _showPageInput = false;
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                LucideIcons.chevron_left,
                size: 22,
                color: c > 0
                    ? cs.onSurface.withOpacity(0.75)
                    : cs.onSurface.withOpacity(0.18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() {
              _showPageInput = !_showPageInput;
              if (_showPageInput) _pageInputController.clear();
            }),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showPageInput
                  ? Container(
                      key: const ValueKey('input'),
                      width: 80,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? cs.outline
                              : const Color(0xFFFF6B35),
                          width: Theme.of(context).brightness == Brightness.dark
                              ? 1
                              : 1.2,
                        ),
                      ),
                      child: Center(
                        child: TextField(
                          controller: _pageInputController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: '페이지',
                            hintStyle: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            color: cs.onSurface,
                          ),
                          onSubmitted: (val) {
                            final n = int.tryParse(val);
                            if (n != null && n >= 1 && n <= totalPages)
                              setState(() {
                                _currentPage = n - 1;
                                _showPageInput = false;
                              });
                            else
                              setState(() => _showPageInput = false);
                          },
                        ),
                      ),
                    )
                  : Container(
                      key: const ValueKey('label'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${c + 1} / $totalPages',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: c < totalPages - 1
                ? () => setState(() {
                    _currentPage = c + 1;
                    _showPageInput = false;
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                LucideIcons.chevron_right,
                size: 22,
                color: c < totalPages - 1
                    ? cs.onSurface.withOpacity(0.75)
                    : cs.onSurface.withOpacity(0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapRefresh(Widget child) {
    if (widget.enablePullToRefresh) {
      return BlindRefreshIndicator(
        onRefresh: widget.onRefresh,
        spinnerOffsetDown: 17.0,
        child: child,
      );
    }
    return child;
  }

  Widget _buildSimpleFreeFeed(
    BuildContext context,
    ColorScheme cs,
    List<Post> posts,
    bool isLoading,
    String? error,
    Future<void> Function() onRefresh,
    String? currentUserAuthor,
    void Function(Post)? onPostUpdated,
    void Function(Post)? onPostDeleted,
  ) {
    final s = CountryScope.of(context).strings;
    if (isLoading && posts.isEmpty) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && posts.isEmpty) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.cloud_off,
              size: 56,
              color: cs.error.withOpacity(0.6),
            ),
            const SizedBox(height: 20),
            Text(
              '글을 불러오지 못했어요',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: cs.error,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onRefresh,
              child: Text(
                '다시 시도',
                style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary),
              ),
            ),
          ],
        ),
      );
    }
    if (posts.isEmpty) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.message_square_plus,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 24),
            Text(
              s.get('postSoon'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      );
    }
    final tabName = s.get('tabGeneral');
    final footerCount = (widget.feedLoadingMore && widget.feedHasMore) ? 1 : 0;
    final listView = ListView.builder(
      controller: widget.feedScrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 900,
      itemCount: posts.length + footerCount + 1,
      itemBuilder: (context, index) {
        if (index < posts.length) {
          final post = posts[index];
          if (widget.useCardFeedLayout) {
            return RepaintBoundary(
              child: FeedPostCard(
                key: ValueKey(post.id),
                post: post,
                currentUserAuthor: currentUserAuthor,
                onPostUpdated: onPostUpdated,
                onPostDeleted: onPostDeleted,
                tabName: tabName,
                onTap: widget.onPostTap != null
                    ? () => widget.onPostTap!(post)
                    : null,
                onUserBlocked: widget.onUserBlocked,
                authorAvatarSize: widget.feedAuthorAvatarSize,
              ),
            );
          }
          return RepaintBoundary(
            key: ValueKey('talk_list_${post.id}'),
            child: TalkAskFeedListRow(
              post: post,
              colorScheme: cs,
              showLeadingDivider: index > 0,
              onTap: widget.onPostTap != null
                  ? () => widget.onPostTap!(post)
                  : null,
            ),
          );
        }
        if (footerCount == 1 && index == posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            ),
          );
        }
        return SizedBox(
          height: widget.shrinkWrap ? 24 : _listBottomPadding(context),
        );
      },
    );
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.deferToChild,
      child: _wrapRefresh(listView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    final posts = widget.posts;
    final isLoading = widget.isLoading;
    final error = widget.error;
    final onRefresh = widget.onRefresh;
    final currentUserAuthor = widget.currentUserAuthor;
    final onPostUpdated = widget.onPostUpdated;
    final onPostDeleted = widget.onPostDeleted;

    if (widget.useSimpleFeedLayout) {
      return _buildSimpleFreeFeed(
        context,
        cs,
        posts,
        isLoading,
        error,
        onRefresh,
        currentUserAuthor,
        onPostUpdated,
        onPostDeleted,
      );
    }

    if (isLoading) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: [
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.cloud_off,
              size: 56,
              color: cs.error.withOpacity(0.6),
            ),
            const SizedBox(height: 20),
            Text(
              '글을 불러오지 못했어요',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: cs.error,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onRefresh,
              child: Text(
                '다시 시도',
                style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary),
              ),
            ),
          ],
        ),
      );
    }
    if (posts.isEmpty) {
      return _wrapRefresh(
        ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
          children: [
            const SizedBox(height: 8),
            Icon(
              LucideIcons.message_square_plus,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 24),
            Text(
              s.get('postSoon'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredPosts;
    final start = _currentPage * _postsPerPage;
    final paginated = start >= filtered.length
        ? <Post>[]
        : filtered.sublist(
            start,
            (start + _postsPerPage).clamp(0, filtered.length),
          );
    final totalPages = filtered.isEmpty
        ? 0
        : (filtered.length / _postsPerPage).ceil();
    if (_currentPage >= totalPages && _currentPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          setState(() => _currentPage = (totalPages - 1).clamp(0, 999999));
      });
    }

    final tabName = CountryScope.of(context).strings.get('tabGeneral');
    final listView = ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 900,
      itemCount: paginated.length + 4,
      itemBuilder: (context, index) {
        if (index < paginated.length) {
          final post = paginated[index];
          return RepaintBoundary(
            child: FeedPostCard(
              key: ValueKey(post.id),
              post: post,
              currentUserAuthor: currentUserAuthor,
              onPostUpdated: onPostUpdated,
              onPostDeleted: onPostDeleted,
              tabName: tabName,
              onTap: widget.onPostTap != null
                  ? () => widget.onPostTap!(post)
                  : null,
              onUserBlocked: widget.onUserBlocked,
              authorAvatarSize: widget.feedAuthorAvatarSize,
            ),
          );
        }
        if (index == paginated.length) return const SizedBox(height: 16);
        if (index == paginated.length + 1)
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildSearchBar(cs),
          );
        if (index == paginated.length + 2)
          return _buildMinimalPagination(cs, totalPages, filtered.length);
        return SizedBox(
          height: widget.shrinkWrap ? 24 : _listBottomPadding(context),
        );
      },
    );
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_showPageInput) setState(() => _showPageInput = false);
      },
      behavior: HitTestBehavior.deferToChild,
      child: _wrapRefresh(listView),
    );
  }
}

class _InlineReplyingToBanner extends StatelessWidget {
  const _InlineReplyingToBanner({
    required this.comment,
    required this.cs,
    required this.onCancel,
  });

  final PostComment comment;
  final ColorScheme cs;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final author = comment.author.startsWith('u/')
        ? comment.author.substring(2)
        : comment.author;
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Transform.rotate(
            angle: math.pi,
            child: const Icon(LucideIcons.reply, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Text(
            'Replying to $author',
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              comment.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 15,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
