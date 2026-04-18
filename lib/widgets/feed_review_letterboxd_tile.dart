import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../screens/user_posts_screen.dart';
import '../screens/write_post_page.dart';
import '../config/app_moderators.dart';
import '../services/drama_list_service.dart';
import '../services/post_service.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import 'country_scope.dart';
import 'feed_review_star_row.dart';
import 'optimized_network_image.dart';
import 'app_delete_confirm_dialog.dart';
import 'review_arrow_tag_chip.dart';
import 'review_card_tap_highlight.dart';
import 'user_profile_nav.dart';
import 'drama_review_feed_tile.dart' show kDramaReviewFeedVerticalGap;

/// 세로 히트만 넓히고 레이아웃 높이는 유지한다.
class _ExpandVerticalHitTest extends SingleChildRenderObjectWidget {
  const _ExpandVerticalHitTest({
    required this.extraTop,
    required this.extraBottom,
    super.child,
  });

  final double extraTop;
  final double extraBottom;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderExpandVerticalHit(
      extraTop: extraTop,
      extraBottom: extraBottom,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderExpandVerticalHit renderObject,
  ) {
    renderObject
      ..extraTop = extraTop
      ..extraBottom = extraBottom;
  }
}

class _RenderExpandVerticalHit extends RenderProxyBox {
  _RenderExpandVerticalHit({
    required double extraTop,
    required double extraBottom,
    RenderBox? child,
  })  : _extraTop = extraTop,
        _extraBottom = extraBottom,
        super(child);

  double _extraTop;
  double _extraBottom;

  double get extraTop => _extraTop;
  set extraTop(double value) {
    if (_extraTop == value) return;
    _extraTop = value;
  }

  double get extraBottom => _extraBottom;
  set extraBottom(double value) {
    if (_extraBottom == value) return;
    _extraBottom = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final expanded = Rect.fromLTRB(
      0.0,
      -_extraTop,
      size.width,
      size.height + _extraBottom,
    );
    if (!expanded.contains(position)) return false;
    return child.hitTest(result, position: position);
  }
}

