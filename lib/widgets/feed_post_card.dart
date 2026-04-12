import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/post_service.dart';
import '../services/saved_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../utils/post_board_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/share_sheet.dart';
import '../screens/login_page.dart';
import '../screens/post_detail_page.dart';
import '../screens/write_post_page.dart';
import '../screens/message_thread_screen.dart';
import '../screens/user_posts_screen.dart';
import '../screens/user_comments_screen.dart';
import '../screens/full_screen_video_page.dart';
import '../services/message_service.dart';
import '../services/home_tab_visibility.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 피드 하단 메타(댓글·조회수) 색 - 투표박스 0일 때와 동일
const _feedMetaGray = Color(0xFFADADAD);

/// 피드 영상 캐시: 탭 시 consume으로 재사용. preload는 피드에서 호출하지 않음(동영상 글 많을 때 무거워짐 방지).
class VideoPreloadCache {
  VideoPreloadCache._();
  static final VideoPreloadCache instance = VideoPreloadCache._();

  static const int _maxSize = 1;
  // url → controller (초기화 완료된 것만 저장)
  final LinkedHashMap<String, VideoPlayerController> _cache = LinkedHashMap();
  // 현재 초기화 진행 중인 url
  final Set<String> _loading = {};

  Future<void> preload(String url) async {
    if (_cache.containsKey(url) || _loading.contains(url)) return;
    _loading.add(url);

    // 한도 초과 시 가장 오래된 항목 제거
    while (_cache.length >= _maxSize) {
      final oldest = _cache.keys.first;
      _cache[oldest]?.dispose();
      _cache.remove(oldest);
    }

    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctrl.initialize();
      if (_loading.contains(url)) {
        _cache[url] = ctrl;
      } else {
        // cancel() 이 호출되어 더 이상 필요 없음
        ctrl.dispose();
      }
    } catch (_) {
      // 무시
    } finally {
      _loading.remove(url);
    }
  }

  /// 캐시에서 컨트롤러를 꺼냄 (사용 후 캐시에서 제거)
  VideoPlayerController? consume(String url) => _cache.remove(url);

  /// 더 이상 필요 없을 때 취소/해제
  void cancel(String url) {
    _loading.remove(url);
    _cache.remove(url)?.dispose();
  }
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
  });

  final Post post;
  final String? currentUserAuthor;
  final void Function(Post)? onPostUpdated;
  final void Function(Post)? onPostDeleted;
  final String? tabName;
  final VoidCallback? onTap;
  /// 차단 시 피드 갱신용
  final VoidCallback? onUserBlocked;

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
  int _voteState = 0;
  late int _displayCount;
  bool _votePending = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _displayCount = widget.post.votes;
    _syncVoteStateFromPost();
    _isSaved = SavedService.instance.isSaved(widget.post.id);
  }

  @override
  void didUpdateWidget(covariant FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id == widget.post.id &&
        (oldWidget.post.likedBy != widget.post.likedBy ||
            oldWidget.post.dislikedBy != widget.post.dislikedBy ||
            oldWidget.post.votes != widget.post.votes)) {
      _displayCount = widget.post.votes;
      _syncVoteStateFromPost();
    }
  }

  void _syncVoteStateFromPost() {
    final uid = AuthService.instance.currentUser.value?.uid;
    final liked = uid != null && widget.post.likedBy.contains(uid);
    final disliked = uid != null && widget.post.dislikedBy.contains(uid);
    final newState = liked ? 1 : disliked ? -1 : 0;
    if (_voteState != newState) setState(() => _voteState = newState);
  }

  Future<void> _onUpTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    if (_votePending) return;
    HapticFeedback.lightImpact();
    final prevState = _voteState;
    final prevCount = _displayCount;
    final nowLiked = _voteState != 1;
    setState(() {
      _votePending = true;
      if (nowLiked) {
        _displayCount += (prevState == -1 ? 2 : 1);
        _voteState = 1;
      } else {
        _voteState = 0;
        _displayCount -= 1;
      }
    });
    PostService.instance.togglePostLike(
      widget.post.id,
      currentVoteState: _voteState,
      postAuthorUid: widget.post.authorUid,
      postTitle: widget.post.title,
    ).then((result) {
      if (!mounted) return;
      if (result == null) setState(() { _voteState = prevState; _displayCount = prevCount; });
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _onDownTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
      if (result == null) setState(() { _voteState = prevState; _displayCount = prevCount; });
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _showAuthorMenu(BuildContext context, String author, TapDownDetails details) async {
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.mail, size: 16, color: Colors.blue),
            const SizedBox(width: 6),
            Text(s.get('sendMessageToUser'), style: GoogleFonts.notoSansKr(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'posts',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.file_text, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Text(s.get('viewUserPosts'), style: GoogleFonts.notoSansKr(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'comments',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.message_circle, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Text(s.get('viewUserComments'), style: GoogleFonts.notoSansKr(fontSize: 13)),
          ]),
        ),
      ],
    );
    if (!mounted || result == null) return;
    if (result == 'message') {
      final conv = await MessageService.instance.startConversation(author, displayName);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => MessageThreadScreen(conversationId: conv.id, otherUserName: displayName),
        ));
      }
    } else if (result == 'posts') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => UserPostsScreen(authorName: author),
      ));
    } else if (result == 'comments') {
      final baseName = author.startsWith('u/') ? author.substring(2) : author;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => UserCommentsScreen(authorName: baseName),
      ));
    }
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    final post = widget.post;
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    final isMyPost = widget.currentUserAuthor != null && post.author == widget.currentUserAuthor;

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
                leading: Icon(LucideIcons.pencil, color: Theme.of(context).colorScheme.onSurface),
                title: Text(s.get('edit'), style: GoogleFonts.notoSansKr(fontSize: 15)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(LucideIcons.trash_2, color: cs.error),
                title: Text(s.get('delete'), style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.error)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ] else ...[
              ListTile(
                leading: Icon(LucideIcons.flag, color: cs.error),
                title: Text(s.get('report'), style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.error)),
                onTap: () => Navigator.pop(context, 'report'),
              ),
              ListTile(
                leading: Icon(LucideIcons.ban, color: cs.onSurface),
                title: Text(s.get('block'), style: GoogleFonts.notoSansKr(fontSize: 15)),
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.get('delete'), style: GoogleFonts.notoSansKr()),
          content: Text(s.get('deletePostConfirm'), style: GoogleFonts.notoSansKr()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await PostService.instance.deletePost(post.id);
        if (mounted) widget.onPostDeleted?.call(post);
      }
    } else if (selected == 'report') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.get('reportPostTitle'), style: GoogleFonts.notoSansKr()),
          content: Text(s.get('reportPostMessage'), style: GoogleFonts.notoSansKr()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.get('report'), style: GoogleFonts.notoSansKr(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('reportSubmitted'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
        );
      }
    } else if (selected == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.get('blockPostTitle'), style: GoogleFonts.notoSansKr()),
          content: Text(s.get('blockPostMessage'), style: GoogleFonts.notoSansKr()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(s.get('block'), style: GoogleFonts.notoSansKr())),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await BlockService.instance.blockPost(post.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.get('blockPostDone'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
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

    return RepaintBoundary(
      child: GestureDetector(
      onTap: widget.onTap ?? () async {
        final updated = await Navigator.push<Post>(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailPage(
              post: post,
              onPostDeleted: widget.onPostDeleted,
              tabName: widget.tabName,
            ),
          ),
        );
        if (updated != null) widget.onPostUpdated?.call(updated);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? cs.surface,
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
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 작성자 + ···
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 아바타 + 닉네임 (닉네임 탭 시 메뉴)
                  Expanded(
                    child: Row(
                      children: [
                        _AuthorAvatar(
                          photoUrl: post.authorPhotoUrl,
                          author: post.author,
                          colorIndex: post.authorAvatarColorIndex,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTapDown: (details) => _showAuthorMenu(context, post.author, details),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        post.author.startsWith('u/') ? post.author.substring(2) : post.author,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          color: cs.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (widget.currentUserAuthor != null && post.author == widget.currentUserAuthor) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.secondary,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          CountryScope.of(context).strings.get('myPostBadge'),
                                          style: GoogleFonts.notoSansKr(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSecondary),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                post.timeAgo,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 11,
                                  color: AppColors.mediumGrey.withOpacity(0.7),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 저장 버튼 (로컬 _isSaved만 사용, 탭 시에만 갱신)
                  GestureDetector(
                    onTap: () {
                      SavedService.instance.toggle(SavedItem(
                        id: post.id,
                        title: post.title,
                        views: formatCompactCount(post.views),
                        type: SavedItemType.post,
                        post: post,
                      ));
                      setState(() => _isSaved = SavedService.instance.isSaved(post.id));
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Icon(
                        _isSaved ? Icons.bookmark : Icons.bookmark_border,
                        size: 20,
                        color: _isSaved ? cs.primary : AppColors.mediumGrey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 제목
              Text(
                post.title,
                style: GoogleFonts.notoSansKr(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  height: 1.45,
                  letterSpacing: -0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // 사진/동영상이 있으면 제목 다음에 미디어, 그 다음 본문
              // 영상 (피드에서 보이면 자동재생, 뮤트)
              if (post.hasVideo && post.videoUrl != null && post.videoUrl!.isNotEmpty) ...[
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
                      child: Icon(LucideIcons.image, size: 56, color: cs.onSurfaceVariant.withOpacity(0.5)),
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
              const SizedBox(height: 12),
              // 하단 액션바
              Padding(
                padding: const EdgeInsets.only(left: 0),
                child: Row(
                  children: [
                    // 투표박스
                    Transform.translate(
                      offset: const Offset(-10, 0),
                      child: _VoteBox(
                        voteState: _voteState,
                        count: _displayCount,
                        onUp: _onUpTap,
                        onDown: _onDownTap,
                        primaryColor: cs.primary,
                      ),
                    ),
                    // 댓글 + 조회수 (투표박스 0일 때와 같은 색)
                    Transform.translate(
                      offset: const Offset(-10, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.message_circle, size: 18, color: _feedMetaGray),
                              const SizedBox(width: 4),
                              Text(
                                formatCompactCount(post.comments),
                                style: GoogleFonts.notoSansKr(color: _feedMetaGray, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.eye, size: 18, color: _feedMetaGray),
                              const SizedBox(width: 4),
                              Text(
                                formatCompactCount(post.views),
                                style: GoogleFonts.notoSansKr(color: _feedMetaGray, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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

/// 작성자 프로필 아바타 (사진 있으면 사진, 없으면 파스텔 배경 + person 아이콘)
class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.photoUrl,
    required this.author,
    this.colorIndex,
    this.size = 22,
  });

  final String? photoUrl;
  final String author;
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
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: OptimizedNetworkImage.avatar(
          imageUrl: photoUrl!,
          size: size,
          errorWidget: _buildDefault(),
        ),
      );
    }
    return _buildDefault();
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

/// 투표박스 위젯 (↑ 숫자 ↓ 가로 배치)
class _VoteBox extends StatelessWidget {
  const _VoteBox({
    required this.voteState,
    required this.count,
    required this.onUp,
    required this.onDown,
    required this.primaryColor,
  });

  final int voteState;
  final int count;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final Color primaryColor;

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
                padding: const EdgeInsets.fromLTRB(0, 7, 1, 7),
                child: Icon(Icons.arrow_drop_up_rounded, size: 26, color: upColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
              child: Text(
                formatCompactCount(count),
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
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
                padding: const EdgeInsets.fromLTRB(1, 7, 8, 7),
                child: Icon(Icons.arrow_drop_down_rounded, size: 26, color: downColor),
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
    this.imageDimensions,
  });

  final List<String> imageUrls;
  final List<List<int>>? imageDimensions;

  static const double _defaultRatio = 1 / 1.15;
  /// 세로 최대 1:1.4 캡 (피드 동영상과 동일)
  static const double _minAspectRatio = 1 / _feedMaxHeightPerWidth;

  double _aspectRatioFor(int index) {
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
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: widget._aspectRatioFor(0),
          child: OptimizedNetworkImage(
            imageUrl: widget.imageUrls.first,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(16),
            errorWidget: Builder(
              builder: (context) {
                final cs2 = Theme.of(context).colorScheme;
                return Container(
                  color: cs2.surfaceContainerHighest,
                  child: Center(
                    child: Icon(LucideIcons.image_off, size: 56, color: cs2.onSurfaceVariant.withOpacity(0.5)),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: widget._aspectRatioFor(_currentPage),
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
                  borderRadius: BorderRadius.circular(16),
                  errorWidget: Container(
                    color: AppColors.lightGrey,
                    child: Center(
                      child: Icon(LucideIcons.image_off, size: 56, color: AppColors.mediumGrey.withOpacity(0.5)),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${_currentPage + 1}/${widget.imageUrls.length}',
                  style: GoogleFonts.notoSansKr(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.imageUrls.length, (i) {
                      final isActive = _currentPage == i;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 8 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
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
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});
  final int level;

  static Color _levelColor(int level) {
    if (level >= 30) return const Color(0xFFD4AF37);
    if (level == 1) return const Color(0xFF9E9E9E);
    return Color.lerp(const Color(0xFF9E9E9E), const Color(0xFF26A69A), (level - 1) / 28)!;
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
          child: Text('$level', style: GoogleFonts.notoSansKr(fontSize: 8, fontWeight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }
}

/// 가로 1 기준 세로 최대 1.4. 피드에서도 숏폼과 동일하게 적용.
const double _feedMaxHeightPerWidth = 1.4;

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
    HomeTabVisibility.isHomeMainTabSelected.removeListener(_onHomeMainTabChanged);
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
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
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
    if (_lastSetStateAt != null && now.difference(_lastSetStateAt!).inMilliseconds < 400) return;
    _lastSetStateAt = now;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final isPlaying = ctrl?.value.isPlaying ?? false;
    // 1:1 프레임에 세로가 꽉 차도록 (fitHeight)
    const double aspectRatio = 1;

    return GestureDetector(
      onTap: _onTap,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              // 썸네일 or 영상: 1:1 비율에 맞게 세로 꽉 차도록
              if (ctrl != null && ctrl.value.isInitialized)
                FittedBox(
                  fit: BoxFit.fitHeight,
                  child: SizedBox(
                    width: ctrl.value.size.width > 0 ? ctrl.value.size.width : 16,
                    height: ctrl.value.size.height > 0 ? ctrl.value.size.height : 9,
                    child: VideoPlayer(ctrl),
                  ),
                )
              else if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: widget.thumbnailUrl!,
                  fit: BoxFit.fitHeight,
                  width: double.infinity,
                  height: double.infinity,
                  errorWidget: (_, __, ___) =>
                      Icon(LucideIcons.video, size: 48, color: AppColors.mediumGrey.withOpacity(0.5)),
                )
              else
                Icon(LucideIcons.video, size: 48, color: AppColors.mediumGrey.withOpacity(0.5)),

              // 로딩 중
              if (_loading)
                const Center(child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                )),

              // 재생 버튼 (로딩 아닐 때, 재생 중이 아닐 때, 배경 없음)
              if (!_loading && !isPlaying)
                const Icon(Icons.play_arrow_rounded, size: 48, color: Colors.white),

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
