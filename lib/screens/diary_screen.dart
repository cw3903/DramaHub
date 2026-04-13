import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../models/profile_favorite.dart';
import '../services/auth_service.dart';
import '../services/country_service.dart';
import '../services/drama_list_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';
import '../widgets/app_bar_back_icon_button.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';

/// Favorites 작품 활동 다이어리 탭과 동일 — 노란 별.
const Color _kDiaryEntryStarYellow = Color(0xFFFFC107);

const List<String> _kMonthNamesEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _MonthSection {
  _MonthSection(this.year, this.month, WatchedDramaItem first)
      : items = [first];

  final int year;
  final int month;
  final List<WatchedDramaItem> items;
}

List<_MonthSection> _groupByMonth(
  List<WatchedDramaItem> list,
  bool newestFirst,
) {
  final sorted = List<WatchedDramaItem>.from(list)
    ..sort(
      (a, b) => newestFirst
          ? b.watchedAt.compareTo(a.watchedAt)
          : a.watchedAt.compareTo(b.watchedAt),
    );
  final groups = <_MonthSection>[];
  for (final item in sorted) {
    final y = item.watchedAt.year;
    final m = item.watchedAt.month;
    if (groups.isEmpty || groups.last.year != y || groups.last.month != m) {
      groups.add(_MonthSection(y, m, item));
    } else {
      groups.last.items.add(item);
    }
  }
  return groups;
}

String _monthHeaderLabel(String appCountry, int year, int month) {
  final mc = month.clamp(1, 12);
  switch (appCountry.toLowerCase()) {
    case 'kr':
      return '$mc월 $year';
    case 'jp':
    case 'cn':
      return '$year年$mc月';
    default:
      return '${_kMonthNamesEn[mc - 1]} $year';
  }
}

String? _resolveImageUrl(WatchedDramaItem item, String? country) {
  if (!item.id.startsWith('short-')) {
    final byId = DramaListService.instance.getDisplayImageUrl(item.id, country);
    if (byId != null && byId.isNotEmpty) return byId;
  }
  final byTitle =
      DramaListService.instance.getDisplayImageUrlByTitle(item.title, country);
  if (byTitle != null && byTitle.isNotEmpty) return byTitle;
  final url = item.imageUrl?.trim();
  if (url != null && url.isNotEmpty) return url;
  return null;
}

String _displayTitle(WatchedDramaItem item, String? country) {
  if (!item.id.startsWith('short-')) {
    final t = DramaListService.instance.getDisplayTitle(item.id, country);
    if (t.isNotEmpty) return t;
  }
  return DramaListService.instance.getDisplayTitleByTitle(item.title, country);
}

/// 즐겨찾기 작품과 동일 시청 기록인지 (다이어리·리뷰 매칭과 동일한 규칙).
bool watchedItemMatchesProfileFavorite(
  WatchedDramaItem item,
  ProfileFavorite f,
  String? country,
) {
  final fid = f.dramaId.trim();
  final iid = item.id.trim();
  if (fid.isNotEmpty && iid == fid) return true;
  final itemTitle = _displayTitle(item, country).trim();
  if (itemTitle.isEmpty) return false;
  String favDisplay;
  if (!f.dramaId.startsWith('short-')) {
    final t = DramaListService.instance.getDisplayTitle(f.dramaId, country);
    favDisplay = t.isNotEmpty ? t : f.dramaTitle.trim();
  } else {
    favDisplay = DramaListService.instance
        .getDisplayTitleByTitle(f.dramaTitle, country)
        .trim();
  }
  if (itemTitle == favDisplay) return true;
  if (itemTitle == f.dramaTitle.trim()) return true;
  if (item.title.trim() == f.dramaTitle.trim()) return true;
  return false;
}

/// [all] 중 이 즐겨찾기 작품에 해당하는 시청 기록만.
List<WatchedDramaItem> watchHistoryForFavorite(
  List<WatchedDramaItem> all,
  ProfileFavorite f,
  String? country,
) {
  return all
      .where((e) => watchedItemMatchesProfileFavorite(e, f, country))
      .toList();
}

/// 프로필 다이어리·즐겨찾기 활동 다이어리 탭 공통 — 시청 줄에서 상세용 [DramaItem].
DramaItem dramaItemForDiaryEntry(WatchedDramaItem item, String? country) {
  for (final it in DramaListService.instance.list) {
    if (it.id == item.id) return it;
  }
  return DramaItem(
    id: item.id,
    title: _displayTitle(item, country),
    subtitle: item.subtitle,
    views: item.views,
    imageUrl: item.imageUrl,
  );
}

