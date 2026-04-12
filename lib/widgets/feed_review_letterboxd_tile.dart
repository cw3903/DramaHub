import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post.dart';
import '../screens/write_post_page.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import 'country_scope.dart';
import 'optimized_network_image.dart';

/// DramaFeed Reviews 탭용 — 카드 없이 구분선 스타일 리스트 아이템
class FeedReviewLetterboxdTile extends StatelessWidget {
  const FeedReviewLetterboxdTile({
    super.key,
    required this.post,
    this.onTap,
    /// 썸네일 오른쪽 열 **하단**에 붙일 위젯(좋아요·댓글 등). 지정 시 본문은 위쪽, 이 영역은 썸네일 하단과 맞춤.
    this.thumbTrailingActions,
    /// 드라마 제목·포스터 탭 시 (상세 이동 등). 지정 시 제목·썸네일만 반응.
    this.onDramaTap,
    /// 리뷰 본문 영역 탭(좋아요·댓글 줄 제외). 댓글 펼침 등.
    this.onReviewBodyTap,
    /// 별점 행 탭 시 (드라마 상세 리뷰 섹션으로 스크롤 등).
    this.onRatingTap,
    /// 로그인 작성자 표기(게시글 `author`와 동일 형식). 내 글이면 닉네임 아래 수정·삭제 표시.
    this.currentUserAuthor,
    this.onPostUpdated,
    this.onPostDeleted,
  });

  final Post post;
  final VoidCallback? onTap;
  final Widget? thumbTrailingActions;
  final VoidCallback? onDramaTap;
  final VoidCallback? onReviewBodyTap;
  final VoidCallback? onRatingTap;
  final String? currentUserAuthor;
  final void Function(Post)? onPostUpdated;
  final void Function(Post)? onPostDeleted;

  static const double _thumbW = 68;
  static const double _thumbH = 96;
  static const double _thumbRadius = 4;

  /// 리스트 구분선 ~ 제목행까지 세로 패딩(이 값을 기준으로 썸네일 쪽 간격도 맞춤).
  static const double _gapDividerToTitleRow = 12;

  static const Color _starOrange = Color(0xFFFFB020);

  static Color _reviewTapSplash(ColorScheme cs) => cs.primary.withValues(alpha: 0.14);
  static Color _reviewTapHighlight(ColorScheme cs) => cs.primary.withValues(alpha: 0.08);

