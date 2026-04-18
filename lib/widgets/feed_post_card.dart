import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_profile_avatar_size.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../utils/post_board_utils.dart';
import '../config/app_moderators.dart';
import '../widgets/app_delete_confirm_dialog.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/share_sheet.dart';
import '../screens/login_page.dart';
import '../screens/post_detail_page.dart';
import '../screens/write_post_page.dart';
import '../screens/message_thread_screen.dart';
import '../screens/user_posts_screen.dart';
import '../widgets/user_profile_nav.dart';
import 'feed_inline_action_colors.dart';
import '../screens/full_screen_video_page.dart';
import '../services/message_service.dart';
import '../services/home_tab_visibility.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 피드 하단 메타(댓글·조회수) 색 - 투표박스 0일 때와 동일
const _feedMetaGray = Color(0xFFADADAD);

/// 톡·에스크: 하트–숫자, 댓글아이콘–숫자 간격 동일
const double talkAskIconCountGap = 4;

/// 피드/상세 영상 프리로드 캐시.
/// 컨트롤러를 생성 즉시 캐시에 저장 — consume 시 초기화 중이더라도 재사용.
/// 이렇게 하면 카드 탭 → 상세 전환(~300 ms) 동안 initialize()가 병행 실행되어
/// 상세 페이지가 열렸을 때 영상을 바로 혹은 훨씬 빨리 재생할 수 있다.
class VideoPreloadCache {
  VideoPreloadCache._();
  static final VideoPreloadCache instance = VideoPreloadCache._();

  // 카드 1개 탭을 노리므로 3개면 충분 (feed 스크롤 시 선행 로드 여유 포함)
  static const int _maxSize = 3;

  // url → controller (초기화 중 또는 완료 모두 저장)
  final LinkedHashMap<String, VideoPlayerController> _cache = LinkedHashMap();

  /// [url]에 대한 VideoPlayerController를 즉시 생성·캐시에 등록하고
  /// 백그라운드에서 initialize()를 실행한다. 이미 캐시에 있으면 no-op.
  Future<void> preload(String url) async {
    if (_cache.containsKey(url)) return;

    // 한도 초과 시 가장 오래된 항목 해제
    while (_cache.length >= _maxSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)?.dispose();
    }

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _cache[url] = ctrl; // ← 초기화 전에 즉시 등록
    try {
      await ctrl.initialize();
    } catch (_) {
      // initialize 실패 → 캐시에서 제거하고 해제
      if (_cache[url] == ctrl) _cache.remove(url);
      ctrl.dispose();
    }
  }

  /// 캐시에서 컨트롤러를 꺼냄 (초기화 중이어도 반환 — caller가 완료 감지 책임).
  VideoPlayerController? consume(String url) => _cache.remove(url);

  /// 더 이상 필요 없을 때 취소·해제
  void cancel(String url) => _cache.remove(url)?.dispose();
}