String? _releaseYearForWatched(WatchedDramaItem item, String? country) {
  if (!item.id.startsWith('short-')) {
    final d = DramaListService.instance.getExtra(item.id)?.releaseDate;
    if (d != null) return '${d.year}';
  }
  final t = item.title.trim();
  if (t.isEmpty) return null;
  for (final it in DramaListService.instance.list) {
    final dt = DramaListService.instance.getDisplayTitle(it.id, country);
    if (dt == t || it.title == t) {
      final d = DramaListService.instance.getExtra(it.id)?.releaseDate;
      if (d != null) return '${d.year}';
      return null;
    }
  }
  return null;
}

MyReviewItem? _reviewForWatched(WatchedDramaItem item, String? country) {
  final byId = ReviewService.instance.getByDramaId(item.id);
  if (byId != null) return byId;
  final displayTitle = _displayTitle(item, country);
  for (final r in ReviewService.instance.listNotifier.value) {
    if (r.dramaTitle.trim() == displayTitle.trim() ||
        r.dramaTitle.trim() == item.title.trim()) {
      return r;
    }
  }
  return null;
}

/// 닉네임 → displayName → 이메일 @ 앞부분. 없으면 null → [diaryTitleWhenAnonymous] 사용.
String? _diaryOwnerDisplayName() {
  final n = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (n != null && n.isNotEmpty) return n;
  final d = AuthService.instance.currentUser.value?.displayName?.trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('@')) return d.split('@').first;
    return d;
  }
  final email = AuthService.instance.currentUser.value?.email?.trim();
  if (email != null && email.contains('@')) {
    final local = email.split('@').first.trim();
    if (local.isNotEmpty) return local;
  }
  return null;
}

/// Letterboxd Diary — 월별 고정 헤더 + 일·포스터·제목·메타 아이콘
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  bool _newestFirst = true;
  /// 프로필 탭 등 아래에 `primary` 스크롤이 있을 때 같은 PrimaryScrollController를 쓰면
  /// 이 화면이 스크롤되지 않는 경우가 있어 분리한다.
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.refresh();
    DramaListService.instance.loadFromAsset();
    ReviewService.instance.loadIfNeeded();
    UserProfileService.instance.loadIfNeeded();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  void _openDrama(BuildContext context, WatchedDramaItem item) {
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final dramaItem = dramaItemForDiaryEntry(item, country);
    final detail =
        DramaListService.instance.buildDetailForItem(dramaItem, country);
    Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => DramaDetailPage(detail: detail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final appCountry = CountryScope.of(context).country;

    return AnimatedBuilder(
      animation: Listenable.merge([
        WatchHistoryService.instance.listNotifier,
        ReviewService.instance.listNotifier,
        DramaListService.instance.listNotifier,
        DramaListService.instance.extraNotifier,
        UserProfileService.instance.favoritesNotifier,
        UserProfileService.instance.nicknameNotifier,
        AuthService.instance.currentUser,
      ]),
      builder: (context, _) {
        final owner = _diaryOwnerDisplayName();
        final titleText = (owner == null || owner.isEmpty)
            ? s.get('diaryTitleWhenAnonymous')
            : s.get('diaryTitleWithName').replaceAll('{name}', owner);
        final sortIconColor =
            cs.onSurfaceVariant.withValues(alpha: 0.78);
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            centerTitle: false,
            titleSpacing: 0,
            title: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: s.get('myReviewsSortTitle'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: sortIconColor,
                      backgroundColor: Colors.transparent,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _openSortSheet(context, s),
                    icon: Icon(
                      LucideIcons.sliders_horizontal,
                      size: 20,
                      color: sortIconColor,
                    ),
                  ),
                ],
              ),
            ),
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            leading: AppBarBackIconButton(
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _buildBody(context, cs, s, appCountry),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme cs,
    dynamic s,
    String appCountry,
  ) {
    final list = WatchHistoryService.instance.list;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.notebook,
                size: 56,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                s.get('diaryEmpty'),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final country = CountryScope.maybeOf(context)?.country ??
        CountryService.instance.countryNotifier.value;
    final groups = _groupByMonth(list, _newestFirst);
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final headerBg = Color.lerp(
          cs.surfaceContainerHighest,
          scaffoldBg,
          0.35,
        ) ??
        cs.surfaceContainerHighest;
    final headerFg = cs.onSurfaceVariant.withValues(alpha: 0.88);

    final slivers = <Widget>[];
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      final label = _monthHeaderLabel(appCountry, g.year, g.month);
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _DiaryMonthHeaderDelegate(
            label: label,
            background: headerBg,
            foreground: headerFg,
          ),
        ),
      );
      final children = <Widget>[];
      for (var ii = 0; ii < g.items.length; ii++) {
        final item = g.items[ii];
        final showDayNumber = ii == 0 ||
            (g.items[ii - 1].watchedAt.year != item.watchedAt.year ||
                g.items[ii - 1].watchedAt.month != item.watchedAt.month ||
                g.items[ii - 1].watchedAt.day != item.watchedAt.day);
        children.add(
          DiaryEntryRow(
            item: item,
            country: country,
            showDayNumber: showDayNumber,
            onTap: () => _openDrama(context, item),
          ),
        );
        if (ii < g.items.length - 1) {
          children.add(
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: cs.outline.withValues(alpha: 0.12),
            ),
          );
        }
      }
      slivers.add(
        SliverList(
          delegate: SliverChildListDelegate(children),
        ),
      );
    }

    return CustomScrollView(
      primary: false,
      controller: _scrollController,
      slivers: slivers,
    );
  }
}