  /// 0.5점: `star_half`는 오른쪽 빈 윤곽이 보이므로, 꽉 찬 별의 왼쪽 절반만 잘라서만 표시.
  static Widget _filledHalfStarOnly(double iconSize, Color color) {
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 0.5,
        child: Icon(Icons.star_rounded, size: iconSize, color: color),
      ),
    );
  }

  /// 채워진 별(+0.5면 반쪽 채움만)만 표시. 빈 테두리 별은 넣지 않음.
  static Widget _starRow(double rating, double thumbWidth) {
    final units = (rating.clamp(0.0, 5.0) * 2).round().clamp(0, 10);
    final fullCount = units ~/ 2;
    final hasHalf = units.isOdd;
    final starCount = fullCount + (hasHalf ? 1 : 0);
    if (starCount == 0) return const SizedBox.shrink();
    final slotW = thumbWidth / 5;
    final iconSize = (slotW * 0.82).clamp(14.0, 22.0);
    return SizedBox(
      width: starCount * slotW,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(starCount, (i) {
          final isHalf = hasHalf && i == fullCount;
          return SizedBox(
            width: slotW,
            child: Center(
              child: isHalf
                  ? _filledHalfStarOnly(iconSize, _starOrange)
                  : Icon(Icons.star_rounded, size: iconSize, color: _starOrange),
            ),
          );
        }),
      ),
    );
  }

  String _displayAuthor(String author) =>
      author.startsWith('u/') ? author.substring(2) : author;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    final thumb = post.dramaThumbnail?.trim();
    final hasHttpThumb = thumb != null && thumb.startsWith('http');
    final dramaTitle =
        post.dramaTitle?.trim().isNotEmpty == true ? post.dramaTitle! : post.title;
    final body = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final r = (post.rating ?? 0).clamp(0.0, 5.0);

    final bodyStyle = GoogleFonts.notoSansKr(
      fontSize: 13,
      height: 1.35,
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );

    Widget bodyText = Text(
      body.isEmpty ? ' ' : body,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: bodyStyle,
    );

    if (post.hasSpoiler) {
      bodyText = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Text(
              body.isEmpty ? ' ' : body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.get('reviewSpoilerDisclaimer'),
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant.withValues(alpha: 0.9),
            ),
          ),
        ],
      );
    }

    final titleStyle = GoogleFonts.notoSansKr(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      height: 1.2,
    );

    /// 제목은 글자 너비만 드라마 탭 (Expanded로 가로 꽉 차지 않게).
    final Widget dramaTitleWidget = onDramaTap != null
        ? Material(
            type: MaterialType.transparency,
            color: Colors.transparent,
            child: InkWell(
              onTap: onDramaTap,
              splashColor: _reviewTapSplash(cs),
              highlightColor: _reviewTapHighlight(cs),
              borderRadius: BorderRadius.circular(6),
              child: Text(
                dramaTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: titleStyle,
              ),
            ),
          )
        : Text(
            dramaTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: titleStyle,
          );

    final Widget thumbChild = hasHttpThumb
        ? OptimizedNetworkImage(
            imageUrl: thumb,
            width: _thumbW,
            height: _thumbH,
            fit: BoxFit.cover,
            memCacheWidth: 136,
            memCacheHeight: 192,
          )
        : Container(
            width: _thumbW,
            height: _thumbH,
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant, size: 26),
          );

    final Widget thumbBlock = onDramaTap != null
        ? Material(
            type: MaterialType.transparency,
            color: Colors.transparent,
            child: InkWell(
              onTap: onDramaTap,
              splashColor: _reviewTapSplash(cs),
              highlightColor: _reviewTapHighlight(cs),
              borderRadius: BorderRadius.circular(_thumbRadius),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_thumbRadius),
                child: thumbChild,
              ),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(_thumbRadius),
            child: thumbChild,
          );

    final authorRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            _displayAuthor(post.author),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _LetterboxdAuthorAvatar(
          photoUrl: post.authorPhotoUrl,
          author: post.author,
          colorIndex: post.authorAvatarColorIndex,
          size: 26,
        ),
      ],
    );

    final bool isMyReview =
        currentUserAuthor != null && post.author == currentUserAuthor;
    final bool showOwnerActions =
        isMyReview && (onPostUpdated != null || onPostDeleted != null);
    final linkStyle = GoogleFonts.notoSansKr(
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    final Widget? ownerActionRow = showOwnerActions
        ? Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onPostUpdated != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: cs.primary,
                    ),
                    onPressed: () async {
                      final updated = await Navigator.push<Post>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WritePostPage(
                            initialPost: post,
                            initialBoard: 'review',
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      if (updated != null) onPostUpdated!(updated);
                    },
                    child: Text(s.get('edit'), style: linkStyle),
                  ),
                if (onPostUpdated != null && onPostDeleted != null)
                  Text(
                    '·',
                    style: linkStyle.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                    ),
                  ),
                if (onPostDeleted != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: cs.error,
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(s.get('delete'), style: GoogleFonts.notoSansKr()),
                          content: Text(s.get('deletePostConfirm'), style: GoogleFonts.notoSansKr()),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                s.get('delete'),
                                style: GoogleFonts.notoSansKr(color: Theme.of(ctx).colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                      final ok = await PostService.instance.deletePost(post.id);
                      if (!context.mounted) return;
                      if (ok) onPostDeleted!(post);
                    },
                    child: Text(s.get('delete'), style: linkStyle.copyWith(color: cs.error)),
                  ),
              ],
            ),
          )
        : null;

    final Widget authorBlock = showOwnerActions && ownerActionRow != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              authorRow,
              ownerActionRow,
            ],
          )
        : authorRow;

    /// 본문 탭은 카드 전역 `InkWell`(투명 스플래시)에서 처리. 여기서는 텍스트만 둔다.
    final Widget bodyForTap = bodyText;

    // 제목은 1줄만. Expanded + Align(가로 꽉 참)으로 닉네임 영역까지의 최대 폭을 주고, 넘치면 … 처리.
    // widthFactor:1 이었을 때는 자식 내재 폭만 쓰면서 긴 제목이 닉네임을 침범할 수 있었다.
    final Widget headerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: dramaTitleWidget,
          ),
        ),
        const SizedBox(width: 8),
        authorBlock,
      ],
    );

    final Widget starRowWidget = onRatingTap != null
        ? Material(
            type: MaterialType.transparency,
            color: Colors.transparent,
            child: InkWell(
              onTap: onRatingTap,
              splashColor: _reviewTapSplash(cs),
              highlightColor: _reviewTapHighlight(cs),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _starRow(r, _thumbW),
              ),
            ),
          )
        : _starRow(r, _thumbW);

    final Widget ratingRow = Align(
      alignment: Alignment.centerLeft,
      child: starRowWidget,
    );

    final Widget rightColumnBody = thumbTrailingActions != null
        ? SizedBox(
            height: _thumbH,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: bodyForTap,
                  ),
                ),
                thumbTrailingActions!,
              ],
            ),
          )
        : bodyForTap;

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(16, _gapDividerToTitleRow, 16, _gapDividerToTitleRow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headerRow,
          const SizedBox(height: 2),
          ratingRow,
          // 구분선~제목 간격(12)을 기준으로, 별~썸네일 사이를 그 2배로 벌려 구분선에서 썸네일까지 여유 확보
          SizedBox(height: _gapDividerToTitleRow * 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumbBlock,
              const SizedBox(width: 12),
              Expanded(child: rightColumnBody),
            ],
          ),
        ],
      ),
    );

    // 카드 대부분 탭 → 댓글 펼침. 제목·별·썸네일·하트·댓글은 각각 안쪽 InkWell이 먼저 소비.
    if (onReviewBodyTap != null) {
      final hoverFill = cs.onSurface.withValues(alpha: 0.06);
      final pressFill = cs.onSurface.withValues(alpha: 0.1);
      content = Material(
        type: MaterialType.transparency,
        color: Colors.transparent,
        child: InkWell(
          onTap: onReviewBodyTap,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          // M3에서는 highlightColor/hoverColor 대신 overlayColor가 적용되는 경우가 많음
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return pressFill;
            if (states.contains(WidgetState.hovered)) return hoverFill;
            return null;
          }),
          child: content,
        ),
      );
    }

    final useWholeCardTap = onTap != null &&
        onDramaTap == null &&
        onReviewBodyTap == null &&
        onRatingTap == null;
    if (!useWholeCardTap) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _LetterboxdAuthorAvatar extends StatelessWidget {
  const _LetterboxdAuthorAvatar({
    required this.photoUrl,
    required this.author,
    this.colorIndex,
    this.size = 26,
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
        child: OptimizedNetworkImage.avatar(
          imageUrl: photoUrl!,
          size: size,
          errorWidget: _buildDefault(context),
        ),
      );
    }
    return _buildDefault(context);
  }

  Widget _buildDefault(BuildContext context) {
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
          size: size * 0.58,
          color: UserProfileService.iconColorFromIndex(idx),
        ),
      ),
    );
  }
}
