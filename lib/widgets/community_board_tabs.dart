import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/feed_review_post_card.dart';
import '../widgets/feed_review_letterboxd_tile.dart';
import '../widgets/blind_refresh_indicator.dart';
import '../widgets/optimized_network_image.dart';
import '../screens/drama_detail_page.dart';
import '../screens/login_page.dart';

const int _postsPerPage = 20;

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
    case PostSearchScope.titleAndBody: return str.get('searchScopeTitleAndBody');
    case PostSearchScope.title: return str.get('searchScopeTitle');
    case PostSearchScope.body: return str.get('searchScopeBody');
    case PostSearchScope.comment: return str.get('searchScopeComment');
    case PostSearchScope.nickname: return str.get('searchScopeNickname');
  }
}

bool commentContainsQuery(PostComment c, String q) {
  if (c.text.toLowerCase().contains(q)) return true;
  return c.replies.any((r) => commentContainsQuery(r, q));
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

  final Set<String> _inlineLikeBusy = {};
  final Set<String> _inlineCommentSubmitting = {};
  /// 리뷰 본문 탭 시 아래에 댓글 목록 펼침(Letterboxd 인라인 피드).
  final Set<String> _expandedReviewComments = {};
  final Map<String, TextEditingController> _inlineCommentControllers = {};

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
    for (final c in _inlineCommentControllers.values) {
      c.dispose();
    }
    _inlineCommentControllers.clear();
    _searchController.dispose();
    _pageInputController.dispose();
    super.dispose();
  }

  Post _latestPost(Post p) {
    try {
      return widget.posts.firstWhere((e) => e.id == p.id);
    } catch (_) {
      return p;
    }
  }

  Future<void> _refreshPostForComments(String postId) async {
    final locale = CountryScope.maybeOf(context)?.country;
    final fresh = await PostService.instance.getPost(postId, locale);
    if (!mounted) return;
    if (fresh != null) widget.onPostUpdated?.call(fresh);
  }

  Future<void> _inlineToggleLike(Post post) async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    if (_inlineLikeBusy.contains(post.id)) return;
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return;
    final p = _latestPost(post);
    final liked = p.likedBy.contains(uid);
    final currentVote = liked ? 1 : (p.dislikedBy.contains(uid) ? -1 : 0);
    _inlineLikeBusy.add(p.id);
    final newLikedBy = List<String>.from(p.likedBy);
    if (!liked) {
      if (!newLikedBy.contains(uid)) newLikedBy.add(uid);
    } else {
      newLikedBy.remove(uid);
    }
    final likeVoteDelta = !liked ? (p.dislikedBy.contains(uid) ? 2 : 1) : -1;
    final optimistic = p.copyWith(
      votes: p.votes + likeVoteDelta,
      likedBy: newLikedBy,
      dislikedBy: !liked ? p.dislikedBy.where((u) => u != uid).toList() : p.dislikedBy,
    );
    widget.onPostUpdated?.call(optimistic);
    final ok = await PostService.instance.togglePostLike(
      p.id,
      currentVoteState: currentVote,
      postAuthorUid: p.authorUid,
      postTitle: p.title,
    );
    if (mounted) _inlineLikeBusy.remove(p.id);
    if (!mounted) return;
    if (ok == null) {
      final loc = CountryScope.maybeOf(context)?.country;
      final re = await PostService.instance.getPost(p.id, loc);
      if (re != null && mounted) widget.onPostUpdated?.call(re);
    }
  }

  Future<void> _openReviewCommentOverlay(Post post) async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    await UserProfileService.instance.loadIfNeeded();
    if (!mounted) return;
    final id = post.id;
    _inlineCommentControllers.putIfAbsent(id, TextEditingController.new);
    _refreshPostForComments(id);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (routeContext, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: _ReviewCommentComposerOverlay(
              controller: _inlineCommentControllers[id]!,
              onSend: (overlayCtx) => _submitInlineComment(post, successPopContext: overlayCtx),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitInlineComment(Post post, {BuildContext? successPopContext}) async {
    final id = post.id;
    final ctrl = _inlineCommentControllers[id];
    if (ctrl == null) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    if (_inlineCommentSubmitting.contains(id)) return;
    setState(() => _inlineCommentSubmitting.add(id));
    final s = CountryScope.of(context).strings;
    await UserProfileService.instance.loadIfNeeded();
    if (!mounted) return;
    final nickname = UserProfileService.instance.nicknameNotifier.value;
    final displayName = AuthService.instance.currentUser.value?.displayName;
    final email = AuthService.instance.currentUser.value?.email;
    var author = nickname?.trim().isNotEmpty == true
        ? nickname!.trim()
        : (displayName?.trim().isNotEmpty == true ? displayName!.trim() : (email != null ? email.split('@').first : ''));
    if (author.isEmpty) author = '익명';
    final p = _latestPost(post);
    final newComment = PostComment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: author,
      timeAgo: s.get('timeAgoJustNow'),
      text: text,
      votes: 0,
      replies: const [],
      authorPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
      authorAvatarColorIndex: UserProfileService.instance.avatarColorNotifier.value,
    );
    final err = await PostService.instance.addComment(id, p, newComment);
    if (!mounted) return;
    if (err != null) {
      setState(() => _inlineCommentSubmitting.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err, style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _inlineCommentSubmitting.remove(id));
    ctrl.clear();
    if (successPopContext != null && successPopContext.mounted) {
      Navigator.of(successPopContext).pop();
    }
    await _refreshPostForComments(id);
  }

  DramaItem? _findDramaItemForPost(Post post, String? locale) {
    final rawId = post.dramaId?.trim();
    if (rawId != null && rawId.isNotEmpty) {
      for (final d in DramaListService.instance.listNotifier.value) {
        if (d.id == rawId) return d;
      }
      final titleSource = post.dramaTitle?.trim().isNotEmpty == true ? post.dramaTitle! : post.title;
      final resolved = DramaListService.instance.getDisplayTitle(rawId, locale);
      return DramaItem(
        id: rawId,
        title: resolved.isNotEmpty ? resolved : titleSource,
        subtitle: '',
        views: '0',
        rating: post.rating ?? 0,
        imageUrl: (post.dramaThumbnail?.trim().isNotEmpty == true) ? post.dramaThumbnail!.trim() : null,
      );
    }
    final titleGuess = post.dramaTitle?.trim().isNotEmpty == true ? post.dramaTitle! : post.title;
    if (titleGuess.trim().isEmpty) return null;
    final tg = titleGuess.trim();
    for (final d in DramaListService.instance.listNotifier.value) {
      final dt = DramaListService.instance.getDisplayTitle(d.id, locale);
      if (dt == tg || d.title == tg) return d;
    }
    return null;
  }

  Future<void> _openDramaDetailForPost(
    BuildContext context,
    Post post, {
    bool scrollToReviews = false,
  }) async {
    await DramaListService.instance.loadFromAsset();
    if (!context.mounted) return;
    final locale = CountryScope.maybeOf(context)?.country;
    final item = _findDramaItemForPost(post, locale);
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('드라마 정보를 찾을 수 없어요', style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final detail = DramaListService.instance.buildDetailForItem(item, locale);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => DramaDetailPage(detail: detail, scrollToRatings: scrollToReviews),
      ),
    );
  }

  void _toggleReviewBodyComments(Post post) {
    final id = post.id;
    final opening = !_expandedReviewComments.contains(id);
    setState(() {
      if (opening) {
        _expandedReviewComments.add(id);
      } else {
        _expandedReviewComments.remove(id);
      }
    });
    if (opening) _refreshPostForComments(id);
  }

  void _flattenCommentsInto(List<PostComment> roots, List<PostComment> out) {
    for (final c in roots) {
      out.add(c);
      if (c.replies.isNotEmpty) _flattenCommentsInto(c.replies, out);
    }
  }

  Widget _buildFlatCommentRow(PostComment c, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.author.startsWith('u/') ? c.author.substring(2) : c.author,
                  style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
              ),
              Text(
                c.displayTimeAgo,
                style: GoogleFonts.notoSansKr(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c.text,
            style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewInlineCommentsListPanel(Post post, ColorScheme cs) {
    final p = _latestPost(post);
    final flat = <PostComment>[];
    _flattenCommentsInto(p.commentsList, flat);
    if (flat.isEmpty) return const SizedBox.shrink();
    return ColoredBox(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: flat.map((c) => _buildFlatCommentRow(c, cs)).toList(),
        ),
      ),
    );
  }

  Widget _buildReviewInlineActionBar(Post post, ColorScheme cs, dynamic s) {
    final p = _latestPost(post);
    final uid = AuthService.instance.currentUser.value?.uid;
    final liked = uid != null && p.likedBy.contains(uid);
    const iconSize = 13.0;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _inlineToggleLike(post),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    size: iconSize,
                    color: liked ? Colors.redAccent : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(p.likedBy.length),
                    style: GoogleFonts.notoSansKr(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _openReviewCommentOverlay(post),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.message_circle, size: iconSize, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(p.comments),
                    style: GoogleFonts.notoSansKr(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submitSearch() => setState(() => _searchQuery = _searchController.text.trim().toLowerCase());

  bool _postMatchesQuery(Post p, String q) {
    final title = p.title.toLowerCase();
    final body = (p.body ?? '').toLowerCase();
    final author = (p.author.startsWith('u/') ? p.author.substring(2) : p.author).toLowerCase();
    switch (_searchScope) {
      case PostSearchScope.titleAndBody: return title.contains(q) || body.contains(q);
      case PostSearchScope.title: return title.contains(q);
      case PostSearchScope.body: return body.contains(q);
      case PostSearchScope.comment: return p.commentsList.any((c) => commentContainsQuery(c, q));
      case PostSearchScope.nickname: return author.contains(q);
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
    if (_searchQuery.isNotEmpty) list = list.where((p) => _postMatchesQuery(p, _searchQuery)).toList();
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
            child: Icon(LucideIcons.search, size: 17, color: cs.onSurfaceVariant.withOpacity(0.8)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: CountryScope.of(context).strings.get('search'),
                hintStyle: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurfaceVariant.withOpacity(0.7), fontWeight: FontWeight.w400),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: GoogleFonts.notoSansKr(fontSize: 14, fontWeight: FontWeight.w400, color: cs.onSurface),
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () { _searchController.clear(); setState(() => _searchQuery = ''); },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant.withOpacity(0.8)),
              ),
            ),
          Container(width: 1, height: 22, color: cs.onSurface.withOpacity(0.08)),
          GestureDetector(
            key: _filterKey,
            onTap: () async {
              final RenderBox btn = _filterKey.currentContext!.findRenderObject() as RenderBox;
              final Offset btnOffset = btn.localToGlobal(Offset.zero);
              final Size screenSize = MediaQuery.of(context).size;
              final selected = await showMenu<PostSearchScope>(
                context: context,
                position: RelativeRect.fromRect(
                  Rect.fromLTWH(btnOffset.dx, btnOffset.dy, btn.size.width, btn.size.height),
                  Offset.zero & screenSize,
                ),
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                items: postSearchScopeOrder.map((scope) {
                  final isSelected = scope == _searchScope;
                  return PopupMenuItem<PostSearchScope>(
                    value: scope,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Row(
                      children: [
                        Text(postSearchScopeLabel(scope, context), style: GoogleFonts.notoSansKr(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? cs.onSurface : cs.onSurfaceVariant)),
                        if (isSelected) ...[const Spacer(), Icon(LucideIcons.check, size: 14, color: cs.onSurface)],
                      ],
                    ),
                  );
                }).toList(),
              );
              if (selected != null && mounted) setState(() => _searchScope = selected);
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(postSearchScopeLabel(_searchScope, context), style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(width: 3),
                  Icon(LucideIcons.chevron_down, size: 13, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalPagination(ColorScheme cs, int totalPages, int totalCount) {
    if (totalCount == 0 || totalPages == 0) return const SizedBox.shrink();
    final c = _currentPage;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: c > 0 ? () => setState(() { _currentPage = c - 1; _showPageInput = false; }) : null,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.chevron_left, size: 22, color: c > 0 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18))),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() { _showPageInput = !_showPageInput; if (_showPageInput) _pageInputController.clear(); }),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showPageInput
                  ? Container(
                      key: const ValueKey('input'),
                      width: 80, height: 34,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark ? cs.outline : const Color(0xFFFF6B35),
                          width: Theme.of(context).brightness == Brightness.dark ? 1 : 1.2,
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
                            hintStyle: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurface),
                          onSubmitted: (val) {
                            final n = int.tryParse(val);
                            if (n != null && n >= 1 && n <= totalPages) setState(() { _currentPage = n - 1; _showPageInput = false; });
                            else setState(() => _showPageInput = false);
                          },
                        ),
                      ),
                    )
                  : Container(
                      key: const ValueKey('label'),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
                      child: Text('${c + 1} / $totalPages', style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant, letterSpacing: 0.2)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: c < totalPages - 1 ? () => setState(() { _currentPage = c + 1; _showPageInput = false; }) : null,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.chevron_right, size: 22, color: c < totalPages - 1 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18))),
          ),
        ],
      ),
    );
  }

  Widget _wrapRefresh(Widget child) {
    if (widget.enablePullToRefresh) {
      return BlindRefreshIndicator(onRefresh: widget.onRefresh, spinnerOffsetDown: 17.0, child: child);
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
          children: const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && posts.isEmpty) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.cloud_off, size: 56, color: cs.error.withOpacity(0.6)),
          const SizedBox(height: 20),
          Text('글을 불러오지 못했어요', textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(error, textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.error, height: 1.5)),
          const SizedBox(height: 20),
          TextButton(onPressed: onRefresh, child: Text('다시 시도', style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary))),
        ],
      ));
    }
    if (posts.isEmpty) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(
            widget.useReviewLayout ? LucideIcons.star : LucideIcons.trending_up,
            size: 64,
            color: cs.onSurfaceVariant.withOpacity(0.4),
          ),
          const SizedBox(height: 24),
          Text(s.get('postSoon'), textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            widget.useReviewLayout ? s.get('reviewsTabEmpty') : s.get('trendTabHint'),
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ));
    }

    final tabName = widget.listTabLabel ?? (widget.useReviewLayout ? s.get('tabReviews') : s.get('tabHot'));
    bool isTypedReview(Post p) => p.type?.trim().toLowerCase() == 'review';
    final useLb = widget.useReviewLayout && widget.useLetterboxdReviewLayout;
    final footerCount = (widget.feedLoadingMore && widget.feedHasMore) ? 1 : 0;
    final listView = ListView.builder(
      controller: widget.feedScrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 400,
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
                      thickness: 0.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                  FeedReviewLetterboxdTile(
                    post: post,
                    onTap: (!inline && widget.onPostTap != null) ? () => widget.onPostTap!(post) : null,
                    thumbTrailingActions: inline ? _buildReviewInlineActionBar(post, cs, s) : null,
                    onDramaTap: inline ? () => _openDramaDetailForPost(context, post) : null,
                    onReviewBodyTap: inline ? () => _toggleReviewBodyComments(post) : null,
                    onRatingTap: inline ? () => _openDramaDetailForPost(context, post, scrollToReviews: true) : null,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                  ),
                  if (inline && _expandedReviewComments.contains(post.id))
                    _buildReviewInlineCommentsListPanel(post, cs),
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
                    onTap: widget.onPostTap != null ? () => widget.onPostTap!(post) : null,
                    onUserBlocked: widget.onUserBlocked,
                  )
                : FeedPostCard(
                    key: ValueKey(post.id),
                    post: post,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    tabName: tabName,
                    onTap: widget.onPostTap != null ? () => widget.onPostTap!(post) : null,
                    onUserBlocked: widget.onUserBlocked,
                  ),
          );
        }
        if (footerCount == 1 && index == posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))),
          );
        }
        return SizedBox(height: widget.shrinkWrap ? 24 : _listBottomPadding(context));
      },
    );
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
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
      return _buildSimplePopularFeed(context, cs, posts, isLoading, error, onRefresh, currentUserAuthor, onPostUpdated, onPostDeleted);
    }

    if (isLoading) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.cloud_off, size: 56, color: cs.error.withOpacity(0.6)),
          const SizedBox(height: 20),
          Text('글을 불러오지 못했어요', textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(error!, textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.error, height: 1.5)),
          const SizedBox(height: 20),
          TextButton(onPressed: onRefresh, child: Text('다시 시도', style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary))),
        ],
      ));
    }
    if (posts.isEmpty) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(
            widget.useReviewLayout ? LucideIcons.star : LucideIcons.trending_up,
            size: 64,
            color: cs.onSurfaceVariant.withOpacity(0.4),
          ),
          const SizedBox(height: 24),
          Text(s.get('postSoon'), textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            widget.useReviewLayout ? s.get('reviewsTabEmpty') : s.get('trendTabHint'),
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ));
    }

    final filtered = _filteredPosts;
    final start = _currentPage * _postsPerPage;
    final paginated = start >= filtered.length ? <Post>[] : filtered.sublist(start, (start + _postsPerPage).clamp(0, filtered.length));
    final totalPages = filtered.isEmpty ? 0 : (filtered.length / _postsPerPage).ceil();
    if (_currentPage >= totalPages && _currentPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentPage = (totalPages - 1).clamp(0, 999999));
      });
    }

    final tabName = widget.listTabLabel ??
        (widget.useReviewLayout ? s.get('tabReviews') : s.get('tabHot'));
    bool isTypedReview(Post p) => p.type?.trim().toLowerCase() == 'review';

    final listView = ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 400,
      itemCount: paginated.length + 4,
      itemBuilder: (context, index) {
        if (index < paginated.length) {
          final post = paginated[index];
          final useLb = widget.useReviewLayout && widget.useLetterboxdReviewLayout;
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
                      thickness: 0.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                  FeedReviewLetterboxdTile(
                    post: post,
                    onTap: (!inline && widget.onPostTap != null) ? () => widget.onPostTap!(post) : null,
                    thumbTrailingActions: inline ? _buildReviewInlineActionBar(post, cs, s) : null,
                    onDramaTap: inline ? () => _openDramaDetailForPost(context, post) : null,
                    onReviewBodyTap: inline ? () => _toggleReviewBodyComments(post) : null,
                    onRatingTap: inline ? () => _openDramaDetailForPost(context, post, scrollToReviews: true) : null,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                  ),
                  if (inline && _expandedReviewComments.contains(post.id))
                    _buildReviewInlineCommentsListPanel(post, cs),
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
                    onTap: widget.onPostTap != null ? () => widget.onPostTap!(post) : null,
                    onUserBlocked: widget.onUserBlocked,
                  )
                : FeedPostCard(
                    key: ValueKey(post.id),
                    post: post,
                    currentUserAuthor: currentUserAuthor,
                    onPostUpdated: onPostUpdated,
                    onPostDeleted: onPostDeleted,
                    tabName: tabName,
                    onTap: widget.onPostTap != null ? () => widget.onPostTap!(post) : null,
                    onUserBlocked: widget.onUserBlocked,
                  ),
          );
        }
        if (index == paginated.length) return const SizedBox(height: 16);
        if (index == paginated.length + 1) return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildSearchBar(cs));
        if (index == paginated.length + 2) return _buildMinimalPagination(cs, totalPages, filtered.length);
        return SizedBox(height: widget.shrinkWrap ? 24 : _listBottomPadding(context));
      },
    );
    return GestureDetector(
      onTap: () { FocusScope.of(context).unfocus(); if (_showPageInput) setState(() => _showPageInput = false); },
      behavior: HitTestBehavior.translucent,
      child: _wrapRefresh(listView),
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
  State<_ReviewCommentComposerOverlay> createState() => _ReviewCommentComposerOverlayState();
}

