import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post.dart';
import '../screens/user_posts_screen.dart';
import '../screens/write_post_page.dart';
import '../config/app_moderators.dart';
import '../services/drama_list_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import 'country_scope.dart';
import 'optimized_network_image.dart';
import 'review_arrow_tag_chip.dart';

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

  /// 리스트 구분선 ~ 제목행까지 세로 패딩.
  static const double _gapDividerToTitleRow = 6;

  /// 제목(헤더) 행 ↔ 별점 행. 별~썸네일보다 좁게 두어 시각적으로 균형 맞춤.
  static const double _gapTitleToStars = 3;

  /// 별점 행 ↔ 썸네일 행.
  static const double _gapStarsToThumb = 5;

  static const Color _starOrange = Color(0xFFFFB020);

  static Color _reviewTapSplash(ColorScheme cs) => cs.primary.withValues(alpha: 0.14);
  static Color _reviewTapHighlight(ColorScheme cs) => cs.primary.withValues(alpha: 0.08);

  /// 반점 표기 — 위 1 · 사선 · 아래 2 (별 높이에 맞춤).
  static Widget _halfFractionLabel({
    required TextStyle halfLabelStyle,
    required double iconSize,
  }) {
    final color = halfLabelStyle.color ?? _starOrange;
    final digitSize = (iconSize * 0.40).clamp(11.0, 12.5);
    final slashSize = (iconSize * 0.58).clamp(15.0, 18.0);

    TextStyle digitStyle() => halfLabelStyle.copyWith(
          fontSize: digitSize,
          height: 1.0,
          fontWeight: FontWeight.w800,
          color: color,
        );

    TextStyle slashStyle() => halfLabelStyle.copyWith(
          fontSize: slashSize,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: color,
        );

    return SizedBox(
      width: iconSize * 0.78,
      height: iconSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            top: iconSize * 0.02,
            child: Text('1', style: digitStyle()),
          ),
          Center(
            child: Transform.rotate(
              angle: -0.92,
              child: Text('/', style: slashStyle()),
            ),
          ),
          Positioned(
            right: 0,
            bottom: iconSize * 0.04,
            child: Text('2', style: digitStyle()),
          ),
        ],
      ),
    );
  }

  /// 채워진 별만 표시(빈 테두리 별 없음). 0.5점은 반별 아이콘 대신 `1/2` 텍스트만 붙임.
  static Widget _starRow(
    double rating,
    double thumbWidth, {
    required TextStyle halfLabelStyle,
  }) {
    final units = (rating.clamp(0.0, 5.0) * 2).round().clamp(0, 10);
    final fullCount = units ~/ 2;
    final hasHalf = units.isOdd;
    final starCount = fullCount;
    if (starCount == 0 && !hasHalf) return const SizedBox.shrink();
    final slotW = thumbWidth / 5;
    final iconSize = (slotW * 0.82).clamp(14.0, 22.0);

    final Widget starsOnly = starCount > 0
        ? SizedBox(
            width: starCount * slotW,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                starCount,
                (i) => SizedBox(
                  width: slotW,
                  child: Center(
                    child: Icon(
                      Icons.star_rounded,
                      size: iconSize,
                      color: _starOrange,
                    ),
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    if (!hasHalf) return starsOnly;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (starCount > 0) starsOnly,
        Padding(
          padding: EdgeInsets.only(left: starCount > 0 ? 1 : 0),
          child: _halfFractionLabel(
            halfLabelStyle: halfLabelStyle,
            iconSize: iconSize,
          ),
        ),
      ],
    );
  }

  String _displayAuthor(String author) =>
      author.startsWith('u/') ? author.substring(2) : author;

  /// [UserPostsScreen] 등 작성자 식별용 (`u/닉네임` 형식).
  static String _authorNavKey(String author) {
    final t = author.trim();
    if (t.isEmpty) return '';
    return t.startsWith('u/') ? t : 'u/$t';
  }

  /// Firestore 제목이 `title_ko` 등과만 맞고 [getDisplayTitleByTitle]이 못 찾을 때(예: 띄어쓰기·대소문자).
  static String _displayTitleFromExtraLanguageMatch(
    String stored,
    String? country,
  ) {
    final st = stored.trim();
    if (st.isEmpty) return '';
    final extras = DramaListService.instance.extraNotifier.value;
    for (final e in extras.entries) {
      final ex = e.value;
      final ko = (ex.title_ko ?? '').trim();
      final en = (ex.title_en ?? '').trim();
      final ja = (ex.title_ja ?? '').trim();
      if (st == ko || st == en || st == ja) {
        final t = DramaListService.instance.getDisplayTitle(e.key, country);
        if (t.isNotEmpty) return t;
      }
    }
    return '';
  }

  /// 앱 언어(가입 국가) 기준 표시 제목 — Firestore `dramaTitle`(한글 저장 등)만 쓰면 영어 UI에서 한글이 남음.
  static String _displayDramaTitle(BuildContext context, Post post) {
    final country = CountryScope.maybeOf(context)?.country;
    final id = post.dramaId?.trim() ?? '';
    if (id.isNotEmpty && !id.startsWith('short-')) {
      final t = DramaListService.instance.getDisplayTitle(id, country);
      if (t.isNotEmpty) return t;
    }
    final stored = post.dramaTitle?.trim();
    if (stored != null && stored.isNotEmpty) {
      final byTitle =
          DramaListService.instance.getDisplayTitleByTitle(stored, country);
      if (byTitle.isNotEmpty && byTitle != stored) return byTitle;
      final fromExtras =
          _displayTitleFromExtraLanguageMatch(stored, country);
      if (fromExtras.isNotEmpty) return fromExtras;
      return stored;
    }
    return post.title.trim();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        DramaListService.instance.extraNotifier,
        DramaListService.instance.listNotifier,
      ]),
      builder: (context, _) => _buildWithCatalog(context),
    );
  }

  Widget _buildWithCatalog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    final bool isMyReview =
        currentUserAuthor != null && post.author == currentUserAuthor;
    final thumb = post.dramaThumbnail?.trim();
    final hasHttpThumb = thumb != null && thumb.startsWith('http');
    final dramaTitle = _displayDramaTitle(context, post);
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

    final Widget bodyForTap = bodyText;

    final titleStyle = GoogleFonts.notoSansKr(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Color.alphaBlend(
        cs.onSurface.withValues(alpha: 0.78),
        cs.surface,
      ),
      height: 1.0,
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

    final authorRowCore = Row(
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
          size: 22,
        ),
      ],
    );

    final navAuthor = _authorNavKey(post.author);
    final authorRow = navAuthor.isEmpty
        ? authorRowCore
        : Material(
            type: MaterialType.transparency,
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                final nav = navAuthor;
                final ctx = context;
                // 상위 InkWell(onReviewBodyTap) 등과 겹칠 때 Navigator 잠금 회피
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!ctx.mounted) return;
                  Navigator.push<void>(
                    ctx,
                    MaterialPageRoute<void>(
                      builder: (_) => UserPostsScreen(authorName: nav),
                    ),
                  );
                });
              },
              borderRadius: BorderRadius.circular(8),
              splashColor: _reviewTapSplash(cs),
              highlightColor: _reviewTapHighlight(cs),
              child: authorRowCore,
            ),
          );

    final bool canModeratorDelete =
        isAppModerator() && onPostDeleted != null && !isMyReview;
    final bool showOwnerActions = (isMyReview &&
            (onPostUpdated != null || onPostDeleted != null)) ||
        canModeratorDelete;
    final bool showEditInRow = isMyReview && onPostUpdated != null;
    final bool showDeleteInRow =
        onPostDeleted != null && (isMyReview || isAppModerator());
    final ownerActionGray = cs.onSurfaceVariant;
    final linkStyle = GoogleFonts.notoSansKr(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: ownerActionGray,
    );
    /// 수정·삭제 (인라인 피드에서는 댓글 아이콘 오른쪽에 붙임)
    Widget? ownerEditDeleteRow;
    if (showOwnerActions) {
      ownerEditDeleteRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showEditInRow)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: ownerActionGray,
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
          if (showEditInRow && showDeleteInRow)
            Text(
              '·',
              style: linkStyle.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.45),
              ),
            ),
          if (showDeleteInRow)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: Colors.redAccent,
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
              child: Text(
                s.get('delete'),
                style: linkStyle.copyWith(color: Colors.redAccent, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      );
    }

    // 제목·닉네임·프로필은 한 줄에서 세로 중앙 정렬. 수정·삭제는 그 아래 오른쪽.
    final Widget headerRow = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: dramaTitleWidget,
              ),
            ),
            const SizedBox(width: 8),
            authorRow,
          ],
        ),
        if (ownerEditDeleteRow != null && thumbTrailingActions == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: ownerEditDeleteRow,
            ),
          ),
      ],
    );

    final halfStarLabelStyle = GoogleFonts.notoSansKr(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.0,
      color: _starOrange,
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
                padding: EdgeInsets.zero,
                child: _starRow(r, _thumbW, halfLabelStyle: halfStarLabelStyle),
              ),
            ),
          )
        : _starRow(r, _thumbW, halfLabelStyle: halfStarLabelStyle);

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
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      thumbTrailingActions!,
                      if (post.tags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var i = 0; i < post.tags.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  ReviewArrowTagChip(
                                    label: post.tags[i],
                                    compact: true,
                                    maxLabelWidth: 100,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (ownerEditDeleteRow != null) ...[
                        const SizedBox(width: 8),
                        ownerEditDeleteRow,
                      ],
                    ],
                  ),
                ),
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
          SizedBox(height: _gapTitleToStars),
          ratingRow,
          SizedBox(height: _gapStarsToThumb),
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
