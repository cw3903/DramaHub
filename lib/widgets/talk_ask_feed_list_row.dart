import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../models/post.dart';
import '../theme/app_theme.dart'
    show AppColors, appUnifiedNicknameMetaTimeStyle, appUnifiedNicknameStyle;
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../utils/format_utils.dart';
import 'feed_inline_action_colors.dart';
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

/// 톡·에스크 피드 — 구분선 리스트(헤더·본문+썸네일·하트·댓글).
/// 하트·댓글 아이콘/숫자는 [PopularPostsTab._buildReviewInlineActionBar]와 동일 스케일.
class TalkAskFeedListRow extends StatelessWidget {
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

  static const Color _dividerLight = Color(0xFFEEEEEE);

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? cs.outline.withValues(alpha: 0.35)
        : _dividerLight;
    final preview = talkAskPlainBodyPreview(post.body);
    final nickname = _displayAuthor(post.author);
    final thumbUrl = _thumbUrlForPost(post);
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
        if (showLeadingDivider)
          Divider(height: 1, thickness: 1, color: dividerColor),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 21, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _TalkListAuthorAvatar(
                        photoUrl: post.authorPhotoUrl,
                        author: post.author,
                        authorUid: post.authorUid,
                        colorIndex: post.authorAvatarColorIndex,
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
                                text: ' · ${post.timeAgo}',
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
                          post.title,
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
                                    post.title,
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
                  const SizedBox(height: 16),
                  ValueListenableBuilder<User?>(
                    valueListenable: AuthService.instance.currentUser,
                    builder: (context, user, _) {
                      const iconSize = 13.0;
                      final uid = user?.uid;
                      final liked = uid != null && post.likedBy.contains(uid);
                      final actionFg = feedInlineActionMutedForeground(cs);
                      final countStyle = GoogleFonts.notoSansKr(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        color: actionFg,
                      );
                      // [_buildReviewInlineActionBar]와 동일: 그룹마다 horizontal 4 + 그룹 사이 4
                      return Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: iconSize,
                                  color: liked
                                      ? Colors.redAccent
                                      : actionFg,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  formatCompactCount(post.likeCount),
                                  style: countStyle,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
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
                                  formatCompactCount(post.comments),
                                  style: countStyle,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
