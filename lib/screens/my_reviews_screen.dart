import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/review_service.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/user_profile_service.dart';
import '../utils/format_utils.dart';
import '../widgets/app_bar_back_icon_button.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';

/// 프로필 내 리뷰 목록 기본 — Letterboxd 스타일 녹색 별(레거시).
/// 즐겨찾기 작품 상세 등에서는 [filledColor]·[interStarGap]·[size]로 앱 공통 노랑 별로 바꿀 수 있음.
const Color _kMyReviewsListStarGreen = Color(0xFF00C46C);
const Color _kMyReviewsListStarYellow = Color(0xFFFFC107);

String? _posterUrlForMyReview(MyReviewItem item, String? country) {
  final id = item.dramaId.trim();
  if (id.isNotEmpty && !id.startsWith('short-')) {
    final u = DramaListService.instance.getDisplayImageUrl(id, country);
    if (u != null && u.isNotEmpty) return u;
  }
  final byTitle = DramaListService.instance.getDisplayImageUrlByTitle(
    item.dramaTitle,
    country,
  );
  if (byTitle != null && byTitle.isNotEmpty) return byTitle;
  return null;
}

class _MyReviewsListStarRow extends StatelessWidget {
  const _MyReviewsListStarRow({
    required this.rating,
    this.size = 18,
    this.interStarGap = 1.0,
    this.filledColor,
    /// [star_rounded] 좌우 여백 보정. 값이 있으면 두 번째 별부터 왼쪽으로 당겨 간격 축소.
    this.glyphOverlap,
  });

  final double rating;
  final double size;
  /// 별 아이콘 사이 오른쪽 여백(픽셀). 0에 가까울수록 더 촘촘함.
  final double interStarGap;
  final Color? filledColor;
  final double? glyphOverlap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = cs.onSurfaceVariant.withValues(alpha: 0.28);
    final fill = filledColor ?? _kMyReviewsListStarGreen;
    final r = rating.clamp(0.0, 5.0);
    final overlap = glyphOverlap;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starValue = i + 1.0;
        final isFull = r >= starValue;
        final isHalf = r >= starValue - 0.5 && r < starValue;
        late IconData icon;
        late Color color;
        if (isFull) {
          icon = Icons.star_rounded;
          color = fill;
        } else if (isHalf) {
          icon = Icons.star_half_rounded;
          color = fill;
        } else {
          icon = Icons.star_border_rounded;
          color = empty;
        }
        if (overlap != null && overlap > 0 && i > 0) {
          return Transform.translate(
            offset: Offset(-overlap * i, 0),
            child: Icon(icon, size: size, color: color),
          );
        }
        return Padding(
          padding: EdgeInsets.only(right: i < 4 ? interStarGap : 0),
          child: Icon(icon, size: size, color: color),
        );
      }),
    );
  }
}

/// 프로필 → Reviews: 제목, 별점, 별 아래 본문 (썸네일 없음)
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    ReviewService.instance.refresh();
    DramaListService.instance.loadFromAsset();
  }

  void _openSortSheet(BuildContext context, dynamic s) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sheetCs = Theme.of(ctx).colorScheme;
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          decoration: BoxDecoration(
            color: sheetCs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    s.get('myReviewsSortTitle'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: sheetCs.onSurface,
                    ),
                  ),
                ),
                ListTile(
                  title: Text(
                    s.get('myReviewsSortNewest'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      color: sheetCs.onSurface,
                    ),
                  ),
                  trailing: _newestFirst
                      ? Icon(Icons.check, color: cs.primary, size: 22)
                      : null,
                  onTap: () {
                    setState(() => _newestFirst = true);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  title: Text(
                    s.get('myReviewsSortOldest'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      color: sheetCs.onSurface,
                    ),
                  ),
                  trailing: !_newestFirst
                      ? Icon(Icons.check, color: cs.primary, size: 22)
                      : null,
                  onTap: () {
                    setState(() => _newestFirst = false);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        centerTitle: true,
        title: Text(
          s.get('tabReviews'),
          style: GoogleFonts.notoSansKr(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.12,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: AppBarBackIconButton(
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.sliders_horizontal, color: cs.onSurface),
            tooltip: s.get('myReviewsSortTitle'),
            onPressed: () => _openSortSheet(context, s),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          ReviewService.instance.listNotifier,
          DramaListService.instance.extraNotifier,
        ]),
        builder: (context, _) {
          final raw = ReviewService.instance.listNotifier.value;
          if (raw.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.star,
                      size: 56,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      s.get('myReviewsEmptyTitle'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.get('myReviewsEmptyHint'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        height: 1.45,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final list = List<MyReviewItem>.from(raw);
          if (_newestFirst) {
            list.sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
          } else {
            list.sort((a, b) => a.writtenAt.compareTo(b.writtenAt));
          }

          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            itemCount: list.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: cs.outline.withValues(alpha: 0.12),
            ),
            itemBuilder: (context, index) {
              return LetterboxdMyReviewTile(
                item: list[index],
                dramaTitleOnSurfaceAlpha: 0.8,
                reviewBodyFontSize: 12.5,
              );
            },
          );
        },
      ),
    );
  }
}

