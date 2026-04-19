import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../models/post.dart';
import '../theme/app_theme.dart'
    show AppColors, appUnifiedNicknameMetaTimeStyle, appUnifiedNicknameStyle;
import '../screens/login_page.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../utils/format_utils.dart';
import '../utils/post_board_utils.dart';
import 'feed_inline_action_colors.dart';
import 'feed_post_card.dart' show TalkAskHeartVote;
import 'optimized_network_image.dart';
import 'user_profile_nav.dart';

/// [FeedReviewLetterboxdTile] 작성자 아바타와 동일.
const double _kTalkAskListAuthorAvatarSize = kAppUnifiedProfileAvatarSize;

/// 리스트 썸네일 한 변 — 제목 2줄 + 간격 + 본문 2줄 블록 높이와 동일.
const double _kTalkAskListThumbSide = 82.0;
const double _kTalkAskListTitleBodyGap = 5.0;

/// 2줄 제목 블록 / 2줄 본문 블록 (합 + gap = [_kTalkAskListThumbSide]).
const double _kTalkAskListTitleBlockH = 42.0;
const double _kTalkAskListBodyBlockH = 35.0;

String talkAskPlainBodyPreview(String? raw, {int maxLen = 220}) {
  if (raw == null || raw.isEmpty) return '';
  var t = raw.replaceAll(RegExp(r'<[^>]*>'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length > maxLen) return '${t.substring(0, maxLen)}…';
  return t;
}

String _displayAuthor(String author) =>
    author.startsWith('u/') ? author.substring(2) : author;

/// 리스트 행용 썸네일 URL (이미지 첫 장 또는 영상 썸네일).
String? _thumbUrlForPost(Post post) {
  if (post.hasImage && post.imageUrls.isNotEmpty) {
    final u = post.imageUrls.first.trim();
    if (u.isNotEmpty) return u;
  }
  final v = post.videoThumbnailUrl?.trim();
  if (v != null && v.isNotEmpty) return v;
  return null;
}

Widget _talkAskListThumbnail(String url) {
  return SizedBox(
    width: _kTalkAskListThumbSide,
    height: _kTalkAskListThumbSide,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: OverflowBox(
        maxWidth: _kTalkAskListThumbSide,
        maxHeight: _kTalkAskListThumbSide,
        minWidth: _kTalkAskListThumbSide,
        minHeight: _kTalkAskListThumbSide,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: _kTalkAskListThumbSide,
          height: _kTalkAskListThumbSide,
        ),
      ),
    ),
  );
}

class _TalkListAuthorAvatar extends StatelessWidget {
  const _TalkListAuthorAvatar({
    required this.photoUrl,
    required this.author,
    this.authorUid,
    this.colorIndex,
    this.size = _kTalkAskListAuthorAvatarSize,
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

  Widget _default() {
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
          size: size * 0.55,
          color: UserProfileService.iconColorFromIndex(idx),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = authorUid?.trim();
    Widget child;
    final url = photoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      child = ClipOval(
        child: OptimizedNetworkImage.avatar(
          imageUrl: url,
          size: size,
          errorWidget: _default(),
        ),
      );
    } else {
      child = _default();
    }
    if (uid == null || uid.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfileFromAuthorUid(context, uid),
      child: child,
    );
  }
}

const Color _kTalkAskRowDividerLight = Color(0xFFEEEEEE);

/// [FeedPostCard] 톡·에스크 카드 배경과 동일 톤 — 리스트 행도 한 덩어리로 보이게.
Color _talkAskListRowFillColor(BuildContext context, ColorScheme cs, Post post) {
  final theme = Theme.of(context);
  final baseCardColor = theme.cardTheme.color ?? cs.surface;
  final boardKind = postDisplayType(post);
  if (boardKind != 'talk' && boardKind != 'ask') return baseCardColor;
  return Color.lerp(
        baseCardColor,
        Colors.black,
        theme.brightness == Brightness.dark ? 0.18 : 0.17,
      ) ??
      baseCardColor;
}

/// 톡·에스크 피드 — 구분선 리스트(헤더·본문+썸네일·하트·댓글).
/// 하트는 [FeedPostCard]와 동일하게 상세 이동과 분리([TalkAskHeartVote] + 토글).
class TalkAskFeedListRow extends StatefulWidget {
  const TalkAskFeedListRow({
    super.key,
    required this.post,
    required this.colorScheme,
    this.showLeadingDivider = true,
    this.onTap,
  });

