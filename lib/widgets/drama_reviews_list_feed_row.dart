import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../models/drama.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../screens/login_page.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../utils/format_utils.dart';
import 'country_scope.dart';
import 'drama_review_feed_tile.dart';
import 'feed_inline_action_colors.dart';
import 'optimized_network_image.dart';
import 'review_card_tap_highlight.dart';

/// [community_board_tabs]의 `reviewInlineActionHitTarget`과 동일 — 터치 영역만 확장.
Widget _dramaReviewsListActionHitTarget({
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

class _InlineCommentEntry {
  const _InlineCommentEntry({required this.comment, required this.depth});
  final PostComment comment;
  final int depth;
}

void _flattenCommentsInto(
  List<PostComment> roots,
  List<_InlineCommentEntry> out, {
  required Set<String> expandedParentIds,
  int depth = 0,
}) {
  for (final c in roots) {
    out.add(_InlineCommentEntry(comment: c, depth: depth));
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

/// 드라마 상세 > 리뷰 전체: 홈 리뷰 피드처럼 펼침 댓글 + 하트·댓글 액션.
class DramaReviewsListFeedRow extends StatefulWidget {
  const DramaReviewsListFeedRow({
    super.key,
    required this.review,
    /// [Post] 로드 전까지 타일·하트 숫자에 쓸 값(예: 상세 카드 낙관적 좋아요).
    this.displayLikeCountOverride,
    /// [Post] 로드 전까지 댓글 수에 쓸 값 (배치 조회 결과 전달용).
    this.displayCommentCountOverride,
    /// [Post] 로드 전까지 하트 활성 여부 (batchGetPostMeta.isLiked 결과 전달용).
    this.initialIsLiked,
    /// null이면 [ColorScheme.surface]. 상세 Ratings 카드 안에서는 부모와 같은 톤으로 맞출 것.
    this.rowMaterialColor,
  });

  final DramaReview review;
  final int? displayLikeCountOverride;
  final int? displayCommentCountOverride;
  final bool? initialIsLiked;
  final Color? rowMaterialColor;

  @override
  State<DramaReviewsListFeedRow> createState() => _DramaReviewsListFeedRowState();
}

class _DramaReviewsListFeedRowState extends State<DramaReviewsListFeedRow> {
  Post? _post;
  bool _loadingPost = false;
  bool _expanded = false;
  TextEditingController? _commentCtrl;
  final FocusNode _commentFocus = FocusNode();
  bool _submitting = false;
  bool _likeBusy = false;

  /// 댓글별 낙관적 좋아요 상태 {commentId → (liked, count)}
  final Map<String, ({bool liked, int count})> _commentLikeState = {};
  /// 현재 답글 대상 댓글 id
  String? _replyingToCommentId;
  /// 현재 답글 대상 댓글 객체 (배너 표시용)
  PostComment? _replyingToComment;
  /// 펼친 답글 스레드 parent comment ids
  final Set<String> _expandedReplyThreads = {};

  String? get _feedPostId {
    final fp = widget.review.feedPostId?.trim();
    if (fp != null && fp.isNotEmpty) return fp;
    final id = widget.review.id?.trim();
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  @override
  void dispose() {
    _commentCtrl?.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _snack(String message) {
    final ctx = context;
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.notoSansKr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadPost() async {
    final id = _feedPostId;
    if (id == null || id.isEmpty) return;
    if (_loadingPost) return;
    setState(() => _loadingPost = true);
    final loc = CountryScope.maybeOf(context)?.country;
    final p = await PostService.instance.getPost(id, loc);
    if (!mounted) return;
    setState(() {
      _loadingPost = false;
      _post = p;
    });
  }

  Future<void> _refreshPost() async {
    final id = _post?.id ?? _feedPostId;
    if (id == null || id.isEmpty) return;
    final loc = CountryScope.maybeOf(context)?.country;
    final p = await PostService.instance.getPost(id, loc);
    if (!mounted) return;
    if (p != null) setState(() => _post = p);
  }

  Future<void> _ensurePostForInteraction() async {
    if (_post != null) return;
    if (_feedPostId == null) return;
    await _loadPost();
  }

  Future<void> _toggleExpand() async {
    final id = _feedPostId;
    if (id == null || id.isEmpty) {
      _snack('피드에 연결된 글이 없어 댓글을 열 수 없어요.');
      return;
    }
    await _ensurePostForInteraction();
    if (!mounted) return;
    if (_post == null) {
      _snack('피드 글을 찾을 수 없어요.');
      return;
    }
    final opening = !_expanded;
    setState(() {
      _expanded = opening;
      if (opening) {
        _commentCtrl ??= TextEditingController();
      }
    });
    if (opening) unawaited(_refreshPost());
  }

  Future<void> _toggleLike() async {
    await _ensurePostForInteraction();
    if (!mounted) return;
    final post = _post;
    if (post == null) {
      _snack('피드 글을 찾을 수 없어요.');
      return;
    }
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return;
    if (_likeBusy) return;
    _likeBusy = true;

    final liked = post.likedBy.contains(uid);
    final newLikedBy = List<String>.from(post.likedBy);
    if (!liked) {
      if (!newLikedBy.contains(uid)) newLikedBy.add(uid);
    } else {
      newLikedBy.remove(uid);
    }
    final likeVoteDelta = !liked ? (post.dislikedBy.contains(uid) ? 2 : 1) : -1;
    var nextLikeCount = post.likeCount;
    var nextDislikeCount = post.dislikeCount;
    if (!liked) {
      if (post.dislikedBy.contains(uid)) {
        nextDislikeCount = (nextDislikeCount - 1).clamp(0, 999999);
      }
      nextLikeCount += 1;
    } else {
      nextLikeCount = (nextLikeCount - 1).clamp(0, 999999);
    }
    final optimistic = post.copyWith(
      votes: post.votes + likeVoteDelta,
      likedBy: newLikedBy,
      dislikedBy: !liked
          ? post.dislikedBy.where((u) => u != uid).toList()
          : post.dislikedBy,
      likeCount: nextLikeCount,
      dislikeCount: nextDislikeCount,
    );
    setState(() => _post = optimistic);

    final latestLiked = optimistic.likedBy.contains(uid);
    final latestVote = latestLiked
        ? 1
        : (optimistic.dislikedBy.contains(uid) ? -1 : 0);

    await PostService.instance.togglePostLike(
      post.id,
      currentVoteState: latestVote,
      postAuthorUid: post.authorUid,
      postTitle: post.title,
    );
    _likeBusy = false;
    if (!mounted) return;
    await _refreshPost();
  }

  Future<void> _submitComment() async {
    final post = _post;
    final ctrl = _commentCtrl;
    if (post == null || ctrl == null) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    final s = CountryScope.of(context).strings;
    final author = await UserProfileService.instance.getAuthorBaseName();
    if (!mounted) return;
    final p = _post!;
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
    );

    final parentId = _replyingToCommentId;
    String? err;
    if (parentId != null && parentId.isNotEmpty) {
      err = await PostService.instance.addReply(p.id, parentId, newComment);
    } else {
      err = await PostService.instance.addComment(p.id, p, newComment);
    }
    if (!mounted) return;
    if (err != null) {
      setState(() => _submitting = false);
      _snack(err);
      return;
    }

    List<PostComment> newComments;
    int newCount;
    if (parentId != null && parentId.isNotEmpty) {
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
        );
        newComments = PostService.replaceCommentById(p.commentsList, parentId, updated);
      } else {
        newComments = p.commentsList;
      }
      newCount = p.comments + 1;
    } else {
      newComments = [...p.commentsList, newComment];
      newCount = (p.commentsList.length + 1 > p.comments)
          ? p.commentsList.length + 1
          : p.comments + 1;
    }

    setState(() {
      _post = p.copyWith(commentsList: newComments, comments: newCount);
      _submitting = false;
      _replyingToCommentId = null;
      _replyingToComment = null;
    });
    ctrl.clear();
    unawaited(_reconcileComment(p.id, newComment.id));
  }

  Future<void> _toggleCommentLike(PostComment c) async {
    final postId = _post?.id ?? _feedPostId;
    if (postId == null || postId.isEmpty) return;
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (!AuthService.instance.isLoggedIn.value) return;
    }
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    final cur = _commentLikeState[c.id];
    final wasLiked = cur?.liked ?? c.likedBy.contains(uid);
    final prevCount = cur?.count ?? c.votes;
    // 낙관적 업데이트
    setState(() {
      _commentLikeState[c.id] = (
        liked: !wasLiked,
        count: wasLiked ? (prevCount - 1).clamp(0, 99999) : prevCount + 1,
      );
    });
    // 포스트 확보 후 Firestore 반영
    await _ensurePostForInteraction();
    if (!mounted) return;
    final updated = await PostService.instance.toggleCommentLike(
      _post?.id ?? postId,
      c.id,
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() => _post = updated);
      // 실제 값으로 동기화
      final fresh = PostService.findCommentById(updated.commentsList, c.id);
      if (fresh != null) {
        setState(() {
          _commentLikeState[c.id] = (
            liked: fresh.likedBy.contains(uid),
            count: fresh.votes,
          );
        });
      }
    }
  }

  void _startReply(PostComment c) {
    setState(() {
      _replyingToCommentId = c.id;
      _replyingToComment = c;
      _expanded = true;
      _commentCtrl ??= TextEditingController();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _commentFocus.requestFocus();
    });
  }

  Future<void> _reconcileComment(String postId, String newCommentId) async {
    final locale = CountryScope.maybeOf(context)?.country;
    for (final delay in [
      Duration.zero,
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (!mounted) return;
      final fresh = await PostService.instance.getPost(postId, locale);
      if (!mounted || fresh == null) continue;
      final has = PostService.findCommentById(fresh.commentsList, newCommentId) != null;
      if (has) {
        setState(() => _post = fresh);
        return;
      }
    }
  }

  Widget _commentAvatar(PostComment c, double size, ColorScheme cs) {
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

  // ignore: unused_element
  Widget _commentRow(_InlineCommentEntry entry, ColorScheme cs, {required bool showReplyIcon}) {
    final c = entry.comment;
    final isReply = entry.depth > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const avatarSize = kAppUnifiedProfileAvatarSize;
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    final likeState = _commentLikeState[c.id];
    final isLiked = likeState?.liked ?? c.likedBy.contains(uid);
    final likeCount = likeState?.count ?? c.votes;

    // ── 톡/에스크 게시판과 동일한 색상·스타일 ──────────────────────────
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
    final replyStyle = appUnifiedNicknameStyle(cs).copyWith(
      fontWeight: FontWeight.w500,
      color: cs.onSurface.withValues(alpha: 0.30),
      height: 1.2,
    );
    final countStyle = appUnifiedNicknameStyle(cs).copyWith(
      fontWeight: FontWeight.w500,
      color: isLiked ? Colors.redAccent : metaColor,
      height: 1.2,
    );

    // ── 상수 (톡/에스크와 동일) ─────────────────────────────────────────
    const talkAskLikeColW = 40.0;
    const talkAskLikeCountDownNudge = 1.0;
    const talkAskBodyVisualUpNudge = 1.5;
    const heartIconSize = 16.0;
    const heartVPad = 4.0;
    final heartBlockH = heartVPad + heartIconSize + heartVPad;
    const gapNameToBody = 1.0;
    const bodyMicroUpPx = 1.0;
    final gapTalkAskNameBodyReply = gapNameToBody - bodyMicroUpPx;

    Widget heartHitTarget() {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_toggleCommentLike(c)),
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

    // ── LayoutBuilder + Stack (톡/에스크와 동일한 픽셀 배치) ───────────
    const replyArrowW = 18.0; // 14px 아이콘 + 4px gap
    final commentBody = LayoutBuilder(
      builder: (context, cons) {
        final innerMaxW = cons.maxWidth;
        final textColumnMaxW =
            (innerMaxW - avatarSize - 8 - talkAskLikeColW -
                    ((isReply || showReplyIcon) ? replyArrowW : 0.0))
                .clamp(1.0, 9999.0);
        final textScaler = MediaQuery.textScalerOf(context);
        final textDir = Directionality.of(context);

        final authorLineStyle = appUnifiedNicknameStyle(cs);
        final authorText =
            c.author.startsWith('u/') ? c.author.substring(2) : c.author;

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
            final line0CenterY = yBodyTop + h0 / 2;
            final line1CenterY = yBodyTop + h0 + h1 / 2;
            heartTop = line0CenterY - heartBlockH / 2;
            countTop =
                line1CenterY - countH / 2 + talkAskLikeCountDownNudge;
            replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
          } else {
            replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
            heartTop = yBodyTop + bodyH / 2 - heartBlockH / 2;
            final countCenterY = replyRowTop + replyRowH / 2;
            final ct =
                countCenterY - countH / 2 + talkAskLikeCountDownNudge;
            final replyBandMin = replyRowTop;
            final replyBandMax = replyRowTop + replyRowH - countH;
            countTop = replyBandMax >= replyBandMin
                ? ct.clamp(replyBandMin, replyBandMax)
                : replyBandMin;
          }
        } else {
          replyRowTop =
              hasText ? yBodyTop + bodyH + gapTalkAskNameBodyReply : yBodyTop;
          heartTop = yBodyTop + replyRowH / 2 - heartBlockH / 2;
          final countCenterY = replyRowTop + replyRowH / 2;
          final ct =
              countCenterY - countH / 2 + talkAskLikeCountDownNudge;
          final replyBandMin = replyRowTop;
          final replyBandMax = replyRowTop + replyRowH - countH;
          countTop = replyBandMax >= replyBandMin
              ? ct.clamp(replyBandMin, replyBandMax)
              : replyBandMin;
        }

        final contentBottom = math.max(
          hasText
              ? yBodyTop + bodyH + gapTalkAskNameBodyReply
              : replyRowTop,
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
            if (isReply || showReplyIcon) ...[
              Padding(
                padding: EdgeInsets.only(
                  left: showReplyIcon && !isReply ? 2 : 0,
                  top: 2,
                ),
                child: Transform.rotate(
                  angle: math.pi,
                  child: Icon(
                    LucideIcons.reply,
                    size: 14,
                    color: metaColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            _commentAvatar(c, avatarSize, cs),
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
                        onTap: () {
                          if (_feedPostId != null) _startReply(c);
                        },
                        child: Text('Reply', style: replyStyle),
                      ),
                    ),
                    // 하트 아이콘
                    Positioned(
                      right: 0,
                      top: heartTop,
                      width: talkAskLikeColW,
                      height: heartBlockH,
                      child: Center(child: heartHitTarget()),
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

    // depth 0: 일반 댓글
    if (!isReply) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: commentBody,
      );
    }

    // depth 1+: 화살표 표시 (아바타 왼쪽), 배경 박스 없음
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: commentBody,
    );
  }

  Widget _buildExpanded(ColorScheme cs) {
    final post = _post;
    if (post == null) return const SizedBox.shrink();
    final flat = <_InlineCommentEntry>[];
    _flattenCommentsInto(
      post.commentsList,
      flat,
      expandedParentIds: _expandedReplyThreads,
    );
    final hasComments = flat.isNotEmpty;
    final ctrl = _commentCtrl ??= TextEditingController();
    final sendLabel =
        CountryScope.maybeOf(context)?.strings.get('replySubmit') ?? '';

    final commentWidgets = <Widget>[];
    final stack = <({int depth, PostComment comment, int flatIndex})>[];
    for (var i = 0; i < flat.length; i++) {
      final entry = flat[i];
      final comment = entry.comment;
      const showReplyIcon = true;
      while (stack.isNotEmpty && stack.last.depth >= entry.depth) {
        stack.removeLast();
      }
      stack.add((depth: entry.depth, comment: comment, flatIndex: i));

      final hasReplies = comment.replies.isNotEmpty;
      final isExpanded = _expandedReplyThreads.contains(comment.id);
      final row = _commentRow(entry, cs, showReplyIcon: showReplyIcon);
      commentWidgets.add(row);

      if (hasReplies && !isExpanded) {
        final hasArrow = entry.depth > 0 || showReplyIcon;
        final toggleLeft = (hasArrow ? 18.0 : 0.0) +
            kAppUnifiedProfileAvatarSize +
            8.0;
        final repliesN = comment.replies.length;
        final label = repliesN == 1 ? 'reply' : 'replies';
        final metaColor = cs.onSurface.withValues(alpha: 0.44);
        commentWidgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(toggleLeft, 0, 0, 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expandedReplyThreads.add(comment.id)),
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
        final parentExpanded = _expandedReplyThreads.contains(parentComment.id);
        if (!parentExpanded || parentComment.replies.isEmpty) continue;
        const parentHasArrow = true;
        final toggleLeft = (parentHasArrow ? 18.0 : 0.0) +
            kAppUnifiedProfileAvatarSize +
            8.0;
        final label = parentComment.replies.length == 1 ? 'reply' : 'replies';
        final metaColor = cs.onSurface.withValues(alpha: 0.44);
        commentWidgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(toggleLeft, 0, 0, 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(
                () => _expandedReplyThreads.remove(parentComment.id),
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
          if (_replyingToComment != null)
            _ReplyingToBanner(
              comment: _replyingToComment!,
              onCancel: () => setState(() {
                _replyingToCommentId = null;
                _replyingToComment = null;
              }),
              cs: cs,
            ),
          _DramaReviewsListInlineComposer(
            controller: ctrl,
            focusNode: _commentFocus,
            isSubmitting: _submitting,
            autofocus: !hasComments,
            sendLabel: sendLabel,
            onSend: _submitComment,
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(ColorScheme cs) {
    final post = _post;
    final likeCount = post?.likeCount ??
        (widget.displayLikeCountOverride ?? (widget.review.likeCount ?? 0));
    final commentCount = post?.comments ??
        widget.displayCommentCountOverride ??
        widget.review.replies.length;
    final uid = AuthService.instance.currentUser.value?.uid;
    final liked = post != null
        ? (uid != null && post.likedBy.contains(uid))
        : (widget.initialIsLiked ?? false);
    const iconSize = 13.0;
    final actionFg = feedInlineActionMutedForeground(cs);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Row(
        children: [
          ReviewCardSuppressParentTap(
            child: _dramaReviewsListActionHitTarget(
              onTap: () {
                if (_feedPostId == null) {
                  _snack('피드에 연결된 글이 없어요.');
                  return;
                }
                unawaited(_toggleLike());
              },
              visual: Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      size: iconSize,
                      color: liked ? Colors.redAccent : actionFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatCompactCount(likeCount),
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
            child: _dramaReviewsListActionHitTarget(
              onTap: () => unawaited(_toggleExpand()),
              visual: Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.message_circle,
                      size: iconSize,
                      color: actionFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatCompactCount(commentCount),
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
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 사전 로드 제거 — 목록 진입 시 행마다 Firestore 요청 없음.
    // _toggleLike / _toggleExpand 탭 시점에 lazy 로드.
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final likeForTile = _post?.likeCount ??
        (widget.displayLikeCountOverride ?? (widget.review.likeCount ?? 0));
    final rowBg = widget.rowMaterialColor ?? cs.surface;
    return Material(
      color: rowBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ReviewCardTapHighlight(
            onTap: () => unawaited(_toggleExpand()),
            pressColor: cs.onSurface.withValues(alpha: 0.12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DramaReviewFeedTile(
                  review: widget.review,
                  displayLikeCount: likeForTile,
                  showLikeCountIndicator: false,
                  expandViaParentTap: true,
                  materialColor: Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 0),
                ),
                const SizedBox(height: kDramaReviewFeedVerticalGap),
                _buildActionBar(cs),
              ],
            ),
          ),
          if (_expanded) _buildExpanded(cs),
        ],
      ),
    );
  }
}

class _DramaReviewsListInlineComposer extends StatelessWidget {
  const _DramaReviewsListInlineComposer({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.autofocus,
    required this.onSend,
    required this.sendLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final bool autofocus;
  final Future<void> Function() onSend;
  final String sendLabel;

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

class _ReplyingToBanner extends StatelessWidget {
  const _ReplyingToBanner({
    required this.comment,
    required this.onCancel,
    required this.cs,
  });

  final PostComment comment;
  final VoidCallback onCancel;
  final ColorScheme cs;

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
            '$author 에게 답글',
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