class _DiaryMonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DiaryMonthHeaderDelegate({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  static const double _h = 32;

  @override
  double get minExtent => _h;

  @override
  double get maxExtent => _h;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      width: double.infinity,
      color: background,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          height: 1.0,
          color: foreground,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DiaryMonthHeaderDelegate oldDelegate) =>
      label != oldDelegate.label ||
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground;
}

/// 다이어리 목록 한 줄 (프로필 즐겨찾기 활동 화면에서도 재사용).
class DiaryEntryRow extends StatelessWidget {
  const DiaryEntryRow({
    super.key,
    required this.item,
    required this.country,
    required this.onTap,
    this.showDayNumber = true,
  });

  final WatchedDramaItem item;
  final String? country;
  final VoidCallback onTap;
  /// 같은 달·같은 날 연속 행이면 false → 일(day) 숫자는 첫 줄만 표시.
  final bool showDayNumber;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = item.watchedAt.day.toString();
    final title = _displayTitle(item, country);
    final year = _releaseYearForWatched(item, country);
    final imageUrl = _resolveImageUrl(item, country);
    final review = _reviewForWatched(item, country);
    final rating = review != null && review.rating > 0 ? review.rating : null;
    final hasReviewText = review?.comment.trim().isNotEmpty ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 32,
                child: Visibility(
                  visible: showDayNumber,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 26,
                      fontWeight: FontWeight.w200,
                      height: 1.0,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  width: 32,
                  height: 48,
                  child: _DiaryThumb(imageUrl: imageUrl, cs: cs),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: title,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: cs.onSurface.withValues(alpha: 0.72),
                            ),
                          ),
                          if (year != null && year.isNotEmpty)
                            TextSpan(
                              text: '  $year',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.25,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (rating != null || hasReviewText) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (rating != null) ...[
                            _DiaryEntryStars(rating: rating, size: 15),
                          ],
                          if (hasReviewText) ...[
                            if (rating != null) const SizedBox(width: 2),
                            Icon(
                              LucideIcons.text_align_start,
                              size: 14,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.62),
                            ),
                          ],
                        ],
                      ),
                    ],
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

class _DiaryEntryStars extends StatelessWidget {
  const _DiaryEntryStars({required this.rating, this.size = 14});

  final double rating;
  final double size;

  /// 인접 별 글리프 간 시각적 겹침(px). Row+SizedBox로 자르면 가로 overflow가 나므로 Stack으로 배치.
  static const double _glyphOverlap = 3.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = cs.onSurfaceVariant.withValues(alpha: 0.28);
    final step = size - _glyphOverlap;
    final w = 4 * step + size;

    return SizedBox(
      width: w,
      height: size,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: List.generate(5, (i) {
            final starValue = i + 1.0;
            final isFull = rating >= starValue;
            final isHalf = rating >= starValue - 0.5 && rating < starValue;
            late IconData icon;
            late Color color;
            if (isFull) {
              icon = Icons.star_rounded;
              color = _kDiaryEntryStarYellow;
            } else if (isHalf) {
              icon = Icons.star_half_rounded;
              color = _kDiaryEntryStarYellow;
            } else {
              icon = Icons.star_border_rounded;
              color = empty;
            }
            return Positioned(
              left: i * step,
              top: 0,
              child: Icon(icon, size: size, color: color),
            );
          }),
        ),
      ),
    );
  }
}

class _DiaryThumb extends StatelessWidget {
  const _DiaryThumb({required this.imageUrl, required this.cs});

  final String? imageUrl;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    const width = 32.0;
    const height = 48.0;
    final url = imageUrl;
    final iconSize = (width * 0.42).clamp(20.0, 40.0);
    final mw = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(48, 512);
    final mh = (height * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(72, 768);
    if (url != null && url.startsWith('http')) {
      return OptimizedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: mw,
        memCacheHeight: mh,
        errorWidget: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Icon(
            LucideIcons.tv,
            size: iconSize,
            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      );
    }
    if (url != null && url.startsWith('assets/')) {
      return Image.asset(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Icon(
            LucideIcons.tv,
            size: iconSize,
            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      );
    }
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(
        LucideIcons.tv,
        size: iconSize,
        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    );
  }
}