class _ReviewCommentComposerOverlayState extends State<_ReviewCommentComposerOverlay> {
  bool _sending = false;

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
        child: Icon(Icons.person, size: size * 0.55, color: UserProfileService.iconColorFromIndex(colorIdx)),
      ),
    );
  }

  Future<void> _onTapSend(BuildContext overlayContext) async {
    if (_sending) return;
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
    final sendLabel = CountryScope.maybeOf(context)?.strings.get('replySubmit') ?? '';

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
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        UserProfileService.instance.profileImageUrlNotifier,
                        UserProfileService.instance.avatarColorNotifier,
                      ]),
                      builder: (context, _) {
                        final rawUrl = UserProfileService.instance.profileImageUrlNotifier.value;
                        final url = rawUrl?.trim();
                        final colorIdx = UserProfileService.instance.avatarColorNotifier.value ?? 0;
                        final Widget avatar = (url != null && url.isNotEmpty)
                            ? ClipOval(
                                child: OptimizedNetworkImage.avatar(
                                  imageUrl: url,
                                  size: 36,
                                  errorWidget: _defaultAvatar(colorIdx, 36),
                                ),
                              )
                            : _defaultAvatar(colorIdx, 36);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            avatar,
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: widget.controller,
                                autofocus: true,
                                minLines: 1,
                                maxLines: 6,
                                style: GoogleFonts.notoSansKr(fontSize: 15, height: 1.35),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: theme.brightness == Brightness.dark
                                      ? cs.surfaceContainerHigh
                                      : cs.surface,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(26),
                                    borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.28)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(26),
                                    borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.28)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(26),
                                    borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.45)),
                                  ),
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
                                    child: Material(
                                      color: _sendBlue,
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () {
                                          if (_sending) return;
                                          _onTapSend(context);
                                        },
                                        child: SizedBox(
                                          width: 34,
                                          height: 34,
                                          child: Center(
                                            child: _sending
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : Icon(
                                                    Icons.arrow_upward,
                                                    color: Colors.white,
                                                    size: 19,
                                                    semanticLabel: sendLabel,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  suffixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
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

  void _submitSearch() => setState(() => _searchQuery = _searchController.text.trim().toLowerCase());

  bool _postMatchesQuery(Post p, String q) {
    final title = p.title.toLowerCase();
    final body = (p.body ?? '').toLowerCase();
    final author = (p.author.startsWith('u/') ? p.author.substring(2) : p.author).toLowerCase();
    switch (_searchScope) {
      case PostSearchScope.titleAndBody: return title.contains(q) || body.contains(q);
      case PostSearchScope.title: return title.contains(q);
      case PostSearchScope.body: return body.contains(q);
      case PostSearchScope.comment: return p.commentsList.any((c) => commentContainsQuery(c, q));
      case PostSearchScope.nickname: return author.contains(q);
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
    if (_searchQuery.isNotEmpty) list = list.where((p) => _postMatchesQuery(p, _searchQuery)).toList();
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
            child: Icon(LucideIcons.search, size: 17, color: cs.onSurfaceVariant.withOpacity(0.8)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: CountryScope.of(context).strings.get('search'),
                hintStyle: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurfaceVariant.withOpacity(0.7), fontWeight: FontWeight.w400),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: GoogleFonts.notoSansKr(fontSize: 14, fontWeight: FontWeight.w400, color: cs.onSurface),
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () { _searchController.clear(); setState(() => _searchQuery = ''); },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant.withOpacity(0.8)),
              ),
            ),
          Container(width: 1, height: 22, color: cs.onSurface.withOpacity(0.08)),
          GestureDetector(
            key: _filterKey,
            onTap: () async {
              final RenderBox btn = _filterKey.currentContext!.findRenderObject() as RenderBox;
              final Offset btnOffset = btn.localToGlobal(Offset.zero);
              final Size screenSize = MediaQuery.of(context).size;
              final selected = await showMenu<PostSearchScope>(
                context: context,
                position: RelativeRect.fromRect(
                  Rect.fromLTWH(btnOffset.dx, btnOffset.dy, btn.size.width, btn.size.height),
                  Offset.zero & screenSize,
                ),
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                items: postSearchScopeOrder.map((scope) {
                  final isSelected = scope == _searchScope;
                  return PopupMenuItem<PostSearchScope>(
                    value: scope,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Row(
                      children: [
                        Text(postSearchScopeLabel(scope, context), style: GoogleFonts.notoSansKr(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? cs.onSurface : cs.onSurfaceVariant)),
                        if (isSelected) ...[const Spacer(), Icon(LucideIcons.check, size: 14, color: cs.onSurface)],
                      ],
                    ),
                  );
                }).toList(),
              );
              if (selected != null && mounted) setState(() => _searchScope = selected);
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(postSearchScopeLabel(_searchScope, context), style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(width: 3),
                  Icon(LucideIcons.chevron_down, size: 13, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalPagination(ColorScheme cs, int totalPages, int totalCount) {
    if (totalCount == 0 || totalPages == 0) return const SizedBox.shrink();
    final c = _currentPage;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: c > 0 ? () => setState(() { _currentPage = c - 1; _showPageInput = false; }) : null,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.chevron_left, size: 22, color: c > 0 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18))),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() { _showPageInput = !_showPageInput; if (_showPageInput) _pageInputController.clear(); }),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showPageInput
                  ? Container(
                      key: const ValueKey('input'),
                      width: 80, height: 34,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark ? cs.outline : const Color(0xFFFF6B35),
                          width: Theme.of(context).brightness == Brightness.dark ? 1 : 1.2,
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
                            hintStyle: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurface),
                          onSubmitted: (val) {
                            final n = int.tryParse(val);
                            if (n != null && n >= 1 && n <= totalPages) setState(() { _currentPage = n - 1; _showPageInput = false; });
                            else setState(() => _showPageInput = false);
                          },
                        ),
                      ),
                    )
                  : Container(
                      key: const ValueKey('label'),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
                      child: Text('${c + 1} / $totalPages', style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant, letterSpacing: 0.2)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: c < totalPages - 1 ? () => setState(() { _currentPage = c + 1; _showPageInput = false; }) : null,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.chevron_right, size: 22, color: c < totalPages - 1 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18))),
          ),
        ],
      ),
    );
  }

  Widget _wrapRefresh(Widget child) {
    if (widget.enablePullToRefresh) {
      return BlindRefreshIndicator(onRefresh: widget.onRefresh, spinnerOffsetDown: 17.0, child: child);
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
          children: const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && posts.isEmpty) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.cloud_off, size: 56, color: cs.error.withOpacity(0.6)),
          const SizedBox(height: 20),
          Text('글을 불러오지 못했어요', textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(error, textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.error, height: 1.5)),
          const SizedBox(height: 20),
          TextButton(onPressed: onRefresh, child: Text('다시 시도', style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary))),
        ],
      ));
    }
    if (posts.isEmpty) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.message_square_plus, size: 64, color: cs.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 24),
          Text(s.get('postSoon'), textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ));
    }
    final tabName = s.get('tabGeneral');
    final footerCount = (widget.feedLoadingMore && widget.feedHasMore) ? 1 : 0;
    final listView = ListView.builder(
      controller: widget.feedScrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 400,
      itemCount: posts.length + footerCount + 1,
      itemBuilder: (context, index) {
        if (index < posts.length) {
          final post = posts[index];
          return RepaintBoundary(
            child: FeedPostCard(
              key: ValueKey(post.id),
              post: post,
              currentUserAuthor: currentUserAuthor,
              onPostUpdated: onPostUpdated,
              onPostDeleted: onPostDeleted,
              tabName: tabName,
              onTap: widget.onPostTap != null ? () => widget.onPostTap!(post) : null,
              onUserBlocked: widget.onUserBlocked,
            ),
          );
        }
        if (footerCount == 1 && index == posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))),
          );
        }
        return SizedBox(height: widget.shrinkWrap ? 24 : _listBottomPadding(context));
      },
    );
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
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
      return _buildSimpleFreeFeed(context, cs, posts, isLoading, error, onRefresh, currentUserAuthor, onPostUpdated, onPostDeleted);
    }

    if (isLoading) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.cloud_off, size: 56, color: cs.error.withOpacity(0.6)),
          const SizedBox(height: 20),
          Text('글을 불러오지 못했어요', textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(error!, textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.error, height: 1.5)),
          const SizedBox(height: 20),
          TextButton(onPressed: onRefresh, child: Text('다시 시도', style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary))),
        ],
      ));
    }
    if (posts.isEmpty) {
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, _listBottomPadding(context)),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.message_square_plus, size: 64, color: cs.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 24),
          Text(s.get('postSoon'), textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ));
    }

    final filtered = _filteredPosts;
    final start = _currentPage * _postsPerPage;
    final paginated = start >= filtered.length ? <Post>[] : filtered.sublist(start, (start + _postsPerPage).clamp(0, filtered.length));
    final totalPages = filtered.isEmpty ? 0 : (filtered.length / _postsPerPage).ceil();
    if (_currentPage >= totalPages && _currentPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentPage = (totalPages - 1).clamp(0, 999999));
      });
    }

    final tabName = CountryScope.of(context).strings.get('tabGeneral');
    final listView = ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 400,
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
              onTap: widget.onPostTap != null ? () => widget.onPostTap!(post) : null,
              onUserBlocked: widget.onUserBlocked,
            ),
          );
        }
        if (index == paginated.length) return const SizedBox(height: 16);
        if (index == paginated.length + 1) return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildSearchBar(cs));
        if (index == paginated.length + 2) return _buildMinimalPagination(cs, totalPages, filtered.length);
        return SizedBox(height: widget.shrinkWrap ? 24 : _listBottomPadding(context));
      },
    );
    return GestureDetector(
      onTap: () { FocusScope.of(context).unfocus(); if (_showPageInput) setState(() => _showPageInput = false); },
      behavior: HitTestBehavior.translucent,
      child: _wrapRefresh(listView),
    );
  }
}