  final Post post;
  final ColorScheme colorScheme;
  final bool showLeadingDivider;
  final VoidCallback? onTap;

  @override
  State<TalkAskFeedListRow> createState() => _TalkAskFeedListRowState();
}

class _TalkAskFeedListRowState extends State<TalkAskFeedListRow> {
  int _voteState = 0;
  late int _displayCount;
  Timer? _likeDebounce;

  @override
  void initState() {
    super.initState();
    _displayCount = widget.post.likeCount;
    _syncVoteFromPost();
  }

  @override
  void dispose() {
    _likeDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TalkAskFeedListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id == widget.post.id &&
        (oldWidget.post.likedBy != widget.post.likedBy ||
            oldWidget.post.likeCount != widget.post.likeCount)) {
      _displayCount = widget.post.likeCount;
      _syncVoteFromPost();
    }
  }

  void _syncVoteFromPost() {
    final uid = AuthService.instance.currentUser.value?.uid;
    final liked = uid != null && widget.post.likedBy.contains(uid);
    final next = liked ? 1 : 0;
    if (_voteState != next) setState(() => _voteState = next);
  }

  Future<void> _onHeartTap() async {
    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
      return;
    }
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
    final prevVoteForNet = nowLiked ? 0 : 1;
    final snapCount = _displayCount;
    _likeDebounce?.cancel();
    _likeDebounce = Timer(const Duration(milliseconds: 350), () async {
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
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? cs.outline.withValues(alpha: 0.35)
        : _kTalkAskRowDividerLight;
    final preview = talkAskPlainBodyPreview(widget.post.body);
    final nickname = _displayAuthor(widget.post.author);
    final thumbUrl = _thumbUrlForPost(widget.post);
    const titleFontSize = 16.0;
    const bodyFontSize = 12.0;
    final titleStyleList = GoogleFonts.notoSansKr(
      fontSize: titleFontSize,
      fontWeight: FontWeight.w700,
      height: _kTalkAskListTitleBlockH / 2 / titleFontSize,
      letterSpacing: -0.25,
      color: AppColors.homeBoardTitleForeground(cs),
    );
    final bodyStyleList = GoogleFonts.notoSansKr(
      fontSize: bodyFontSize,
      fontWeight: FontWeight.w400,
      height: _kTalkAskListBodyBlockH / 2 / bodyFontSize,
      color: isDark ? cs.onSurfaceVariant : const Color(0xFF555555),
    );

    Widget? thumb;
    if (thumbUrl != null) {
      thumb = _talkAskListThumbnail(thumbUrl);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showLeadingDivider)
          Divider(height: 1, thickness: 1, color: dividerColor),
        Material(
          color: _talkAskListRowFillColor(context, cs, widget.post),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _TalkListAuthorAvatar(
                            photoUrl: widget.post.authorPhotoUrl,
                            author: widget.post.author,
                            authorUid: widget.post.authorUid,
                            colorIndex: widget.post.authorAvatarColorIndex,
                            size: _kTalkAskListAuthorAvatarSize,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: nickname,
                                    style: appUnifiedNicknameStyle(cs).copyWith(
                                      height: 1.2,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' · ${widget.post.timeAgo}',
                                    style: appUnifiedNicknameMetaTimeStyle(cs)
                                        .copyWith(height: 1.2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (thumb == null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.post.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyleList,
                            ),
                            if (preview.isNotEmpty) ...[
                              const SizedBox(height: _kTalkAskListTitleBodyGap),
                              Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: bodyStyleList,
                              ),
                            ],
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: _kTalkAskListThumbSide,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      height: _kTalkAskListTitleBlockH,
                                      width: double.infinity,
                                      child: Text(
                                        widget.post.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: titleStyleList,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: _kTalkAskListTitleBodyGap,
                                    ),
                                    SizedBox(
                                      height: _kTalkAskListBodyBlockH,
                                      width: double.infinity,
                                      child: Text(
                                        preview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: bodyStyleList,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            thumb,
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: Row(
                  children: [
                    TalkAskHeartVote(
                      voteState: _voteState,
                      count: _displayCount,
                      onTap: _onHeartTap,
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.message_circle,
                              size: 13,
                              color: feedInlineActionMutedForeground(cs),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatCompactCount(widget.post.comments),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.0,
                                color: feedInlineActionMutedForeground(cs),
                              ),
                            ),
                          ],
                        ),
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
}
