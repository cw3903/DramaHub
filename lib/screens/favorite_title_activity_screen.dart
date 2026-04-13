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
import '../widgets/write_review_sheet.dart';
import 'diary_screen.dart';
import 'drama_detail_page.dart';
import 'login_page.dart';
import 'my_reviews_screen.dart';

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

String _activityOwnerDisplayName() {
  final n = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (n != null && n.isNotEmpty) return n;
  final d = AuthService.instance.currentUser.value?.displayName?.trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('@')) return d.split('@').first;
    return d;
  }
  return 'DramaHub';
}

typedef _FavoriteDramaLine = ({
  String displayTitle,
  String? releaseYear,
  String? posterUrl,
});

/// 즐겨찾기 한 작품 — 제목·연도·포스터 URL을 행마다가 아니라 한 번만 계산.
_FavoriteDramaLine _favoriteDramaLineMeta(ProfileFavorite f, String? country) {
  final fid = f.dramaId.trim();
  String title;
  if (!fid.startsWith('short-')) {
    title = DramaListService.instance.getDisplayTitle(fid, country);
    if (title.isEmpty) title = f.dramaTitle.trim();
  } else {
    title = DramaListService.instance.getDisplayTitleByTitle(
      f.dramaTitle,
      country,
    );
    if (title.isEmpty) title = f.dramaTitle.trim();
  }
  String? thumb;
  if (!fid.startsWith('short-')) {
    thumb = DramaListService.instance.getDisplayImageUrl(fid, country);
  }
  thumb ??=
      DramaListService.instance.getDisplayImageUrlByTitle(f.dramaTitle, country);
  thumb = thumb?.trim();
  if (thumb == null || thumb.isEmpty) {
    final t = f.dramaThumbnail?.trim();
    if (t != null && t.isNotEmpty) thumb = t;
  }
  String? year;
  if (!fid.startsWith('short-')) {
    final d = DramaListService.instance.getExtra(fid)?.releaseDate;
    if (d != null) year = '${d.year}';
  }
  return (
    displayTitle: title,
    releaseYear: year,
    posterUrl: thumb,
  );
}

DramaItem _navDramaItemForFavorite(ProfileFavorite f, _FavoriteDramaLine line) {
  return DramaItem(
    id: f.dramaId,
    title: line.displayTitle,
    subtitle: '',
    views: '0',
    imageUrl: line.posterUrl ?? f.dramaThumbnail,
  );
}

class _FavoriteDiaryThumb extends StatelessWidget {
  const _FavoriteDiaryThumb({
    required this.url,
    required this.cs,
    this.width = 48,
    this.height = 72,
  });

