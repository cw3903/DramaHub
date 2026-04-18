import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../models/profile_favorite.dart';
import '../services/auth_service.dart';
import '../services/country_service.dart';
import '../services/drama_list_service.dart';
import '../services/locale_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/feed_review_star_row.dart';
import '../widgets/review_body_lines_indicator.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/write_review_sheet.dart';
import 'drama_search_screen.dart';
import 'login_page.dart';
import 'profile_screen.dart'
    show RecentActivityWatchOnlyPage, RecentActivityReviewGate;

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

/// 다이어리 월별 그룹 — [groupDiaryByMonth] 결과.
class DiaryMonthSection {
  DiaryMonthSection(this.year, this.month, WatchedDramaItem first)
      : items = [first];

  final int year;
  final int month;
  final List<WatchedDramaItem> items;
}

List<DiaryMonthSection> groupDiaryByMonth(
  List<WatchedDramaItem> list,
  bool newestFirst,
) {
  final sorted = List<WatchedDramaItem>.from(list)
    ..sort(
      (a, b) => newestFirst
          ? b.watchedAt.compareTo(a.watchedAt)
          : a.watchedAt.compareTo(b.watchedAt),
    );
  final groups = <DiaryMonthSection>[];
  for (final item in sorted) {
    final y = item.watchedAt.year;
    final m = item.watchedAt.month;
    if (groups.isEmpty || groups.last.year != y || groups.last.month != m) {
      groups.add(DiaryMonthSection(y, m, item));
    } else {
      groups.last.items.add(item);
    }
  }
  return groups;
}

