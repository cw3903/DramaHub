import 'dart:async';
import 'dart:io';
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
import '../widgets/share_sheet.dart';
import '../services/saved_service.dart';
import '../models/post.dart';
import '../models/drama.dart';
import '../services/drama_list_service.dart';
import 'drama_detail_page.dart';
import 'login_page.dart';
import 'message_thread_screen.dart';
import 'user_posts_screen.dart';
import 'user_comments_screen.dart';
import 'full_screen_image_page.dart';
import 'full_screen_video_page.dart';
import 'write_post_page.dart';
import '../widgets/feed_post_card.dart';
import 'community_search_page.dart';
import 'notification_screen.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/blind_refresh_indicator.dart';
import '../widgets/community_board_tabs.dart';
import 'question_board_tab.dart';
import 'package:video_player/video_player.dart';
import '../widgets/feed_post_card.dart' show VideoPreloadCache;

// 글 상세 하단: 구분선/여백을 상수로 두어 글이 몇 개든 동일하게 보이도록 함
const double _kBrowserNavBarHeight = 48; // 하단 네비 바 높이 (BrowserNavBar와 동일)
const double _kMorePostsDividerHeight = 40; // 댓글 영역 ~ 인기/자유/질문 탭 사이 얇은 구분선

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
  });

  final Post post;
  final void Function(Post)? onPostDeleted;
  final String? tabName;
  final List<(Post, int)> initialBackStack;
  final List<(Post, int)> initialForwardStack;
  final int? initialTabIndex;
  /// 홈탭 게시판 목록(인기글/자유/질문). 넘기면 글 상세 하단 DramaFeed에 그대로 표시
  final List<Post>? initialBoardPosts;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _commentsKey = GlobalKey();
  final GlobalKey _inputCardKey = GlobalKey();
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
  final ValueNotifier<String?> _commentImagePathNotifier = ValueNotifier<String?>(null);
  int _commentPage = 0;
  static const int _commentsPerPage = 20;
  /// 글별로 마지막으로 보던 댓글 페이지 (다시 들어왔을 때 복원)
  static final Map<String, int> _savedCommentPageByPostId = {};
  final ValueNotifier<bool> _commentSortByTop = ValueNotifier(false); // true: 추천순, false: 시간순
  bool _showFab = false;
  late int _morePostsTabIndex;
  Timer? _keyboardDebounceTimer;
  bool _isRefreshing = false;
  /// Letterboxd 리뷰 상세: 스포일러 본문 공개 여부 (글 바뀌면 초기화)
  bool _reviewSpoilerRevealed = false;
  String? _letterboxdSpoilerBoundPostId;
  // 브라우저 히스토리 스택 (Post, tabIndex)
  late final List<(Post, int)> _backStack;
  late final List<(Post, int)> _forwardStack;

  Post get _post => _currentPost ?? widget.post;
  bool get _isMine => _currentUserAuthor != null && _post.author == _currentUserAuthor;
  /// 운영자는 타인 글도 삭제 가능(UID는 [kAppModeratorAuthUids]).
  bool get _canDeletePost => _isMine || isAppModerator();

  Future<void> _showPostAuthorMenu(BuildContext context, String author, TapDownDetails details) async {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backStack = List.of(widget.initialBackStack);
    _forwardStack = List.of(widget.initialForwardStack);
    _morePostsTabIndex = (widget.initialTabIndex ?? 0).clamp(0, 2);
    _scrollController.addListener(_updateFabVisibility);
    _currentPost = widget.post;
    final n = widget.post.commentsList.length;
    if (n > 0) {
      final totalPages = (n / _commentsPerPage).ceil().clamp(1, 9999);
      if (totalPages > 1) {
        _commentPage = totalPages - 1;
      }
    }
    _loadCurrentUserAuthor();
    final uid = AuthService.instance.currentUser.value?.uid;
    _isLiked = uid != null && widget.post.likedBy.contains(uid);
    _isDisliked = uid != null && widget.post.dislikedBy.contains(uid);
    _loadLatestPost();
    _incrementViews();
    _commentController.addListener(() {
      final lines = '\n'.allMatches(_commentController.text).length + 2;
      final clamped = lines.clamp(2, 6);
      if (clamped != _commentLines) setState(() => _commentLines = clamped);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initialTabIndex == null) {
      final s = CountryScope.of(context).strings;
      var idx = 0;
      if (widget.tabName == s.get('tabReviews')) {
        idx = 0;
      } else if (widget.tabName == s.get('tabHot')) {
        idx = 1;
      } else if (widget.tabName == s.get('freeBoard') || widget.tabName == s.get('tabGeneral')) {
        idx = 1;
      } else if (widget.tabName == s.get('tabQnA')) {
        idx = 2;
      }
      final clamped = idx.clamp(0, 2);
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
      final n = latest.commentsList.length;
      final totalPages = (n / _commentsPerPage).ceil().clamp(1, 9999);
      if (totalPages > 1) {
        _commentPage = totalPages - 1;
      }
      setState(() {
        _currentPost = latest;
        _isLiked = uid != null && latest.likedBy.contains(uid);
        _isDisliked = uid != null && latest.dislikedBy.contains(uid);
        _isRefreshing = false;
      });
    } else if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  int get _likeCount => _post.votes;

  Future<void> _submitComment() async {
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
      imageUrl = await PostService.instance.uploadCommentImage(_commentImagePath!);
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!mounted) { _isSubmittingComment = false; return; }
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
    await UserProfileService.instance.loadIfNeeded();
    final nickname = UserProfileService.instance.nicknameNotifier.value;
    final displayName = AuthService.instance.currentUser.value?.displayName;
    final email = AuthService.instance.currentUser.value?.email;
    String author = nickname?.trim().isNotEmpty == true
        ? nickname!.trim()
        : (displayName?.trim().isNotEmpty == true ? displayName!.trim() : (email != null ? email.split('@').first : ''));
    if (author.isEmpty) author = '익명';
    final s = CountryScope.of(context).strings;
    final newComment = PostComment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: author,
      timeAgo: s.get('timeAgoJustNow'),
      text: text.isEmpty ? ' ' : text,
      votes: 0,
      replies: const [],
      authorPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
      authorAvatarColorIndex: UserProfileService.instance.avatarColorNotifier.value,
      imageUrl: imageUrl,
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
      final parent = parentId != null ? PostService.findCommentById(_post.commentsList, parentId!) : null;
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
            final total = newList.length;
            final totalPages = (total / _commentsPerPage).ceil().clamp(1, 9999);
            _commentPage = (totalPages - 1).clamp(0, 9999);
            _scrollToCommentId = newComment.id;
          }
        });
      }
      // 서버에서 글 다시 불러와 동기화 (실패해도 이미 화면에는 반영됨)
      final locale = CountryScope.maybeOf(context)?.country;
      final updated = await PostService.instance.getPost(widget.post.id, locale);
      if (mounted && updated != null) {
        setState(() {
          _currentPost = updated;
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
          if (ctx != null && _scrollToCommentId != null && _scrollController.hasClients) {
            final box = ctx.findRenderObject() as RenderBox?;
            final scrollableContext = _scrollController.position.context.storageContext;
            final viewportBox = scrollableContext.findRenderObject() as RenderBox?;
            if (box != null && viewportBox != null) {
              final commentTop = box.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
              final targetOffset = (_scrollController.offset + commentTop).clamp(0.0, _scrollController.position.maxScrollExtent);
              _scrollController.animateTo(targetOffset, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
            }
            setState(() => _scrollToCommentId = null);
          } else {
            final commentsCtx = _commentsKey.currentContext;
            if (commentsCtx != null) {
              Scrollable.ensureVisible(commentsCtx, alignment: 0.0, duration: const Duration(milliseconds: 300));
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
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
        dislikedBy: nowLiked ? _post.dislikedBy.where((u) => u != uid).toList() : _post.dislikedBy,
        likeCount: nextLikeCount,
        dislikeCount: nextDislikeCount,
      );
    });
    PostService.instance.togglePostLike(
      widget.post.id,
      postAuthorUid: _post.authorUid,
      postTitle: _post.title,
    ).then((result) {
      if (!mounted) return;
      if (result == null) {
        setState(() { _isLiked = prevLiked; _isDisliked = prevDisliked; _currentPost = prevPost; });
      }
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _onDislikeTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
    final newLikedBy = nowDisliked ? _post.likedBy.where((u) => u != uid).toList() : _post.likedBy;
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
        setState(() { _isLiked = prevLiked; _isDisliked = prevDisliked; _currentPost = prevPost; });
      }
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _onCommentTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
            content: Text('이미지 선택 실패: ${e.toString()}', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onGifTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    await _pickImageFromSource(ImageSource.gallery);
  }

  static const _pickFromFilesSentinel = _PostDetailPickFromFiles();

  Future<void> _onPhotoTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
            content: Text('이미지 선택 실패: ${e.toString()}', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _savedCommentPageByPostId[widget.post.id] = _commentPage;
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_updateFabVisibility);
    _scrollController.dispose();
    _keyboardDebounceTimer?.cancel();
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
    _keyboardDebounceTimer = Timer(const Duration(milliseconds: 150), _scrollToShowInputCard);
  }

  void _scrollToShowInputCard() {
    if (!mounted || !_scrollController.hasClients) return;
    final ctx = _inputCardKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    // 카드 하단의 현재 화면 상의 y좌표
    final cardBottomGlobal = box.localToGlobal(Offset(0, box.size.height)).dy;
    // 키보드를 제외한 실제 뷰포트 하단 y좌표
    final viewportBottom = MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom;
    final overflow = cardBottomGlobal - viewportBottom + 16; // 16px 여백
    if (overflow > 0) {
      _scrollController.animateTo(
        (_scrollController.offset + overflow).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
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

  // 글 상세 내에서 다른 글로 이동 (히스토리 push)
  void _navigateToPost(Post post, {int tabIndex = 0}) {
    setState(() {
      _backStack.add((_post, _morePostsTabIndex));
      _forwardStack.clear();
      _currentPost = post;
      _morePostsTabIndex = tabIndex.clamp(0, 2);
      _commentPage = 0;
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
      _morePostsTabIndex = tabIndex.clamp(0, 2);
      _commentPage = 0;
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
      _morePostsTabIndex = tabIndex.clamp(0, 2);
      _commentPage = 0;
      _commentLines = 2;
      _commentController.clear();
      _replyingToCommentId = null;
      final uid = AuthService.instance.currentUser.value?.uid;
      _isLiked = uid != null && _post.likedBy.contains(uid);
      _isDisliked = uid != null && _post.dislikedBy.contains(uid);
    });
    _scrollController.jumpTo(0);
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
          content: Text(s.get('postSubmitted'), style: GoogleFonts.notoSansKr()),
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

  Future<void> _showAuthorMenu(BuildContext context, TapDownDetails details, String authorName) async {
    final nickname = authorName.startsWith('u/') ? authorName.substring(2) : authorName;
    if (nickname.isEmpty) return;
    final s = CountryScope.of(context).strings;
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
              Text(s.get('sendMessageToUser'), style: GoogleFonts.notoSansKr(fontSize: 13)),
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
              Text(s.get('viewUserPosts'), style: GoogleFonts.notoSansKr(fontSize: 13)),
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
              Text(s.get('viewUserComments'), style: GoogleFonts.notoSansKr(fontSize: 13)),
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
            builder: (_) => UserCommentsScreen(authorName: nickname),
          ),
        );
        break;
    }
  }

  /// TextField를 dispose 없이 유지하여 키보드 유지. hasFocus에 따라 주변 레이아웃만 변경.
  Widget _buildInputLayout(ColorScheme cs, dynamic s) {
    return ListenableBuilder(
      listenable: _commentFocusNode,
      builder: (context, _) {
        final hasFocus = _commentFocusNode.hasFocus;
        final replyingTo = _replyingToCommentId != null
            ? PostService.findCommentById(_post.commentsList, _replyingToCommentId!)
            : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 답글 대상 댓글 배너
            if (replyingTo != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.6),
                  border: Border(
                    top: BorderSide(color: cs.outline.withOpacity(0.15)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.reply, size: 14, color: cs.primary),
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
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
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
                      child: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant),
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
          return InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outline.withOpacity(0.12)),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                s.get('joinConversation'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        final replyingTo = _replyingToCommentId != null
            ? PostService.findCommentById(_post.commentsList, _replyingToCommentId!)
            : null;
        return TextField(
          controller: _commentController,
          focusNode: _commentFocusNode,
          decoration: InputDecoration(
            isDense: true,
            hintText: replyingTo != null
                ? '${replyingTo.author}님에게 답글...'
                : s.get('joinConversation'),
            hintStyle: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withOpacity(0.9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: cs.outline.withOpacity(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: cs.outline.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.5), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          ),
          style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurface),
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
                child: Text('GIF', style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurfaceVariant)),
              ),
              IconButton(
                icon: Icon(LucideIcons.image_plus, size: 24, color: cs.onSurfaceVariant),
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
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
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
                            icon: const Icon(LucideIcons.arrow_up, size: 24, color: Colors.white),
                          ),
                        )
                      : Row(
                          key: const ValueKey<bool>(false),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _onGifTap,
                              child: Text('GIF', style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurfaceVariant)),
                            ),
                            IconButton(
                              icon: Icon(LucideIcons.image_plus, size: 24, color: cs.onSurfaceVariant),
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

  Widget _buildReviewStarRowLetterboxd(double? rating, {double totalWidth = 168}) {
    final r = (rating ?? 0).clamp(0.0, 5.0);
    final units = (r * 2).round().clamp(0, 10);
    final fullCount = units ~/ 2;
    final hasHalf = units.isOdd;
    const starOrange = Color(0xFFFFB020);
    final slotW = totalWidth / 5;
    final iconSize = (slotW * 0.82).clamp(15.0, 24.0);
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
          return SizedBox(
            width: slotW,
            child: Center(child: Icon(icon, size: iconSize, color: starOrange)),
          );
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
          : DramaListService.instance.getDisplayTitleByTitle(post.title, locale);
      final thumb = post.dramaThumbnail?.trim();
      final hasImg = thumb != null && (thumb.startsWith('http') || thumb.startsWith('assets/'));
      item = DramaItem(
        id: dramaId.isNotEmpty ? dramaId : 'review_${post.id}',
        title: title,
        subtitle: '',
        views: '0',
        rating: post.rating ?? 0,
        imageUrl: hasImg ? thumb : null,
      );
    }
    final detail = DramaListService.instance.buildDetailForItem(item, locale);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(builder: (_) => DramaDetailPage(detail: detail)),
    );
  }

  Future<void> _onLetterboxdPostMenuSelected(String? value, Post post, ColorScheme cs, dynamic s) async {
    if (!mounted || value == null) return;
    if (value == 'edit') {
      final updated = await Navigator.push<Post>(context, MaterialPageRoute(builder: (_) => WritePostPage(initialPost: post)));
      if (updated != null && mounted) setState(() => _currentPost = updated);
    } else if (value == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.get('delete'), style: GoogleFonts.notoSansKr()),
          content: Text(s.get('deletePostConfirm'), style: GoogleFonts.notoSansKr()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: cs.error))),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await PostService.instance.deletePost(post.id);
        if (mounted) {
          widget.onPostDeleted?.call(post);
          Navigator.pop(context);
        }
      }
    } else if (value == 'report') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.get('reportPostTitle'), style: GoogleFonts.notoSansKr()),
          content: Text(s.get('reportPostMessage'), style: GoogleFonts.notoSansKr()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.get('reportSubmitted'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
                );
              },
              child: Text(s.get('report'), style: GoogleFonts.notoSansKr(color: cs.error)),
            ),
          ],
        ),
      );
    } else if (value == 'block') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.get('blockPostTitle'), style: GoogleFonts.notoSansKr()),
          content: Text(s.get('blockPostMessage'), style: GoogleFonts.notoSansKr()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.get('block'), style: GoogleFonts.notoSansKr())),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await BlockService.instance.blockPost(post.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.get('blockPostDone'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
          );
          Navigator.pop(context);
        }
      }
    }
  }

  Widget _buildGifPhotoReplyRow(ColorScheme cs, dynamic s) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.isLoggedIn,
      builder: (context, loggedIn, _) {
        if (!loggedIn) return const SizedBox.shrink();
        return Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _onGifTap,
              child: Text('GIF', style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.all(4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(LucideIcons.image_plus, size: 20, color: cs.onSurfaceVariant),
              onPressed: _onPhotoTap,
            ),
            const Spacer(),
            ValueListenableBuilder<String?>(
              valueListenable: _commentImagePathNotifier,
              builder: (context, imagePath, _) {
                return ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _commentController,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    final hasContent = hasText || imagePath != null;
                    return Material(
                      color: hasContent ? cs.primary : Colors.grey.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: hasContent ? _submitComment : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text(
                            s.get('replySubmit'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: hasContent ? Colors.white : Colors.white70,
                            ),
                          ),
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

  Widget _buildReviewSmallPoster(Post post, ColorScheme cs, double w, double h) {
    final t = post.dramaThumbnail?.trim();
    final ok = t != null && t.startsWith('http');
    if (ok) {
      return OptimizedNetworkImage(
        imageUrl: t!,
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

  Widget _buildLetterboxdReviewSection(BuildContext context, ThemeData theme, ColorScheme cs, Post post) {
    final s = CountryScope.of(context).strings;
    final heroThumb = post.dramaThumbnail?.trim();
    final hasHttpHero = heroThumb != null && heroThumb.startsWith('http');
    final dramaTitle = post.dramaTitle?.trim().isNotEmpty == true ? post.dramaTitle! : post.title;
    final bodyRaw = post.body ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasHttpHero)
                OptimizedNetworkImage.thumbnail(
                  imageUrl: heroThumb!,
                  height: 220,
                  width: MediaQuery.sizeOf(context).width,
                )
              else
                const ColoredBox(color: _kLetterboxdHeroOrange),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0.38), Colors.transparent],
                      stops: const [0, 0.42],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.arrow_left, color: Colors.white, size: 26),
                        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: () => Navigator.pop(context, _buildResult(updatedPost: _post)),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.share_2, color: Colors.white, size: 22),
                        onPressed: () => ShareSheet.show(context, title: post.title, type: 'post'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PostAuthorAvatar(
                      photoUrl: post.authorPhotoUrl,
                      author: post.author,
                      colorIndex: post.authorAvatarColorIndex,
                      size: 40,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTapDown: (d) => _showPostAuthorMenu(context, post.author, d),
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          post.author.startsWith('u/') ? post.author.substring(2) : post.author,
                          style: GoogleFonts.notoSansKr(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openDramaDetailFromReview(post),
                      borderRadius: BorderRadius.circular(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildReviewSmallPoster(post, cs, 60, 85),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(LucideIcons.ellipsis, size: 20, color: cs.onSurfaceVariant),
                    onSelected: (v) => _onLetterboxdPostMenuSelected(v, post, cs, s),
                    itemBuilder: (ctx) => [
                      if (_isMine) ...[
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
                            const SizedBox(width: 8),
                            Text(s.get('edit'), style: GoogleFonts.notoSansKr()),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline, size: 18, color: cs.error),
                            const SizedBox(width: 8),
                            Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: cs.error)),
                          ]),
                        ),
                      ] else if (isAppModerator()) ...[
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline, size: 18, color: cs.error),
                            const SizedBox(width: 8),
                            Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: cs.error)),
                          ]),
                        ),
                      ] else ...[
                        PopupMenuItem(
                          value: 'report',
                          child: Row(children: [
                            Icon(LucideIcons.flag, size: 18, color: cs.error),
                            const SizedBox(width: 8),
                            Text(s.get('report'), style: GoogleFonts.notoSansKr(color: cs.error)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'block',
                          child: Row(children: [
                            Icon(LucideIcons.ban, size: 18, color: cs.onSurface),
                            const SizedBox(width: 8),
                            Text(s.get('block'), style: GoogleFonts.notoSansKr()),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _openDramaDetailFromReview(post),
                child: Text(
                  dramaTitle,
                  style: GoogleFonts.notoSansKr(fontSize: 19, fontWeight: FontWeight.w800, color: cs.onSurface, height: 1.25),
                ),
              ),
              const SizedBox(height: 8),
              _buildReviewStarRowLetterboxd(post.rating),
              const SizedBox(height: 6),
              Text(post.timeAgo, style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        if (post.hasSpoiler && !_reviewSpoilerRevealed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: InkWell(
              onTap: () => setState(() => _reviewSpoilerRevealed = true),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outline.withOpacity(0.22)),
                ),
                child: Text(
                  s.get('reviewSpoilerTapToRevealLetterboxd'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    height: 1.45,
                    color: cs.onSurfaceVariant,
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
                if (_isMine) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    style: GoogleFonts.notoSansKr(fontSize: 16, color: cs.onSurface, height: 1.65),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: InkWell(
            onTap: _onLikeTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 26,
                    color: _isLiked ? Colors.redAccent : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    s.get('reviewLikeLabel'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${post.likeCount}',
                    style: GoogleFonts.notoSansKr(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _openDramaDetailFromReview(post),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                side: BorderSide(color: cs.outline.withOpacity(0.35)),
              ),
              child: Text(
                s.get('reviewFilmButton'),
                style: GoogleFonts.notoSansKr(fontSize: 15, fontWeight: FontWeight.w700, color: cs.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isTypedReview = postDisplayType(post) == 'review';
    final boardKind = postDisplayType(post);
    final hideViewsInTalkAskDetail = boardKind == 'talk' || boardKind == 'ask';
    final deleteLabelColor =
        (boardKind == 'talk' || boardKind == 'ask') ? Colors.redAccent : cs.error;
    _letterboxdEnsureSpoilerStateForPost(post.id);
    return PopScope(
      canPop: _backStack.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _backStack.isNotEmpty) {
          _goBack();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        body: ValueListenableBuilder<bool>(
          valueListenable: HomeTabVisibility.isHomeMainTabSelected,
          builder: (context, isHomeMainTab, _) {
          final hideBottomBrowserBar = isHomeMainTab;
          final bottomScrollPad = hideBottomBrowserBar
              ? (MediaQuery.paddingOf(context).bottom + 16)
              : (_kBrowserNavBarHeight + MediaQuery.paddingOf(context).bottom);
          return Stack(
        children: [
        Column(
        children: [
          if (!isTypedReview)
          // 상단 바: 댓글 0/시간순 영역과 동일한 배경색
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(10, MediaQuery.of(context).padding.top, 10, 0),
            color: theme.cardTheme.color ?? cs.surface,
            child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.pop(context, _buildResult(updatedPost: _post)),
                        child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(LucideIcons.x, size: 22, color: cs.onSurface),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.tabName ?? '',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
            ),
          ),
          Expanded(
              child: BlindRefreshIndicator(
                onRefresh: _loadLatestPost,
                spinnerOffsetDown: 15.0,
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.zero,
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (isTypedReview) _buildLetterboxdReviewSection(context, theme, cs, post),
                    if (!isTypedReview) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 아바타 + 닉네임/시간
                              _PostAuthorAvatar(photoUrl: post.authorPhotoUrl, author: post.author, colorIndex: post.authorAvatarColorIndex, size: 38),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTapDown: (details) => _showPostAuthorMenu(context, post.author, details),
                                      behavior: HitTestBehavior.opaque,
                                      child: Text(
                                        post.author.startsWith('u/') ? post.author.substring(2) : post.author,
                                        style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      post.timeAgo,
                                      style: GoogleFonts.notoSansKr(fontSize: 11, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              // 공유 아이콘
                              GestureDetector(
                                onTap: () => ShareSheet.show(context, title: post.title, type: 'post'),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: Icon(LucideIcons.share_2, size: 18, color: cs.onSurfaceVariant),
                                ),
                              ),
                              // 저장 아이콘
                              ValueListenableBuilder<List<SavedItem>>(
                                valueListenable: SavedService.instance.savedList,
                                builder: (context, _, __) {
                                  final isSaved = SavedService.instance.isSaved(post.id);
                                  return GestureDetector(
                                    onTap: () => SavedService.instance.toggle(SavedItem(
                                      id: post.id,
                                      title: post.title,
                                      views: formatCompactCount(post.views),
                                      type: SavedItemType.post,
                                      post: post,
                                    )),
                                    behavior: HitTestBehavior.opaque,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                      child: Icon(
                                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                                        size: 20,
                                        color: isSaved ? cs.primary : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // ··· 버튼 (오른쪽 상단)
                              GestureDetector(
                                onTapDown: (details) async {
                                  final value = await showMenu<String>(
                                    context: context,
                                    position: RelativeRect.fromLTRB(
                                      details.globalPosition.dx,
                                      details.globalPosition.dy,
                                      details.globalPosition.dx + 1,
                                      details.globalPosition.dy + 1,
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    color: cs.surface,
                                    items: [
                                      if (_isMine) ...[
                                        PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: cs.onSurface), const SizedBox(width: 10), Text(s.get('edit'), style: GoogleFonts.notoSansKr())])),
                                        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: cs.error), const SizedBox(width: 10), Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: cs.error))])),
                                      ] else if (isAppModerator()) ...[
                                        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: cs.error), const SizedBox(width: 10), Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: cs.error))])),
                                      ] else ...[
                                        PopupMenuItem(value: 'report', child: Row(children: [Icon(LucideIcons.flag, size: 18, color: cs.error), const SizedBox(width: 10), Text(s.get('report'), style: GoogleFonts.notoSansKr(color: cs.error))])),
                                        PopupMenuItem(value: 'block', child: Row(children: [Icon(LucideIcons.ban, size: 18, color: cs.onSurface), const SizedBox(width: 10), Text(s.get('block'), style: GoogleFonts.notoSansKr())])),
                                      ],
                                    ],
                                  );
                                  if (!mounted || value == null) return;
                                  if (value == 'edit') {
                                    final updated = await Navigator.push<Post>(context, MaterialPageRoute(builder: (_) => WritePostPage(initialPost: _post)));
                                    if (updated != null && mounted) setState(() => _currentPost = updated);
                                  } else if (value == 'delete') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(s.get('delete'), style: GoogleFonts.notoSansKr()),
                                        content: Text(s.get('deletePostConfirm'), style: GoogleFonts.notoSansKr()),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: cs.error))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && mounted) {
                                      await PostService.instance.deletePost(_post.id);
                                      if (mounted) { widget.onPostDeleted?.call(_post); Navigator.pop(context); }
                                    }
                                  } else if (value == 'report') {
                                    await showDialog<void>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(s.get('reportPostTitle'), style: GoogleFonts.notoSansKr()),
                                        content: Text(s.get('reportPostMessage'), style: GoogleFonts.notoSansKr()),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
                                          TextButton(onPressed: () { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.get('reportSubmitted'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating)); }, child: Text(s.get('report'), style: GoogleFonts.notoSansKr(color: cs.error))),
                                        ],
                                      ),
                                    );
                                  } else if (value == 'block') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(s.get('blockPostTitle'), style: GoogleFonts.notoSansKr()),
                                        content: Text(s.get('blockPostMessage'), style: GoogleFonts.notoSansKr()),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.get('block'), style: GoogleFonts.notoSansKr())),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && mounted) {
                                      await BlockService.instance.blockPost(_post.id);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(s.get('blockPostDone'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
                                        );
                                        Navigator.pop(context);
                                      }
                                    }
                                  }
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: Icon(LucideIcons.ellipsis, size: 17, color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
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
                          if (post.hasVideo && post.videoUrl != null && post.videoUrl!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: _PostVideoPlayer(
                                videoUrl: post.videoUrl!,
                                thumbnailUrl: post.videoThumbnailUrl,
                                isGif: post.isGif == true,
                              ),
                            ),
                          ] else if (post.hasImage && post.imageUrls.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: _PostImageCarousel(
                                imageUrls: post.imageUrls,
                                imageDimensions: post.imageDimensions,
                                onTap: (index) => FullScreenImagePage.show(context, post.imageUrls, initialIndex: index),
                              ),
                            ),
                          ] else if (post.hasImage) ...[
                            const SizedBox(height: 16),
                            AspectRatio(
                              aspectRatio: 1 / 1.15,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Icon(LucideIcons.image, size: 56, color: cs.onSurfaceVariant.withOpacity(0.4)),
                                ),
                              ),
                            ),
                          ],
                          if (post.body != null && post.body!.isNotEmpty) ...[
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
                          if (post.linkUrl != null && post.linkUrl!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(LucideIcons.link, size: 18, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    post.linkUrl!,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      color: cs.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
                      padding: const EdgeInsets.only(left: 4, right: 15, top: 4, bottom: 15),
                      child: Row(
                        children: [
                          // 투표박스
                          _DetailVoteBox(
                            voteState: _isLiked ? 1 : (_isDisliked ? -1 : 0),
                            count: _likeCount,
                            onUp: _onLikeTap,
                            onDown: _onDislikeTap,
                            primaryColor: cs.primary,
                          ),
                          const SizedBox(width: 4),
                          // 댓글
                          GestureDetector(
                            onTap: _onCommentTap,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.message_circle, size: 16, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  formatCompactCount(post.comments),
                                  style: GoogleFonts.notoSansKr(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (!hideViewsInTalkAskDetail) ...[
                            const SizedBox(width: 14),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.eye, size: 16, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  formatCompactCount(post.views),
                                  style: GoogleFonts.notoSansKr(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                          if (_canDeletePost) ...[
                            const Spacer(),
                            if (_isMine)
                              GestureDetector(
                                onTap: () async {
                                  final updated = await Navigator.push<Post>(
                                    context,
                                    MaterialPageRoute(builder: (_) => WritePostPage(initialPost: _post)),
                                  );
                                  if (updated != null && mounted) setState(() => _currentPost = updated);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  child: Text(s.get('edit'), style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant)),
                                ),
                              ),
                            if (_canDeletePost)
                              GestureDetector(
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(s.get('delete'), style: GoogleFonts.notoSansKr()),
                                      content: Text(s.get('deletePostConfirm'), style: GoogleFonts.notoSansKr()),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr())),
                                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.get('delete'), style: GoogleFonts.notoSansKr(color: cs.error))),
                                      ],
                                    ),
                                  );
                                  if (confirm == true && mounted) {
                                    await PostService.instance.deletePost(_post.id);
                                    if (mounted) {
                                      widget.onPostDeleted?.call(_post);
                                      Navigator.pop(context);
                                    }
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  child: Text(
                                    s.get('delete'),
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: deleteLabelColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    ],
                    // 액션 바 아래 구분선 (댓글 시간순 위) - 얇은 회색선
                    Container(height: 1, color: cs.outline.withOpacity(0.4)),
                    // 댓글 섹션 (contentWidth로 3행 버튼 오른쪽 끝 통일)
                    KeyedSubtree(
                      key: _commentsKey,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final contentWidth = constraints.maxWidth;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                color: theme.brightness == Brightness.light
                                    ? cs.surfaceContainerHighest
                                    : (theme.cardTheme.color ?? cs.surface),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                child: Row(
                                  children: [
                                    Text(
                                      '${s.get('comments')} ${post.comments}',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const Spacer(),
                                    ValueListenableBuilder<bool>(
                                      valueListenable: _commentSortByTop,
                                      builder: (context, sortByTop, _) => PopupMenuButton<bool>(
                                        offset: const Offset(0, 36),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: EdgeInsets.zero,
                                        onSelected: (value) {
                                          _commentSortByTop.value = value;
                                          setState(() => _commentPage = 0);
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(value: false, child: Text(s.get('sortByTime'), style: GoogleFonts.notoSansKr(fontSize: 14))),
                                          PopupMenuItem(value: true, child: Text(s.get('sortByTop'), style: GoogleFonts.notoSansKr(fontSize: 14))),
                                        ],
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              sortByTop ? s.get('sortByTop') : s.get('sortByTime'),
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(Icons.keyboard_arrow_down, size: 18, color: cs.onSurfaceVariant),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // 페이지네이션 적용된 댓글 목록 (빈 목록일 때는 플레이스홀더 없이 아래 입력칸만 사용)
                              ValueListenableBuilder<bool>(
                                valueListenable: _commentSortByTop,
                                builder: (context, sortByTop, _) {
                                  if (post.commentsList.isEmpty) return const SizedBox.shrink();
                                  final allComments = List<PostComment>.from(post.commentsList);
                                if (sortByTop) {
                                  allComments.sort((a, b) {
                                    final voteCmp = b.votes.compareTo(a.votes);
                                    if (voteCmp != 0) return voteCmp;
                                    final aTime = a.createdAtDate?.millisecondsSinceEpoch ?? int.tryParse(a.id) ?? 0;
                                    final bTime = b.createdAtDate?.millisecondsSinceEpoch ?? int.tryParse(b.id) ?? 0;
                                    return aTime.compareTo(bTime);
                                  });
                                } else {
                                    allComments.sort((a, b) {
                                      final aTime = a.createdAtDate?.millisecondsSinceEpoch ?? int.tryParse(a.id) ?? 0;
                                      final bTime = b.createdAtDate?.millisecondsSinceEpoch ?? int.tryParse(b.id) ?? 0;
                                      return aTime.compareTo(bTime);
                                    });
                                  }
                                  final totalPages = (allComments.length / _commentsPerPage).ceil().clamp(1, 9999);
                                  final safePage = _commentPage.clamp(0, totalPages - 1);
                                  final start = safePage * _commentsPerPage;
                                  final end = (start + _commentsPerPage).clamp(0, allComments.length);
                                  // 페이지마다 다른 key로 해당 페이지 목록이 확실히 보이도록 함
                                  return Column(
                                    key: ValueKey('comment_list_page_$safePage'),
                                    children: allComments.sublist(start, end).map((c) {
                                      final tile = _CommentTile(
                                        key: ValueKey(c.id),
                                        comment: c,
                                        strings: s,
                                        depth: 0,
                                        postId: _post.id,
                                        contentWidth: contentWidth,
                                        onPostUpdated: (Post p) => setState(() => _currentPost = p),
                                        onReplyTap: (String commentId) {
                                          setState(() => _replyingToCommentId = commentId);
                                          _commentFocusNode.requestFocus();
                                          Future.delayed(const Duration(milliseconds: 350), () {
                                            if (!mounted) return;
                                            final ctx = _inputCardKey.currentContext;
                                            if (ctx == null || !_scrollController.hasClients) return;
                                            final box = ctx.findRenderObject() as RenderBox?;
                                            if (box == null) return;
                                            final scrollBox = _scrollController.position.context.storageContext
                                                .findRenderObject() as RenderBox?;
                                            if (scrollBox == null) return;
                                            final cardTopInScroll = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
                                            final cardBottom = cardTopInScroll + box.size.height + _scrollController.offset;
                                            final target = (cardBottom - _scrollController.position.viewportDimension)
                                                .clamp(0.0, _scrollController.position.maxScrollExtent);
                                            _scrollController.animateTo(
                                              target,
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeOut,
                                            );
                                          });
                                        },
                                      );
                                      return c.id == _scrollToCommentId
                                          ? KeyedSubtree(key: _newCommentKey, child: tile)
                                          : tile;
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // 댓글 페이지네이션
                    Builder(builder: (context) {
                      final allComments = post.commentsList;
                      if (allComments.isEmpty) return const SizedBox.shrink();
                      final totalPages = (allComments.length / _commentsPerPage).ceil().clamp(1, 9999);
                      final safePage = _commentPage.clamp(0, totalPages - 1);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: safePage > 0
                                  ? () {
                                      setState(() => _commentPage = safePage - 1);
                                      _savedCommentPageByPostId[_post.id] = safePage - 1;
                                      _scrollToComments();
                                    }
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(LucideIcons.chevron_left, size: 22,
                                  color: safePage > 0 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${safePage + 1} / $totalPages',
                                style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant, letterSpacing: 0.2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: safePage < totalPages - 1
                                  ? () {
                                      setState(() => _commentPage = safePage + 1);
                                      _savedCommentPageByPostId[_post.id] = safePage + 1;
                                      _scrollToComments();
                                    }
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(LucideIcons.chevron_right, size: 22,
                                  color: safePage < totalPages - 1 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    // 댓글 입력 카드 (배경색과 입력칸 색 사이의 중간색)
                    Container(
                      key: _inputCardKey,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Color.lerp(theme.scaffoldBackgroundColor, cs.surfaceContainerHighest, 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outline.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: cs.shadow.withOpacity(0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: Row(
                              children: [
                                Text(
                                  '${s.get('writeComment')}  ',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('(', style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                                    ShaderMask(
                                      blendMode: BlendMode.srcIn,
                                      shaderCallback: (bounds) => const LinearGradient(
                                        colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ).createShader(bounds),
                                      child: const Icon(Icons.local_fire_department_rounded, size: 13, color: Colors.white),
                                    ),
                                    Text(s.get('activityPoint'), style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, thickness: 0.8, color: cs.outline.withOpacity(0.1)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                            child: _buildInputLayout(cs, s),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(height: _kMorePostsDividerHeight, color: theme.colorScheme.outline.withOpacity(0.2)),
                    SizedBox(
                      key: _morePostsSectionKey,
                      child: _MorePostsSection(
                        key: ValueKey('${_post.id}_$_morePostsTabIndex'),
                        excludePostId: _post.id,
                        currentUserAuthor: _currentUserAuthor,
                        initialTabIndex: _morePostsTabIndex,
                        initialPosts: widget.initialBoardPosts,
                        onTabChanged: (i) => setState(() => _morePostsTabIndex = i),
                        onPostTap: (post) => _navigateToPost(post, tabIndex: _morePostsTabIndex),
                      ),
                    ),
                    // 제일 아래: 홈 메인 탭일 때는 브라우저 바 없음 → 패딩만
                    SizedBox(height: bottomScrollPad),
                      ],
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
          },
        ),
      ),
    );
  }
}

/// 댓글 아래 인기글/자유게시판 탭 + 글 목록 (홈탭과 동일한 PopularPostsTab, FreeBoardTab, QuestionBoardTab 사용)
class _MorePostsSection extends StatefulWidget {
  const _MorePostsSection({
    super.key,
    required this.excludePostId,
    this.currentUserAuthor,
    this.initialTabIndex = 0,
    this.initialPosts,
    this.onTabChanged,
    this.onPostTap,
  });

  final String excludePostId;
  final String? currentUserAuthor;
  final int initialTabIndex;
  /// 홈탭에서 넘긴 게시판 목록이 있으면 즉시 표시(인기글/자유/질문 동일 피드)
  final List<Post>? initialPosts;
  final void Function(int)? onTabChanged;
  final void Function(Post)? onPostTap;

  @override
  State<_MorePostsSection> createState() => _MorePostsSectionState();
}

class _MorePostsSectionState extends State<_MorePostsSection> with SingleTickerProviderStateMixin {
  static const List<String> _feedBoards = ['review', 'talk', 'ask'];

  late TabController _tabController;
  final List<List<Post>> _tabFeedPosts = List.generate(3, (_) => []);
  final List<DocumentSnapshot<Map<String, dynamic>>?> _tabLastDoc = List.generate(3, (_) => null);
  final List<bool> _tabHasMore = List.generate(3, (_) => true);
  final List<bool> _tabLoadingMore = List.generate(3, (_) => false);
  final List<bool> _tabInitialLoading = List.generate(3, (_) => true);
  late final List<ScrollController> _feedScrollControllers;
  String? _postsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _feedScrollControllers = List.generate(3, (i) {
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
        if (BlockService.instance.isBlocked(p.author) || BlockService.instance.isPostBlocked(p.id)) continue;
        if (p.id == widget.excludePostId) continue;
        for (var t = 0; t < 3; t++) {
          if (postMatchesFeedFilter(p, _feedBoards[t])) {
            if (!_tabFeedPosts[t].any((e) => e.id == p.id)) {
              _tabFeedPosts[t].add(p);
            }
          }
        }
      }
      for (var t = 0; t < 3; t++) {
        _tabInitialLoading[t] = _tabFeedPosts[t].isEmpty;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureFeedTabBootstrapped(widget.initialTabIndex.clamp(0, 2));
    });
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
        ? (UserProfileService.instance.signupCountryNotifier.value ?? LocaleService.instance.locale)
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
    if (tabIndex < 0 || tabIndex > 2) return;
    if (_tabFeedPosts[tabIndex].isEmpty && !_tabLoadingMore[tabIndex]) {
      _loadFeedTabPage(tabIndex, reset: false);
    }
  }

  Future<void> _loadFeedTabPage(int tabIndex, {required bool reset}) async {
    if (tabIndex < 0 || tabIndex > 2) return;
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

      for (var attempt = 0; attempt < 24; attempt++) {
        final page = await PostService.instance.getPosts(
          country: viewerLanguage,
          type: _feedBoards[tabIndex],
          lastDocument: cursor,
          limit: 20,
        );
        pageHasMore = page.hasMore;
        cursor = page.lastDocument;
        for (final p in page.posts) {
          if (p.id == widget.excludePostId) continue;
          if (!BlockService.instance.isBlocked(p.author) && !BlockService.instance.isPostBlocked(p.id)) {
            accumulated.add(p);
          }
        }
        if (accumulated.isNotEmpty || !pageHasMore || page.lastDocument == null) {
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
              style: GoogleFonts.notoSansKr(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.5),
            ),
        ),
        // 탭바 (홈탭과 동일한 스타일)
        Container(
          color: theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: AnimatedBuilder(
            animation: _tabController.animation!,
            builder: (context, _) {
              const tabW = 60.0;
              const tabH = 26.0;
              const tabGap = 5.0;
              final animValue = _tabController.animation?.value ?? _tabController.index.toDouble();
              final idx = animValue.round().clamp(0, 2);
              final s = CountryScope.of(context).strings;
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: (tabW + tabGap) * 2 + tabW,
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
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      for (var i = 0; i < 3; i++)
                        Positioned(
                          left: (tabW + tabGap) * i,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => _tabController.animateTo(i),
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              width: tabW,
                              height: tabH,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(color: cs.outline.withOpacity(0.6), width: 0.7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  [s.get('tabReviews'), s.get('tabGeneral'), s.get('tabQnA')][i],
                                  strutStyle: const StrutStyle(
                                    forceStrutHeight: true,
                                    height: 1.15,
                                    fontSize: 11,
                                    leadingDistribution: TextLeadingDistribution.even,
                                  ),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                    color: idx == i ? cs.onInverseSurface : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // 탭 아래 영역: IndexedStack 대신 현재 탭만 렌더링 → 다른 탭 높이로 빈 공간 생기는 문제 방지
        Builder(builder: (context) {
          final idx = _tabController.index;
          void onUpdated(Post updated) {
            setState(() {
              for (var t = 0; t < 3; t++) {
                final j = _tabFeedPosts[t].indexWhere((p) => p.id == updated.id);
                if (j >= 0) {
                  if (postMatchesFeedFilter(updated, _feedBoards[t])) {
                    _tabFeedPosts[t][j] = updated;
                  } else {
                    _tabFeedPosts[t].removeAt(j);
                  }
                } else if (postMatchesFeedFilter(updated, _feedBoards[t]) &&
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
              for (var t = 0; t < 3; t++) {
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
            );
          }
          if (idx == 1) {
            return FreeBoardTab(
              posts: _postsForTab(1),
              isLoading: _tabFeedPosts[1].isEmpty && _tabInitialLoading[1],
              error: _postsError,
              currentUserAuthor: widget.currentUserAuthor,
              onRefresh: () => _loadFeedTabPage(1, reset: true),
              enablePullToRefresh: false,
              shrinkWrap: true,
              useSimpleFeedLayout: true,
              feedScrollController: _feedScrollControllers[1],
              feedLoadingMore: _tabLoadingMore[1],
              feedHasMore: _tabHasMore[1],
              onPostUpdated: onUpdated,
              onPostDeleted: onDeleted,
              onPostTap: widget.onPostTap,
            );
          }
          return QuestionBoardTab(
            posts: _postsForTab(2),
            isLoading: _tabFeedPosts[2].isEmpty && _tabInitialLoading[2],
            error: _postsError,
            currentUserAuthor: widget.currentUserAuthor,
            onRefresh: () => _loadFeedTabPage(2, reset: true),
            enablePullToRefresh: false,
            shrinkWrap: true,
            useSimpleFeedLayout: true,
            feedScrollController: _feedScrollControllers[2],
            feedLoadingMore: _tabLoadingMore[2],
            feedHasMore: _tabHasMore[2],
            onPostUpdated: onUpdated,
            onPostDeleted: onDeleted,
            onPostTap: widget.onPostTap,
          );
        }),
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
    this.contentWidth,
    required this.onPostUpdated,
    this.onReplyTap,
  });

  final PostComment comment;
  final dynamic strings;
  final int depth;
  final String postId;
  /// 댓글 영역 전체 너비. 지정 시 3행(답글·좋아요·싫어요)을 이 너비의 오른쪽 끝에 맞춤.
  final double? contentWidth;
  final void Function(Post) onPostUpdated;
  final void Function(String commentId)? onReplyTap;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _isLiked = false;
  bool _isDisliked = false;
  late int _likeCount;
  late int _dislikeCount;
  bool _votePending = false;

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
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
    PostService.instance.toggleCommentLike(widget.postId, widget.comment.id).then((updated) {
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _isLiked = prevLiked; _isDisliked = prevDisliked;
          _likeCount = prevLikeCount; _dislikeCount = prevDislikeCount;
        });
      } else {
        widget.onPostUpdated(updated);
      }
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _onReplyTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    widget.onReplyTap?.call(widget.comment.id);
  }

  Future<void> _onDislikeTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
    PostService.instance.toggleCommentDislike(widget.postId, widget.comment.id).then((updated) {
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _isLiked = prevLiked; _isDisliked = prevDisliked;
          _likeCount = prevLikeCount; _dislikeCount = prevDislikeCount;
        });
      } else {
        widget.onPostUpdated(updated);
      }
      if (mounted) setState(() => _votePending = false);
    });
  }

  Future<void> _showNicknameMenu(BuildContext context, TapDownDetails details) async {
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
              Text(s.get('sendMessageToUser'), style: GoogleFonts.notoSansKr(fontSize: 13)),
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
              Text(s.get('viewUserPosts'), style: GoogleFonts.notoSansKr(fontSize: 13)),
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
              Text(s.get('viewUserComments'), style: GoogleFonts.notoSansKr(fontSize: 13)),
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
            builder: (_) => UserCommentsScreen(authorName: nickname),
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
    final useAlignedButtons = widget.contentWidth != null;
    final contentWidth = widget.contentWidth ?? double.infinity;

    // 3행: 답글 · 좋아요 · 숫자 · 싫어요 — 테두리 없이 인라인
    final actionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async => await _onReplyTap(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.reply, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(s.get('reply'), style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _DetailVoteBox(
          voteState: _isLiked ? 1 : (_isDisliked ? -1 : 0),
          count: _likeCount,
          onUp: _onLikeTap,
          onDown: _onDislikeTap,
          primaryColor: cs.primary,
          useThumbIcons: true,
          thumbBaseColor: cs.onSurfaceVariant,
        ),
      ],
    );

    // 1·2·3행 영역 (Padding 포함) — 레딧 스타일: 아바타 왼쪽 고정, 콘텐츠 오른쪽 컬럼
    final rowsSection = Padding(
      padding: widget.depth == 0
          ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
          : const EdgeInsets.fromLTRB(0, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 왼쪽: 아바타 (닉네임 탭 메뉴)
          GestureDetector(
            onTapDown: (details) => _showNicknameMenu(context, details),
            behavior: HitTestBehavior.opaque,
            child: _PostAuthorAvatar(
              photoUrl: comment.authorPhotoUrl,
              author: comment.author,
              colorIndex: comment.authorAvatarColorIndex,
              size: 28,
            ),
          ),
          const SizedBox(width: 6),
          // 오른쪽: 닉네임·시간 / 이미지 / 텍스트 / 액션
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1행: 닉네임 · 시간
                GestureDetector(
                  onTapDown: (details) => _showNicknameMenu(context, details),
                  behavior: HitTestBehavior.opaque,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: comment.author,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                        TextSpan(
                          text: ' · ${comment.displayTimeAgo}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                // 첨부 이미지 (아바타 오른쪽 컬럼에 위치 — 레딧 스타일)
                if (comment.imageUrl != null && comment.imageUrl!.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullScreenImagePage(imageUrls: [comment.imageUrl!]),
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
                          errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: cs.surfaceContainerHighest,
                            child: Icon(LucideIcons.image_off, size: 40, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                // 내용 (텍스트)
                if (comment.text.trim().isNotEmpty)
                  Text(
                    comment.text,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: cs.onSurface,
                      height: 1.45,
                    ),
                  ),
                // 액션 행 (오른쪽 정렬)
                Align(
                  alignment: Alignment.centerRight,
                  child: actionRow,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // depth 0: 풀 width 카드 (레딧 스타일 - 좌우 여백 없음)
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
                children: comment.replies.map((r) => _CommentTile(
                      comment: r,
                      strings: s,
                      depth: widget.depth + 1,
                      postId: widget.postId,
                      contentWidth: widget.contentWidth,
                      onPostUpdated: widget.onPostUpdated,
                      onReplyTap: widget.onReplyTap,
                    )).toList(),
              ),
          ],
        ),
      );
    }

    // depth 1+: 대댓글 - 왼쪽 세로선 + 들여쓰기 + 하위 답글도 표시
    final isFirstReply = widget.depth == 1;
    return Container(
      margin: EdgeInsets.only(left: isFirstReply ? 20 : 12),
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: cs.outline.withOpacity(0.6), width: 0.7),
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
              children: comment.replies.map((r) => _CommentTile(
                    comment: r,
                    strings: s,
                    depth: widget.depth + 1,
                    postId: widget.postId,
                    contentWidth: widget.contentWidth,
                    onPostUpdated: widget.onPostUpdated,
                    onReplyTap: widget.onReplyTap,
                  )).toList(),
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
                color: isHighlighted ? cs.primary : cs.onSurfaceVariant.withOpacity(0.65),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isHighlighted ? cs.primary : cs.onSurfaceVariant.withOpacity(0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 글 상세·피드 공통: 가로 1 기준 세로 최대 1.4
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

  @override
  void initState() {
    super.initState();
    // 피드에서 사전 로딩된 컨트롤러 재사용 시도
    final cached = VideoPreloadCache.instance.consume(widget.videoUrl);
    if (cached != null && cached.value.isInitialized) {
      _controller = cached;
      _controller.setLooping(widget.isGif);
      if (widget.isGif) {
        _controller.setVolume(0);
        _muted = true;
      } else {
        _controller.setVolume(1);
        _muted = false;
      }
      _controller.addListener(() { if (mounted) setState(() {}); });
      _controller.play();
    } else {
      cached?.dispose();
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          _controller.setLooping(widget.isGif);
          if (widget.isGif) {
            _controller.setVolume(0);
            _muted = true;
          } else {
            _controller.setVolume(1);
            _muted = false;
          }
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
                  else if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          widget.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: Colors.black),
                        ),
                        const Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('GIF', style: GoogleFonts.notoSansKr(fontSize: 10, color: Colors.white)),
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
                      _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: _togglePlayPause,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
                    style: GoogleFonts.notoSansKr(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(duration),
                    style: GoogleFonts.notoSansKr(fontSize: 12, color: Colors.white54),
                  ),
                  if (!widget.isGif)
                    IconButton(
                      icon: Icon(
                        _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _toggleMute,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () {
                      FullScreenVideoPage.show(
                        context,
                        videoUrl: widget.videoUrl,
                        thumbnailUrl: widget.thumbnailUrl,
                        isGif: widget.isGif,
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: widget.aspectRatioFor(0),
          child: OptimizedNetworkImage(
            imageUrl: widget.imageUrls.first,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(16),
            errorWidget: Container(
              color: cs.surfaceContainerHighest,
              child: Center(
                child: Icon(LucideIcons.image_off, size: 56, color: cs.onSurfaceVariant.withOpacity(0.4)),
              ),
            ),
            onTap: () => widget.onTap(0),
          ),
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
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: OptimizedNetworkImage(
                      imageUrl: widget.imageUrls[index],
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(16),
                      errorWidget: Container(
                        color: cs.surfaceContainerHighest,
                        child: Center(
                          child: Icon(LucideIcons.image_off, size: 56, color: cs.onSurfaceVariant.withOpacity(0.4)),
                        ),
                      ),
                      onTap: () => widget.onTap(index),
                    ),
                  );
                },
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
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
    this.colorIndex,
    this.size = 28,
  });

  final String? photoUrl;
  final String author;
  final int? colorIndex;
  final double size;

  int _resolvedIndex() {
    if (colorIndex != null) return colorIndex!;
    final name = author.startsWith('u/') ? author.substring(2) : author;
    return name.codeUnits.fold(0, (prev, c) => prev + c);
  }

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefault(),
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
                    ? Colors.black87          // 1 이상: 검은색
                    : count < 0
                        ? const Color(0xFFCCCCCC) // 음수: 더 옅은 색
                        : baseColor)          // 0: 기본 회색
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
                    ? Icon(Icons.thumb_up_alt_outlined, size: 14, color: upColor)
                    : Icon(Icons.arrow_drop_up_rounded, size: 22, color: upColor),
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
                    ? Icon(Icons.thumb_down_alt_outlined, size: 14, color: downColor)
                    : Icon(Icons.arrow_drop_down_rounded, size: 22, color: downColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