/// 모던 카드형 게시글 카드
class FeedPostCard extends StatefulWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    this.currentUserAuthor,
    this.onPostUpdated,
    this.onPostDeleted,
    this.tabName,
    this.onTap,
    this.onUserBlocked,
    /// null이면 톡/에스크 33·그 외 38. 글 상세 DramaFeed 등에서 통일할 때 지정.
    this.authorAvatarSize,
  });

  final Post post;
  final String? currentUserAuthor;
  final void Function(Post)? onPostUpdated;
  final void Function(Post)? onPostDeleted;
  final String? tabName;
  final VoidCallback? onTap;

  /// 차단 시 피드 갱신용
  final VoidCallback? onUserBlocked;

  /// 상단 작성자 원형 아바타 직경
  final double? authorAvatarSize;

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
  int _voteState = 0;
  late int _displayCount;
  bool _votePending = false;

  // 톡·에스크 하트: 디바운스 타이머 (연속 탭 시 UI는 즉시, 네트워크는 한 번만)
  Timer? _talkAskDebounce;
  int _pendingVoteTarget = 0; // 디바운스 시간 내 최종 목표 voteState

  bool get _isTalkOrAsk {
    final b = postDisplayType(widget.post);
    return b == 'talk' || b == 'ask';
  }

  @override
  void initState() {
    super.initState();
    _displayCount = _isTalkOrAsk ? widget.post.likeCount : widget.post.votes;
    _syncVoteStateFromPost();
  }

  @override
  void dispose() {
    _talkAskDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id == widget.post.id &&
        (oldWidget.post.likedBy != widget.post.likedBy ||
            oldWidget.post.dislikedBy != widget.post.dislikedBy ||
            oldWidget.post.votes != widget.post.votes ||
            oldWidget.post.likeCount != widget.post.likeCount ||
            oldWidget.post.dislikeCount != widget.post.dislikeCount)) {
      _displayCount = _isTalkOrAsk ? widget.post.likeCount : widget.post.votes;
      _syncVoteStateFromPost();
    }
  }

  void _syncVoteStateFromPost() {
    final uid = AuthService.instance.currentUser.value?.uid;
    final liked = uid != null && widget.post.likedBy.contains(uid);
    final disliked = uid != null && widget.post.dislikedBy.contains(uid);
    final newState = liked
        ? 1
        : disliked
        ? -1
        : 0;
    if (_voteState != newState) setState(() => _voteState = newState);
  }

  Future<void> _onUpTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }

    // 톡·에스크: UI 즉시 반전 + 디바운스로 네트워크 한 번만 호출
    if (_isTalkOrAsk) {
      HapticFeedback.lightImpact();
      final nowLiked = _voteState != 1;
      setState(() {
        if (nowLiked) {
          _voteState = 1;
          _displayCount += 1;
        } else {
          _voteState = 0;
          _displayCount -= 1;
        }
      });
      _pendingVoteTarget = _voteState;
      _talkAskDebounce?.cancel();
      final snapState = _voteState;
      final snapCount = _displayCount;
      final prevVoteForNet =
          nowLiked ? 0 : 1; // 디바운스 시점 직전 상태 (서버 반영 기준)
      _talkAskDebounce = Timer(const Duration(milliseconds: 350), () async {
        if (!mounted) return;
        final result = await PostService.instance.togglePostLike(
          widget.post.id,
          currentVoteState: prevVoteForNet,
          postAuthorUid: widget.post.authorUid,
          postTitle: widget.post.title,
        );
        if (!mounted) return;
        if (result == null) {
          setState(() {
            _voteState = prevVoteForNet;
            _displayCount = snapCount + (nowLiked ? -1 : 1);
          });
        }
      });
      return;
    }

    // 일반 탭 (리뷰 등): 기존 _votePending 방식 유지
    if (_votePending) return;
    HapticFeedback.lightImpact();
    final prevState = _voteState;
    final prevCount = _displayCount;
    final nowLiked = _voteState != 1;
    setState(() {
      _votePending = true;
      if (nowLiked) {
        _displayCount += prevState == -1 ? 2 : 1;
        _voteState = 1;
      } else {
        _voteState = 0;
        _displayCount -= 1;
      }
    });
    PostService.instance
        .togglePostLike(
          widget.post.id,
          currentVoteState: prevState,
          postAuthorUid: widget.post.authorUid,
          postTitle: widget.post.title,
        )
        .then((result) {
          if (!mounted) return;
          if (result == null)
            setState(() {
              _voteState = prevState;
              _displayCount = prevCount;
            });
          if (mounted) setState(() => _votePending = false);
        });
  }

  Future<void> _onDownTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    if (_votePending) return;
    HapticFeedback.lightImpact();
    final prevState = _voteState;
    final prevCount = _displayCount;
    final nowDisliked = _voteState != -1;
    setState(() {
      _votePending = true;
      if (nowDisliked) {
        _displayCount -= (prevState == 1 ? 2 : 1);
        _voteState = -1;
      } else {
        _voteState = 0;
        _displayCount += 1;
      }
    });
    PostService.instance.togglePostDislike(widget.post.id).then((result) {
      if (!mounted) return;
      if (result == null)
        setState(() {
          _voteState = prevState;
          _displayCount = prevCount;
        });
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _showAuthorMenu(
    BuildContext context,
    String author,
    TapDownDetails details,
  ) async {
    if (author.isEmpty) return;
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

  Future<void> _showMoreMenu(BuildContext context) async {
    final post = widget.post;
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    final myUid = AuthService.instance.currentUser.value?.uid.trim();
    final isMineByUid =
        myUid != null &&
        myUid.isNotEmpty &&
        post.authorUid?.trim() == myUid;
    final isMyPost =
        isMineByUid ||
        (widget.currentUserAuthor != null &&
            post.author == widget.currentUserAuthor);
    final canModerateDelete = isAppModerator() && !isMyPost;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (isMyPost) ...[
              ListTile(
                leading: Icon(
                  LucideIcons.pencil,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  s.get('edit'),
                  style: GoogleFonts.notoSansKr(fontSize: 15),
                ),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(LucideIcons.trash_2, color: kAppDeleteActionColor),
                title: Text(
                  s.get('delete'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: kAppDeleteActionColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ] else if (canModerateDelete) ...[
              ListTile(
                leading: Icon(LucideIcons.trash_2, color: kAppDeleteActionColor),
                title: Text(
                  s.get('delete'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: kAppDeleteActionColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ] else ...[
              ListTile(
                leading: Icon(LucideIcons.flag, color: cs.error),
                title: Text(
                  s.get('report'),
                  style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.error),
                ),
                onTap: () => Navigator.pop(context, 'report'),
              ),
              ListTile(
                leading: Icon(LucideIcons.ban, color: cs.onSurface),
                title: Text(
                  s.get('block'),
                  style: GoogleFonts.notoSansKr(fontSize: 15),
                ),
                onTap: () => Navigator.pop(context, 'block'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;

    if (selected == 'edit') {
      final updated = await Navigator.push<Post>(
        context,
        MaterialPageRoute(
          builder: (_) => WritePostPage(
            initialPost: post,
            initialBoard: postDisplayType(post) == 'review'
                ? 'review'
                : (postDisplayType(post) == 'ask' ? 'ask' : 'talk'),
          ),
        ),
      );
      if (updated != null && mounted) widget.onPostUpdated?.call(updated);
    } else if (selected == 'delete') {
      final confirmed = await showAppDeleteConfirmDialog(
        context,
        message: s.get('deletePostConfirm'),
        cancelText: s.get('cancel'),
        confirmText: s.get('delete'),
      );
      if (confirmed == true && mounted) {
        await PostService.instance.deletePost(post.id, postIfKnown: post);
        if (mounted) widget.onPostDeleted?.call(post);
      }
    } else if (selected == 'report') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
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
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                s.get('report'),
                style: GoogleFonts.notoSansKr(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.get('reportSubmitted'),
              style: GoogleFonts.notoSansKr(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (selected == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.get('blockPostTitle'), style: GoogleFonts.notoSansKr()),
          content: Text(
            s.get('blockPostMessage'),
            style: GoogleFonts.notoSansKr(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.get('block'), style: GoogleFonts.notoSansKr()),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
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
          widget.onUserBlocked?.call();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final boardKind = postDisplayType(post);
    final compactTalkAskBar = boardKind == 'talk' || boardKind == 'ask';
    final talkAskFeedTitleStyle = GoogleFonts.notoSansKr(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: AppColors.homeBoardTitleForeground(cs),
      height: 1.42,
      letterSpacing: -0.25,
    );
    /// 홈 리뷰 게시판 [FeedReviewPostCard] 닉네임과 동일.
    final talkAskAuthorNameStyle = appUnifiedNicknameStyle(cs);
    final baseCardColor = theme.cardTheme.color ?? cs.surface;

    /// 톡·에스크 탭 카드만 배경을 한 톤 더 짙게(리뷰/인기 등과 구분).
    final cardFillColor = (boardKind == 'talk' || boardKind == 'ask')
        ? Color.lerp(
                baseCardColor,
                Colors.black,
                theme.brightness == Brightness.dark ? 0.18 : 0.17,
              ) ??
              baseCardColor
        : baseCardColor;

    final headerAvatarSize =
        widget.authorAvatarSize ?? kAppUnifiedProfileAvatarSize;
    final authorUid = post.authorUid?.trim();
    final myUid = AuthService.instance.currentUser.value?.uid.trim();
    final isMineByUid =
        myUid != null &&
        myUid.isNotEmpty &&
        authorUid != null &&
        authorUid.isNotEmpty &&
        authorUid == myUid;
    final mineAuthor =
        UserProfileService.instance.effectiveAuthorLabelForMyPost(
      isMineByUid: isMineByUid,
      currentUserAuthor: widget.currentUserAuthor,
      postAuthor: post.author,
    );
    final canonicalAuthor = mineAuthor ?? post.author;
    final displayAuthor = canonicalAuthor.startsWith('u/')
        ? canonicalAuthor.substring(2)
        : canonicalAuthor;
    final isMyPost =
        isMineByUid ||
        (widget.currentUserAuthor != null &&
            post.author == widget.currentUserAuthor);
    final authorNicknameRow = authorUid != null && authorUid.isNotEmpty
        ? GestureDetector(
            onTap: () => openUserProfileFromAuthorUid(context, authorUid),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    displayAuthor,
                    style: compactTalkAskBar
                        ? talkAskAuthorNameStyle
                        : appUnifiedNicknameStyle(cs),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMyPost) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      CountryScope.of(context).strings.get('myPostBadge'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          )
        : GestureDetector(
            onTapDown: (details) =>
                _showAuthorMenu(context, canonicalAuthor, details),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    displayAuthor,
                    style: compactTalkAskBar
                        ? talkAskAuthorNameStyle
                        : appUnifiedNicknameStyle(cs),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMyPost) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      CountryScope.of(context).strings.get('myPostBadge'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
    final timeText = Text(
      post.timeAgo,
      style: GoogleFonts.notoSansKr(
        fontSize: compactTalkAskBar ? 10 : 11,
        fontWeight: compactTalkAskBar ? FontWeight.w500 : FontWeight.w600,
        color: compactTalkAskBar
            ? cs.onSurfaceVariant.withValues(alpha: 0.85)
            : AppColors.mediumGrey.withOpacity(0.7),
      ),
    );

    void openPostDetail() {
      if (widget.onTap != null) {
        widget.onTap!();
        return;
      }
      if (post.hasVideo &&
          post.videoUrl != null &&
          post.videoUrl!.isNotEmpty) {
        VideoPreloadCache.instance.preload(post.videoUrl!);
      }
      Navigator.push<PostDetailResult>(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailPage(
            post: post,
            onPostDeleted: widget.onPostDeleted,
            tabName: widget.tabName,
          ),
        ),
      ).then((result) {
        final updated = result?.updatedPost;
        if (updated != null && mounted) {
          widget.onPostUpdated?.call(updated);
        }
      });
    }

    /// 하트·투표와 부모 [GestureDetector]가 탭을 두지 않게, 상세는 본문·메타 영역만 연다.
    final trailingMetaForDetailTap = Transform.translate(
      offset: Offset(compactTalkAskBar ? 0 : -10, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: compactTalkAskBar ? 8 : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (compactTalkAskBar)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Center(
                      child: Icon(
                        LucideIcons.message_circle,
                        size: 13,
                        color: feedInlineActionMutedForeground(
                          cs,
                        ),
                      ),
                    ),
                  )
                else
                  Icon(
                    LucideIcons.message_circle,
                    size: 18,
                    color: _feedMetaGray,
                  ),
                if (compactTalkAskBar && post.comments > 0) ...[
                  SizedBox(width: talkAskIconCountGap),
                  Text(
                    formatCompactCount(post.comments),
                    style: GoogleFonts.notoSansKr(
                      color: feedInlineActionMutedForeground(cs),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ] else if (!compactTalkAskBar) ...[
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(post.comments),
                    style: GoogleFonts.notoSansKr(
                      color: _feedMetaGray,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!compactTalkAskBar) ...[
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.eye,
                  size: 18,
                  color: _feedMetaGray,
                ),
                const SizedBox(width: 4),
                Text(
                  formatCompactCount(post.views),
                  style: GoogleFonts.notoSansKr(
                    color: _feedMetaGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return RepaintBoundary(
      child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cardFillColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.16),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              16,
              18,
              compactTalkAskBar ? 9 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: openPostDetail,
                  behavior: HitTestBehavior.deferToChild,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                // 상단: 작성자 (톡·에스크: IntrinsicHeight로 배지·닉 높이 초과 시 오버플로 방지)
                compactTalkAskBar
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: _AuthorAvatar(
                                photoUrl: post.authorPhotoUrl,
                                author: canonicalAuthor,
                                authorUid: post.authorUid,
                                colorIndex: post.authorAvatarColorIndex,
                                size: headerAvatarSize,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  authorNicknameRow,
                                  timeText,
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AuthorAvatar(
                            photoUrl: post.authorPhotoUrl,
                            author: canonicalAuthor,
                            authorUid: post.authorUid,
                            colorIndex: post.authorAvatarColorIndex,
                            size: headerAvatarSize,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                authorNicknameRow,
                                const SizedBox(height: 2),
                                timeText,
                              ],
                            ),
                          ),
                        ],
                      ),
                const SizedBox(height: 10),
                // 제목
                Text(
                  post.title,
                  style: compactTalkAskBar
                      ? talkAskFeedTitleStyle
                      : GoogleFonts.notoSansKr(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.homeBoardTitleForeground(cs),
                          height: 1.45,
                          letterSpacing: -0.3,
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // 사진/동영상이 있으면 제목 다음에 미디어, 그 다음 본문
                // 영상 (피드에서 보이면 자동재생, 뮤트)
                if (post.hasVideo &&
                    post.videoUrl != null &&
                    post.videoUrl!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FeedVideoPlayer(
                      videoUrl: post.videoUrl!,
                      thumbnailUrl: post.videoThumbnailUrl,
                      isGif: post.isGif ?? false,
                    ),
                  ),
                ]
                // 이미지
                else if (post.hasImage && post.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FeedImageCarousel(
                    imageUrls: post.imageUrls,
                    imageDimensions: post.imageDimensions,
                  ),
                ] else if (post.hasImage) ...[
                  const SizedBox(height: 10),
                  AspectRatio(
                    aspectRatio: 1 / 1.15,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Icon(
                          LucideIcons.image,
                          size: 56,
                          color: cs.onSurfaceVariant.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ],
                // 본문 미리보기 (사진/동영상 다음)
                if ((post.body?.trim() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.body!.trim(),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                SizedBox(height: compactTalkAskBar ? 7 : 12),
                    ],
                  ),
                ),
                // 하단: 하트·투표는 상세로 전파되지 않음 — 댓글·조회수 쪽만 상세 탭
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(compactTalkAskBar ? 0 : -10, 0),
                      child: compactTalkAskBar
                          ? TalkAskHeartVote(
                              voteState: _voteState,
                              count: _displayCount,
                              onTap: _onUpTap,
                            )
                          : _VoteBox(
                              voteState: _voteState,
                              count: _displayCount,
                              onUp: _onUpTap,
                              onDown: _onDownTap,
                              primaryColor: cs.primary,
                              compact: false,
                            ),
                    ),
                    if (compactTalkAskBar) const SizedBox(width: 4),
                    Expanded(
                      child: GestureDetector(
                        onTap: openPostDetail,
                        behavior: HitTestBehavior.translucent,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: trailingMetaForDetailTap,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }
}

/// 작성자 프로필 아바타 (사진 있으면 사진, 없으면 파스텔 배경 + person 아이콘)
class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.photoUrl,
    required this.author,
    this.authorUid,
    this.colorIndex,
    this.size = 22,
  });

  final String? photoUrl;
  final String author;
  final String? authorUid;
  final int? colorIndex;
  final double size;

  int _resolvedIndex() {
    if (colorIndex != null) return colorIndex!;
    // fallback: 닉네임 해시
    final name = author.startsWith('u/') ? author.substring(2) : author;
    return name.codeUnits.fold(0, (prev, c) => prev + c);
  }

  @override
  Widget build(BuildContext context) {
    final uid = authorUid?.trim();
    Widget child;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      child = ClipOval(
        child: OptimizedNetworkImage.avatar(
          imageUrl: photoUrl!,
          size: size,
          errorWidget: _buildDefault(),
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

/// 톡·에스크: 싫어요 UI 없이 하트 + 좋아요 수만 (토글은 [togglePostLike]).
/// Ink 스플래시 없음 — 탭 시 primary 색 번쩍임 방지.
class TalkAskHeartVote extends StatelessWidget {
  const TalkAskHeartVote({
    super.key,
    required this.voteState,
    required this.count,
    required this.onTap,
    this.compact = true,
  });

  final int voteState;
  final int count;
  final VoidCallback onTap;

  /// true: 피드 카드, false: 글 상세 등 여유 있는 레이아웃
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final liked = voteState == 1;
    final icon = liked ? Icons.favorite : Icons.favorite_border;
    final cs = Theme.of(context).colorScheme;
    final actionFg = feedInlineActionMutedForeground(cs);
    final iconColor = liked ? Colors.redAccent : actionFg;
    final textColor = actionFg;
    final iconSize = compact ? 13.0 : 18.0;
    final fontSize = compact ? 10.0 : 13.0;
    final iconBox = compact ? 20.0 : 24.0;
    // 피드(compact): 좌만 0 — 하트·댓글 행과 세로 패딩 통일(대칭)
    /// compact: 리뷰 인라인 액션바([PopularPostsTab._buildReviewInlineActionBar])와
    /// 하트↔댓글 그룹 간격(4)에 맞춤 — 우측 여백 과다하면 간격이 벌어짐.
    final pad = compact
        ? const EdgeInsets.fromLTRB(0, 8, 4, 8)
        : const EdgeInsets.fromLTRB(12, 12, 16, 12);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: pad,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: iconBox,
              height: iconBox,
              child: Center(
                child: Icon(icon, size: iconSize, color: iconColor),
              ),
            ),
            SizedBox(width: talkAskIconCountGap),
            Text(
              formatCompactCount(count),
              style: GoogleFonts.notoSansKr(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 투표박스 위젯 (↑ 숫자 ↓ 가로 배치)
class _VoteBox extends StatelessWidget {
  const _VoteBox({
    required this.voteState,
    required this.count,
    required this.onUp,
    required this.onDown,
    required this.primaryColor,
    this.compact = false,
  });

  final int voteState;
  final int count;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final Color primaryColor;

  /// TALK/ASK 피드: 화살표·숫자만 약간 축소
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFFADADAD);
    // 싫어요 활성 시 파란색으로 구분
    const dislikeActiveColor = Color(0xFF0A84FF);
    final upColor = voteState == 1 ? primaryColor : baseColor;
    final downColor = voteState == -1 ? dislikeActiveColor : baseColor;
    final countColor = voteState == 1
        ? primaryColor
        : voteState == -1
        ? dislikeActiveColor
        : baseColor;
    final iconSize = compact ? 22.0 : 26.0;
    final countFontSize = compact ? 12.0 : 13.0;
    final padV = compact ? 5.0 : 7.0;

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onUp,
            splashColor: primaryColor.withOpacity(0.2),
            highlightColor: primaryColor.withOpacity(0.1),
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, padV, 1, padV),
              child: Icon(
                Icons.arrow_drop_up_rounded,
                size: iconSize,
                color: upColor,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 0, vertical: padV),
            child: Text(
              formatCompactCount(count),
              style: GoogleFonts.notoSansKr(
                fontSize: countFontSize,
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
              padding: EdgeInsets.fromLTRB(1, padV, 8, padV),
              child: Icon(
                Icons.arrow_drop_down_rounded,
                size: iconSize,
                color: downColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 피드용 이미지 캐러셀
class FeedImageCarousel extends StatefulWidget {
  const FeedImageCarousel({
    super.key,
    required this.imageUrls,
    this.imageDimensions, // 호환용, 표시는 항상 1:1 cover
  });

  final List<String> imageUrls;
  final List<List<int>>? imageDimensions;

  @override
  State<FeedImageCarousel> createState() => _FeedImageCarouselState();
}

class _FeedImageCarouselState extends State<FeedImageCarousel> {
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
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();
    if (widget.imageUrls.length == 1) {
      return SizedBox(
        width: double.infinity,
        height: 300, // 고정 높이로 테스트
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            widget.imageUrls.first,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 300,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                return Image.network(
                  widget.imageUrls[index],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});
  final int level;

  static Color _levelColor(int level) {
    if (level >= 30) return const Color(0xFFD4AF37);
    if (level == 1) return const Color(0xFF9E9E9E);
    return Color.lerp(
      const Color(0xFF9E9E9E),
      const Color(0xFF26A69A),
      (level - 1) / 28,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(level);
    final isMax = level >= 30;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color.withOpacity(isMax ? 0.25 : 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: isMax ? 1.5 : 1),
      ),
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -0.5),
          child: Text(
            '$level',
            style: GoogleFonts.notoSansKr(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// 피드 내 영상: 기본은 썸네일+재생 버튼, 탭 시에만 영상 로드해 재생 (OOM 방지)
class FeedVideoPlayer extends StatefulWidget {
  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.isGif = false,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final bool isGif;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  DateTime? _lastSetStateAt;

  @override
  void initState() {
    super.initState();
    HomeTabVisibility.isHomeMainTabSelected.addListener(_onHomeMainTabChanged);
    // preload 호출 제거: 동영상 게시글이 많을 때 카드마다 preload하면 동시 초기화로 앱이 무거워짐. 탭 시에만 로드.
  }

  void _onHomeMainTabChanged() {
    if (HomeTabVisibility.isHomeMainTabSelected.value) return;
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.isPlaying) {
      c.pause();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    HomeTabVisibility.isHomeMainTabSelected.removeListener(
      _onHomeMainTabChanged,
    );
    VideoPreloadCache.instance.cancel(widget.videoUrl);
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_loading) return;
    if (_controller != null && _controller!.value.isInitialized) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      setState(() {});
      return;
    }
    setState(() => _loading = true);
    final cached = VideoPreloadCache.instance.consume(widget.videoUrl);
    if (cached != null && cached.value.isInitialized) {
      _controller = cached;
    } else {
      cached?.dispose();
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      await _controller!.initialize();
    }
    if (!mounted) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    _controller!.setVolume(0);
    _controller!.setLooping(widget.isGif);
    _controller!.addListener(_onPlayerUpdate);
    setState(() => _loading = false);
    _controller!.play();
  }

  void _onPlayerUpdate() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastSetStateAt != null &&
        now.difference(_lastSetStateAt!).inMilliseconds < 400)
      return;
    _lastSetStateAt = now;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final isPlaying = ctrl?.value.isPlaying ?? false;
    // 1:1 정사각 — 원본 비율 유지, 중앙 기준 cover 크롭
    const double aspectRatio = 1;

    return GestureDetector(
      onTap: _onTap,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          color: Colors.black,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ctrl != null && ctrl.value.isInitialized
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: ctrl.value.size.width > 0
                              ? ctrl.value.size.width
                              : 16,
                          height: ctrl.value.size.height > 0
                              ? ctrl.value.size.height
                              : 9,
                          child: VideoPlayer(ctrl),
                        ),
                      )
                    : widget.thumbnailUrl != null &&
                            widget.thumbnailUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.thumbnailUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: (_, __, ___) => Icon(
                              LucideIcons.video,
                              size: 48,
                              color: AppColors.mediumGrey.withOpacity(0.5),
                            ),
                          )
                        : Center(
                            child: Icon(
                              LucideIcons.video,
                              size: 48,
                              color: AppColors.mediumGrey.withOpacity(0.5),
                            ),
                          ),
              ),

              // 로딩 중
              if (_loading)
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

              // 재생 버튼 (로딩 아닐 때, 재생 중이 아닐 때, 배경 없음)
              if (!_loading && !isPlaying)
                const Icon(
                  Icons.play_arrow_rounded,
                  size: 48,
                  color: Colors.white,
                ),

              // 음소거 + 전체화면 (재생 중)
              if (isPlaying)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (ctrl == null) return;
                          final muted = ctrl.value.volume == 0;
                          ctrl.setVolume(muted ? 1 : 0);
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            (ctrl?.value.volume ?? 0) == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          FullScreenVideoPage.show(
                            context,
                            videoUrl: widget.videoUrl,
                            thumbnailUrl: widget.thumbnailUrl,
                            isGif: widget.isGif,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.fullscreen_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