  final String? url;
  final ColorScheme cs;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim() ?? '';
    final iconSize = (width * 0.42).clamp(20.0, 40.0);
    final mw = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(48, 512);
    final mh = (height * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(72, 768);
    if (u.startsWith('http')) {
      return OptimizedNetworkImage(
        imageUrl: u,
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
    if (u.startsWith('assets/')) {
      return Image.asset(
        u,
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

MyReviewItem? _reviewForFavorite(ProfileFavorite f, String? country) {
  final byId = ReviewService.instance.getByDramaId(f.dramaId);
  if (byId != null) return byId;
  String favTitle;
  if (!f.dramaId.startsWith('short-')) {
    final t = DramaListService.instance.getDisplayTitle(f.dramaId, country);
    favTitle = t.isNotEmpty ? t : f.dramaTitle;
  } else {
    favTitle =
        DramaListService.instance.getDisplayTitleByTitle(f.dramaTitle, country);
  }
  favTitle = favTitle.trim();
  for (final r in ReviewService.instance.listNotifier.value) {
    if (r.dramaTitle.trim() == favTitle ||
        r.dramaTitle.trim() == f.dramaTitle.trim()) {
      return r;
    }
  }
  return null;
}

/// 프로필 FAVORITES 썸네일 탭 → 이 작품에 대한 내 다이어리·내 리뷰.
class FavoriteTitleActivityScreen extends StatefulWidget {
  const FavoriteTitleActivityScreen({
    super.key,
    required this.favorite,
    /// true면 읽기 전용 — 타인 프로필에서 열 때 전달.
    this.readOnly = false,
  });

  final ProfileFavorite favorite;
  final bool readOnly;

  @override
  State<FavoriteTitleActivityScreen> createState() =>
      _FavoriteTitleActivityScreenState();
}

class _FavoriteTitleActivityScreenState
    extends State<FavoriteTitleActivityScreen> {
  int _segment = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 첫 프레임(앱바·세그먼트)을 먼저 그린 뒤 로드 — 라우트 전환 체감 지연 완화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WatchHistoryService.instance.loadIfNeeded();
      ReviewService.instance.loadIfNeeded();
      DramaListService.instance.loadFromAsset();
      UserProfileService.instance.loadIfNeeded();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _headerTitle(dynamic s) {
    final name = _activityOwnerDisplayName();
    return s.get('favoriteActivityTitle').replaceAll('{name}', name);
  }

  void _openDramaDetailForFavorite(BuildContext context, String? country) {
    final line = _favoriteDramaLineMeta(widget.favorite, country);
    final navDrama = _navDramaItemForFavorite(widget.favorite, line);
    final detail =
        DramaListService.instance.buildDetailForItem(navDrama, country);
    Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => DramaDetailPage(detail: detail),
      ),
    );
  }

  /// 프로필 다이어리와 동일 — 시청 줄마다 해당 작품 상세로 이동.
  void _openDramaFromWatchedDiaryEntry(
    BuildContext context,
    WatchedDramaItem item,
    String? country,
  ) {
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

  /// Reviews 탭 상단 — 즐겨찾기 작품 포스터·제목 (중앙 정렬).
  Widget _buildFavoriteReviewsDramaHeader(
    BuildContext context,
    ColorScheme cs,
    String? country,
  ) {
    final line = _favoriteDramaLineMeta(widget.favorite, country);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => _openDramaDetailForFavorite(context, country),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: _FavoriteDiaryThumb(
                    url: line.posterUrl,
                    cs: cs,
                    width: 84,
                    height: 126,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            line.displayTitle,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWriteReviewForFavorite(
    BuildContext context,
    String? country,
  ) async {
    final line = _favoriteDramaLineMeta(widget.favorite, country);
    final dramaId = widget.favorite.dramaId;
    var dramaTitle = line.displayTitle.trim();
    if (dramaTitle.isEmpty) dramaTitle = widget.favorite.dramaTitle.trim();

    Future<void> openSheet() async {
      await WriteReviewSheet.show(
        context,
        dramaId: dramaId,
        dramaTitle: dramaTitle.isNotEmpty ? dramaTitle : null,
      );
    }

    if (AuthService.instance.isLoggedIn.value) {
      await openSheet();
    } else {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (ok == true && AuthService.instance.isLoggedIn.value) {
        await openSheet();
      }
    }
  }

  Future<void> _confirmDeleteReview(
    BuildContext context,
    dynamic s,
    MyReviewItem review,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.get('delete'), style: GoogleFonts.notoSansKr()),
        content: Text(
          s.get('deleteReviewConfirm'),
          style: GoogleFonts.notoSansKr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.get('ok'), style: GoogleFonts.notoSansKr()),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ReviewService.instance.deleteById(review.id);
    }
  }

  /// 리뷰/다이어리 세그먼트 — 트랙 안을 칩이 가득 채움(내부 inset 없음).
  Widget _segmentBar(ColorScheme cs, Brightness brightness, dynamic s) {
    const segmentTrackRadius = 7.0;
    /// 트랙 clip과 맞춘 선택 칩 모서리(1px 테두리 안쪽 느낌).
    const innerCornerRadius = 6.0;
    const trackDark = Color(0xFF1C1C1E);
    const trackBorderDark = Color(0xFF2C2C2E);
    final trackBg = brightness == Brightness.dark
        ? trackDark
        : cs.surfaceContainerHighest.withValues(alpha: 0.92);
    final trackBorder = brightness == Brightness.dark
        ? trackBorderDark
        : cs.outline.withValues(alpha: 0.22);
    const selectedBlueGray = Color(0xFF5D6D7E);
    final selectedBg = brightness == Brightness.dark
        ? selectedBlueGray
        : Color.lerp(selectedBlueGray, cs.surface, 0.25) ?? selectedBlueGray;
    final dimLabel = brightness == Brightness.dark
        ? const Color(0xFF8E8E93)
        : cs.onSurfaceVariant.withValues(alpha: 0.72);
    const barHeight = 28.0;

    BorderRadius chipRadius(bool on, int index) {
      if (!on) return BorderRadius.zero;
      if (index == 0) {
        return const BorderRadius.only(
          topLeft: Radius.circular(innerCornerRadius),
          bottomLeft: Radius.circular(innerCornerRadius),
        );
      }
      return const BorderRadius.only(
        topRight: Radius.circular(innerCornerRadius),
        bottomRight: Radius.circular(innerCornerRadius),
      );
    }

    Widget chip(String label, int index) {
      final on = _segment == index;
      final radius = chipRadius(on, index);
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? selectedBg : Colors.transparent,
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _segment = index),
              borderRadius: radius,
              splashColor: cs.primary.withValues(alpha: 0.1),
              highlightColor: Colors.transparent,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    height: 1.0,
                    fontWeight: on ? FontWeight.w900 : FontWeight.w800,
                    color: on ? Colors.white : dimLabel,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: SizedBox(
        height: barHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: trackBg,
            borderRadius: BorderRadius.circular(segmentTrackRadius),
            border: Border.all(color: trackBorder, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(segmentTrackRadius),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chip(s.get('tabReviews'), 0),
                chip(s.get('diary'), 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiaryTab(
    BuildContext context,
    ColorScheme cs,
    dynamic s,
    String appCountry,
  ) {
    final diaryCountry = CountryScope.maybeOf(context)?.country ??
        CountryService.instance.countryNotifier.value;
    final filtered = watchHistoryForFavorite(
      WatchHistoryService.instance.list,
      widget.favorite,
      diaryCountry,
    );
    if (filtered.isEmpty) {
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
                s.get('favoriteActivityDiaryEmpty'),
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

    final groups = _groupByMonth(filtered, true);
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final headerBg = Color.lerp(
          cs.surfaceContainerHighest,
          scaffoldBg,
          0.35,
        ) ??
        cs.surfaceContainerHighest;
    final headerFg = cs.onSurfaceVariant.withValues(alpha: 0.88);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            primary: false,
            controller: _scrollController,
            slivers: [
              for (final g in groups) ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FavoriteActivityMonthHeaderDelegate(
                    label: _monthHeaderLabel(appCountry, g.year, g.month),
                    background: headerBg,
                    foreground: headerFg,
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    addAutomaticKeepAlives: false,
                    (context, ii) {
                      final item = g.items[ii];
                      final showDayNumber = ii == 0 ||
                          (g.items[ii - 1].watchedAt.year != item.watchedAt.year ||
                              g.items[ii - 1].watchedAt.month !=
                                  item.watchedAt.month ||
                              g.items[ii - 1].watchedAt.day !=
                                  item.watchedAt.day);
                      return RepaintBoundary(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DiaryEntryRow(
                              item: item,
                              country: diaryCountry,
                              showDayNumber: showDayNumber,
                              onTap: () => _openDramaFromWatchedDiaryEntry(
                                context,
                                item,
                                diaryCountry,
                              ),
                            ),
                            if (ii < g.items.length - 1)
                              Divider(
                                height: 1,
                                thickness: 1,
                                indent: 16,
                                endIndent: 16,
                                color: cs.outline.withValues(alpha: 0.12),
                              ),
                          ],
                        ),
                      );
                    },
                    childCount: g.items.length,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final appCountry = CountryScope.of(context).country;
    final brightness = theme.brightness;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          _headerTitle(s),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          WatchHistoryService.instance.listNotifier,
          ReviewService.instance.listNotifier,
          DramaListService.instance.listNotifier,
          DramaListService.instance.extraNotifier,
          UserProfileService.instance.nicknameNotifier,
        ]),
        builder: (context, _) {
          // CountryScope는 상위 build에서 이미 of로 구독함. 여기서 maybeOf(dependOn) 중복 시
          // framework ancestor assertion이 날 수 있어 appCountry 사용.
          final review = _reviewForFavorite(widget.favorite, appCountry);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _segmentBar(cs, brightness, s),
              Expanded(
                child: _segment == 0
                    ? (review == null
                        ? CustomScrollView(
                            primary: false,
                            slivers: [
                              SliverToBoxAdapter(
                                child: _buildFavoriteReviewsDramaHeader(
                                  context,
                                  cs,
                                  appCountry,
                                ),
                              ),
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    32,
                                    48,
                                    32,
                                    32,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.get('favoriteActivityReviewEmpty'),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 16,
                                          color: cs.onSurfaceVariant
                                              .withValues(alpha: 0.52),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Center(
                                        child: FilledButton(
                                          onPressed: () =>
                                              _openWriteReviewForFavorite(
                                            context,
                                            appCountry,
                                          ),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: Text(
                                            s.get('writeReview'),
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 32),
                            children: [
                              _buildFavoriteReviewsDramaHeader(
                                context,
                                cs,
                                appCountry,
                              ),
                              LetterboxdMyReviewTile(
                                item: review,
                                showDramaTitle: false,
                                letterboxdActivityAuthorRow: true,
                                activityAuthorNameFontSize: 12,
                                starSize: 16,
                                starInterGap: 0,
                                starFilledColor: const Color(0xFFFFC107),
                                onEdit: widget.readOnly
                                    ? null
                                    : () => _openWriteReviewForFavorite(
                                        context, appCountry),
                                onDelete: widget.readOnly
                                    ? null
                                    : () => _confirmDeleteReview(
                                        context, s, review),
                              ),
                            ],
                          ))
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _buildDiaryTab(
                          context,
                          cs,
                          s,
                          appCountry,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FavoriteActivityMonthHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  _FavoriteActivityMonthHeaderDelegate({
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
  bool shouldRebuild(covariant _FavoriteActivityMonthHeaderDelegate oldDelegate) =>
      label != oldDelegate.label ||
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground;
}