/// 프로필 Reviews 목록 — 우측 포스터 썸네일.
class _MyReviewListPosterThumb extends StatelessWidget {
  const _MyReviewListPosterThumb({required this.item, required this.cs});

  final MyReviewItem item;
  final ColorScheme cs;

  static const double _w = 48;
  static const double _h = 72;

  @override
  Widget build(BuildContext context) {
    final country = CountryScope.maybeOf(context)?.country;
    final url = _posterUrlForMyReview(item, country)?.trim();
    if (url != null && url.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: _w,
          height: _h,
          child: OptimizedNetworkImage(
            imageUrl: url,
            width: _w,
            height: _h,
            fit: BoxFit.cover,
            memCacheWidth: 160,
            memCacheHeight: 240,
            errorWidget: ColoredBox(
              color: cs.surfaceContainerHighest,
              child: Icon(
                LucideIcons.tv,
                size: 22,
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      );
    }
    if (url != null && url.startsWith('assets/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: _w,
          height: _h,
          child: Image.asset(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: cs.surfaceContainerHighest,
              child: Icon(
                LucideIcons.tv,
                size: 22,
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: cs.surfaceContainerHighest,
        child: SizedBox(
          width: _w,
          height: _h,
          child: Icon(
            LucideIcons.tv,
            size: 22,
            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

String? _releaseYearLabel(String dramaId, String dramaTitle, String? country) {
  if (dramaId.isNotEmpty) {
    final d = DramaListService.instance.getExtra(dramaId)?.releaseDate;
    if (d != null) return '${d.year}';
  }
  if (dramaTitle.trim().isEmpty) return null;
  for (final item in DramaListService.instance.list) {
    final t = DramaListService.instance.getDisplayTitle(item.id, country);
    if (t == dramaTitle.trim() || item.title == dramaTitle.trim()) {
      final d = DramaListService.instance.getExtra(item.id)?.releaseDate;
      if (d != null) return '${d.year}';
      return null;
    }
  }
  return null;
}

DramaDetail _detailFromReview(BuildContext context, MyReviewItem item) {
  const similarList = [
    DramaItem(
      id: 's1',
      title: '사랑은 시간 뒤에 서다',
      subtitle: '비밀신분',
      views: '9.1M',
      rating: 4.5,
      isPopular: true,
    ),
    DramaItem(
      id: 's2',
      title: '폭풍같은 결혼생활',
      subtitle: '대여주',
      views: '45.3M',
      rating: 4.3,
      isNew: true,
    ),
    DramaItem(
      id: 's3',
      title: '동생이 훔친 사랑',
      subtitle: '로맨스',
      views: '2.1M',
      rating: 4.6,
      isPopular: true,
    ),
    DramaItem(
      id: 's4',
      title: '후회·집착남',
      subtitle: '독립적인 여성',
      views: '567K',
      rating: 3.5,
      isPopular: true,
    ),
  ];
  final locale = CountryScope.maybeOf(context)?.country;
  final displayTitle = item.dramaId.isNotEmpty
      ? (DramaListService.instance.getDisplayTitle(item.dramaId, locale).isNotEmpty
          ? DramaListService.instance.getDisplayTitle(item.dramaId, locale)
          : item.dramaTitle)
      : DramaListService.instance.getDisplayTitleByTitle(item.dramaTitle, locale);
  final dramaItem = DramaItem(
    id: item.dramaId,
    title: displayTitle,
    subtitle: '',
    views: '0',
    rating: item.rating,
    isPopular: false,
  );
  const fullSynopsis =
      '태성바이오 창립자 박창욱은 신분을 숨긴 채 청소부로 살아가고, 아들 정훈은 만삭의 아내 미연과 장차 이어질 가족의 행복을 꿈꾼다.';
  final userName =
      AuthService.instance.currentUser.value?.displayName?.split('@').first ??
      '나';
  final myReview = DramaReview(
    id: item.id,
    userName: userName,
    rating: item.rating,
    comment: item.comment,
    timeAgo: formatTimeAgo(item.writtenAt, locale),
    likeCount: 0,
    replies: const [],
    writtenAt: item.writtenAt,
  );
  final reviews = [myReview];
  final episodes = [
    const DramaEpisode(number: 1, title: '1화', duration: '45분'),
  ];
  final yearLabel =
      _releaseYearLabel(item.dramaId, item.dramaTitle, locale) ?? '2024';
  return DramaDetail(
    item: dramaItem,
    synopsis: fullSynopsis,
    year: yearLabel,
    genre: '',
    averageRating: item.rating,
    ratingCount: 1,
    episodes: episodes,
    reviews: reviews,
    similar: similarList,
  );
}

/// 즐겨찾기 활동 등: 프로필 닉네임·아바타와 동기화된 표시 이름.
String _reviewActivityDisplayName(MyReviewItem item) {
  final n = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (n != null && n.isNotEmpty) return n;
  final a = item.authorName?.trim();
  if (a != null && a.isNotEmpty) return a;
  final d = AuthService.instance.currentUser.value?.displayName?.trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('@')) return d.split('@').first;
    return d;
  }
  return 'Member';
}

String _avatarLetterFromName(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  final r = t.runes;
  if (r.isEmpty) return '?';
  final first = String.fromCharCode(r.first);
  return first.isEmpty ? '?' : first.toUpperCase();
}

/// 내 리뷰 한 줄 (내 리뷰 목록·즐겨찾기 작품 활동 화면 공통).
class LetterboxdMyReviewTile extends StatelessWidget {
  const LetterboxdMyReviewTile({
    super.key,
    required this.item,
    this.showDramaTitle = true,
    this.starSize,
    this.starInterGap,
    this.starFilledColor,
    this.starRowScale,
    /// 기본 리스트 별 줄에만 적용. null이면 기본값(겹침) 사용.
    this.starGlyphOverlap,
    /// true: 아바타 + (닉네임|별점 한 줄) + 본문 — Letterboxd 활동 피드 스타일.
    this.letterboxdActivityAuthorRow = false,
    /// 지정 시 닉네임 옆에 Edit 버튼 표시 (letterboxdActivityAuthorRow일 때만).
    this.onEdit,
    /// 지정 시 닉네임 옆에 Delete 버튼 표시 (letterboxdActivityAuthorRow일 때만).
    this.onDelete,
    /// letterboxdActivityAuthorRow일 때 오른쪽 닉네임 글자 크기. null이면 15.
    this.activityAuthorNameFontSize,
    /// 드라마 제목 색 (`onSurface` 알파). null이면 0.66 (프로필 리뷰 목록 등에서 더 밝게 지정 가능).
    this.dramaTitleOnSurfaceAlpha,
    /// 리뷰 본문 글자 크기. null이면 14.
    this.reviewBodyFontSize,
  });

  final MyReviewItem item;
  final bool showDramaTitle;
  final double? starSize;
  final double? starInterGap;
  final Color? starFilledColor;
  /// 1 미만이면 별 줄 전체를 가로로 살짝 축소해 간격을 더 좁게 보이게 함.
  final double? starRowScale;
  final double? starGlyphOverlap;
  final bool letterboxdActivityAuthorRow;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final double? activityAuthorNameFontSize;
  final double? dramaTitleOnSurfaceAlpha;
  final double? reviewBodyFontSize;

  static const double _verticalPadding = 14;

  String _displayTitle(BuildContext context) {
    final locale = CountryScope.maybeOf(context)?.country;
    if (item.dramaId.isNotEmpty) {
      final t = DramaListService.instance.getDisplayTitle(item.dramaId, locale);
      if (t.isNotEmpty) return t;
    }
    return DramaListService.instance.getDisplayTitleByTitle(
      item.dramaTitle,
      locale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final detail = _detailFromReview(context, item);
    final r = item.rating.clamp(0.0, 5.0);
    final rawComment = item.comment.replaceAll(RegExp(r'\s+'), ' ').trim();
    final bodyFontSize = reviewBodyFontSize ?? 14.0;
    final titleAlpha = dramaTitleOnSurfaceAlpha ?? 0.66;
    final bodyStyle = GoogleFonts.notoSansKr(
      fontSize: bodyFontSize,
      height: 1.45,
      color: cs.onSurfaceVariant.withValues(alpha: 0.88),
      fontWeight: FontWeight.w400,
    );
    final titleStyle = GoogleFonts.notoSansKr(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: cs.onSurface.withValues(alpha: titleAlpha.clamp(0.0, 1.0)),
      height: 1.15,
    );

    if (letterboxdActivityAuthorRow) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push<void>(
              context,
              CupertinoPageRoute<void>(
                builder: (_) =>
                    DramaDetailPage(detail: detail, scrollToRatings: true),
              ),
            );
          },
          child: ListenableBuilder(
            listenable: Listenable.merge([
              UserProfileService.instance.nicknameNotifier,
              UserProfileService.instance.profileImageUrlNotifier,
              UserProfileService.instance.avatarColorNotifier,
              AuthService.instance.currentUser,
            ]),
            builder: (context, _) {
              final displayName = _reviewActivityDisplayName(item);
              var url = UserProfileService.instance.profileImageUrlNotifier.value
                  ?.trim();
              if (url == null || url.isEmpty) {
                url = AuthService.instance.currentUser.value?.photoURL?.trim();
              }
              final colorIdx =
                  UserProfileService.instance.avatarColorNotifier.value ?? 0;
              final letter = _avatarLetterFromName(displayName);
              final fill = UserProfileService.bgColorFromIndex(colorIdx);
              final letterColor =
                  UserProfileService.iconColorFromIndex(colorIdx);
              const avatarD = 40.0;

              Widget avatar;
              final u = url;
              if (u != null && u.isNotEmpty && u.startsWith('http')) {
                avatar = ClipOval(
                  child: OptimizedNetworkImage.avatar(
                    imageUrl: u,
                    size: avatarD,
                    errorWidget: CircleAvatar(
                      radius: avatarD / 2,
                      backgroundColor: fill,
                      child: Text(
                        letter,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: letterColor,
                        ),
                      ),
                    ),
                  ),
                );
              } else {
                avatar = CircleAvatar(
                  radius: avatarD / 2,
                  backgroundColor: fill,
                  child: Text(
                    letter,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: letterColor,
                    ),
                  ),
                );
              }

              final nameStyle = GoogleFonts.notoSansKr(
                fontSize: activityAuthorNameFontSize ?? 15,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: cs.onSurface.withValues(alpha: 0.60),
              );
              Widget starRow = _MyReviewsListStarRow(
                rating: r,
                size: starSize ?? 16,
                interStarGap: starInterGap ?? 0,
                filledColor: starFilledColor ?? const Color(0xFFFFC107),
                glyphOverlap: 3,
              );

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              starRow,
                              if (onEdit != null) ...[
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: onEdit,
                                  child: Text(
                                    'Edit',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.82),
                                    ),
                                  ),
                                ),
                              ],
                              if (onDelete != null) ...[
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: onDelete,
                                  child: Text(
                                    'Delete',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.82),
                                    ),
                                  ),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: nameStyle,
                                ),
                              ),
                            ],
                          ),
                          if (rawComment.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              rawComment,
                              maxLines: 24,
                              overflow: TextOverflow.ellipsis,
                              style: bodyStyle,
                            ),
                          ] else if (r > 0) ...[
                            const SizedBox(height: 6),
                            Text('-', style: bodyStyle),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    Widget buildDefaultStarRow() {
      Widget row = _MyReviewsListStarRow(
        rating: r,
        size: starSize ?? 16,
        interStarGap: starInterGap ?? 0,
        filledColor: starFilledColor ?? _kMyReviewsListStarYellow,
        glyphOverlap: starGlyphOverlap ?? 3,
      );
      final sc = starRowScale;
      if (sc != null && sc > 0 && sc < 1) {
        row = Transform.scale(
          scale: sc,
          alignment: Alignment.centerLeft,
          child: row,
        );
      }
      return row;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push<void>(
            context,
            CupertinoPageRoute<void>(
              builder: (_) =>
                  DramaDetailPage(detail: detail, scrollToRatings: true),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            _verticalPadding,
            16,
            _verticalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDramaTitle) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: rawComment.isNotEmpty
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _displayTitle(context),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: buildDefaultStarRow(),
                            ),
                            if (rawComment.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                rawComment,
                                maxLines: 24,
                                overflow: TextOverflow.ellipsis,
                                style: bodyStyle,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _MyReviewListPosterThumb(item: item, cs: cs),
                    ],
                  ),
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: buildDefaultStarRow(),
                ),
                if (rawComment.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    rawComment,
                    maxLines: 24,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
