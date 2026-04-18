import 'dart:async';
import 'dart:io';
import 'dart:math' show max, pi;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/browser_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/format_utils.dart';
import '../utils/post_board_utils.dart';
import '../config/app_moderators.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/home_tab_visibility.dart';
import '../services/block_service.dart';
import '../services/level_service.dart';
import '../services/message_service.dart';
import '../services/locale_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/share_sheet.dart';
import '../widgets/review_share_card.dart';
import '../constants/app_profile_avatar_size.dart';
import '../models/post.dart';
import '../models/drama.dart';
import '../services/drama_list_service.dart';
import 'drama_detail_page.dart';
import 'login_page.dart';
import 'message_thread_screen.dart';
import 'user_posts_screen.dart';
import 'full_screen_image_page.dart';
import 'full_screen_video_page.dart';
import 'write_post_page.dart';
import 'community_search_page.dart';
import 'notification_screen.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/app_delete_confirm_dialog.dart';
import '../widgets/blind_refresh_indicator.dart';
import '../widgets/community_board_tabs.dart';
import '../widgets/user_profile_nav.dart';
import 'package:video_player/video_player.dart';
import '../widgets/feed_inline_action_colors.dart';
import '../widgets/feed_post_card.dart'
    show VideoPreloadCache, TalkAskHeartVote, talkAskIconCountGap;
import '../widgets/feed_review_post_card.dart';

// 글 상세 하단: 구분선/여백을 상수로 두어 글이 몇 개든 동일하게 보이도록 함
const double _kBrowserNavBarHeight = 48; // 하단 네비 바 높이 (BrowserNavBar와 동일)
const double _kMorePostsDividerHeight = 40; // 댓글 영역 ~ 인기/자유/질문 탭 사이 얇은 구분선

/// 첫 프레임은 가벼운 placeholder만 — 전환이 바로 시작된 뒤 다음 프레임에서 [builder]로 본문 생성
class _DeferredFrame2Body extends StatefulWidget {
  const _DeferredFrame2Body({
    required this.placeholderColor,
    required this.builder,
  });

  final Color placeholderColor;
  final Widget Function() builder;

  @override
  State<_DeferredFrame2Body> createState() => _DeferredFrame2BodyState();
}

class _DeferredFrame2BodyState extends State<_DeferredFrame2Body> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return ColoredBox(
        color: widget.placeholderColor,
        child: const SizedBox.expand(),
      );
    }
    return widget.builder();
  }
}

class _PostDetailPickFromFiles {
  const _PostDetailPickFromFiles();
}

/// PostDetailPage pop 시 반환값
class PostDetailResult {
  const PostDetailResult({
    this.updatedPost,
    this.backStack = const [],
    this.forwardStack = const [],
    this.tabIndex = 0,
  });
  final Post? updatedPost;
  final List<(Post, int)> backStack;
  final List<(Post, int)> forwardStack;
  final int tabIndex;
}