/// [ReviewArrowTagChip] `compact` 세로 높이와 동일 — 에디트/딜리트 줄 정렬용.
const double _kLetterboxdCompactTagLineHeight = 19.0;

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
    /// 태그 칩 탭 시 (예: 통합 검색으로 이동).
    this.onTagTap,

    /// null이면 22. 글 상세 DramaFeed에서 본문·댓글과 맞출 때 지정.
    this.authorAvatarSize,
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
  final ValueChanged<String>? onTagTap;

  final double? authorAvatarSize;

  static const double _thumbW = kFeedReviewRatingThumbWidth;
  static const double _thumbH = 88;
  static const double _thumbRadius = 4;

  /// 리스트 구분선 ~ 제목행까지 세로 패딩.
  static const double _gapDividerToTitleRow = 15;

  /// 제목(헤더) 행 ↔ 별점 행.
  static const double _gapTitleToStars = 3;

  /// 별점 행 ↔ 썸네일 행.
  static const double _gapStarsToThumb = 5;

  static Color _reviewTapSplash(ColorScheme cs) =>
      cs.primary.withValues(alpha: 0.14);
  static Color _reviewTapHighlight(ColorScheme cs) =>
      cs.primary.withValues(alpha: 0.08);

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
      final byTitle = DramaListService.instance.getDisplayTitleByTitle(
        stored,
        country,
      );
      if (byTitle.isNotEmpty && byTitle != stored) return byTitle;
      final fromExtras = _displayTitleFromExtraLanguageMatch(stored, country);
      if (fromExtras.isNotEmpty) return fromExtras;
      return stored;
    }
    return post.title.trim();
  }

  // 본문 정규식: 매 빌드마다 새 객체 생성 방지
  static final _wsRe = RegExp(r'\s+');

  @override
  Widget build(BuildContext context) => _buildWithCatalog(context);

  Widget _buildWithCatalog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    final myUid = AuthService.instance.currentUser.value?.uid.trim();
    final isMineByUid =
        myUid != null &&
        myUid.isNotEmpty &&
        post.authorUid?.trim() == myUid;
    final mineAuthor =
        UserProfileService.instance.effectiveAuthorLabelForMyPost(
      isMineByUid: isMineByUid,
      currentUserAuthor: currentUserAuthor,
      postAuthor: post.author,
    );
    final canonicalAuthor = mineAuthor ?? post.author;
    final bool isMyReview =
        isMineByUid ||
        (currentUserAuthor != null && post.author == currentUserAuthor);
    final thumb = post.dramaThumbnail?.trim();
    final hasHttpThumb = thumb != null && thumb.startsWith('http');
    final dramaTitle = _displayDramaTitle(context, post);
    final body = (post.body ?? '').replaceAll(_wsRe, ' ').trim();
    final r = (post.rating ?? 0).clamp(0.0, 5.0);

    final bodyStyle = GoogleFonts.notoSansKr(
      fontSize: 12,
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
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppColors.homeBoardTitleForeground(cs),
      height: 1.0,
    );

    /// 제목은 글자 너비만 드라마 탭 (Expanded로 가로 꽉 차지 않게).
    final dramaTap = onDramaTap;
    final Widget dramaTitleWidget = dramaTap != null
        ? _TapBehindExpanded(
            onTap: dramaTap,
            outsets: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            borderRadius: BorderRadius.circular(6),
            splashColor: _reviewTapSplash(cs),
            highlightColor: _reviewTapHighlight(cs),
            child: Text(
              dramaTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: titleStyle,
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
            memCacheWidth: 124,
            memCacheHeight: 176,
          )
        : Container(
            width: _thumbW,
            height: _thumbH,
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(
              Icons.movie_outlined,
              color: cs.onSurfaceVariant,
              size: 26,
            ),
          );

    final Widget thumbBlock = dramaTap != null
        ? _TapBehindExpanded(
            onTap: dramaTap,
            outsets: const EdgeInsets.all(10),
            borderRadius: BorderRadius.circular(_thumbRadius),
            splashColor: _reviewTapSplash(cs),
            highlightColor: _reviewTapHighlight(cs),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_thumbRadius),
              child: thumbChild,
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
            _displayAuthor(canonicalAuthor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: appUnifiedNicknameStyle(cs),
          ),
        ),
        const SizedBox(width: 4),
        _LetterboxdAuthorAvatar(
          photoUrl: post.authorPhotoUrl,
          author: canonicalAuthor,
          authorUid: post.authorUid,
          colorIndex: post.authorAvatarColorIndex,
          size: authorAvatarSize ?? kAppUnifiedProfileAvatarSize,
        ),
      ],
    );

    final navAuthor = _authorNavKey(canonicalAuthor);
    final authorRow = navAuthor.isEmpty
        ? authorRowCore
        : _TapBehindExpanded(
            onTap: () {
              final ctx = context;
              final uid = post.authorUid?.trim();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!ctx.mounted) return;
                if (uid != null && uid.isNotEmpty) {
                  openUserProfileFromAuthorUid(ctx, uid);
                  return;
                }
                final nav = navAuthor;
                if (nav.isEmpty) return;
                Navigator.push<void>(
                  ctx,
                  MaterialPageRoute<void>(
                    builder: (_) => UserPostsScreen(authorName: nav),
                  ),
                );
              });
            },
            outsets: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            borderRadius: BorderRadius.circular(8),
            splashColor: _reviewTapSplash(cs),
            highlightColor: _reviewTapHighlight(cs),
            child: authorRowCore,
          );

    final bool canModeratorDelete =
        isAppModerator() && onPostDeleted != null && !isMyReview;
    final bool showOwnerActions =
        (isMyReview && (onPostUpdated != null || onPostDeleted != null)) ||
        canModeratorDelete;
    final bool showEditInRow = isMyReview && onPostUpdated != null;
    final bool showDeleteInRow =
        onPostDeleted != null && (isMyReview || isAppModerator());
    // Edit — 숫자 행과 톤 맞춘 회색 / Delete는 빨간색 유지.
    final editLinkColor = cs.onSurface.withValues(alpha: 0.48);
    final linkStyle = GoogleFonts.notoSansKr(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1.0,
      color: editLinkColor,
    );

    /// 수정·삭제 — 인라인: 하트·댓글 행 바로 오른쪽 / 비인라인: 본문 아래 오른쪽
    Widget? ownerEditDeleteRow;
    if (showOwnerActions) {
      ownerEditDeleteRow = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showEditInRow)
            _ExpandVerticalHitTest(
              extraTop: 10,
              extraBottom: 10,
              child: InkWell(
                onTap: () async {
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
                borderRadius: BorderRadius.circular(6),
                splashColor: _reviewTapSplash(cs),
                highlightColor: _reviewTapHighlight(cs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(s.get('edit'), style: linkStyle),
                ),
              ),
            ),
          if (showEditInRow && showDeleteInRow)
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(
                '·',
                style: linkStyle.copyWith(
                  color: editLinkColor.withValues(alpha: 0.55),
                ),
              ),
            ),
          if (showDeleteInRow)
            _ExpandVerticalHitTest(
              extraTop: 10,
              extraBottom: 10,
              child: InkWell(
                onTap: () async {
                  final confirmed = await showAppDeleteConfirmDialog(
                    context,
                    message: s.get('deletePostConfirm'),
                    cancelText: s.get('cancel'),
                    confirmText: s.get('delete'),
                  );
                  if (confirmed != true || !context.mounted) return;
                  final ok = await PostService.instance.deletePost(
                    post.id,
                    postIfKnown: post,
                  );
                  if (!context.mounted) return;
                  if (ok) onPostDeleted!(post);
                },
                borderRadius: BorderRadius.circular(6),
                splashColor: _reviewTapSplash(cs),
                highlightColor: _reviewTapHighlight(cs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    s.get('delete'),
                    style: linkStyle.copyWith(
                      color: kAppDeleteActionColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // 제목(좌) + 닉네임(우). 수정·삭제는 하트·댓글 행 오른쪽(인라인) 또는 본문 아래.
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
                child: dramaTap != null
                    ? ReviewCardSuppressParentTap(child: dramaTitleWidget)
                    : dramaTitleWidget,
              ),
            ),
            const SizedBox(width: 8),
            ReviewCardSuppressParentTap(child: authorRow),
          ],
        ),
      ],
    );

    final ratingTap = onRatingTap;
    final Widget starRowWidget = ratingTap != null
        ? _TapBehindExpanded(
            onTap: ratingTap,
            outsets: const EdgeInsets.fromLTRB(6, 2, 6, 4),
            borderRadius: BorderRadius.circular(6),
            splashColor: _reviewTapSplash(cs),
            highlightColor: _reviewTapHighlight(cs),
            child: FeedReviewRatingStars(rating: r, layoutThumbWidth: _thumbW),
          )
        : FeedReviewRatingStars(rating: r, layoutThumbWidth: _thumbW);

    final Widget ratingRow = Align(
      alignment: Alignment.centerLeft,
      child: ReviewCardSuppressParentTap(child: starRowWidget),
    );

    final Widget rightColumnBody = thumbTrailingActions != null
        ? SizedBox(
            height: _thumbH,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(alignment: Alignment.topLeft, child: bodyForTap),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: kDramaReviewFeedVerticalGap,
                    ),
                    child: SizedBox(
                      height: _kLetterboxdCompactTagLineHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          thumbTrailingActions!,
                        if (ownerEditDeleteRow != null) ...[
                          const SizedBox(width: 6),
                          ReviewCardSuppressParentTap(
                            child: Material(
                              type: MaterialType.transparency,
                              child: ownerEditDeleteRow,
                            ),
                          ),
                        ],
                        if (post.tags.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (var i = 0;
                                      i < post.tags.length;
                                      i++) ...[
                                    if (i > 0) const SizedBox(width: 6),
                                    ReviewCardSuppressParentTap(
                                      child: ReviewArrowTagChip(
                                        label: post.tags[i],
                                        compact: true,
                                        maxLabelWidth: 100,
                                        onTap: onTagTap != null
                                            ? () =>
                                                onTagTap!(post.tags[i].trim())
                                            : null,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                ),
              ],
            ),
          )
        : (ownerEditDeleteRow != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bodyForTap,
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ReviewCardSuppressParentTap(
                          child: Material(
                            type: MaterialType.transparency,
                            child: ownerEditDeleteRow,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : bodyForTap);

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        _gapDividerToTitleRow,
        16,
        _gapDividerToTitleRow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          headerRow,
          SizedBox(height: _gapTitleToStars),
          ratingRow,
          SizedBox(height: _gapStarsToThumb),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dramaTap != null
                  ? ReviewCardSuppressParentTap(child: thumbBlock)
                  : thumbBlock,
              const SizedBox(width: 12),
              Expanded(child: rightColumnBody),
            ],
          ),
        ],
      ),
    );

    // 카드 대부분 탭 → 댓글 펼침. 제목·별·썸네일·하트·댓글은 각각 안쪽 InkWell이 먼저 소비.
    if (onReviewBodyTap != null) {
      content = ReviewCardTapHighlight(
        onTap: onReviewBodyTap!,
        pressColor: cs.onSurface.withValues(alpha: 0.12),
        child: content,
      );
    }

    final useWholeCardTap =
        onTap != null &&
        onDramaTap == null &&
        onReviewBodyTap == null &&
        onRatingTap == null;
    if (!useWholeCardTap) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// 레이아웃·시각 크기는 [child]만큼이고, 터치만 [outsets]만큼 바깥으로 넓힘.