String diaryMonthHeaderLabel(String appCountry, int year, int month) {
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
  final dramaId = item.dramaKey;
  if (!dramaId.startsWith('short-')) {
    final byId = DramaListService.instance.getDisplayImageUrl(dramaId, country);
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
  final dramaId = item.dramaKey;
  if (!dramaId.startsWith('short-')) {
    final t = DramaListService.instance.getDisplayTitle(dramaId, country);
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
  final iid = item.dramaKey.trim();
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
  final dramaId = item.dramaKey;
  for (final it in DramaListService.instance.list) {
    if (it.id == dramaId) return it;
  }
  return DramaItem(
    id: dramaId,
    title: _displayTitle(item, country),
    subtitle: item.subtitle,
    views: item.views,
    imageUrl: item.imageUrl,
  );
}

String? _releaseYearForWatched(WatchedDramaItem item, String? country) {
  final dramaId = item.dramaKey;
  if (!dramaId.startsWith('short-')) {
    final d = DramaListService.instance.getExtra(dramaId)?.releaseDate;
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
  final byId = ReviewService.instance.getByDramaId(item.dramaKey);
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

/// [WatchHistoryService.entryIdForLinkedFeedReview] 역변환.
String? _feedPostIdFromWatchHistoryEntryId(String entryId) {
  const prefix = 'feed_';
  final t = entryId.trim();
  if (!t.startsWith(prefix)) return null;
  final rest = t.substring(prefix.length).trim();
  return rest.isEmpty ? null : rest;
}

/// 다이어리 행 → 피드 상세([RecentActivityReviewGate])용 [MyReviewItem] 매칭.
MyReviewItem? _myReviewForDiaryEntry(WatchedDramaItem item, String? country) {
  var matched = _reviewForWatched(item, country);
  final fp = _feedPostIdFromWatchHistoryEntryId(item.id);
  if (fp != null) {
    if (matched?.feedPostId?.trim() != fp) {
      matched = null;
      for (final r in ReviewService.instance.listNotifier.value) {
        if (r.feedPostId?.trim() == fp) {
          matched = r;
          break;
        }
      }
    }
  }
  return matched;
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
    LocaleService.instance.localeNotifier.addListener(_onLocaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WatchHistoryService.instance.refresh();
      DramaListService.instance.loadFromAsset();
      ReviewService.instance.loadIfNeeded();
      UserProfileService.instance.loadIfNeeded();
    });
  }

  void _onLocaleChanged() {
    if (!mounted) return;
    WatchHistoryService.instance.refresh();
    ReviewService.instance.loadIfNeeded();
  }

  @override
  void dispose() {
    LocaleService.instance.localeNotifier.removeListener(_onLocaleChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// 프로필 다이어리 헤더 `+` — 작품 검색 후 드라마 상세 리뷰 탭과 동일 [WriteReviewSheet].
  Future<void> _openAddDiaryReview(BuildContext context, dynamic s) async {
    if (!AuthService.instance.isLoggedIn.value) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
      );
      if (!context.mounted ||
          ok != true ||
          !AuthService.instance.isLoggedIn.value) {
        return;
      }
    }
    if (!context.mounted) return;
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final picked = await Navigator.push<DramaItem>(
      context,
      MaterialPageRoute<DramaItem>(
        builder: (_) => const DramaSearchScreen(pickMode: true),
      ),
    );
    if (!context.mounted || picked == null) return;
    final locTitle =
        DramaListService.instance.getDisplayTitle(picked.id, country);
    final dramaTitle = locTitle.trim().isNotEmpty ? locTitle : picked.title;
    if (!context.mounted) return;
    await WriteReviewSheet.show(
      context,
      dramaId: picked.id,
      dramaTitle: dramaTitle.trim().isNotEmpty ? dramaTitle : null,
    );
    if (!context.mounted) return;
    unawaited(WatchHistoryService.instance.refresh());
    unawaited(ReviewService.instance.loadIfNeeded());
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
    final locale = CountryScope.maybeOf(context)?.country;
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    final matched = _myReviewForDiaryEntry(item, country);

    // DiaryEntryRow 표시 로직과 동일: item 직접 → ReviewService 폴백
    final itemRating = item.rating;
    final itemComment = item.comment?.trim();
    final bool hasRating;
    final bool hasReviewText;
    final double effectiveRating;
    final String effectiveComment;
    if ((itemRating != null && itemRating > 0) ||
        (itemComment != null && itemComment.isNotEmpty)) {
      hasRating = (itemRating ?? 0) > 0;
      hasReviewText = itemComment?.isNotEmpty ?? false;
      effectiveRating = itemRating ?? 0;
      effectiveComment = itemComment ?? '';
    } else {
      hasRating = (matched?.rating ?? 0) > 0;
      hasReviewText = matched?.comment.trim().isNotEmpty ?? false;
      effectiveRating = matched?.rating ?? 0;
      effectiveComment = matched?.comment ?? '';
    }
    final isWatchOnly = !hasRating && !hasReviewText;
    final feedPid = _feedPostIdFromWatchHistoryEntryId(item.id);
    final titleForReview =
        (matched?.dramaTitle.trim().isNotEmpty ?? false)
            ? matched!.dramaTitle
            : _displayTitle(item, country);

    // WatchedDramaItem → MyReviewItem 변환 (`feed_<postId>` 다이어리 행은 feedPostId 필수)
    final review = MyReviewItem(
      id: (matched?.id.trim().isNotEmpty ?? false)
          ? matched!.id.trim()
          : (feedPid ?? item.id),
      dramaId: matched?.dramaId.trim().isNotEmpty == true
          ? matched!.dramaId.trim()
          : item.dramaKey,
      dramaTitle: titleForReview,
      rating: effectiveRating,
      comment: effectiveComment,
      writtenAt: matched?.writtenAt ?? item.watchedAt,
      authorName: matched?.authorName,
      modifiedAt: matched?.modifiedAt,
      feedPostId: (matched?.feedPostId?.trim().isNotEmpty == true)
          ? matched!.feedPostId!.trim()
          : feedPid,
      appLocale: matched?.appLocale ?? item.appLocale,
    );

    Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => isWatchOnly
            ? RecentActivityWatchOnlyPage(
                authorUid: uid,
                review: review,
                country: country,
                locale: locale,
              )
            : RecentActivityReviewGate(
                authorUid: uid,
                dramaId: item.dramaKey,
                locale: locale,
                review: review,
                country: country,
              ),
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
        LocaleService.instance.localeNotifier,
        WatchHistoryService.instance.listNotifier,
        ReviewService.instance.listNotifier,
        DramaListService.instance.listNotifier,
        DramaListService.instance.extraNotifier,
        UserProfileService.instance.favoritesNotifier,
        UserProfileService.instance.nicknameNotifier,
        AuthService.instance.currentUser,
      ]),
      builder: (context, _) {
        final titleText = s.get('diary');
        final sortIconColor =
            cs.onSurfaceVariant.withValues(alpha: 0.78);
        final headerBg = listsStyleSubpageHeaderBackground(theme);
        return ListsStyleSwipeBack(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: listsStyleSubpageSystemOverlay(theme, headerBg),
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: PreferredSize(
              preferredSize:
                  ListsStyleSubpageHeaderBar.preferredSizeOf(context),
              child: ListsStyleSubpageHeaderBar(
                title: titleText,
                onBack: () => popListsStyleSubpage(context),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: s.get('myReviewsSortTitle'),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _openSortSheet(context, s),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              LucideIcons.sliders_horizontal,
                              size: 18,
                              color: sortIconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: s.get('writeReview'),
                      child: ListsStyleSubpageHeaderAddButton(
                        onTap: () => _openAddDiaryReview(context, s),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: _buildBody(context, cs, s, appCountry),
          ),
        ),
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
    // 서비스 로드 단계에서 로케일·레거시(저장 시 country 없음) 규칙으로 이미 필터됨.
    // UI에서 userScopedLocaleVisible을 한 번 더 쓰면 appLocale null인 기록이 전부 빠짐.
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
    final groups = groupDiaryByMonth(list, _newestFirst);
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
      final label = diaryMonthHeaderLabel(appCountry, g.year, g.month);
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: DiaryMonthHeaderDelegate(
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
          final divAlpha =
              Theme.of(context).brightness == Brightness.dark ? 0.30 : 0.22;
          children.add(
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: cs.outline.withValues(alpha: divAlpha),
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

    slivers.add(
      SliverPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 80,
        ),
      ),
    );

    return CustomScrollView(
      primary: false,
      controller: _scrollController,
      slivers: slivers,
    );
  }
}

class DiaryMonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  DiaryMonthHeaderDelegate({
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
  bool shouldRebuild(covariant DiaryMonthHeaderDelegate oldDelegate) =>
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

    // item 자체에 별점/코멘트가 저장돼 있으면 직접 사용 (워치+별, 워치+별+리뷰).
    // 없으면 ReviewService로 폴백 (리뷰탭에서 별도 작성한 리뷰와의 매칭용).
    final double? rating;
    final bool hasReviewText;
    final itemRating = item.rating;
    final itemComment = item.comment?.trim();
    if ((itemRating != null && itemRating > 0) ||
        (itemComment != null && itemComment.isNotEmpty)) {
      rating = (itemRating != null && itemRating > 0) ? itemRating : null;
      hasReviewText = itemComment?.isNotEmpty ?? false;
    } else {
      final review = _myReviewForDiaryEntry(item, country);
      rating = review != null && review.rating > 0 ? review.rating : null;
      hasReviewText = review?.comment.trim().isNotEmpty ?? false;
    }

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
                      SizedBox(
                        height: 20,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            if (rating != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FeedReviewRatingStars(
                                  rating: rating.clamp(0.0, 5.0),
                                  layoutThumbWidth: kFeedReviewRatingThumbWidth,
                                ),
                              ),
                            if (hasReviewText)
                              Positioned(
                                left: kFeedReviewRatingThumbWidth + 4,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: ReviewBodyLinesIndicator(
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.44,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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