/// 글 상세 - 레딧 스타일
class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
    super.key,
    required this.post,
    this.onPostDeleted,
    this.tabName,
    this.initialBackStack = const [],
    this.initialForwardStack = const [],
    this.initialTabIndex,
    this.initialBoardPosts,
    this.hideBelowLetterboxdLike = false,

    /// [hideBelowLetterboxdLike]인 Letterboxd 리뷰에서 댓글 목록·입력까지 숨김. false면 프로필 Posts 등에서 댓글 유지.
    this.suppressLetterboxdCommentsSection = true,

    /// true면 글 상세 하단 DramaFeed(리뷰/톡/질문 탭 목록)만 숨김. 리뷰 본문·댓글·Film 버튼은 유지 ([hideBelowLetterboxdLike]와 별개).
    this.hideBottomDramaFeed = false,

    /// Firestore에 없는 로컬 전용 합성 리뷰 글 — 조회수/재조회/좋아요 API·편집·삭제 생략.
    this.offlineSyntheticReview = false,

    /// 홈 톡/에스크와 동일: false면 하단 DramaFeed 자유·질문 탭에 [TalkAskFeedListRow], true면 [FeedPostCard].
    /// 커뮤니티에서만 넘기면 됨. 생략 시 true(기존 글상세 하단 동작).
    this.dramaFeedTalkAskUseCardFeedLayout = true,

    /// 워치 전용 로그 — 별점 행·LIKE 행 숨김. [hideBelowLetterboxdLike]와 함께 사용.
    this.hideLetterboxdRatingAndLike = false,

    /// 타이틀을 강제로 "Watch"로 표시. [hideLetterboxdRatingAndLike]와 독립적으로 동작.
    this.forceWatchPageTitle = false,
  });

  final Post post;
  final void Function(Post)? onPostDeleted;
  final String? tabName;
  final List<(Post, int)> initialBackStack;
  final List<(Post, int)> initialForwardStack;
  final int? initialTabIndex;

  /// 홈탭 게시판 목록(인기글/자유/질문). 넘기면 글 상세 하단 DramaFeed에 그대로 표시
  final List<Post>? initialBoardPosts;

  /// 프로필 Recent Activity 등 — Letterboxd 리뷰 상세에서 LIKE 행 아래(Film·댓글·피드) 숨김.
  final bool hideBelowLetterboxdLike;

  /// [hideBelowLetterboxdLike]일 때 댓글 블록까지 숨길지(기본 true). false면 댓글만 표시.
  final bool suppressLetterboxdCommentsSection;

  /// 라이크 리뷰 등 — 하단 DramaFeed만 숨김(댓글·Film 유지).
  final bool hideBottomDramaFeed;

  /// [hideBelowLetterboxdLike]와 함께 쓰는 로컬-only 리뷰 상세 (posts 문서 없음).
  final bool offlineSyntheticReview;

  /// 하단 DramaFeed 톡/에스크 레이아웃 — [CommunityScreen._talkAskUseCardFeedLayout]과 맞춤.
  final bool dramaFeedTalkAskUseCardFeedLayout;

  /// 워치 전용 로그 상세 — 별점 행·LIKE 행 숨김.
  final bool hideLetterboxdRatingAndLike;

  /// 타이틀을 "Watch"로 강제 표시 (LIKE 행 표시 여부와 독립적).
  final bool forceWatchPageTitle;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _commentsKey = GlobalKey();
  final GlobalKey _inputCardKey = GlobalKey();
  final GlobalKey _inlineReplyInputKey = GlobalKey();
  final GlobalKey _morePostsSectionKey = GlobalKey();
  final GlobalKey _newCommentKey = GlobalKey();

  /// 등록 직후 이 댓글을 화면 맨 위로 스크롤할 id (한 번 쓰고 null로 초기화)
  String? _scrollToCommentId;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLiked = false;
  bool _isDisliked = false;
  bool _votePending = false;
  Post? _currentPost;
  String? _currentUserAuthor;

  /// 답글 달 댓글 id (null이면 일반 댓글)
  String? _replyingToCommentId;
  bool _isSubmittingComment = false;
  int _commentLines = 2;

  /// 댓글에 첨부할 이미지/GIF 로컬 경로 (선택 시 설정, 전송 후 초기화)
  String? _commentImagePath;
  final ValueNotifier<String?> _commentImagePathNotifier =
      ValueNotifier<String?>(null);

  /// 현재 화면에 표시 중인 최상위 댓글 수 (무한스크롤)
  int _visibleCommentCount = 15;
  static const int _commentsPageSize = 10;
  final ValueNotifier<bool> _commentSortByTop = ValueNotifier(
    false,
  ); // true: 추천순, false: 시간순
  bool _showFab = false;
  late int _morePostsTabIndex;

  /// 초기 라우트 [tabName]으로 탭 인덱스를 한 번만 맞춤(하단에서 다른 글로 이동 후에는 덮어쓰지 않음)
  bool _morePostsTabSyncedFromRoute = false;
  Timer? _keyboardDebounceTimer;

  /// 톡·에스크 좋아요: 네트워크 디바운스 타이머 (피드 카드와 동일 패턴)
  Timer? _talkAskLikeDebounce;

  /// 초기 [getPost] 등과 낙관적 좋아요 레이스 시 서버 스냅샷이 덮어쓰지 않도록
  bool _talkAskLikeInFlight = false;
  bool _isRefreshing = false;

  /// Letterboxd 리뷰 상세: 스포일러 본문 공개 여부 (글 바뀌면 초기화)
  bool _reviewSpoilerRevealed = false;
  String? _letterboxdSpoilerBoundPostId;
  // 브라우저 히스토리 스택 (Post, tabIndex)
  late final List<(Post, int)> _backStack;
  late final List<(Post, int)> _forwardStack;

  Post get _post => _currentPost ?? widget.post;
  bool get _isMine {
    final myUid = AuthService.instance.currentUser.value?.uid.trim();
    if (myUid != null && myUid.isNotEmpty && _post.authorUid?.trim() == myUid) {
      return true;
    }
    return _currentUserAuthor != null && _post.author == _currentUserAuthor;
  }

  /// 운영자는 타인 글도 삭제 가능(UID는 [kAppModeratorAuthUids]).
  bool get _canDeletePost => _isMine || isAppModerator();

  Future<void> _showPostAuthorMenu(
    BuildContext context,
    String author,
    TapDownDetails details,
  ) async {
    if (author.isEmpty) return;
    final kind = postDisplayType(_post);
    if (kind == 'talk' || kind == 'ask') return;
    final s = CountryScope.of(context).strings;
    final displayName = author.startsWith('u/') ? author.substring(2) : author;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 1,
        details.globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'message',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.mail, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
              Text(
                s.get('sendMessageToUser'),
                style: GoogleFonts.notoSansKr(fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'posts',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.file_text, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                s.get('viewUserPosts'),
                style: GoogleFonts.notoSansKr(fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'comments',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.message_circle, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                s.get('viewUserComments'),
                style: GoogleFonts.notoSansKr(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || result == null) return;
    if (result == 'message') {
      final conv = await MessageService.instance.startConversation(
        author,
        displayName,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessageThreadScreen(
              conversationId: conv.id,
              otherUserName: displayName,
            ),
          ),
        );
      }
    } else if (result == 'posts') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserPostsScreen(authorName: author)),
      );
    } else if (result == 'comments') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              UserPostsScreen(authorName: author, initialSegment: 1),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backStack = List.of(widget.initialBackStack);
    _forwardStack = List.of(widget.initialForwardStack);
    _morePostsTabIndex = (widget.initialTabIndex ?? 0).clamp(0, 1);
    _scrollController.addListener(() {
      _updateFabVisibility();
      // 스크롤 끝에서 300px 이내: 댓글 더 불러오기
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 300) {
        _loadMoreComments();
      }
    });
    _currentPost = widget.post;
    final uid = AuthService.instance.currentUser.value?.uid;
    _isLiked = uid != null && widget.post.likedBy.contains(uid);
    _isDisliked = uid != null && widget.post.dislikedBy.contains(uid);
    // 영상 게시글: 전환 애니메이션 중에 preload 시작 — deferred frame 이전이므로
    // _PostVideoPlayer.initState 가 실행될 때 이미 초기화 중(또는 완료)인 컨트롤러를 재사용.
    if (widget.post.hasVideo &&
        widget.post.videoUrl != null &&
        widget.post.videoUrl!.isNotEmpty) {
      VideoPreloadCache.instance.preload(widget.post.videoUrl!);
    }
    // 첫 프레임이 화면에 그려진 뒤 비동기 작업 시작 — 전환 애니메이션 jank 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCurrentUserAuthor();
      if (!widget.offlineSyntheticReview) {
        _loadLatestPost();
        _incrementViews();
      }
    });
    _commentController.addListener(() {
      final lines = '\n'.allMatches(_commentController.text).length + 2;
      final clamped = lines.clamp(2, 6);
      if (clamped != _commentLines) setState(() => _commentLines = clamped);
    });
  }

  @override
  void didUpdateWidget(covariant PostDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Smooth transition when parent (e.g. RecentActivityReviewGate) swaps from
    // the offline synthetic placeholder to the real Firestore post.
    // Instead of using a ValueKey (which causes a full page rebuild / flicker),
    // we update _currentPost in-place and trigger a Firestore refresh.
    final postChanged = oldWidget.post.id != widget.post.id;
    final syntheticToReal =
        oldWidget.offlineSyntheticReview && !widget.offlineSyntheticReview;
    if (postChanged || syntheticToReal) {
      // widget.post (_feedPost) was just fetched from Firestore via getPost(),
      // so it already has fresh commentsList, likeCount, isLiked, etc.
      // Use setState so Flutter immediately rebuilds with the real data.
      // Calling _loadLatestPost() here would be a redundant second Firestore
      // round-trip, doubling latency and causing a visible flicker.
      final uid = AuthService.instance.currentUser.value?.uid;
      setState(() {
        _currentPost = widget.post;
        _isLiked = uid != null && widget.post.likedBy.contains(uid);
        _isDisliked = uid != null && widget.post.dislikedBy.contains(uid);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initialTabIndex == null && !_morePostsTabSyncedFromRoute) {
      _morePostsTabSyncedFromRoute = true;
      final s = CountryScope.of(context).strings;
      var idx = 0;
      if (widget.tabName == s.get('tabReviews')) {
        idx = 0;
      } else if (widget.tabName == s.get('tabHot')) {
        idx = 1;
      } else if (widget.tabName == s.get('freeBoard') ||
          widget.tabName == s.get('tabGeneral')) {
        idx = 1;
      } else if (widget.tabName == s.get('tabQnA')) {
        idx = 1;
      }
      final clamped = idx.clamp(0, 1);
      if (_morePostsTabIndex != clamped) {
        _morePostsTabIndex = clamped;
      }
    }
  }

  Future<void> _incrementViews() async {
    // 낙관적 업데이트: 화면에 먼저 +1 반영 (인기글 mock·네트워크 실패 시에도 조회수 표시)
    if (mounted) {
      setState(() {
        _currentPost = _post.copyWith(views: _post.views + 1);
      });
    }
    await PostService.instance.incrementPostViews(widget.post.id);
  }

  Future<void> _loadCurrentUserAuthor() async {
    if (!AuthService.instance.isLoggedIn.value) return;
    final author = await UserProfileService.instance.getAuthorForPost();
    if (mounted) setState(() => _currentUserAuthor = author);
  }

  Future<void> _loadLatestPost() async {
    if (mounted) setState(() => _isRefreshing = true);
    final locale = CountryScope.maybeOf(context)?.country;
    final latest = await PostService.instance.getPost(widget.post.id, locale);
    if (latest != null && mounted) {
      final uid = AuthService.instance.currentUser.value?.uid;
      setState(() {
        if (_votePending || _talkAskLikeInFlight) {
          _currentPost = latest.copyWith(
            votes: _post.votes,
            likedBy: _post.likedBy,
            dislikedBy: _post.dislikedBy,
            likeCount: _post.likeCount,
            dislikeCount: _post.dislikeCount,
          );
        } else {
          _currentPost = latest;
          _isLiked = uid != null && latest.likedBy.contains(uid);
          _isDisliked = uid != null && latest.dislikedBy.contains(uid);
        }
        _isRefreshing = false;
      });
    } else if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  int get _likeCount => _post.votes;

  Future<void> _submitComment() async {
    if (widget.offlineSyntheticReview) return;
    final text = _commentController.text.trim();
    final hasImage = _commentImagePath != null && _commentImagePath!.isNotEmpty;
    if (text.isEmpty && !hasImage) return;
    if (_isSubmittingComment) return;
    _isSubmittingComment = true;
    String? imageUrl;
    if (hasImage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지 업로드 중…', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
          ),
        );
      }
      imageUrl = await PostService.instance.uploadCommentImage(
        _commentImagePath!,
      );
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!mounted) {
        _isSubmittingComment = false;
        return;
      }
      if (imageUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지 업로드에 실패했어요.', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _isSubmittingComment = false;
        return;
      }
    }
    final author = await UserProfileService.instance.getAuthorBaseName();
    final s = CountryScope.of(context).strings;
    final ctry = _post.country?.trim().isNotEmpty == true
        ? _post.country!.trim()
        : LocaleService.instance.locale;
    final newComment = PostComment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: author,
      timeAgo: s.get('timeAgoJustNow'),
      text: text.isEmpty ? ' ' : text,
      votes: 0,
      replies: const [],
      authorPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
      authorAvatarColorIndex:
          UserProfileService.instance.avatarColorNotifier.value,
      imageUrl: imageUrl,
      createdAtDate: DateTime.now(),
      authorUid: AuthService.instance.currentUser.value?.uid,
      country: Post.normalizeFeedCountry(ctry),
    );
    final parentId = _replyingToCommentId;
    final errorMsg = parentId != null
        ? await PostService.instance.addReply(_post.id, parentId!, newComment)
        : await PostService.instance.addComment(_post.id, _post, newComment);
    if (!mounted) return;
    if (errorMsg == null) {
      _replyingToCommentId = null;
      _commentImagePath = null;
      _commentImagePathNotifier.value = null;
      // 낙관적 업데이트: 답글/댓글을 로컬에 반영 후 서버 재조회로 동기화
      final parent = parentId != null
          ? PostService.findCommentById(_post.commentsList, parentId!)
          : null;
      final newList = parent != null
          ? PostService.replaceCommentById(
              _post.commentsList,
              parent.id,
              PostComment(
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
              ),
            )
          : [..._post.commentsList, newComment];
      final optimisticPost = _post.copyWith(
        comments: _post.comments + 1,
        commentsList: newList,
      );
      if (mounted) {
        setState(() {
          _currentPost = optimisticPost;
          if (parentId == null) {
            // 새 댓글이 보이도록 visible count 확장
            _visibleCommentCount = newList.length;
            _scrollToCommentId = newComment.id;
          }
        });
      }
      // 서버에서 글 다시 불러와 동기화 (실패해도 이미 화면에는 반영됨)
      // 단, 서버 데이터에 새 댓글이 없으면(race condition) 낙관적 업데이트를 보존.
      final locale = CountryScope.maybeOf(context)?.country;
      final updated = await PostService.instance.getPost(_post.id, locale);
      if (mounted && updated != null) {
        final serverHasNewComment = parentId != null
            ? (PostService.findCommentById(
                    updated.commentsList,
                    parentId,
                  )?.replies.any((r) => r.id == newComment.id) ??
                  false)
            : updated.commentsList.any((c) => c.id == newComment.id);
        setState(() {
          if (serverHasNewComment) {
            _currentPost = updated;
          } else {
            // 서버가 아직 새 댓글을 반환하지 않음 → 낙관적 업데이트 유지
            _currentPost = optimisticPost;
          }
          if (parentId != null) _scrollToCommentId = null;
        });
      }
      if (mounted) {
        _commentController.clear();
        FocusScope.of(context).unfocus();
      }
      await LevelService.instance.addPoints(1);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final ctx = _newCommentKey.currentContext;
          if (ctx != null &&
              _scrollToCommentId != null &&
              _scrollController.hasClients) {
            final box = ctx.findRenderObject() as RenderBox?;
            final scrollableContext =
                _scrollController.position.context.storageContext;
            final viewportBox =
                scrollableContext.findRenderObject() as RenderBox?;
            if (box != null && viewportBox != null) {
              final commentTop = box
                  .localToGlobal(Offset.zero, ancestor: viewportBox)
                  .dy;
              final targetOffset = (_scrollController.offset + commentTop)
                  .clamp(0.0, _scrollController.position.maxScrollExtent);
              _scrollController.animateTo(
                targetOffset,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              );
            }
            setState(() => _scrollToCommentId = null);
          } else {
            final commentsCtx = _commentsKey.currentContext;
            if (commentsCtx != null) {
              Scrollable.ensureVisible(
                commentsCtx,
                alignment: 0.0,
                duration: const Duration(milliseconds: 300),
              );
            }
          }
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('댓글 등록 실패: $errorMsg', style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    if (mounted) _isSubmittingComment = false;
  }

  Future<void> _onLikeTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    if (widget.offlineSyntheticReview) return;

    final talkOrAsk =
        postDisplayType(_post) == 'talk' || postDisplayType(_post) == 'ask';
    if (talkOrAsk) {
      HapticFeedback.lightImpact();
      final uid = AuthService.instance.currentUser.value?.uid;
      final nowLiked = !_isLiked;
      final prevLiked = _isLiked;
      final prevDisliked = _isDisliked;
      final prevPost = _currentPost;
      final newLikedBy = List<String>.from(_post.likedBy);
      if (nowLiked) {
        if (uid != null && !newLikedBy.contains(uid)) newLikedBy.add(uid);
      } else {
        newLikedBy.remove(uid);
      }
      final likeVoteDelta = nowLiked ? (_isDisliked ? 2 : 1) : -1;
      var nextLikeCount = _post.likeCount;
      var nextDislikeCount = _post.dislikeCount;
      if (nowLiked) {
        if (_isDisliked) {
          nextDislikeCount = (nextDislikeCount - 1).clamp(0, 999999);
          nextLikeCount += 1;
        } else {
          nextLikeCount += 1;
        }
      } else {
        nextLikeCount = (nextLikeCount - 1).clamp(0, 999999);
      }
      _talkAskLikeInFlight = true;
      setState(() {
        _isLiked = nowLiked;
        _isDisliked = false;
        _currentPost = _post.copyWith(
          votes: _post.votes + likeVoteDelta,
          likedBy: newLikedBy,
          dislikedBy: nowLiked
              ? _post.dislikedBy.where((u) => u != uid).toList()
              : _post.dislikedBy,
          likeCount: nextLikeCount,
          dislikeCount: nextDislikeCount,
        );
      });
      final prevVoteForNet = nowLiked ? 0 : 1;
      _talkAskLikeDebounce?.cancel();
      _talkAskLikeDebounce = Timer(const Duration(milliseconds: 280), () async {
        try {
          if (!mounted) return;
          final result = await PostService.instance.togglePostLike(
            widget.post.id,
            currentVoteState: prevVoteForNet,
            postAuthorUid: _post.authorUid,
            postTitle: _post.title,
          );
          if (!mounted) return;
          if (result == null) {
            setState(() {
              _isLiked = prevLiked;
              _isDisliked = prevDisliked;
              _currentPost = prevPost;
            });
          }
        } finally {
          if (mounted) _talkAskLikeInFlight = false;
        }
      });
      return;
    }

    if (_votePending) return;
    HapticFeedback.lightImpact();
    final uid = AuthService.instance.currentUser.value?.uid;
    final nowLiked = !_isLiked;
    final prevLiked = _isLiked;
    final prevDisliked = _isDisliked;
    final prevPost = _currentPost;
    // 낙관적 업데이트: 즉시 UI 반영
    final newLikedBy = List<String>.from(_post.likedBy);
    if (nowLiked) {
      if (uid != null && !newLikedBy.contains(uid)) newLikedBy.add(uid);
    } else {
      newLikedBy.remove(uid);
    }
    final likeVoteDelta = nowLiked ? (_isDisliked ? 2 : 1) : -1;
    var nextLikeCount = _post.likeCount;
    var nextDislikeCount = _post.dislikeCount;
    if (nowLiked) {
      if (_isDisliked) {
        nextDislikeCount = (nextDislikeCount - 1).clamp(0, 999999);
        nextLikeCount += 1;
      } else {
        nextLikeCount += 1;
      }
    } else {
      nextLikeCount = (nextLikeCount - 1).clamp(0, 999999);
    }
    setState(() {
      _votePending = true;
      _isLiked = nowLiked;
      _isDisliked = false;
      _currentPost = _post.copyWith(
        votes: _post.votes + likeVoteDelta,
        likedBy: newLikedBy,
        dislikedBy: nowLiked
            ? _post.dislikedBy.where((u) => u != uid).toList()
            : _post.dislikedBy,
        likeCount: nextLikeCount,
        dislikeCount: nextDislikeCount,
      );
    });
    PostService.instance
        .togglePostLike(
          widget.post.id,
          postAuthorUid: _post.authorUid,
          postTitle: _post.title,
        )
        .then((result) {
          if (!mounted) return;
          if (result == null) {
            setState(() {
              _isLiked = prevLiked;
              _isDisliked = prevDisliked;
              _currentPost = prevPost;
            });
          }
          if (mounted) setState(() => _votePending = false);
        });
  }

  Future<void> _onDislikeTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    if (_votePending) return;
    HapticFeedback.lightImpact();
    final uid = AuthService.instance.currentUser.value?.uid;
    final nowDisliked = !_isDisliked;
    final prevLiked = _isLiked;
    final prevDisliked = _isDisliked;
    final prevPost = _currentPost;
    // 낙관적 업데이트: 즉시 UI 반영
    final newDislikedBy = List<String>.from(_post.dislikedBy);
    if (nowDisliked) {
      if (uid != null && !newDislikedBy.contains(uid)) newDislikedBy.add(uid);
    } else {
      newDislikedBy.remove(uid);
    }
    final newLikedBy = nowDisliked
        ? _post.likedBy.where((u) => u != uid).toList()
        : _post.likedBy;
    final voteDelta = nowDisliked ? (_isLiked ? -2 : -1) : 1;
    var nextLikeCountD = _post.likeCount;
    var nextDislikeCountD = _post.dislikeCount;
    if (nowDisliked) {
      if (_isLiked) {
        nextLikeCountD = (nextLikeCountD - 1).clamp(0, 999999);
        nextDislikeCountD += 1;
      } else {
        nextDislikeCountD += 1;
      }
    } else {
      nextDislikeCountD = (nextDislikeCountD - 1).clamp(0, 999999);
    }
    setState(() {
      _votePending = true;
      _isDisliked = nowDisliked;
      _isLiked = false;
      _currentPost = _post.copyWith(
        votes: _post.votes + voteDelta,
        likedBy: newLikedBy,
        dislikedBy: newDislikedBy,
        likeCount: nextLikeCountD,
        dislikeCount: nextDislikeCountD,
      );
    });
    PostService.instance.togglePostDislike(widget.post.id).then((result) {
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _isLiked = prevLiked;
          _isDisliked = prevDisliked;
          _currentPost = prevPost;
        });
      }
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _onCommentTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    _scrollToComments();
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      // 댓글용: 최대 720px·품질 70으로 리사이즈 (업로드 속도 최적화)
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 720,
      );
      if (!mounted || file == null) return;

      // 이미지 자르기: 자유 비율 크롭 (lockAspectRatio: false)
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        compressQuality: 70,
        compressFormat: ImageCompressFormat.jpg,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '이미지 자르기',
            toolbarColor: Theme.of(context).colorScheme.surface,
            toolbarWidgetColor: Theme.of(context).colorScheme.onSurface,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
            initAspectRatio: CropAspectRatioPreset.original,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '이미지 자르기',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            aspectRatioPickerButtonHidden: false,
          ),
        ],
      );
      final path = cropped?.path ?? file.path;
      if (!mounted) return;
      _commentImagePath = path;
      _commentImagePathNotifier.value = path;
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '이미지 선택 실패: ${e.toString()}',
              style: GoogleFonts.notoSansKr(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onGifTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    await _pickImageFromSource(ImageSource.gallery);
  }

  static const _pickFromFilesSentinel = _PostDetailPickFromFiles();

  Future<void> _onPhotoTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    final source = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Icon(LucideIcons.image, color: cs.primary),
                title: Text(
                  s.get('pickFromGallery'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(LucideIcons.folder_open, color: cs.primary),
                title: Text(
                  s.get('pickFromFiles'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, _pickFromFilesSentinel),
              ),
              ListTile(
                leading: Icon(LucideIcons.camera, color: cs.primary),
                title: Text(
                  s.get('takePhoto'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == _pickFromFilesSentinel) {
      await _pickImageFromFiles();
      return;
    }
    if (source is ImageSource) await _pickImageFromSource(source);
  }

  Future<void> _pickImageFromFiles() async {
    try {
      // FileType.image는 기기에서 갤러리(Select photos)를 띄워 비어 보일 수 있음 → custom으로 파일 브라우저(다운로드 등) 노출
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final pf = result.files.single;
      final path = pf.path ?? pf.xFile?.path;
      if (path == null || path.isEmpty) return;
      final file = XFile(path);
      if (!mounted) return;
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        compressQuality: 70,
        compressFormat: ImageCompressFormat.jpg,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '이미지 자르기',
            toolbarColor: Theme.of(context).colorScheme.surface,
            toolbarWidgetColor: Theme.of(context).colorScheme.onSurface,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
            initAspectRatio: CropAspectRatioPreset.original,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '이미지 자르기',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            aspectRatioPickerButtonHidden: false,
          ),
        ],
      );
      final outPath = cropped?.path ?? file.path;
      if (!mounted) return;
      _commentImagePath = outPath;
      _commentImagePathNotifier.value = outPath;
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '이미지 선택 실패: ${e.toString()}',
              style: GoogleFonts.notoSansKr(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_updateFabVisibility);
    _scrollController.dispose();
    _keyboardDebounceTimer?.cancel();
    _talkAskLikeDebounce?.cancel();
    _talkAskLikeInFlight = false;
    _commentController.dispose();
    _commentFocusNode.dispose();
    _commentImagePathNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!_commentFocusNode.hasFocus) return;
    // 키보드 애니메이션 중 수십 번 호출되므로 디바운스: 마지막 호출 후 150ms가 지나야 실행
    _keyboardDebounceTimer?.cancel();
    _keyboardDebounceTimer = Timer(
      const Duration(milliseconds: 150),
      _scrollToShowInputCard,
    );
  }

  void _scrollToShowInputCard() {
    if (!mounted || !_scrollController.hasClients) return;
    final ctx =
        _inlineReplyInputKey.currentContext ?? _inputCardKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    // 카드 하단의 현재 화면 상의 y좌표
    final cardBottomGlobal = box.localToGlobal(Offset(0, box.size.height)).dy;
    // 키보드를 제외한 실제 뷰포트 하단 y좌표
    final viewportBottom =
        MediaQuery.of(context).size.height -
        MediaQuery.of(context).viewInsets.bottom;
    final overflow = cardBottomGlobal - viewportBottom + 16; // 16px 여백
    if (overflow > 0) {
      _scrollController.animateTo(
        (_scrollController.offset + overflow).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _loadMoreComments() {
    final total = _post.commentsList.length;
    if (_visibleCommentCount >= total) return;
    setState(() {
      _visibleCommentCount = (_visibleCommentCount + _commentsPageSize).clamp(
        0,
        total,
      );
    });
  }

  void _updateFabVisibility() {
    final ctx = _morePostsSectionKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final isVisible = pos.dy < screenHeight && pos.dy + box.size.height > 0;
    if (isVisible != _showFab) setState(() => _showFab = isVisible);
  }

  /// DramaFeed 하단 탭 인덱스(0=리뷰, 1=톡) — 에스크 탭 비표시, 질문 글은 톡 탭과 동일 인덱스
  int _feedTabIndexForPost(Post post) {
    switch (postDisplayType(post)) {
      case 'review':
        return 0;
      case 'ask':
        return 1;
      default:
        return 1;
    }
  }

  String _appBarBoardTitle() {
    final s = CountryScope.of(context).strings;
    switch (postDisplayType(_post)) {
      case 'review':
        return s.get('tabReviews');
      case 'ask':
        return s.get('tabQnA');
      default:
        return s.get('tabGeneral');
    }
  }

  // 글 상세 내에서 다른 글로 이동 (히스토리 push)
  void _navigateToPost(Post post) {
    final nextTab = _feedTabIndexForPost(post);
    setState(() {
      _backStack.add((_post, _morePostsTabIndex));
      _forwardStack.clear();
      _currentPost = post;
      _morePostsTabIndex = nextTab;
      _visibleCommentCount = 15;
      _commentLines = 2;
      _commentController.clear();
      _replyingToCommentId = null;
      final uid = AuthService.instance.currentUser.value?.uid;
      _isLiked = uid != null && post.likedBy.contains(uid);
      _isDisliked = uid != null && post.dislikedBy.contains(uid);
    });
    _scrollController.jumpTo(0);
  }

  PostDetailResult _buildResult({Post? updatedPost}) => PostDetailResult(
    updatedPost: updatedPost,
    backStack: List.of(_backStack),
    forwardStack: List.of(_forwardStack),
    tabIndex: _morePostsTabIndex,
  );

  /// 가로 스와이프 뒤로: 글 스택이 있으면 이전 글, 없으면 [_goBack]과 동일하게 닫기.
  void _onHorizontalSwipeBack() {
    if (_backStack.isNotEmpty) {
      _goBack();
      return;
    }
    _forwardStack.add((_post, _morePostsTabIndex));
    popListsStyleSubpage(context, _buildResult());
  }

  void _goBack() {
    if (_backStack.isEmpty) {
      // 더 이상 뒤로 갈 글이 없으면 현재 글을 forwardStack에 넣고 화면 종료
      _forwardStack.add((_post, _morePostsTabIndex));
      Navigator.of(context).pop(_buildResult());
      return;
    }
    setState(() {
      _forwardStack.add((_post, _morePostsTabIndex));
      final (post, tabIndex) = _backStack.removeLast();
      _currentPost = post;
      _morePostsTabIndex = tabIndex.clamp(0, 1);
      _visibleCommentCount = 15;
      _commentLines = 2;
      _commentController.clear();
      _replyingToCommentId = null;
      final uid = AuthService.instance.currentUser.value?.uid;
      _isLiked = uid != null && _post.likedBy.contains(uid);
      _isDisliked = uid != null && _post.dislikedBy.contains(uid);
    });
    _scrollController.jumpTo(0);
  }

  void _goForward() {
    if (_forwardStack.isEmpty) return;
    setState(() {
      _backStack.add((_post, _morePostsTabIndex));
      final (post, tabIndex) = _forwardStack.removeLast();
      _currentPost = post;
      _morePostsTabIndex = tabIndex.clamp(0, 1);
      _visibleCommentCount = 15;
      _commentLines = 2;
      _commentController.clear();
      _replyingToCommentId = null;
      final uid = AuthService.instance.currentUser.value?.uid;
      _isLiked = uid != null && _post.likedBy.contains(uid);
      _isDisliked = uid != null && _post.dislikedBy.contains(uid);
    });
    _scrollController.jumpTo(0);
  }

  ReviewShareCardData _reviewShareDataFromPost(Post post) {
    final dramaTitle = post.dramaTitle?.trim().isNotEmpty == true
        ? post.dramaTitle!
        : post.title;
    final thumb = post.dramaThumbnail?.trim();
    String? posterUrl;
    String? posterAsset;
    if (thumb != null && thumb.isNotEmpty) {
      if (thumb.startsWith('http')) {
        posterUrl = thumb;
      } else {
        posterAsset = thumb;
      }
    }
    final nick = post.author.startsWith('u/')
        ? post.author.substring(2)
        : post.author;
    return ReviewShareCardData(
      dramaTitle: dramaTitle,
      rating: post.rating,
      reviewPreview: post.body ?? '',
      userNickname: nick,
      posterUrl: posterUrl,
      posterAsset: posterAsset,
    );
  }

  Future<void> _sharePostOrReview(BuildContext context, Post post) async {
    if (postDisplayType(post) == 'review') {
      await ReviewShareImageHelper.captureAndShare(
        context,
        _reviewShareDataFromPost(post),
      );
    } else {
      await ShareSheet.show(context, title: post.title, type: 'post');
    }
  }

  Future<void> _openWritePost() async {
    final ib = postDisplayType(_post) == 'review'
        ? 'review'
        : (postDisplayType(_post) == 'ask' ? 'ask' : 'talk');
    final post = await Navigator.push<Post>(
      context,
      MaterialPageRoute(builder: (_) => WritePostPage(initialBoard: ib)),
    );
    if (post != null && mounted) {
      final s = CountryScope.of(context).strings;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.get('postSubmitted'),
            style: GoogleFonts.notoSansKr(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      LevelService.instance.addPoints(5);
      // Firestore 저장 백그라운드 재시도
      PostService.instance.addPostWithRetry(post);
    }
  }

  void _scrollToComments() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _commentsKey.currentContext;
      if (ctx != null) {
        // 댓글 섹션을 화면 상단(alignment: 0.0)에 맞춰 해당 페이지가 보이게
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Widget _buildCommentInputCard(
    ColorScheme cs,
    dynamic s, {
    Key? key,
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(horizontal: 16),
  }) {
    return Container(
      key: key,
      margin: margin,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.13)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: _buildInputLayout(cs, s),
      ),
    );
  }

  /// TextField를 dispose 없이 유지하여 키보드 유지. hasFocus에 따라 주변 레이아웃만 변경.
  Widget _buildInputLayout(ColorScheme cs, dynamic s) {
    return ListenableBuilder(
      listenable: _commentFocusNode,
      builder: (context, _) {
        final hasFocus = _commentFocusNode.hasFocus;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final replyingTo = _replyingToCommentId != null
            ? PostService.findCommentById(
                _post.commentsList,
                _replyingToCommentId!,
              )
            : null;
        final boardKind = postDisplayType(_post);
        final isTalkAskBoard = boardKind == 'talk' || boardKind == 'ask';
        final replyingBannerAuthorColor = isTalkAskBoard
            ? cs.onSurface.withValues(alpha: 0.56)
            : cs.onSurface;
        final replyingBannerAuthorWeight = isTalkAskBoard
            ? FontWeight.w600
            : FontWeight.w500;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 답글 대상 댓글 배너
            if (replyingTo != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.6),
                  border: Border(
                    top: BorderSide(color: cs.outline.withOpacity(0.15)),
                  ),
                ),
                child: Row(
                  children: [
                    Transform.rotate(
                      angle: pi,
                      child: Icon(
                        LucideIcons.reply,
                        size: 14,
                        color: isDark ? Colors.white : cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            replyingTo.author,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: replyingBannerAuthorWeight,
                              color: replyingBannerAuthorColor,
                            ),
                          ),
                          Text(
                            replyingTo.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _replyingToCommentId = null;
                          _commentImagePath = null;
                          _commentImagePathNotifier.value = null;
                        });
                      },
                      child: Icon(
                        LucideIcons.x,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            _buildCommentImagePreview(cs),
            _buildInputField(cs, s),
            const SizedBox(height: 8),
            _buildGifPhotoReplyRow(cs, s),
          ],
        );
      },
    );
  }

  Widget _buildCommentImagePreview(ColorScheme cs) {
    if (_commentImagePath == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(_commentImagePath!),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _commentImagePath = null;
                _commentImagePathNotifier.value = null;
              });
            },
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.x, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(ColorScheme cs, dynamic s) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.isLoggedIn,
      builder: (context, loggedIn, _) {
        if (!loggedIn) {
          return GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            child: Text(
              s.get('joinConversation'),
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          );
        }
        final isReplying = _replyingToCommentId != null;
        return TextField(
          controller: _commentController,
          focusNode: _commentFocusNode,
          decoration: InputDecoration(
            isDense: true,
            hintText: isReplying ? null : s.get('joinConversation'),
            hintStyle: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: isReplying
                ? const EdgeInsets.fromLTRB(0, 10, 0, 0)
                : EdgeInsets.zero,
          ),
          style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurface),
          maxLines: 6,
          minLines: _commentLines,
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
        );
      },
    );
  }

  Widget _buildGifPhotoRow(ColorScheme cs, dynamic s) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.isLoggedIn,
      builder: (context, loggedIn, _) {
        if (!loggedIn) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _onGifTap,
                child: Text(
                  'GIF',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  LucideIcons.image_plus,
                  size: 24,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: _onPhotoTap,
              ),
            ],
          );
        }
        return ValueListenableBuilder<String?>(
          valueListenable: _commentImagePathNotifier,
          builder: (context, imagePath, _) {
            return ValueListenableBuilder<TextEditingValue>(
              valueListenable: _commentController,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                final hasContent = hasText || imagePath != null;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.92,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                  child: hasContent
                      ? Material(
                          key: const ValueKey<bool>(true),
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(28),
                          child: IconButton(
                            onPressed: _submitComment,
                            icon: const Icon(
                              LucideIcons.arrow_up,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : Row(
                          key: const ValueKey<bool>(false),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _onGifTap,
                              child: Text(
                                'GIF',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                LucideIcons.image_plus,
                                size: 24,
                                color: cs.onSurfaceVariant,
                              ),
                              onPressed: _onPhotoTap,
                            ),
                          ],
                        ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _letterboxdEnsureSpoilerStateForPost(String postId) {
    if (_letterboxdSpoilerBoundPostId != postId) {
      _letterboxdSpoilerBoundPostId = postId;
      _reviewSpoilerRevealed = false;
    }
  }

  static const Color _kLetterboxdHeroOrange = Color(0xFFFF6B35);
  static const Color _kLetterboxdReviewTabGreen = Color(0xFFFFB020);
  static const Color _kLetterboxdReviewStarYellow = Color(0xFFFFB020);
  static const Color _kLetterboxdReviewScreenBg = Color(0xFF000000);

  String _letterboxdAuthorShort(Post post) {
    final a = post.author;
    return a.startsWith('u/') ? a.substring(2) : a;
  }

  String? _dramaReleaseYearForReview(Post post) {
    final id = post.dramaId?.trim() ?? '';
    if (id.isEmpty) return null;
    final rd = DramaListService.instance.getExtra(id)?.releaseDate;
    return rd != null ? '${rd.year}' : null;
  }

  String _letterboxdReviewDateForMeta(Post post, String? country) {
    final dt = post.createdAt;
    if (dt == null) return post.timeAgo;
    final c = country?.toLowerCase();
    if (c == 'kr') {
      return '${dt.year}년 ${dt.month}월 ${dt.day}일';
    }
    if (c == 'jp' || c == 'cn') {
      return '${dt.year}年${dt.month}月${dt.day}日';
    }
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _buildLetterboxdReviewAppBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    dynamic s,
    Post post,
  ) {
    final isRecentCompact = widget.hideBelowLetterboxdLike;
    final likesReviewDetail = widget.hideBottomDramaFeed && !isRecentCompact;
    final title = (widget.hideLetterboxdRatingAndLike || widget.forceWatchPageTitle)
        ? 'Watch'
        : (isRecentCompact
              ? s.get('letterboxdReviewDetailTabReview')
              : s
                    .get('letterboxdReviewDetailAppBarTitle')
                    .replaceAll('{name}', _letterboxdAuthorShort(post)));
    final headerBg = likesReviewDetail
        ? listsStyleSubpageHeaderBackground(theme)
        : (isRecentCompact
              ? listsStyleSubpageHeaderBackground(theme)
              : Colors.black);
    final menuIconColor = likesReviewDetail || isRecentCompact
        ? cs.onSurface
        : Colors.white;
    final trailing = likesReviewDetail
        ? null
        : PopupMenuButton<String>(
            color: cs.surface,
            icon: Icon(
              LucideIcons.ellipsis_vertical,
              color: menuIconColor,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            onSelected: (v) => _onLetterboxdPostMenuSelected(v, post, cs, s),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(LucideIcons.send, size: 18, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Text(s.get('share'), style: GoogleFonts.notoSansKr()),
                  ],
                ),
              ),
              if (_isMine && !widget.offlineSyntheticReview) ...[
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
                      const SizedBox(width: 8),
                      Text(s.get('edit'), style: GoogleFonts.notoSansKr()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: kAppDeleteActionColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.get('delete'),
                        style: GoogleFonts.notoSansKr(
                          color: kAppDeleteActionColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!_isMine &&
                  isAppModerator() &&
                  !widget.offlineSyntheticReview) ...[
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: kAppDeleteActionColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.get('delete'),
                        style: GoogleFonts.notoSansKr(
                          color: kAppDeleteActionColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!_isMine) ...[
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(LucideIcons.flag, size: 18, color: cs.error),
                      const SizedBox(width: 8),
                      Text(
                        s.get('report'),
                        style: GoogleFonts.notoSansKr(color: cs.error),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(LucideIcons.ban, size: 18, color: cs.onSurface),
                      const SizedBox(width: 8),
                      Text(s.get('block'), style: GoogleFonts.notoSansKr()),
                    ],
                  ),
                ),
              ],
            ],
          );
    return ListsStyleSubpageHeaderBar(
      title: title,
      onBack: () =>
          popListsStyleSubpage(context, _buildResult(updatedPost: _post)),
      backgroundColor: headerBg,
      titleColor: likesReviewDetail || isRecentCompact ? null : Colors.white,
      leadingMutedColor: likesReviewDetail
          ? listsStyleSubpageLeadingMuted(theme, cs)
          : (isRecentCompact ? null : Colors.white.withValues(alpha: 0.52)),
      trailing: trailing,
    );
  }

  Widget _buildReviewStarRowLetterboxd(
    double? rating, {
    double totalWidth = 168,
    Color? fillColor,
    Color? emptyColor,

    /// 0보다 크면 별 글리프를 왼쪽으로 겹쳐 간격을 줄임.
    double glyphOverlap = 0,

    /// 1보다 크면 아이콘 크기 상한을 조금 올림 (Recent Activity 등).
    double iconScale = 1.0,
  }) {
    final r = (rating ?? 0).clamp(0.0, 5.0);
    final units = (r * 2).round().clamp(0, 10);
    final fullCount = units ~/ 2;
    final hasHalf = units.isOdd;
    final fill = fillColor ?? _kLetterboxdReviewTabGreen;
    final empty =
        emptyColor ?? _kLetterboxdReviewTabGreen.withValues(alpha: 0.28);
    final slotW = totalWidth / 5;
    final iconLo = fillColor != null ? 18.0 : 15.0;
    final iconHi = fillColor != null ? 28.0 : 24.0;
    final iconSize = (slotW * 0.82 * iconScale).clamp(iconLo, iconHi);
    return SizedBox(
      width: totalWidth,
      child: Row(
        children: List.generate(5, (i) {
          final IconData icon;
          if (i < fullCount) {
            icon = Icons.star_rounded;
          } else if (i == fullCount && hasHalf) {
            icon = Icons.star_half_rounded;
          } else {
            icon = Icons.star_border_rounded;
          }
          final c = (i < fullCount || (i == fullCount && hasHalf))
              ? fill
              : empty;
          final slot = SizedBox(
            width: slotW,
            child: Center(
              child: Icon(icon, size: iconSize, color: c),
            ),
          );
          if (glyphOverlap > 0) {
            return Transform.translate(
              offset: Offset(-glyphOverlap * i, 0),
              child: slot,
            );
          }
          return slot;
        }),
      ),
    );
  }

  Future<void> _openDramaDetailFromReview(Post post) async {
    await DramaListService.instance.loadFromAsset();
    if (!mounted) return;
    final locale = CountryScope.maybeOf(context)?.country;
    final dramaId = post.dramaId?.trim() ?? '';
    DramaItem item;
    DramaItem? fromList;
    for (final e in DramaListService.instance.list) {
      if (dramaId.isNotEmpty && e.id == dramaId) {
        fromList = e;
        break;
      }
    }
    if (fromList != null) {
      item = fromList;
    } else {
      final title = (post.dramaTitle?.trim().isNotEmpty == true)
          ? post.dramaTitle!.trim()
          : DramaListService.instance.getDisplayTitleByTitle(
              post.title,
              locale,
            );
      final thumb = post.dramaThumbnail?.trim();
      final hasImg =
          thumb != null &&
          (thumb.startsWith('http') || thumb.startsWith('assets/'));
      item = DramaItem(
        id: dramaId.isNotEmpty ? dramaId : 'review_${post.id}',
        title: title,
        subtitle: '',
        views: '0',
        rating: post.rating ?? 0,
        imageUrl: hasImg ? thumb : null,
      );
    }
    if (!mounted) return;
    await DramaDetailPage.openFromItem(context, item, country: locale);
  }

  /// Letterboxd 리뷰/Watch 상세: 오프라인 합성 글은 Firestore 삭제 없이 콜백만, 실제 글은 삭제 성공 시에만 pop.
  Future<void> _confirmLetterboxdDelete(
    BuildContext context,
    Post post,
    dynamic strings,
  ) async {
    final confirm = await showAppDeleteConfirmDialog(
      context,
      message: strings.get('deletePostConfirm'),
      cancelText: strings.get('cancel'),
      confirmText: strings.get('delete'),
    );
    if (confirm != true || !mounted) return;

    if (widget.offlineSyntheticReview) {
      widget.onPostDeleted?.call(post);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final ok = await PostService.instance.deletePost(post.id, postIfKnown: post);
    if (!mounted) return;
    if (ok) {
      widget.onPostDeleted?.call(post);
      Navigator.of(context).pop();
    }
  }

  Future<void> _onLetterboxdPostMenuSelected(
    String? value,
    Post post,
    ColorScheme cs,
    dynamic s,
  ) async {
    if (!mounted || value == null) return;
    if (value == 'share') {
      await _sharePostOrReview(context, post);
      return;
    }
    if (value == 'edit') {
      final updated = await Navigator.push<Post>(
        context,
        MaterialPageRoute(builder: (_) => WritePostPage(initialPost: post)),
      );
      if (updated != null && mounted) setState(() => _currentPost = updated);
    } else if (value == 'delete') {
      await _confirmLetterboxdDelete(context, post, s);
    } else if (value == 'report') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            s.get('reportPostTitle'),
            style: GoogleFonts.notoSansKr(),
          ),
          content: Text(
            s.get('reportPostMessage'),
            style: GoogleFonts.notoSansKr(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      s.get('reportSubmitted'),
                      style: GoogleFonts.notoSansKr(),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text(
                s.get('report'),
                style: GoogleFonts.notoSansKr(color: cs.error),
              ),
            ),
          ],
        ),
      );
    } else if (value == 'block') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.get('blockPostTitle'), style: GoogleFonts.notoSansKr()),
          content: Text(
            s.get('blockPostMessage'),
            style: GoogleFonts.notoSansKr(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.get('block'), style: GoogleFonts.notoSansKr()),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await BlockService.instance.blockPost(post.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                s.get('blockPostDone'),
                style: GoogleFonts.notoSansKr(),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context);
        }
      }
    }
  }

  Widget _buildGifPhotoReplyRow(ColorScheme cs, dynamic s) {
    final gifPhotoTint = cs.onSurface.withValues(alpha: 0.78);
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.isLoggedIn,
      builder: (context, loggedIn, _) {
        if (!loggedIn) return const SizedBox.shrink();
        return Row(
          children: [
            if (!widget.hideBottomDramaFeed) ...[
              GestureDetector(
                onTap: _onGifTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Text(
                    'GIF',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: gifPhotoTint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _onPhotoTap,
                child: Icon(
                  LucideIcons.image_plus,
                  size: 18,
                  color: gifPhotoTint,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            ValueListenableBuilder<String?>(
              valueListenable: _commentImagePathNotifier,
              builder: (context, imagePath, _) {
                return ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _commentController,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    final hasContent = hasText || imagePath != null;
                    return GestureDetector(
                      onTap: hasContent ? _submitComment : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: hasContent
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.arrow_up,
                          size: 17,
                          color: hasContent
                              ? Colors.white
                              : cs.onSurfaceVariant.withValues(alpha: 0.45),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildReviewSmallPoster(
    Post post,
    ColorScheme cs,
    double w,
    double h,
  ) {
    final t = post.dramaThumbnail?.trim();
    final ok = t != null && t.startsWith('http');
    if (ok) {
      return OptimizedNetworkImage(
        imageUrl: t,
        width: w,
        height: h,
        fit: BoxFit.cover,
        memCacheWidth: (w * 2).round(),
        memCacheHeight: (h * 2).round(),
      );
    }
    return Container(
      width: w,
      height: h,
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant, size: 28),
    );
  }

  /// Letterboxd 리뷰 포스터 — [Positioned.fill] 등 **유한한** 부모 안에서 쓰는 것을 권장.
  /// (IntrinsicHeight Row + SizedBox.expand + infinity 크기는 semantics/layout 오류 유발)
  Widget _buildReviewPosterStretch(Post post, ColorScheme cs) {
    final t = post.dramaThumbnail?.trim();
    final ok = t != null && t.startsWith('http');
    if (ok) {
      return OptimizedNetworkImage(
        imageUrl: t,
        fit: BoxFit.cover,
        memCacheWidth: 280,
        memCacheHeight: 420,
      );
    }
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant, size: 28),
    );
  }

  Widget _buildLetterboxdReviewSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    Post post,
  ) {
    final s = CountryScope.of(context).strings;
    final country = CountryScope.maybeOf(context)?.country;

    // 앱 언어 기준 표시 제목 — Firestore에 한글로 저장된 경우도 표시 언어에 맞게 변환
    String dramaTitle;
    final dramaId = post.dramaId?.trim() ?? '';
    if (dramaId.isNotEmpty && !dramaId.startsWith('short-')) {
      final t = DramaListService.instance.getDisplayTitle(dramaId, country);
      dramaTitle = t.isNotEmpty
          ? t
          : (post.dramaTitle?.trim().isNotEmpty == true
                ? post.dramaTitle!
                : post.title);
    } else if (post.dramaTitle?.trim().isNotEmpty == true) {
      final byTitle = DramaListService.instance.getDisplayTitleByTitle(
        post.dramaTitle!,
        country,
      );
      dramaTitle = byTitle.isNotEmpty ? byTitle : post.dramaTitle!;
    } else {
      dramaTitle = post.title;
    }
    final bodyRaw = post.body ?? '';
    final year = _dramaReleaseYearForReview(post);
    final watchedCaption = s
        .get('letterboxdReviewWatchedLine')
        .replaceAll('{date}', _letterboxdReviewDateForMeta(post, country));
    final recentCompact = widget.hideBelowLetterboxdLike;
    final likesReviewCompactHeader =
        widget.hideBottomDramaFeed && !recentCompact;
    final useCompactReviewHeaderRow =
        recentCompact || widget.hideBottomDramaFeed;
    // Recent Activity: 포스터는 제목 1줄 기준 왼쪽 열 높이(고정)에 맞춘 2:3 — 제목이 2줄이어도 크기 불변.
    const recentPosterOneLineBlockH = 126.0;
    final recentPosterW = recentPosterOneLineBlockH * 2 / 3;

    final screenBg = recentCompact || likesReviewCompactHeader
        ? theme.scaffoldBackgroundColor
        : _kLetterboxdReviewScreenBg;
    return ColoredBox(
      color: screenBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLetterboxdReviewAppBar(context, theme, cs, s, post),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: useCompactReviewHeaderRow
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: likesReviewCompactHeader
                            ? SizedBox(
                                height: recentPosterOneLineBlockH,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        _PostAuthorAvatar(
                                          photoUrl: post.authorPhotoUrl,
                                          author: post.author,
                                          authorUid: post.authorUid,
                                          colorIndex:
                                              post.authorAvatarColorIndex,
                                          size: kAppUnifiedProfileAvatarSize,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: () =>
                                                  openUserProfileFromAuthorUid(
                                                    context,
                                                    post.authorUid,
                                                  ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 2,
                                                    ),
                                                child: Text(
                                                  _letterboxdAuthorShort(post),
                                                  style:
                                                      appUnifiedNicknameStyle(
                                                        cs,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (_isMine &&
                                            !widget.offlineSyntheticReview)
                                          TextButton(
                                            onPressed: () =>
                                                _onLetterboxdPostMenuSelected(
                                                  'edit',
                                                  post,
                                                  cs,
                                                  s,
                                                ),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              foregroundColor: cs
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.72),
                                            ),
                                            child: Text(
                                              s.get('edit'),
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        if (_isMine &&
                                            !widget.offlineSyntheticReview)
                                          TextButton(
                                            onPressed: () =>
                                                _onLetterboxdPostMenuSelected(
                                                  'delete',
                                                  post,
                                                  cs,
                                                  s,
                                                ),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              foregroundColor: cs
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.72),
                                            ),
                                            child: Text(
                                              s.get('delete'),
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    InkWell(
                                      onTap: () =>
                                          _openDramaDetailFromReview(post),
                                      child: Text(
                                        dramaTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.82,
                                          ),
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child:
                                          FeedReviewPostCard.homeFeedStyleStarRow(
                                            (post.rating ?? 0).clamp(0.0, 5.0),
                                            iconSize: 16,
                                            slotIconFraction: 0.98,
                                            starOverlapPx: 3,
                                          ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      watchedCaption,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        color: cs.onSurfaceVariant.withValues(
                                          alpha: 0.62,
                                        ),
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _PostAuthorAvatar(
                                        photoUrl: post.authorPhotoUrl,
                                        author: post.author,
                                        authorUid: post.authorUid,
                                        colorIndex: post.authorAvatarColorIndex,
                                        size: kAppUnifiedProfileAvatarSize,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child:
                                            post.authorUid?.trim().isNotEmpty ==
                                                true
                                            ? Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: () =>
                                                      openUserProfileFromAuthorUid(
                                                        context,
                                                        post.authorUid,
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 2,
                                                        ),
                                                    child: Text(
                                                      _letterboxdAuthorShort(
                                                        post,
                                                      ),
                                                      style:
                                                          GoogleFonts.notoSansKr(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Colors.white
                                                                .withValues(
                                                                  alpha: 0.72,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : GestureDetector(
                                                onTapDown: (d) =>
                                                    _showPostAuthorMenu(
                                                      context,
                                                      post.author,
                                                      d,
                                                    ),
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                child: Text(
                                                  _letterboxdAuthorShort(post),
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.72,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  InkWell(
                                    onTap: () =>
                                        _openDramaDetailFromReview(post),
                                    child: Text(
                                      dramaTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  if (!widget.hideLetterboxdRatingAndLike) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: _buildReviewStarRowLetterboxd(
                                        post.rating,
                                        totalWidth: 122,
                                        fillColor: _kLetterboxdReviewStarYellow,
                                        emptyColor: _kLetterboxdReviewStarYellow
                                            .withValues(alpha: 0.28),
                                        glyphOverlap: 5,
                                        iconScale: 1.12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ] else
                                    const SizedBox(height: 10),
                                  Text(
                                    watchedCaption,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      color: Colors.white.withValues(
                                        alpha: 0.38,
                                      ),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(width: 12),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openDramaDetailFromReview(post),
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: recentPosterW,
                            height: recentPosterOneLineBlockH,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: _buildReviewPosterStretch(post, cs),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _PostAuthorAvatar(
                                    photoUrl: post.authorPhotoUrl,
                                    author: post.author,
                                    authorUid: post.authorUid,
                                    colorIndex: post.authorAvatarColorIndex,
                                    size: kAppUnifiedProfileAvatarSize,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child:
                                        post.authorUid?.trim().isNotEmpty ==
                                            true
                                        ? Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: () =>
                                                  openUserProfileFromAuthorUid(
                                                    context,
                                                    post.authorUid,
                                                  ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 2,
                                                    ),
                                                child: Text(
                                                  _letterboxdAuthorShort(post),
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                        : GestureDetector(
                                            onTapDown: (d) =>
                                                _showPostAuthorMenu(
                                                  context,
                                                  post.author,
                                                  d,
                                                ),
                                            behavior: HitTestBehavior.opaque,
                                            child: Text(
                                              _letterboxdAuthorShort(post),
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: () => _openDramaDetailFromReview(post),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: dramaTitle,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          height: 1.2,
                                        ),
                                      ),
                                      if (year != null && year.isNotEmpty)
                                        TextSpan(
                                          text: '  $year',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withValues(
                                              alpha: 0.55,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _buildReviewStarRowLetterboxd(
                                    post.rating,
                                    totalWidth: 110,
                                  ),
                                  if (!widget.hideBottomDramaFeed) ...[
                                    const SizedBox(width: 10),
                                    Icon(
                                      Icons.favorite_rounded,
                                      size: 20,
                                      color: post.isLiked
                                          ? _kLetterboxdHeroOrange
                                          : Colors.white.withValues(
                                              alpha: 0.35,
                                            ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                watchedCaption,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.38),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openDramaDetailFromReview(post),
                            borderRadius: BorderRadius.circular(6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 70,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned.fill(
                                      child: _buildReviewPosterStretch(
                                        post,
                                        cs,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (post.hasSpoiler && !_reviewSpoilerRevealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: InkWell(
                onTap: () => setState(() => _reviewSpoilerRevealed = true),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: likesReviewCompactHeader
                        ? cs.surfaceContainerHighest
                        : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: likesReviewCompactHeader
                          ? cs.outline.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    s.get('reviewSpoilerTapToRevealLetterboxd'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      height: 1.45,
                      color: likesReviewCompactHeader
                          ? cs.onSurfaceVariant
                          : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )
          else if (bodyRaw.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isMine &&
                      !recentCompact &&
                      !likesReviewCompactHeader) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s.get('myPostBadge'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      bodyRaw,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        color: likesReviewCompactHeader
                            ? cs.onSurface.withValues(alpha: 0.74)
                            : Colors.white.withValues(
                                alpha: recentCompact ? 0.72 : 0.88,
                              ),
                        height: 1.65,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!widget.hideLetterboxdRatingAndLike)
            Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                4,
                16,
                recentCompact ? 20 : (likesReviewCompactHeader ? 8 : 4),
              ),
              child: InkWell(
                onTap: _onLikeTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: recentCompact
                        ? 8
                        : (likesReviewCompactHeader ? 5 : 10),
                    horizontal: likesReviewCompactHeader ? 6 : 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        size: recentCompact
                            ? 21
                            : (likesReviewCompactHeader ? 18 : 26),
                        color: _isLiked
                            ? Colors.redAccent.withValues(
                                alpha: recentCompact
                                    ? 0.88
                                    : (likesReviewCompactHeader ? 0.95 : 1),
                              )
                            : (recentCompact
                                  ? Colors.white.withValues(alpha: 0.42)
                                  : (likesReviewCompactHeader
                                        ? cs.onSurface.withValues(alpha: 0.38)
                                        : Colors.white54)),
                      ),
                      SizedBox(
                        width: recentCompact
                            ? 8
                            : (likesReviewCompactHeader ? 6 : 10),
                      ),
                      Text(
                        s.get('reviewLikeLabel'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: recentCompact
                              ? 13
                              : (likesReviewCompactHeader ? 12 : 15),
                          fontWeight: FontWeight.w800,
                          letterSpacing: likesReviewCompactHeader ? 0.25 : 0.4,
                          color: recentCompact
                              ? Colors.white.withValues(alpha: 0.68)
                              : (likesReviewCompactHeader
                                    ? cs.onSurface.withValues(alpha: 0.58)
                                    : Colors.white),
                        ),
                      ),
                      SizedBox(
                        width: recentCompact
                            ? 8
                            : (likesReviewCompactHeader ? 6 : 10),
                      ),
                      Text(
                        '${post.likeCount}',
                        style: GoogleFonts.notoSansKr(
                          fontSize: recentCompact
                              ? 13
                              : (likesReviewCompactHeader ? 12 : 15),
                          fontWeight: FontWeight.w600,
                          color: recentCompact
                              ? Colors.white.withValues(alpha: 0.45)
                              : (likesReviewCompactHeader
                                    ? cs.onSurface.withValues(alpha: 0.44)
                                    : Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!widget.hideBelowLetterboxdLike && !widget.hideBottomDramaFeed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _openDramaDetailFromReview(post),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: Colors.white.withValues(alpha: 0.92),
                    backgroundColor: const Color(0xFF1C1C1E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Text(
                    s.get('reviewFilmButton'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isTypedReview = postDisplayType(post) == 'review';
    final useScaffoldBgForReview =
        isTypedReview &&
        (widget.hideBelowLetterboxdLike || widget.hideBottomDramaFeed);
    final hideLetterboxdCommentsBlock =
        isTypedReview &&
        widget.hideBelowLetterboxdLike &&
        widget.suppressLetterboxdCommentsSection;
    final hideLetterboxdMorePostsFeed =
        isTypedReview && widget.hideBelowLetterboxdLike;
    final boardKind = postDisplayType(post);
    final showAuthorProfileMenu = boardKind != 'talk' && boardKind != 'ask';

    /// 리뷰 게시판 글 상세: 댓글 타일을 톡/에스크와 동일(아바타·닉+시간·Reply·하트)로 표시.
    final showCommentAuthorProfileMenu =
        showAuthorProfileMenu && !isTypedReview;

    /// Letterboxd 전용 다크 댓글 헤더 스트립(검은 바 + 흰 글씨). 라이크 리뷰 상세에서는 스캐폴드 톤.
    final letterboxdCommentsDarkChrome =
        isTypedReview && !widget.hideBottomDramaFeed;
    final hideViewsInTalkAskDetail = boardKind == 'talk' || boardKind == 'ask';
    final listsHeaderBg = listsStyleSubpageHeaderBackground(theme);
    final deleteLabelColor = kAppDeleteActionColor;
    _letterboxdEnsureSpoilerStateForPost(post.id);
    return PopScope(
      canPop: _backStack.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _backStack.isNotEmpty) {
          _goBack();
        }
      },
      child: ListsStyleSubpageHorizontalSwipeBack(
        onSwipePop: _onHorizontalSwipeBack,
        child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: (isTypedReview && !useScaffoldBgForReview)
            ? _kLetterboxdReviewScreenBg
            : (hideViewsInTalkAskDetail
                  ? listsHeaderBg
                  : theme.scaffoldBackgroundColor),
        body: ValueListenableBuilder<bool>(
          valueListenable: HomeTabVisibility.isHomeMainTabSelected,
          builder: (context, isHomeMainTab, _) {
            final hideBottomBrowserBar =
                isHomeMainTab ||
                widget.hideBelowLetterboxdLike ||
                widget.hideBottomDramaFeed;
            final bottomScrollPad = hideBottomBrowserBar
                ? (MediaQuery.paddingOf(context).bottom + 16)
                : (_kBrowserNavBarHeight +
                      MediaQuery.paddingOf(context).bottom);
            final mainStack = Stack(
              children: [
                Column(
                  children: [
                    if (!isTypedReview)
                      ListsStyleSubpageHeaderBar(
                        title: _appBarBoardTitle(),
                        onBack: () => popListsStyleSubpage(
                          context,
                          _buildResult(updatedPost: _post),
                        ),
                        backgroundColor: listsHeaderBg,
                      ),
                    Expanded(
                      child: _DeferredFrame2Body(
                        placeholderColor:
                            (isTypedReview && !useScaffoldBgForReview)
                            ? _kLetterboxdReviewScreenBg
                            : theme.scaffoldBackgroundColor,
                        builder: () => BlindRefreshIndicator(
                          onRefresh: _loadLatestPost,
                          spinnerOffsetDown: 15.0,
                          child: Container(
                            color: (isTypedReview && !useScaffoldBgForReview)
                                ? _kLetterboxdReviewScreenBg
                                : theme.scaffoldBackgroundColor,
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.zero,
                              child: GestureDetector(
                                onTap: () => FocusScope.of(context).unfocus(),
                                behavior: HitTestBehavior.opaque,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isTypedReview)
                                      _buildLetterboxdReviewSection(
                                        context,
                                        theme,
                                        cs,
                                        post,
                                      ),
                                    if (!isTypedReview) ...[
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          15,
                                          8,
                                          15,
                                          8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                // 아바타 + 닉네임/시간
                                                _PostAuthorAvatar(
                                                  photoUrl: post.authorPhotoUrl,
                                                  author: post.author,
                                                  authorUid: post.authorUid,
                                                  colorIndex: post
                                                      .authorAvatarColorIndex,
                                                  size:
                                                      kAppUnifiedProfileAvatarSize,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      post.authorUid
                                                                  ?.trim()
                                                                  .isNotEmpty ==
                                                              true
                                                          ? Material(
                                                              color: Colors
                                                                  .transparent,
                                                              child: InkWell(
                                                                onTap: () =>
                                                                    openUserProfileFromAuthorUid(
                                                                      context,
                                                                      post.authorUid,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        vertical:
                                                                            2,
                                                                      ),
                                                                  child: Text(
                                                                    post.author.startsWith(
                                                                          'u/',
                                                                        )
                                                                        ? post.author.substring(
                                                                            2,
                                                                          )
                                                                        : post.author,
                                                                    style:
                                                                        appUnifiedNicknameStyle(
                                                                          cs,
                                                                        ),
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                          : GestureDetector(
                                                              onTapDown: (details) =>
                                                                  _showPostAuthorMenu(
                                                                    context,
                                                                    post.author,
                                                                    details,
                                                                  ),
                                                              behavior:
                                                                  HitTestBehavior
                                                                      .opaque,
                                                              child: Text(
                                                                post.author
                                                                        .startsWith(
                                                                          'u/',
                                                                        )
                                                                    ? post.author
                                                                          .substring(
                                                                            2,
                                                                          )
                                                                    : post.author,
                                                                style:
                                                                    appUnifiedNicknameStyle(
                                                                      cs,
                                                                    ),
                                                              ),
                                                            ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        post.timeAgo,
                                                        style:
                                                            GoogleFonts.notoSansKr(
                                                              fontSize: 11,
                                                              color: AppColors
                                                                  .mediumGrey
                                                                  .withOpacity(
                                                                    0.7,
                                                                  ),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // 공유 — 보내기(send) 아이콘 톤
                                                Tooltip(
                                                  message: s.get('share'),
                                                  child: GestureDetector(
                                                    onTap: () =>
                                                        _sharePostOrReview(
                                                          context,
                                                          post,
                                                        ),
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 4,
                                                          ),
                                                      child: Icon(
                                                        LucideIcons.send,
                                                        size:
                                                            hideViewsInTalkAskDetail
                                                            ? 20
                                                            : 18,
                                                        color:
                                                            cs.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                // ··· 버튼 (오른쪽 상단)
                                                GestureDetector(
                                                  onTapDown: (details) async {
                                                    final value = await showMenu<String>(
                                                      context: context,
                                                      position: RelativeRect.fromLTRB(
                                                        details
                                                            .globalPosition
                                                            .dx,
                                                        details
                                                            .globalPosition
                                                            .dy,
                                                        details
                                                                .globalPosition
                                                                .dx +
                                                            1,
                                                        details
                                                                .globalPosition
                                                                .dy +
                                                            1,
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      color: cs.surface,
                                                      items: [
                                                        if (_isMine) ...[
                                                          if (!widget
                                                              .offlineSyntheticReview)
                                                            PopupMenuItem(
                                                              value: 'edit',
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    Icons
                                                                        .edit_outlined,
                                                                    size: 18,
                                                                    color: cs
                                                                        .onSurface,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                  Text(
                                                                    s.get('edit'),
                                                                    style:
                                                                        GoogleFonts.notoSansKr(),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          PopupMenuItem(
                                                            value: 'delete',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .delete_outline,
                                                                  size: 18,
                                                                  color:
                                                                      kAppDeleteActionColor,
                                                                ),
                                                                const SizedBox(
                                                                  width: 10,
                                                                ),
                                                                Text(
                                                                  s.get(
                                                                    'delete',
                                                                  ),
                                                                  style: GoogleFonts.notoSansKr(
                                                                    color:
                                                                        kAppDeleteActionColor,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ] else if (isAppModerator() &&
                                                            !widget
                                                                .offlineSyntheticReview) ...[
                                                          PopupMenuItem(
                                                            value: 'delete',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .delete_outline,
                                                                  size: 18,
                                                                  color:
                                                                      kAppDeleteActionColor,
                                                                ),
                                                                const SizedBox(
                                                                  width: 10,
                                                                ),
                                                                Text(
                                                                  s.get(
                                                                    'delete',
                                                                  ),
                                                                  style: GoogleFonts.notoSansKr(
                                                                    color:
                                                                        kAppDeleteActionColor,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ] else ...[
                                                          PopupMenuItem(
                                                            value: 'report',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  LucideIcons
                                                                      .flag,
                                                                  size: 18,
                                                                  color:
                                                                      cs.error,
                                                                ),
                                                                const SizedBox(
                                                                  width: 10,
                                                                ),
                                                                Text(
                                                                  s.get(
                                                                    'report',
                                                                  ),
                                                                  style: GoogleFonts.notoSansKr(
                                                                    color: cs
                                                                        .error,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          PopupMenuItem(
                                                            value: 'block',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  LucideIcons
                                                                      .ban,
                                                                  size: 18,
                                                                  color: cs
                                                                      .onSurface,
                                                                ),
                                                                const SizedBox(
                                                                  width: 10,
                                                                ),
                                                                Text(
                                                                  s.get(
                                                                    'block',
                                                                  ),
                                                                  style:
                                                                      GoogleFonts.notoSansKr(),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    );
                                                    if (!mounted ||
                                                        value == null)
                                                      return;
                                                    if (value == 'edit') {
                                                      final updated =
                                                          await Navigator.push<
                                                            Post
                                                          >(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) =>
                                                                  WritePostPage(
                                                                    initialPost:
                                                                        _post,
                                                                  ),
                                                            ),
                                                          );
                                                      if (updated != null &&
                                                          mounted)
                                                        setState(
                                                          () => _currentPost =
                                                              updated,
                                                        );
                                                    } else if (value ==
                                                        'delete') {
                                                      await _confirmLetterboxdDelete(
                                                        context,
                                                        _post,
                                                        s,
                                                      );
                                                    } else if (value ==
                                                        'report') {
                                                      await showDialog<void>(
                                                        context: context,
                                                        builder: (ctx) => AlertDialog(
                                                          title: Text(
                                                            s.get(
                                                              'reportPostTitle',
                                                            ),
                                                            style:
                                                                GoogleFonts.notoSansKr(),
                                                          ),
                                                          content: Text(
                                                            s.get(
                                                              'reportPostMessage',
                                                            ),
                                                            style:
                                                                GoogleFonts.notoSansKr(),
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    ctx,
                                                                  ),
                                                              child: Text(
                                                                s.get('cancel'),
                                                                style:
                                                                    GoogleFonts.notoSansKr(),
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () {
                                                                Navigator.pop(
                                                                  ctx,
                                                                );
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      s.get(
                                                                        'reportSubmitted',
                                                                      ),
                                                                      style:
                                                                          GoogleFonts.notoSansKr(),
                                                                    ),
                                                                    behavior:
                                                                        SnackBarBehavior
                                                                            .floating,
                                                                  ),
                                                                );
                                                              },
                                                              child: Text(
                                                                s.get('report'),
                                                                style:
                                                                    GoogleFonts.notoSansKr(
                                                                      color: cs
                                                                          .error,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    } else if (value ==
                                                        'block') {
                                                      final confirm = await showDialog<bool>(
                                                        context: context,
                                                        builder: (ctx) => AlertDialog(
                                                          title: Text(
                                                            s.get(
                                                              'blockPostTitle',
                                                            ),
                                                            style:
                                                                GoogleFonts.notoSansKr(),
                                                          ),
                                                          content: Text(
                                                            s.get(
                                                              'blockPostMessage',
                                                            ),
                                                            style:
                                                                GoogleFonts.notoSansKr(),
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    ctx,
                                                                    false,
                                                                  ),
                                                              child: Text(
                                                                s.get('cancel'),
                                                                style:
                                                                    GoogleFonts.notoSansKr(),
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    ctx,
                                                                    true,
                                                                  ),
                                                              child: Text(
                                                                s.get('block'),
                                                                style:
                                                                    GoogleFonts.notoSansKr(),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      if (confirm == true &&
                                                          mounted) {
                                                        await BlockService
                                                            .instance
                                                            .blockPost(
                                                              _post.id,
                                                            );
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                s.get(
                                                                  'blockPostDone',
                                                                ),
                                                                style:
                                                                    GoogleFonts.notoSansKr(),
                                                              ),
                                                              behavior:
                                                                  SnackBarBehavior
                                                                      .floating,
                                                            ),
                                                          );
                                                          Navigator.pop(
                                                            context,
                                                          );
                                                        }
                                                      }
                                                    }
                                                  },
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                          vertical: 4,
                                                        ),
                                                    child: Icon(
                                                      LucideIcons.ellipsis,
                                                      size: 17,
                                                      color:
                                                          cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              post.title,
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 21,
                                                fontWeight: FontWeight.w700,
                                                color: cs.onSurface,
                                                height: 1.4,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                            if (post.hasVideo &&
                                                post.videoUrl != null &&
                                                post.videoUrl!.isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              _PostVideoPlayer(
                                                videoUrl: post.videoUrl!,
                                                thumbnailUrl:
                                                    post.videoThumbnailUrl,
                                                isGif: post.isGif == true,
                                              ),
                                            ] else if (post.hasImage &&
                                                post.imageUrls.isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              _PostImageCarousel(
                                                imageUrls: post.imageUrls,
                                                imageDimensions:
                                                    post.imageDimensions,
                                                onTap: (index) =>
                                                    FullScreenImagePage.show(
                                                      context,
                                                      post.imageUrls,
                                                      initialIndex: index,
                                                    ),
                                              ),
                                            ] else if (post.hasImage) ...[
                                              const SizedBox(height: 16),
                                              AspectRatio(
                                                aspectRatio: 1 / 1.15,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: cs
                                                        .surfaceContainerHighest,
                                                  ),
                                                  child: Center(
                                                    child: Icon(
                                                      LucideIcons.image,
                                                      size: 56,
                                                      color: cs.onSurfaceVariant
                                                          .withOpacity(0.4),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (post.body != null &&
                                                post.body!.isNotEmpty) ...[
                                              const SizedBox(height: 14),
                                              Text(
                                                post.body!,
                                                style: GoogleFonts.notoSansKr(
                                                  fontSize: 15,
                                                  color: cs.onSurface,
                                                  height: 1.7,
                                                ),
                                              ),
                                            ],
                                            if (post.linkUrl != null &&
                                                post.linkUrl!.isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              Row(
                                                children: [
                                                  Icon(
                                                    LucideIcons.link,
                                                    size: 18,
                                                    color: cs.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      post.linkUrl!,
                                                      style:
                                                          GoogleFonts.notoSansKr(
                                                            fontSize: 14,
                                                            color: cs.primary,
                                                            decoration:
                                                                TextDecoration
                                                                    .underline,
                                                          ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      // 액션 바
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          right: 15,
                                          top: 4,
                                          bottom: 15,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            // 톡·에스크: 피드와 동일 하트 / 그 외 투표박스
                                            if (hideViewsInTalkAskDetail)
                                              TalkAskHeartVote(
                                                voteState: _isLiked ? 1 : 0,
                                                count: _likeCount,
                                                onTap: _onLikeTap,
                                                compact: false,
                                              )
                                            else
                                              _DetailVoteBox(
                                                voteState: _isLiked
                                                    ? 1
                                                    : (_isDisliked ? -1 : 0),
                                                count: _likeCount,
                                                onUp: _onLikeTap,
                                                onDown: _onDislikeTap,
                                                primaryColor: cs.primary,
                                              ),
                                            const SizedBox(width: 4),
                                            // 댓글
                                            GestureDetector(
                                              onTap: _onCommentTap,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    SizedBox(
                                                      width: 24,
                                                      height: 24,
                                                      child: Center(
                                                        child: Icon(
                                                          LucideIcons
                                                              .message_circle,
                                                          size: 18,
                                                          color:
                                                              feedInlineActionMutedForeground(
                                                                  cs),
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: talkAskIconCountGap,
                                                    ),
                                                    Text(
                                                      formatCompactCount(
                                                        post.comments,
                                                      ),
                                                      style: GoogleFonts.notoSansKr(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.0,
                                                        color:
                                                            feedInlineActionMutedForeground(
                                                                cs),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (!hideViewsInTalkAskDetail) ...[
                                              const SizedBox(width: 14),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    LucideIcons.eye,
                                                    size: 16,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    formatCompactCount(
                                                      post.views,
                                                    ),
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (_canDeletePost ||
                                                (_isMine &&
                                                    !widget
                                                        .offlineSyntheticReview)) ...[
                                              const Spacer(),
                                              if (_isMine &&
                                                  !widget.offlineSyntheticReview)
                                                GestureDetector(
                                                  onTap: () async {
                                                    final updated =
                                                        await Navigator.push<
                                                          Post
                                                        >(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                WritePostPage(
                                                                  initialPost:
                                                                      _post,
                                                                ),
                                                          ),
                                                        );
                                                    if (updated != null &&
                                                        mounted)
                                                      setState(
                                                        () => _currentPost =
                                                            updated,
                                                      );
                                                  },
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 6,
                                                        ),
                                                    child: Text(
                                                      s.get('edit'),
                                                      style:
                                                          GoogleFonts.notoSansKr(
                                                            fontSize: 12,
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              if (_canDeletePost)
                                                GestureDetector(
                                                  onTap: () => _confirmLetterboxdDelete(
                                                    context,
                                                    _post,
                                                    s,
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 6,
                                                        ),
                                                    child: Text(
                                                      s.get('delete'),
                                                      style:
                                                          GoogleFonts.notoSansKr(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                deleteLabelColor,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (!hideLetterboxdCommentsBlock) ...[
                                      // 액션 바 아래 구분선 (댓글 시간순 위) - 얇은 회색선
                                      Container(
                                        height: 1,
                                        color: letterboxdCommentsDarkChrome
                                            ? Colors.white.withValues(
                                                alpha: 0.1,
                                              )
                                            : cs.outline.withValues(alpha: 0.4),
                                      ),
                                      // 댓글 섹션 (contentWidth로 3행 버튼 오른쪽 끝 통일)
                                      KeyedSubtree(
                                        key: _commentsKey,
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final contentWidth =
                                                constraints.maxWidth;
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: double.infinity,
                                                  color:
                                                      letterboxdCommentsDarkChrome
                                                      ? const Color(0xFF1C1C1E)
                                                      : (theme.brightness ==
                                                                Brightness.light
                                                            ? cs.surfaceContainerHighest
                                                            : (theme
                                                                      .cardTheme
                                                                      .color ??
                                                                  cs.surface)),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 20,
                                                        vertical: 10,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        letterboxdCommentsDarkChrome
                                                            ? s
                                                                  .get(
                                                                    'letterboxdReviewDetailTabPostWithCount',
                                                                  )
                                                                  .replaceAll(
                                                                    '{n}',
                                                                    '${post.comments}',
                                                                  )
                                                            : '${s.get('comments')} ${post.comments}',
                                                        style: GoogleFonts.notoSansKr(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              letterboxdCommentsDarkChrome
                                                              ? Colors.white
                                                                    .withValues(
                                                                      alpha:
                                                                          0.88,
                                                                    )
                                                              : cs.onSurface,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      ValueListenableBuilder<
                                                        bool
                                                      >(
                                                        valueListenable:
                                                            _commentSortByTop,
                                                        builder: (context, sortByTop, _) => PopupMenuButton<bool>(
                                                          offset: const Offset(
                                                            0,
                                                            36,
                                                          ),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          padding:
                                                              EdgeInsets.zero,
                                                          onSelected: (value) {
                                                            _commentSortByTop
                                                                    .value =
                                                                value;
                                                            setState(
                                                              () =>
                                                                  _visibleCommentCount =
                                                                      15,
                                                            );
                                                          },
                                                          itemBuilder: (context) => [
                                                            PopupMenuItem(
                                                              value: false,
                                                              child: Text(
                                                                s.get(
                                                                  'sortByTime',
                                                                ),
                                                                style:
                                                                    GoogleFonts.notoSansKr(
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value: true,
                                                              child: Text(
                                                                s.get(
                                                                  'sortByTop',
                                                                ),
                                                                style:
                                                                    GoogleFonts.notoSansKr(
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                sortByTop
                                                                    ? s.get(
                                                                        'sortByTop',
                                                                      )
                                                                    : s.get(
                                                                        'sortByTime',
                                                                      ),
                                                                style: GoogleFonts.notoSansKr(
                                                                  fontSize:
                                                                      11.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color:
                                                                      letterboxdCommentsDarkChrome
                                                                      ? Colors.white.withValues(
                                                                          alpha:
                                                                              0.55,
                                                                        )
                                                                      : cs.onSurfaceVariant,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 2,
                                                              ),
                                                              Icon(
                                                                Icons
                                                                    .keyboard_arrow_down,
                                                                size: 16,
                                                                color:
                                                                    letterboxdCommentsDarkChrome
                                                                    ? Colors
                                                                          .white
                                                                          .withValues(
                                                                            alpha:
                                                                                0.55,
                                                                          )
                                                                    : cs.onSurfaceVariant,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                // 댓글 목록 (무한스크롤)
                                                ValueListenableBuilder<bool>(
                                                  valueListenable:
                                                      _commentSortByTop,
                                                  builder: (context, sortByTop, _) {
                                                    if (post
                                                        .commentsList
                                                        .isEmpty)
                                                      return const SizedBox.shrink();
                                                    final allComments =
                                                        List<PostComment>.from(
                                                          post.commentsList,
                                                        );
                                                    if (sortByTop) {
                                                      allComments.sort((a, b) {
                                                        final voteCmp = b.votes
                                                            .compareTo(a.votes);
                                                        if (voteCmp != 0)
                                                          return voteCmp;
                                                        final aTime =
                                                            a
                                                                .createdAtDate
                                                                ?.millisecondsSinceEpoch ??
                                                            int.tryParse(
                                                              a.id,
                                                            ) ??
                                                            0;
                                                        final bTime =
                                                            b
                                                                .createdAtDate
                                                                ?.millisecondsSinceEpoch ??
                                                            int.tryParse(
                                                              b.id,
                                                            ) ??
                                                            0;
                                                        return aTime.compareTo(
                                                          bTime,
                                                        );
                                                      });
                                                    } else {
                                                      allComments.sort((a, b) {
                                                        final aTime =
                                                            a
                                                                .createdAtDate
                                                                ?.millisecondsSinceEpoch ??
                                                            int.tryParse(
                                                              a.id,
                                                            ) ??
                                                            0;
                                                        final bTime =
                                                            b
                                                                .createdAtDate
                                                                ?.millisecondsSinceEpoch ??
                                                            int.tryParse(
                                                              b.id,
                                                            ) ??
                                                            0;
                                                        return aTime.compareTo(
                                                          bTime,
                                                        );
                                                      });
                                                    }
                                                    final visible =
                                                        _visibleCommentCount
                                                            .clamp(
                                                              0,
                                                              allComments
                                                                  .length,
                                                            );
                                                    final hasMore =
                                                        visible <
                                                        allComments.length;
                                                    return Column(
                                                      children: [
                                                        ...allComments.take(visible).map((
                                                          c,
                                                        ) {
                                                          final tile = _CommentTile(
                                                            key: ValueKey(c.id),
                                                            comment: c,
                                                            strings: s,
                                                            depth: 0,
                                                            postId: _post.id,
                                                            showAuthorProfileMenu:
                                                                showCommentAuthorProfileMenu,
                                                            contentWidth:
                                                                contentWidth,
                                                            replyingToCommentId:
                                                                _replyingToCommentId,
                                                            buildInlineReplyCard:
                                                                _replyingToCommentId !=
                                                                    null
                                                                ? () => _buildCommentInputCard(
                                                                    cs,
                                                                    s,
                                                                    key:
                                                                        _inlineReplyInputKey,
                                                                    margin:
                                                                        EdgeInsets
                                                                            .zero,
                                                                  )
                                                                : null,
                                                            onPostUpdated:
                                                                (
                                                                  Post p,
                                                                ) => setState(
                                                                  () =>
                                                                      _currentPost =
                                                                          p,
                                                                ),
                                                            onReplyTap: (String commentId) {
                                                              setState(
                                                                () => _replyingToCommentId =
                                                                    commentId,
                                                              );
                                                              // 인라인 답글 입력이 붙은 뒤, 잘못된 offset 조합으로 맨 위로 튀는 것 방지
                                                              WidgetsBinding.instance.addPostFrameCallback((
                                                                _,
                                                              ) {
                                                                WidgetsBinding.instance.addPostFrameCallback((
                                                                  _,
                                                                ) {
                                                                  if (!mounted) {
                                                                    return;
                                                                  }
                                                                  final ctx =
                                                                      _inlineReplyInputKey
                                                                          .currentContext ??
                                                                      _inputCardKey
                                                                          .currentContext;
                                                                  if (ctx ==
                                                                      null) {
                                                                    return;
                                                                  }
                                                                  Scrollable.ensureVisible(
                                                                    ctx,
                                                                    duration: const Duration(
                                                                      milliseconds:
                                                                          280,
                                                                    ),
                                                                    curve: Curves
                                                                        .easeOut,
                                                                    alignment:
                                                                        0.35,
                                                                  );
                                                                  _commentFocusNode
                                                                      .requestFocus();
                                                                });
                                                              });
                                                            },
                                                            reviewReplyIconLayout:
                                                                isTypedReview,
                                                          );
                                                          return c.id ==
                                                                  _scrollToCommentId
                                                              ? KeyedSubtree(
                                                                  key:
                                                                      _newCommentKey,
                                                                  child: tile,
                                                                )
                                                              : tile;
                                                        }),
                                                        // 더 보기 버튼 (무한스크롤 수동 트리거)
                                                        if (hasMore)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 12,
                                                                ),
                                                            child: GestureDetector(
                                                              onTap:
                                                                  _loadMoreComments,
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          20,
                                                                      vertical:
                                                                          8,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: cs
                                                                      .onSurface
                                                                      .withValues(
                                                                        alpha:
                                                                            0.06,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                ),
                                                                child: Text(
                                                                  '댓글 ${allComments.length - visible}개 더 보기',
                                                                  style: GoogleFonts.notoSansKr(
                                                                    fontSize:
                                                                        13,
                                                                    color: cs
                                                                        .onSurfaceVariant,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      if (_replyingToCommentId == null) ...[
                                        const SizedBox(height: 8),
                                        _buildCommentInputCard(
                                          cs,
                                          s,
                                          key: _inputCardKey,
                                        ),
                                      ],
                                    ],
                                    if (!hideLetterboxdMorePostsFeed &&
                                        !widget.hideBottomDramaFeed) ...[
                                      const SizedBox(height: 40),
                                      Container(
                                        height: _kMorePostsDividerHeight,
                                        color: theme.colorScheme.outline
                                            .withOpacity(0.2),
                                      ),
                                      SizedBox(
                                        key: _morePostsSectionKey,
                                        child: _MorePostsSection(
                                          key: ValueKey(
                                            '${_post.id}_$_morePostsTabIndex',
                                          ),
                                          excludePostId: _post.id,
                                          currentUserAuthor: _currentUserAuthor,
                                          initialTabIndex: _morePostsTabIndex,
                                          initialPosts:
                                              widget.initialBoardPosts,
                                          talkAskUseCardFeedLayout: widget
                                              .dramaFeedTalkAskUseCardFeedLayout,
                                          onTabChanged: (i) => setState(
                                            () => _morePostsTabIndex = i,
                                          ),
                                          onPostTap: _navigateToPost,
                                          feedAuthorAvatarSize:
                                              kAppUnifiedProfileAvatarSize,
                                        ),
                                      ),
                                    ],
                                    // 제일 아래: 홈 메인 탭일 때는 브라우저 바 없음 → 패딩만
                                    SizedBox(height: bottomScrollPad),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Visibility(
                    visible: !hideBottomBrowserBar,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: false,
                    child: IgnorePointer(
                      ignoring: hideBottomBrowserBar,
                      child: BrowserNavBar(
                        canGoBack: true,
                        canGoForward: _forwardStack.isNotEmpty,
                        isRefreshing: _isRefreshing,
                        onBack: _goBack,
                        onForward: _goForward,
                        onRefresh: _loadLatestPost,
                      ),
                    ),
                  ),
                ),
              ],
            );
            return hideViewsInTalkAskDetail
                ? AnnotatedRegion<SystemUiOverlayStyle>(
                    value: listsStyleSubpageSystemOverlay(theme, listsHeaderBg),
                    child: mainStack,
                  )
                : mainStack;
          },
        ),
        ),
      ),
    );
  }
}

/// 댓글 아래 DramaFeed: 리뷰·톡 탭 (에스크 탭 없음 — 홈과 동일 PopularPostsTab / FreeBoardTab)
class _MorePostsSection extends StatefulWidget {
  const _MorePostsSection({
    super.key,
    required this.excludePostId,
    this.currentUserAuthor,
    this.initialTabIndex = 0,
    this.initialPosts,
    this.talkAskUseCardFeedLayout = true,
    this.onTabChanged,
    this.onPostTap,
    this.feedAuthorAvatarSize,
  });

  final String excludePostId;
  final String? currentUserAuthor;
  final int initialTabIndex;

  /// 홈탭에서 넘긴 게시판 목록이 있으면 즉시 표시(인기글/자유/질문 동일 피드)
  final List<Post>? initialPosts;

  /// 자유·질문 DramaFeed: [CommunityScreen] 톡/에스크 레이아웃 토글과 동일.
  final bool talkAskUseCardFeedLayout;
  final void Function(int)? onTabChanged;
  final void Function(Post)? onPostTap;

  /// null이면 피드 카드 기본 아바타. 글 상세에서는 본문·댓글과 동일 크기로 전달.
  final double? feedAuthorAvatarSize;

  @override
  State<_MorePostsSection> createState() => _MorePostsSectionState();
}

class _MorePostsSectionState extends State<_MorePostsSection>
    with SingleTickerProviderStateMixin {
  static const List<String> _feedBoards = ['review', 'talk'];

  /// 탭 [t]에 캐시·갱신 글 [p]가 속하는지 (에스크 탭 숨김 — ask는 톡 탭에만 매칭)
  bool _tabMatchesPost(int t, Post p) {
    if (t == 0) return postMatchesFeedFilter(p, _feedBoards[0]);
    return postMatchesFeedFilter(p, 'talk') ||
        postMatchesFeedFilter(p, 'ask');
  }

  late TabController _tabController;
  final List<List<Post>> _tabFeedPosts = List.generate(2, (_) => []);
  final List<DocumentSnapshot<Map<String, dynamic>>?> _tabLastDoc =
      List.generate(2, (_) => null);
  final List<bool> _tabHasMore = List.generate(2, (_) => true);
  final List<bool> _tabLoadingMore = List.generate(2, (_) => false);
  final List<bool> _tabInitialLoading = List.generate(2, (_) => true);
  late final List<ScrollController> _feedScrollControllers;
  String? _postsError;

  /// 홈 [CommunityScreen._talkAskUseCardFeedLayout]과 동일 — 자유·질문 탭만 사용.
  late bool _talkAskUseCardFeedLayout;

  @override
  void initState() {
    super.initState();
    _talkAskUseCardFeedLayout = widget.talkAskUseCardFeedLayout;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _feedScrollControllers = List.generate(2, (i) {
      final c = ScrollController();
      c.addListener(() => _onFeedScrollNearEnd(i));
      return c;
    });
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        widget.onTabChanged?.call(_tabController.index);
        _ensureFeedTabBootstrapped(_tabController.index);
      }
    });
    // 홈에서 넘긴 캐시가 있으면 탭별로 나눠 채움(즉시 표시)
    final initial = widget.initialPosts;
    if (initial != null && initial.isNotEmpty) {
      for (final p in initial) {
        if (BlockService.instance.isBlocked(p.author) ||
            BlockService.instance.isPostBlocked(p.id))
          continue;
        if (p.id == widget.excludePostId) continue;
        for (var t = 0; t < 2; t++) {
          if (_tabMatchesPost(t, p)) {
            if (!_tabFeedPosts[t].any((e) => e.id == p.id)) {
              _tabFeedPosts[t].add(p);
            }
          }
        }
      }
      for (var t = 0; t < 2; t++) {
        _tabInitialLoading[t] = _tabFeedPosts[t].isEmpty;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureFeedTabBootstrapped(widget.initialTabIndex.clamp(0, 1));
    });
  }

  @override
  void didUpdateWidget(covariant _MorePostsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.talkAskUseCardFeedLayout != oldWidget.talkAskUseCardFeedLayout) {
      _talkAskUseCardFeedLayout = widget.talkAskUseCardFeedLayout;
    }
  }

  @override
  void dispose() {
    for (final c in _feedScrollControllers) {
      c.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  /// 글 상세 하단 DramaFeed: 홈과 동일한 국가 기준(us/kr/jp/cn).
  String _viewerLanguageForFeed() {
    return AuthService.instance.isLoggedIn.value
        ? (UserProfileService.instance.signupCountryNotifier.value ??
              LocaleService.instance.locale)
        : LocaleService.instance.locale;
  }

  void _onFeedScrollNearEnd(int tabIndex) {
    if (_tabController.index != tabIndex) return;
    final c = _feedScrollControllers[tabIndex];
    if (!c.hasClients) return;
    if (_tabLoadingMore[tabIndex] || !_tabHasMore[tabIndex]) return;
    if (c.position.extentAfter > 200) return;
    _loadFeedTabPage(tabIndex, reset: false);
  }

  void _ensureFeedTabBootstrapped(int tabIndex) {
    if (tabIndex < 0 || tabIndex > 1) return;
    if (_tabFeedPosts[tabIndex].isEmpty && !_tabLoadingMore[tabIndex]) {
      _loadFeedTabPage(tabIndex, reset: false);
    }
  }

  Future<void> _loadFeedTabPage(int tabIndex, {required bool reset}) async {
    if (tabIndex < 0 || tabIndex > 1) return;
    if (_tabLoadingMore[tabIndex]) return;
    if (!reset && !_tabHasMore[tabIndex]) return;

    if (reset) {
      setState(() {
        _tabFeedPosts[tabIndex].clear();
        _tabLastDoc[tabIndex] = null;
        _tabHasMore[tabIndex] = true;
        _postsError = null;
      });
    }

    if (_tabFeedPosts[tabIndex].isEmpty) {
      setState(() => _tabInitialLoading[tabIndex] = true);
    }
    setState(() => _tabLoadingMore[tabIndex] = true);

    try {
      final viewerLanguage = _viewerLanguageForFeed();
      final accumulated = <Post>[];
      DocumentSnapshot<Map<String, dynamic>>? cursor = _tabLastDoc[tabIndex];
      var pageHasMore = _tabHasMore[tabIndex];

      for (var attempt = 0; attempt < 48; attempt++) {
        final page = await PostService.instance.getPosts(
          country: null,
          timeAgoLocale: viewerLanguage,
          type: _feedBoards[tabIndex],
          lastDocument: cursor,
          limit: 20,
        );
        pageHasMore = page.hasMore;
        cursor = page.lastDocument;
        for (final p in page.posts) {
          if (p.id == widget.excludePostId) continue;
          if (!BlockService.instance.isBlocked(p.author) &&
              !BlockService.instance.isPostBlocked(p.id)) {
            accumulated.add(p);
          }
        }
        if (accumulated.isNotEmpty ||
            !pageHasMore ||
            page.lastDocument == null) {
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        final ids = _tabFeedPosts[tabIndex].map((e) => e.id).toSet();
        for (final p in accumulated) {
          if (ids.add(p.id)) {
            _tabFeedPosts[tabIndex].add(p);
          }
        }
        _tabLastDoc[tabIndex] = cursor;
        _tabHasMore[tabIndex] = pageHasMore;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _postsError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _tabLoadingMore[tabIndex] = false;
          _tabInitialLoading[tabIndex] = false;
        });
      }
    }
  }

  List<Post> _postsForTab(int tabIndex) {
    final ex = widget.excludePostId;
    return _tabFeedPosts[tabIndex].where((p) => p.id != ex).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DramaFeed 헤더
        Container(
          color: theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.fromLTRB(12, 30, 14, 20),
          alignment: Alignment.centerLeft,
          child: Text(
            'DramaFeed',
            style: GoogleFonts.notoSansKr(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
          ),
        ),
        // 탭바 — 홈탭과 완전 동일한 스타일
        Container(
          color: theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: ListenableBuilder(
            listenable: _tabController,
            builder: (context, _) {
              final r = (MediaQuery.sizeOf(context).width / 360).clamp(
                0.85,
                1.15,
              );
              final tabW = 60.0 * r;
              final tabH = 26.0 * r;
              final tabGap = 5.0 * r;
              // animation.value 대신 index(정수)를 써서 즉시 이동
              final animValue = _tabController.index.toDouble();
              final idx = _tabController.index;
              final s = CountryScope.of(context).strings;
              final showLayoutToggle = idx == 1;
              final tip = _talkAskUseCardFeedLayout
                  ? s.get('talkAskFeedLayoutSwitchToList')
                  : s.get('talkAskFeedLayoutSwitchToCards');
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: (tabW + tabGap) * 1 + tabW,
                        height: tabH,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: (tabW + tabGap) * animValue,
                              top: 0,
                              child: Container(
                                width: tabW,
                                height: tabH,
                                decoration: BoxDecoration(
                                  color: cs.inverseSurface,
                                  borderRadius: BorderRadius.circular(6 * r),
                                ),
                              ),
                            ),
                            for (var i = 0; i < 2; i++)
                              Positioned(
                                left: (tabW + tabGap) * i,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => _tabController.animateTo(
                                    i,
                                    duration: Duration.zero,
                                  ),
                                  behavior: HitTestBehavior.opaque,
                                  child: SizedBox(
                                    width: tabW,
                                    height: tabH,
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: cs.outline,
                                          width: 1.25 * r,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          6 * r,
                                        ),
                                      ),
                                      child: Text(
                                        [
                                          s.get('tabReviews'),
                                          s.get('tabGeneral'),
                                        ][i],
                                        textHeightBehavior:
                                            const TextHeightBehavior(
                                              applyHeightToFirstAscent: false,
                                              applyHeightToLastDescent: false,
                                            ),
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 10 * r,
                                          height: 1.0,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.2,
                                          foreground: Paint()
                                            ..style = PaintingStyle.fill
                                            ..strokeWidth = 0.4
                                            ..color = (idx == i
                                                ? cs.onInverseSurface
                                                : cs.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showLayoutToggle)
                    Padding(
                      padding: EdgeInsets.only(right: 6 * r),
                      child: Tooltip(
                        message: tip,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(
                              () => _talkAskUseCardFeedLayout =
                                  !_talkAskUseCardFeedLayout,
                            ),
                            borderRadius: BorderRadius.circular(8 * r),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6 * r,
                                vertical: 2 * r,
                              ),
                              child: Icon(
                                _talkAskUseCardFeedLayout
                                    ? LucideIcons.menu
                                    : LucideIcons.layout_grid,
                                size: 14 * r,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(width: 14 * r),
                ],
              );
            },
          ),
        ),
        // 탭 아래 영역: IndexedStack 대신 현재 탭만 렌더링 → 다른 탭 높이로 빈 공간 생기는 문제 방지
        Builder(
          builder: (context) {
            final idx = _tabController.index;
            void onUpdated(Post updated) {
              setState(() {
                for (var t = 0; t < 2; t++) {
                  final j = _tabFeedPosts[t].indexWhere(
                    (p) => p.id == updated.id,
                  );
                  if (j >= 0) {
                    if (_tabMatchesPost(t, updated)) {
                      _tabFeedPosts[t][j] = updated;
                    } else {
                      _tabFeedPosts[t].removeAt(j);
                    }
                  } else if (_tabMatchesPost(t, updated) &&
                      updated.id != widget.excludePostId &&
                      !BlockService.instance.isBlocked(updated.author) &&
                      !BlockService.instance.isPostBlocked(updated.id)) {
                    _tabFeedPosts[t].insert(0, updated);
                  }
                }
              });
            }

            void onDeleted(Post deleted) {
              setState(() {
                for (var t = 0; t < 2; t++) {
                  _tabFeedPosts[t].removeWhere((p) => p.id == deleted.id);
                }
              });
            }

            if (idx == 0) {
              return PopularPostsTab(
                posts: _postsForTab(0),
                isLoading: _tabFeedPosts[0].isEmpty && _tabInitialLoading[0],
                error: _postsError,
                currentUserAuthor: widget.currentUserAuthor,
                onRefresh: () => _loadFeedTabPage(0, reset: true),
                enablePullToRefresh: false,
                shrinkWrap: true,
                useReviewLayout: true,
                useLetterboxdReviewLayout: true,
                useSimpleFeedLayout: true,
                reviewLetterboxdInlineFeed: true,
                feedScrollController: _feedScrollControllers[0],
                feedLoadingMore: _tabLoadingMore[0],
                feedHasMore: _tabHasMore[0],
                onPostUpdated: onUpdated,
                onPostDeleted: onDeleted,
                onPostTap: widget.onPostTap,
                feedAuthorAvatarSize: widget.feedAuthorAvatarSize,
              );
            }
            return FreeBoardTab(
              posts: _postsForTab(1),
              isLoading: _tabFeedPosts[1].isEmpty && _tabInitialLoading[1],
              error: _postsError,
              currentUserAuthor: widget.currentUserAuthor,
              onRefresh: () => _loadFeedTabPage(1, reset: true),
              enablePullToRefresh: false,
              shrinkWrap: true,
              useSimpleFeedLayout: true,
              useCardFeedLayout: _talkAskUseCardFeedLayout,
              feedScrollController: _feedScrollControllers[1],
              feedLoadingMore: _tabLoadingMore[1],
              feedHasMore: _tabHasMore[1],
              onPostUpdated: onUpdated,
              onPostDeleted: onDeleted,
              onPostTap: widget.onPostTap,
              feedAuthorAvatarSize: widget.feedAuthorAvatarSize,
            );
          },
        ),
      ],
    );
  }
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.strings,
    this.depth = 0,
    required this.postId,
    this.showAuthorProfileMenu = true,
    this.contentWidth,
    required this.onPostUpdated,
    this.onReplyTap,
    this.replyingToCommentId,
    this.buildInlineReplyCard,
    this.reviewReplyIconLayout = false,
  });

  final PostComment comment;
  final dynamic strings;
  final int depth;
  final String postId;

  /// false: 톡/에스크 등 — 닉네임·아바타 탭 시 쪽지/글·댓글 메뉴 비표시
  final bool showAuthorProfileMenu;

  /// 댓글 영역 전체 너비. 지정 시 3행(답글·좋아요·싫어요)을 이 너비의 오른쪽 끝에 맞춤.
  final double? contentWidth;
  final void Function(Post) onPostUpdated;
  final void Function(String commentId)? onReplyTap;

  /// Reply 탭 시 이 id와 일치하는 타일 아래에 [buildInlineReplyCard] 표시
  final String? replyingToCommentId;
  final Widget Function()? buildInlineReplyCard;
  final bool reviewReplyIconLayout;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _isLiked = false;
  bool _isDisliked = false;
  late int _likeCount;
  late int _dislikeCount;
  bool _votePending = false;

  /// 톡·에스크: 답글을 접었다가 '답글 N개 더보기'로 펼침
  bool _talkAskRepliesExpanded = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.comment.votes;
    _dislikeCount = widget.comment.dislikedBy.length;
    _syncLikedFromComment();
    _syncDislikedFromComment();
  }

  @override
  void didUpdateWidget(covariant _CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id) {
      _talkAskRepliesExpanded = false;
    }
    if (oldWidget.comment.id == widget.comment.id &&
        (oldWidget.comment.likedBy != widget.comment.likedBy ||
            oldWidget.comment.dislikedBy != widget.comment.dislikedBy ||
            oldWidget.comment.votes != widget.comment.votes)) {
      _likeCount = widget.comment.votes;
      _dislikeCount = widget.comment.dislikedBy.length;
      _syncLikedFromComment();
      _syncDislikedFromComment();
    }
  }

  void _syncLikedFromComment() {
    final uid = AuthService.instance.currentUser.value?.uid;
    final liked = uid != null && widget.comment.likedBy.contains(uid);
    if (_isLiked != liked) setState(() => _isLiked = liked);
  }

  void _syncDislikedFromComment() {
    final uid = AuthService.instance.currentUser.value?.uid;
    final disliked = uid != null && widget.comment.dislikedBy.contains(uid);
    if (_isDisliked != disliked) setState(() => _isDisliked = disliked);
  }

  Future<void> _onLikeTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    if (_votePending) return;
    HapticFeedback.lightImpact();
    // 낙관적 업데이트
    final prevLiked = _isLiked;
    final prevDisliked = _isDisliked;
    final prevLikeCount = _likeCount;
    final prevDislikeCount = _dislikeCount;
    final nowLiked = !_isLiked;
    setState(() {
      _votePending = true;
      if (nowLiked) {
        _likeCount += (_isDisliked ? 2 : 1);
        if (_isDisliked) _dislikeCount = (_dislikeCount - 1).clamp(0, 9999);
        _isLiked = true;
        _isDisliked = false;
      } else {
        _likeCount -= 1;
        _isLiked = false;
      }
    });
    PostService.instance
        .toggleCommentLike(widget.postId, widget.comment.id)
        .then((updated) {
          if (!mounted) return;
          if (updated == null) {
            setState(() {
              _isLiked = prevLiked;
              _isDisliked = prevDisliked;
              _likeCount = prevLikeCount;
              _dislikeCount = prevDislikeCount;
            });
          } else {
            widget.onPostUpdated(updated);
          }
          if (mounted) setState(() => _votePending = false);
        });
  }

  Future<void> _onReplyTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    widget.onReplyTap?.call(widget.comment.id);
  }

  Future<void> _onDislikeTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    if (_votePending) return;
    HapticFeedback.lightImpact();
    // 낙관적 업데이트
    final prevLiked = _isLiked;
    final prevDisliked = _isDisliked;
    final prevLikeCount = _likeCount;
    final prevDislikeCount = _dislikeCount;
    final nowDisliked = !_isDisliked;
    setState(() {
      _votePending = true;
      if (nowDisliked) {
        _likeCount -= (_isLiked ? 2 : 1);
        _isDisliked = true;
        _isLiked = false;
      } else {
        _likeCount += 1;
        _isDisliked = false;
      }
    });
    PostService.instance
        .toggleCommentDislike(widget.postId, widget.comment.id)
        .then((updated) {
          if (!mounted) return;
          if (updated == null) {
            setState(() {
              _isLiked = prevLiked;
              _isDisliked = prevDisliked;
              _likeCount = prevLikeCount;
              _dislikeCount = prevDislikeCount;
            });
          } else {
            widget.onPostUpdated(updated);
          }
          if (mounted) setState(() => _votePending = false);
        });
  }

  Widget _wrapAuthorTap({required Widget child}) {
    final uid = widget.comment.authorUid?.trim();
    if (uid != null && uid.isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openUserProfileFromAuthorUid(context, uid),
        child: child,
      );
    }
    if (!widget.showAuthorProfileMenu) return child;
    return GestureDetector(
      onTapDown: (details) => _showNicknameMenu(context, details),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }

  Future<void> _showNicknameMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    if (!widget.showAuthorProfileMenu) return;
    final s = widget.strings;
    final nickname = widget.comment.author;
    if (nickname.isEmpty) return;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 1,
        details.globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'message',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.mail, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
              Text(
                s.get('sendMessageToUser'),
                style: GoogleFonts.notoSansKr(fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'posts',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.file_text, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                s.get('viewUserPosts'),
                style: GoogleFonts.notoSansKr(fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'comments',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.message_circle, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                s.get('viewUserComments'),
                style: GoogleFonts.notoSansKr(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || result == null) return;
    switch (result) {
      case 'message':
        final conv = await MessageService.instance.startConversation(
          'user_${nickname.hashCode}',
          nickname,
        );
        if (!mounted) return;
        Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => MessageThreadScreen(
              conversationId: conv.id,
              otherUserName: conv.otherUserName,
            ),
          ),
        );
        break;
      case 'posts':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserPostsScreen(authorName: nickname),
          ),
        );
        break;
      case 'comments':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                UserPostsScreen(authorName: nickname, initialSegment: 1),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final s = widget.strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // showAuthorProfileMenu == false → 톡·에스크 게시판
    final isTalkAsk = !widget.showAuthorProfileMenu;
    final contentWidth = widget.contentWidth ?? double.infinity;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final commentImgLogicalW = contentWidth.isFinite
        ? contentWidth
        : MediaQuery.sizeOf(context).width;
    final commentImgCacheW = (commentImgLogicalW * dpr).round().clamp(1, 4096);
    final commentImgCacheH = (400 * dpr).round().clamp(1, 4096);

    // ── 톡·에스크 전용 새 레이아웃 ─────────────────────────────────
    if (isTalkAsk) {
      final isReply = widget.depth > 0;
      final metaColor = cs.onSurface.withValues(alpha: 0.44);
      // 닉·본문을 살짝 줄이고 아바타만 키워 한 블록 높이를 맞추기 쉽게
      final avatarSize = kAppUnifiedProfileAvatarSize;
      final timeFontSize = isReply ? 8.0 : 8.5;
      final hasImage = comment.imageUrl != null && comment.imageUrl!.isNotEmpty;
      final hasText = comment.text.trim().isNotEmpty;

      /// 닉↔본문 기준 간격. 본문↔Reply 도 동일 (텍스트 Stack에서 [bodyMicroUpPx] 만큼만 본문을 위로 당김)
      final gapNameToBody = 1.0;
      const bodyMicroUpPx = 1.0;
      final gapTalkAskNameBodyReply = gapNameToBody - bodyMicroUpPx;

      /// 본문 마지막 줄 아래 line-height 여백을 줄여 본문↔Reply 가 닉↔본문과 비슷하게 보이게
      const talkAskBodyTextHeightBehavior = TextHeightBehavior(
        applyHeightToLastDescent: false,
      );
      final bodyFontSize = isReply ? 12.0 : 13.0;
      final bodyTextStyle = GoogleFonts.notoSansKr(
        fontSize: bodyFontSize,
        color: cs.onSurface,
        height: 1.38,
      );

      Widget nameRow() {
        return Transform.translate(
          offset: const Offset(0, -1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _wrapAuthorTap(
                  child: Text(
                    comment.author,
                    style: appUnifiedNicknameStyle(cs),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                comment.displayTimeAgo,
                style: GoogleFonts.notoSansKr(
                  fontSize: timeFontSize,
                  color: metaColor,
                ),
              ),
            ],
          ),
        );
      }

      // 톡·에스크 텍스트만: 2줄 이상 → 하트=1째 줄 오른쪽·세로중앙, 숫자=2째 줄 오른쪽·세로중앙.
      // 1줄 → 하트=본문 블록 세로중앙, 숫자=Reply 행과 맞춤.
      const talkAskLikeColW = 40.0;
      const talkAskLikeCountDownNudge = 1.0;
      const talkAskBodyVisualUpNudge = 1.5;
      const heartIconSize = 16.0;
      const heartVPad = 4.0;
      final heartBlockH = heartVPad + heartIconSize + heartVPad;

      const replyArrowW = 18.0; // 14px 아이콘 + 4px gap — 답글 행에서만 사용
      final commentBody = LayoutBuilder(
        builder: (context, cons) {
          final innerMaxW = cons.maxWidth;
          final textColumnMaxW = (innerMaxW - avatarSize - 8 - talkAskLikeColW -
                  (isReply ? replyArrowW : 0.0))
              .clamp(1.0, 9999.0);
          final textScaler = MediaQuery.textScalerOf(context);
          final textDir = Directionality.of(context);
          final authorLineStyle = appUnifiedNicknameStyle(cs);
          final timeLineStyle = GoogleFonts.notoSansKr(
            fontSize: timeFontSize,
            color: metaColor,
          );
          final tpAuthorLine = TextPainter(
            text: TextSpan(
              text: comment.author.isEmpty ? ' ' : comment.author,
              style: authorLineStyle,
            ),
            textDirection: textDir,
            maxLines: 1,
            textScaler: textScaler,
          )..layout(maxWidth: textColumnMaxW);
          final tpTimeLine = TextPainter(
            text: TextSpan(text: comment.displayTimeAgo, style: timeLineStyle),
            textDirection: textDir,
            maxLines: 1,
            textScaler: textScaler,
          )..layout();
          final nameBlockH = max(tpAuthorLine.height, tpTimeLine.height);

          final replyStyle = appUnifiedNicknameStyle(cs).copyWith(
            fontWeight: FontWeight.w500,
            color: metaColor,
            height: 1.2,
          );
          final tpReply = TextPainter(
            text: TextSpan(text: s.get('reply'), style: replyStyle),
            textDirection: textDir,
            maxLines: 1,
            textScaler: textScaler,
          )..layout();
          final replyRowH = max(tpReply.height + 2.0, 18.0);

          // Reply와 동일 크기·행고정 (좋아요 수만 색상 변화)
          final countStyle = appUnifiedNicknameStyle(cs).copyWith(
            fontWeight: FontWeight.w500,
            color: _isLiked ? Colors.redAccent : metaColor,
            height: 1.2,
          );
          // 좋아요 수 0↔1 전환 시 높이가 달라지며 아래 레이아웃이 밀리지 않도록 숫자 줄 높이 고정
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

          final avatarChip = _wrapAuthorTap(
            child: _PostAuthorAvatar(
              photoUrl: comment.authorPhotoUrl,
              author: comment.author,
              authorUid: comment.authorUid,
              colorIndex: comment.authorAvatarColorIndex,
              size: avatarSize,
            ),
          );

          Widget imageBlock() {
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FullScreenImagePage(imageUrls: [comment.imageUrl!]),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Image.network(
                    comment.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topLeft,
                    cacheWidth: commentImgCacheW,
                    cacheHeight: commentImgCacheH,
                    errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      color: cs.surfaceContainerHighest,
                      child: Icon(
                        LucideIcons.image_off,
                        size: 36,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          Widget heartHitTarget() {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onLikeTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: heartVPad),
                child: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  size: heartIconSize,
                  color: _isLiked ? Colors.redAccent : metaColor,
                ),
              ),
            );
          }

          if (hasImage) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isReply || widget.reviewReplyIconLayout) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Transform.rotate(
                      angle: pi,
                      child: Icon(
                        LucideIcons.reply,
                        size: 14,
                        color: metaColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                avatarChip,
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      nameRow(),
                      SizedBox(height: gapNameToBody),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  imageBlock(),
                                  if (hasText) ...[
                                    const SizedBox(height: 4),
                                    Transform.translate(
                                      offset: const Offset(
                                        0,
                                        -talkAskBodyVisualUpNudge,
                                      ),
                                      child: Text(
                                        comment.text,
                                        style: bodyTextStyle,
                                        textHeightBehavior:
                                            talkAskBodyTextHeightBehavior,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(
                              width: talkAskLikeColW,
                              child: Center(child: heartHitTarget()),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: gapNameToBody),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () async => await _onReplyTap(),
                                child: Text(s.get('reply'), style: replyStyle),
                              ),
                            ),
                            SizedBox(
                              width: talkAskLikeColW,
                              height: countSlotH,
                              child: Center(
                                child: _likeCount > 0
                                    ? Text(
                                        formatCompactCount(_likeCount),
                                        textAlign: TextAlign.center,
                                        style: countStyle,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final yBodyTop = nameBlockH + gapTalkAskNameBodyReply;

          double bodyH = 0;
          List<LineMetrics>? bodyLineMetrics;
          if (hasText) {
            final tpBody = TextPainter(
              text: TextSpan(text: comment.text, style: bodyTextStyle),
              textDirection: textDir,
              maxLines: null,
              textScaler: textScaler,
              textHeightBehavior: talkAskBodyTextHeightBehavior,
            )..layout(maxWidth: textColumnMaxW);
            bodyH = tpBody.height;
            bodyLineMetrics = tpBody.computeLineMetrics();
          }

          double countH = countSlotH;
          if (_likeCount > 0) {
            final tpC = TextPainter(
              text: TextSpan(
                text: formatCompactCount(_likeCount),
                style: countStyle,
              ),
              textDirection: textDir,
              maxLines: 1,
              textScaler: textScaler,
            )..layout();
            countH = max(countSlotH, tpC.height);
          }

          final double heartTop;
          final double countTop;
          final double replyRowTop;
          if (hasText && bodyH > 0 && bodyLineMetrics != null) {
            final lines = bodyLineMetrics;
            if (lines.length >= 2) {
              final h0 = lines[0].height;
              final h1 = lines[1].height;
              final line0CenterY = yBodyTop + h0 / 2;
              final line1CenterY = yBodyTop + h0 + h1 / 2;
              heartTop = line0CenterY - heartBlockH / 2;
              countTop = line1CenterY - countH / 2 + talkAskLikeCountDownNudge;
              replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
            } else {
              replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
              heartTop = yBodyTop + bodyH / 2 - heartBlockH / 2;
              final countCenterY = replyRowTop + replyRowH / 2;
              var ct = countCenterY - countH / 2 + talkAskLikeCountDownNudge;
              final replyBandMin = replyRowTop;
              final replyBandMax = replyRowTop + replyRowH - countH;
              countTop = replyBandMax >= replyBandMin
                  ? ct.clamp(replyBandMin, replyBandMax)
                  : replyBandMin;
            }
          } else {
            replyRowTop = hasText
                ? yBodyTop + bodyH + gapTalkAskNameBodyReply
                : yBodyTop;
            heartTop = yBodyTop + replyRowH / 2 - heartBlockH / 2;
            final countCenterY = replyRowTop + replyRowH / 2;
            var ct = countCenterY - countH / 2 + talkAskLikeCountDownNudge;
            final replyBandMin = replyRowTop;
            final replyBandMax = replyRowTop + replyRowH - countH;
            countTop = replyBandMax >= replyBandMin
                ? ct.clamp(replyBandMin, replyBandMax)
                : replyBandMin;
          }

          final contentBottom = max(
            hasText ? yBodyTop + bodyH + gapTalkAskNameBodyReply : replyRowTop,
            replyRowTop + replyRowH,
          );
          var stackH = max(
            contentBottom,
            max(heartTop + heartBlockH, countTop + countH),
          );
          stackH = max(stackH, avatarSize);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isReply || widget.reviewReplyIconLayout) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Transform.rotate(
                    angle: pi,
                    child: Icon(
                      LucideIcons.reply,
                      size: 14,
                      color: metaColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              avatarChip,
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: stackH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: talkAskLikeColW,
                        top: 0,
                        child: nameRow(),
                      ),
                      if (hasText)
                        Positioned(
                          left: 0,
                          right: talkAskLikeColW,
                          top: yBodyTop,
                          child: Transform.translate(
                            offset: const Offset(0, -talkAskBodyVisualUpNudge),
                            child: Text(
                              comment.text,
                              style: bodyTextStyle,
                              textHeightBehavior: talkAskBodyTextHeightBehavior,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: talkAskLikeColW,
                        top: replyRowTop,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async => await _onReplyTap(),
                          child: Text(s.get('reply'), style: replyStyle),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: heartTop,
                        width: talkAskLikeColW,
                        height: heartBlockH,
                        child: Center(child: heartHitTarget()),
                      ),
                      Positioned(
                        right: 0,
                        top: countTop,
                        width: talkAskLikeColW,
                        height: countH,
                        child: Center(
                          child: _likeCount > 0
                              ? Text(
                                  formatCompactCount(_likeCount),
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

      final List<Widget> replyWidgets = comment.replies
          .map(
            (r) => _CommentTile(
              comment: r,
              strings: s,
              depth: widget.depth + 1,
              postId: widget.postId,
              showAuthorProfileMenu: widget.showAuthorProfileMenu,
              contentWidth: widget.contentWidth,
              onPostUpdated: widget.onPostUpdated,
              onReplyTap: widget.onReplyTap,
              replyingToCommentId: widget.replyingToCommentId,
              buildInlineReplyCard: widget.buildInlineReplyCard,
              reviewReplyIconLayout: widget.reviewReplyIconLayout,
            ),
          )
          .toList();
      final langCode = Localizations.localeOf(context).languageCode.toLowerCase();
      String viewMoreRepliesText(int count) {
        if (langCode.startsWith('ko')) return '답글 $count개 더보기';
        return 'View $count more ${count == 1 ? 'reply' : 'replies'}';
      }
      String hideRepliesText(int count) {
        if (langCode.startsWith('ko')) return count == 1 ? '답글 숨기기' : '답글 숨기기';
        return 'Hide ${count == 1 ? 'reply' : 'replies'}';
      }

      // depth 0: 전체 너비, 하단 구분선 + 답글 목록
      if (!isReply) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: commentBody,
            ),
            if (comment.replies.isNotEmpty && !_talkAskRepliesExpanded)
              Padding(
                padding: EdgeInsets.fromLTRB(16 + avatarSize + 8, 0, 16, 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _talkAskRepliesExpanded = true),
                  child: Text.rich(
                    TextSpan(
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: metaColor,
                        height: 1.25,
                      ),
                      children: [
                        const TextSpan(text: '\u2014 '),
                        TextSpan(
                          text: viewMoreRepliesText(comment.replies.length),
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
            if (comment.replies.isNotEmpty && _talkAskRepliesExpanded)
              ...replyWidgets,
            if (comment.replies.isNotEmpty && _talkAskRepliesExpanded)
              Padding(
                padding: EdgeInsets.fromLTRB(16 + avatarSize + 8, 0, 16, 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _talkAskRepliesExpanded = false),
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
                          text: hideRepliesText(comment.replies.length),
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
            if (widget.replyingToCommentId == widget.comment.id &&
                widget.buildInlineReplyCard != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: widget.buildInlineReplyCard!(),
              ),
            const SizedBox(height: 10),
          ],
        );
      }

      // depth 1+: 화살표 표시 (아바타 왼쪽), 배경 박스 없음
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: commentBody,
          ),
          if (comment.replies.isNotEmpty && !_talkAskRepliesExpanded)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16 + replyArrowW + avatarSize + 8, 0, 16, 4),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _talkAskRepliesExpanded = true),
                child: Text.rich(
                  TextSpan(
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      color: metaColor,
                      height: 1.25,
                    ),
                    children: [
                      const TextSpan(text: '\u2014 '),
                      TextSpan(
                        text: viewMoreRepliesText(comment.replies.length),
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
          if (comment.replies.isNotEmpty && _talkAskRepliesExpanded)
            ...replyWidgets,
          if (comment.replies.isNotEmpty && _talkAskRepliesExpanded)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16 + replyArrowW + avatarSize + 8, 0, 16, 4),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _talkAskRepliesExpanded = false),
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
                        text: hideRepliesText(comment.replies.length),
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
          if (widget.replyingToCommentId == widget.comment.id &&
              widget.buildInlineReplyCard != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: widget.buildInlineReplyCard!(),
            ),
        ],
      );
    }

    // ── 기존 리뷰 등 게시판 레이아웃 (변경 없음) ─────────────────────
    final metaGray = cs.onSurfaceVariant;
    final isReviewReply = widget.reviewReplyIconLayout;

    // 3행: 답글 + 투표박스 (오른쪽 정렬)
    final actionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async => await _onReplyTap(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Icon(LucideIcons.message_circle, size: 14, color: metaGray),
          ),
        ),
        const SizedBox(width: 6),
        _DetailVoteBox(
          voteState: _isLiked ? 1 : (_isDisliked ? -1 : 0),
          count: _likeCount,
          onUp: _onLikeTap,
          onDown: _onDislikeTap,
          primaryColor: cs.primary,
          useThumbIcons: true,
          thumbBaseColor: metaGray,
        ),
      ],
    );

    // 1·2·3행 영역 (Padding 포함) — 레딧 스타일: 아바타 왼쪽 고정
    final rowsSection = Padding(
      padding: widget.depth == 0
          ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
          : const EdgeInsets.fromLTRB(0, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isReviewReply)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Icon(
                LucideIcons.reply,
                size: 13,
                color: metaGray.withValues(alpha: 0.9),
              ),
            ),
          _wrapAuthorTap(
            child: _PostAuthorAvatar(
              photoUrl: comment.authorPhotoUrl,
              author: comment.author,
              authorUid: comment.authorUid,
              colorIndex: comment.authorAvatarColorIndex,
              size: kAppUnifiedProfileAvatarSize,
            ),
          ),
          SizedBox(width: isReviewReply ? 8 : 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _wrapAuthorTap(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: comment.author,
                          style: appUnifiedNicknameStyle(cs),
                        ),
                        TextSpan(
                          text: ' · ${comment.displayTimeAgo}',
                          style: appUnifiedNicknameMetaTimeStyle(cs),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                if (comment.imageUrl != null &&
                    comment.imageUrl!.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullScreenImagePage(
                            imageUrls: [comment.imageUrl!],
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: Image.network(
                          comment.imageUrl!,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topLeft,
                          cacheWidth: commentImgCacheW,
                          cacheHeight: commentImgCacheH,
                          errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              LucideIcons.image_off,
                              size: 40,
                              color: metaGray,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                if (comment.text.trim().isNotEmpty)
                  Text(
                    comment.text,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: cs.onSurface,
                      height: 1.45,
                    ),
                  ),
                Align(alignment: Alignment.centerRight, child: actionRow),
              ],
            ),
          ),
        ],
      ),
    );

    // depth 0: 풀 width (리뷰 등)
    if (widget.depth == 0) {
      return Container(
        color: theme.brightness == Brightness.light
            ? cs.surfaceContainerHighest
            : cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            rowsSection,
            if (comment.replies.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: comment.replies
                    .map(
                      (r) => _CommentTile(
                        comment: r,
                        strings: s,
                        depth: widget.depth + 1,
                        postId: widget.postId,
                        showAuthorProfileMenu: widget.showAuthorProfileMenu,
                        contentWidth: widget.contentWidth,
                        onPostUpdated: widget.onPostUpdated,
                        onReplyTap: widget.onReplyTap,
                        replyingToCommentId: widget.replyingToCommentId,
                        buildInlineReplyCard: widget.buildInlineReplyCard,
                        reviewReplyIconLayout: widget.reviewReplyIconLayout,
                      ),
                    )
                    .toList(),
              ),
            if (widget.replyingToCommentId == widget.comment.id &&
                widget.buildInlineReplyCard != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: widget.buildInlineReplyCard!(),
              ),
          ],
        ),
      );
    }

    // depth 1+: 왼쪽 세로선 + 들여쓰기
    final isFirstReply = widget.depth == 1;
    return Container(
      margin: EdgeInsets.only(
        left: isReviewReply
            ? (isFirstReply ? 64 : 56)
            : (isFirstReply ? 20 : 12),
      ),
      padding: isReviewReply ? EdgeInsets.zero : const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: cs.outline.withValues(alpha: 0.6),
            width: 0.7,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          rowsSection,
          if (comment.replies.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: comment.replies
                  .map(
                    (r) => _CommentTile(
                      comment: r,
                      strings: s,
                      depth: widget.depth + 1,
                      postId: widget.postId,
                      showAuthorProfileMenu: widget.showAuthorProfileMenu,
                      contentWidth: widget.contentWidth,
                      onPostUpdated: widget.onPostUpdated,
                      onReplyTap: widget.onReplyTap,
                      replyingToCommentId: widget.replyingToCommentId,
                      buildInlineReplyCard: widget.buildInlineReplyCard,
                      reviewReplyIconLayout: widget.reviewReplyIconLayout,
                    ),
                  )
                  .toList(),
            ),
          if (widget.replyingToCommentId == widget.comment.id &&
              widget.buildInlineReplyCard != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 16, 8),
              child: widget.buildInlineReplyCard!(),
            ),
        ],
      ),
    );
  }
}

/// 좋아요/댓글/공유 액션 칩
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isHighlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isHighlighted
                    ? cs.primary
                    : cs.onSurfaceVariant.withOpacity(0.65),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isHighlighted
                      ? cs.primary
                      : cs.onSurfaceVariant.withOpacity(0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _detailMaxHeightPerWidth = 1.4;

/// 글 상세 영상 재생: 탭 시 재생/일시정지, 하단 컨트롤 바(재생, 진행바, 시간, 음소거)
class _PostVideoPlayer extends StatefulWidget {
  const _PostVideoPlayer({
    required this.videoUrl,
    this.thumbnailUrl,
    this.isGif = false,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final bool isGif;

  @override
  State<_PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<_PostVideoPlayer> {
  late VideoPlayerController _controller;
  bool _muted = false;
  /// 초기 자동재생이 이미 시작됐는지 추적 (리스너가 반복 play()하는 버그 방지)
  bool _autoPlayStarted = false;

  void _applySettings() {
    _controller.setLooping(widget.isGif);
    if (widget.isGif) {
      _controller.setVolume(0);
      _muted = true;
    } else {
      _controller.setVolume(1);
      _muted = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // preload로 생성된 컨트롤러 재사용 (초기화 중이어도 재사용)
    final cached = VideoPreloadCache.instance.consume(widget.videoUrl);
    if (cached != null) {
      _controller = cached;
      if (cached.value.isInitialized) {
        // 이미 완료 → 즉시 재생
        _applySettings();
        _controller.addListener(() {
          if (mounted) setState(() {});
        });
        _controller.play();
      } else {
        // 아직 초기화 중 → 완료 후 한 번만 재생 (중복 네트워크 요청 없음)
        _controller.addListener(() {
          if (!mounted) return;
          if (_controller.value.isInitialized && !_autoPlayStarted) {
            _autoPlayStarted = true;
            _applySettings();
            _controller.play();
          }
          setState(() {});
        });
      }
    } else {
      // 캐시 없음 — 콜드 스타트
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          _applySettings();
          setState(() {});
          _controller.play();
        });
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_controller.value.isInitialized || !mounted) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  void _toggleMute() {
    if (!_controller.value.isInitialized || !mounted) return;
    _muted = !_muted;
    _controller.setVolume(_muted ? 0 : 1);
    setState(() {});
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final initialized = _controller.value.isInitialized;
    final duration = initialized ? _controller.value.duration : Duration.zero;
    final position = initialized ? _controller.value.position : Duration.zero;
    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds;
    final progress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    final videoThumbCacheW = (screenW * dpr).round().clamp(1, 2048);
    final videoThumbCacheH = (videoThumbCacheW * 1.3).round().clamp(1, 2048);

    // 가로 비율에 맞게: 1:1.3 프레임에 꽉 채우고 세로는 잘림 (cover)
    const double aspectRatio = 1 / 1.3;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 초기화 완료 시 영상: 가로 꽉 채우고 세로 잘림 (cover)
                  if (initialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller.value.size.width,
                        height: _controller.value.size.height,
                        child: VideoPlayer(_controller),
                      ),
                    )
                  else if (widget.thumbnailUrl != null &&
                      widget.thumbnailUrl!.isNotEmpty)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          widget.thumbnailUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: videoThumbCacheW,
                          cacheHeight: videoThumbCacheH,
                          errorBuilder: (_, __, ___) =>
                              Container(color: Colors.black),
                        ),
                        const Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    const Center(child: CircularProgressIndicator()),
                  if (widget.isGif)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'GIF',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (initialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: _togglePlayPause,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white38,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: (v) {
                            if (initialized && totalMs > 0) {
                              final ms = (v * totalMs).round();
                              _controller.seekTo(Duration(milliseconds: ms));
                            }
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(position),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(duration),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                    if (!widget.isGif)
                      IconButton(
                        icon: Icon(
                          _muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: _toggleMute,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () {
                        // 초기화된 컨트롤러를 전달하면 fullscreen에서 즉시 재생
                        final ctrl = _controller.value.isInitialized
                            ? _controller
                            : null;
                        FullScreenVideoPage.show(
                          context,
                          videoUrl: widget.videoUrl,
                          thumbnailUrl: widget.thumbnailUrl,
                          isGif: widget.isGif,
                          existingController: ctrl,
                        );
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 여러 장의 이미지를 가로 스와이프로 보여주는 캐러셀
/// 피드와 동일: 원본 비율, 세로 최대 1:1.4 캡 (imageDimensions 있으면 원본, 없으면 1:1.15)
class _PostImageCarousel extends StatefulWidget {
  const _PostImageCarousel({
    required this.imageUrls,
    this.imageDimensions,
    required this.onTap,
  });

  final List<String> imageUrls;
  final List<List<int>>? imageDimensions;
  final void Function(int index) onTap;

  static const double _defaultRatio = 1 / 1.15;
  static const double _minAspectRatio = 1 / _detailMaxHeightPerWidth;

  double aspectRatioFor(int index) {
    double raw;
    if (imageDimensions != null && index < imageDimensions!.length) {
      final d = imageDimensions![index];
      if (d.length >= 2 && d[0] > 0 && d[1] > 0) {
        raw = d[0] / d[1];
      } else {
        raw = _defaultRatio;
      }
    } else {
      raw = _defaultRatio;
    }
    return raw < _minAspectRatio ? _minAspectRatio : raw;
  }

  @override
  State<_PostImageCarousel> createState() => _PostImageCarouselState();
}

class _PostImageCarouselState extends State<_PostImageCarousel> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();
    if (widget.imageUrls.length == 1) {
      return AspectRatio(
        aspectRatio: widget.aspectRatioFor(0),
        child: OptimizedNetworkImage(
          imageUrl: widget.imageUrls.first,
          fit: BoxFit.cover,
          errorWidget: Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(
                LucideIcons.image_off,
                size: 56,
                color: cs.onSurfaceVariant.withOpacity(0.4),
              ),
            ),
          ),
          onTap: () => widget.onTap(0),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatioFor(_currentPage),
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.imageUrls.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  return OptimizedNetworkImage(
                    imageUrl: widget.imageUrls[index],
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      color: cs.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          LucideIcons.image_off,
                          size: 56,
                          color: cs.onSurfaceVariant.withOpacity(0.4),
                        ),
                      ),
                    ),
                    onTap: () => widget.onTap(index),
                  );
                },
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_currentPage + 1}/${widget.imageUrls.length}',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(widget.imageUrls.length, (i) {
                        final isActive = _currentPage == i;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: isActive ? 8 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : Colors.white.withOpacity(0.4),
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 글 상세용 회원 레벨 배지 (1: 회색, 2~29: 단계별 색, 30: 골드)
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  static Color _levelColor(int level) {
    if (level >= 30) return const Color(0xFFD4AF37);
    if (level == 1) return const Color(0xFF9E9E9E);
    final t = (level - 1) / 28;
    return Color.lerp(const Color(0xFF9E9E9E), const Color(0xFF26A69A), t)!;
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(level);
    final isMax = level >= 30;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color.withOpacity(isMax ? 0.25 : 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: isMax ? 1.5 : 1),
      ),
      child: Center(
        child: Text(
          '$level',
          style: GoogleFonts.notoSansKr(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// 글 상세 페이지용 작성자 프로필 아바타
class _PostAuthorAvatar extends StatelessWidget {
  const _PostAuthorAvatar({
    required this.photoUrl,
    required this.author,
    this.authorUid,
    this.colorIndex,
    this.size = kAppUnifiedProfileAvatarSize,
  });

  final String? photoUrl;
  final String author;
  final String? authorUid;
  final int? colorIndex;
  final double size;

  int _resolvedIndex() {
    if (colorIndex != null) return colorIndex!;
    final name = author.startsWith('u/') ? author.substring(2) : author;
    return name.codeUnits.fold(0, (prev, c) => prev + c);
  }

  @override
  Widget build(BuildContext context) {
    final uid = authorUid?.trim();
    Widget child;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final avatarCache = (size * dpr).round().clamp(1, 512);
      child = ClipOval(
        child: Image.network(
          photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: avatarCache,
          cacheHeight: avatarCache,
          errorBuilder: (_, __, ___) => _buildDefault(),
        ),
      );
    } else {
      child = _buildDefault();
    }
    if (uid == null || uid.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfileFromAuthorUid(context, uid),
      child: child,
    );
  }

  Widget _buildDefault() {
    final idx = _resolvedIndex();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UserProfileService.bgColorFromIndex(idx),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.person,
          size: size * 0.6,
          color: UserProfileService.iconColorFromIndex(idx),
        ),
      ),
    );
  }
}

/// 글 상세 페이지용 투표박스 (카드의 _VoteBox와 동일한 스타일)
class _DetailVoteBox extends StatelessWidget {
  const _DetailVoteBox({
    required this.voteState,
    required this.count,
    required this.onUp,
    required this.onDown,
    required this.primaryColor,
    this.useThumbIcons = false,
    this.thumbBaseColor = const Color(0xFFADADAD),
  });

  final int voteState;
  final int count;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final Color primaryColor;
  final bool useThumbIcons;
  final Color thumbBaseColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = useThumbIcons ? thumbBaseColor : cs.onSurfaceVariant;
    const dislikeActiveColor = Color(0xFF0A84FF);
    final upColor = voteState == 1
        ? primaryColor
        : (useThumbIcons && voteState == 0 && count > 0)
        ? Colors.black87
        : baseColor;
    final downColor = voteState == -1 ? dislikeActiveColor : baseColor;
    // 숫자 색상: 본인이 누른 경우 활성색, 아무것도 안 누른 경우 옆 댓글/조회수와 동일
    final countColor = voteState == 1
        ? primaryColor
        : voteState == -1
        ? dislikeActiveColor
        : useThumbIcons
        ? (count > 0
              ? Colors
                    .black87 // 1 이상: 검은색
              : count < 0
              ? const Color(0xFFCCCCCC) // 음수: 더 옅은 색
              : baseColor) // 0: 기본 회색
        : baseColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onUp,
              splashColor: primaryColor.withOpacity(0.2),
              highlightColor: primaryColor.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 0, 4),
                child: useThumbIcons
                    ? Icon(
                        Icons.thumb_up_alt_outlined,
                        size: 14,
                        color: upColor,
                      )
                    : Icon(
                        Icons.arrow_drop_up_rounded,
                        size: 22,
                        color: upColor,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Text(
                formatCompactCount(count),
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: countColor,
                ),
              ),
            ),
            InkWell(
              onTap: onDown,
              splashColor: dislikeActiveColor.withOpacity(0.2),
              highlightColor: dislikeActiveColor.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 6, 4),
                child: useThumbIcons
                    ? Icon(
                        Icons.thumb_down_alt_outlined,
                        size: 14,
                        color: downColor,
                      )
                    : Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 22,
                        color: downColor,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