class _TapBehindExpanded extends StatelessWidget {
  const _TapBehindExpanded({
    required this.child,
    required this.onTap,
    required this.outsets,
    required this.borderRadius,
    required this.splashColor,
    required this.highlightColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets outsets;
  final BorderRadius borderRadius;
  final Color splashColor;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -outsets.left,
            top: -outsets.top,
            right: -outsets.right,
            bottom: -outsets.bottom,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              splashColor: splashColor,
              highlightColor: highlightColor,
              child: const SizedBox.expand(),
            ),
          ),
          IgnorePointer(child: child),
        ],
      ),
    );
  }
}

class _LetterboxdAuthorAvatar extends StatelessWidget {
  const _LetterboxdAuthorAvatar({
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
    final cs = Theme.of(context).colorScheme;
    final uid = authorUid?.trim();
    final borderColor = cs.outline.withValues(alpha: 0.38);

    Widget child;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      child = ClipOval(
        child: OptimizedNetworkImage.avatar(
          imageUrl: photoUrl!,
          size: size,
          errorWidget: _buildDefault(context),
        ),
      );
    } else {
      child = _buildDefault(context);
    }

    child = SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: child),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (uid == null || uid.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfileFromAuthorUid(context, uid),
      child: child,
    );
  }

  Widget _buildDefault(BuildContext context) {
    final idx = _resolvedIndex();
    final cs = Theme.of(context).colorScheme;
    final base = UserProfileService.bgColorFromIndex(idx);
    final fill = Color.alphaBlend(cs.surface.withValues(alpha: 0.55), base);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
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
