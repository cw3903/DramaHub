import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/drama_view_service.dart';
import '../services/review_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/drama_grid_card.dart';
import 'drama_detail_page.dart';
import 'drama_search_screen.dart';

/// 1페이지당 드라마 카드 개수 (홈탭 페이지네이션과 동일 디자인)
const int _dramaCardsPerPage = 30;

/// 리뷰 탭 - 검색창 + 인기 순위 / 신작 / 카테고리 탭 + 그리드 드라마 카드
class DramaScreen extends StatefulWidget {
  const DramaScreen({super.key});

  @override
  State<DramaScreen> createState() => _DramaScreenState();
}

class _DramaScreenState extends State<DramaScreen> {
  /// [build]마다 새 [Future]를 만들면 [FutureBuilder]가 조회를 반복 호출함 → 한 번만.
  late final Future<Map<String, int>> _allViewCountsFuture =
      DramaViewService.instance.getAllViewCounts();

  /// 카테고리 탭 타깃 필터. null 또는 '전체'면 전체.
  String? _categoryTargetFilter;

  /// 카테고리 탭 장르 필터. null 또는 '전체'면 전체 표시.
  String? _categoryGenreFilter;

  /// 카테고리 탭 정렬: 'popular' = 인기순, 'latest' = 최신순
  String _categorySortOrder = 'popular';

  /// 카테고리 탭에서 필터 패널 접기·펼치기. false = 접힘, true = 펼침
  bool _showFilterPanel = false;

  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
  }

  /// 등장 횟수 상위 [n]개 장르만 반환 (한국어 기준).
  List<String> _extractTopGenres(
    List<DramaItem> list,
    String? country, {
    int n = 20,
  }) {
    final count = <String, int>{};
    for (final item in list) {
      final sub = DramaListService.instance.getDisplaySubtitle(
        item.id,
        country,
      );
      for (final part in sub.split(RegExp(r'[,·]'))) {
        final t = part.trim();
        if (t.isNotEmpty) count[t] = (count[t] ?? 0) + 1;
      }
    }
    final sorted = count.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  List<DramaItem> _getCategoryFilteredList(
    List<DramaItem> baseList,
    String? country,
  ) {
    var list = baseList;
    // 타깃 필터 (Female/Male은 데이터의 여성향/남성향과도 매칭)
    if (_categoryTargetFilter != null) {
      final target = _categoryTargetFilter!;
      list = list.where((item) {
        final sub = DramaListService.instance.getDisplaySubtitle(
          item.id,
          country,
        );
        final tags = sub.split(RegExp(r'[,·]')).map((s) => s.trim()).toList();
        if (target == 'Female')
          return tags.any((t) => t == 'Female' || t == '여성향');
        if (target == 'Male') return tags.any((t) => t == 'Male' || t == '남성향');
        return tags.any((t) => t == target);
      }).toList();
    }
    // 장르 필터
    if (_categoryGenreFilter != null && _categoryGenreFilter != '전체') {
      final genre = _categoryGenreFilter!;
      list = list.where((item) {
        final sub = DramaListService.instance.getDisplaySubtitle(
          item.id,
          country,
        );
        final tags = sub.split(RegExp(r'[,·]')).map((s) => s.trim()).toList();
        return tags.contains(genre);
      }).toList();
    }
    return list;
  }

  List<DramaItem> _getCategorySortedList(
    List<DramaItem> list,
    String? country,
    Map<String, int> viewCounts,
  ) {
    if (_categorySortOrder == 'latest') {
      final byRelease = DramaListService.instance
          .getListForCountrySortedByReleaseDate(country);
      final ids = list.map((e) => e.id).toSet();
      return byRelease.where((item) => ids.contains(item.id)).toList();
    }
    final sorted = [
      ...list,
    ]..sort((a, b) => (viewCounts[b.id] ?? 0).compareTo(viewCounts[a.id] ?? 0));
    return sorted;
  }

  /// 일본어 카테고리탭 2줄(장르) 선택 시: 조회수 몇십만~몇백만 오버레이
  static const List<int> _jpGenreOverlayViewCounts = [
    500000,
    1200000,
    3500000,
    8900000,
    15000000,
    28000000,
    51000000,
    680000,
    2100000,
    4200000,
    9500000,
    18000000,
    32000000,
    68000000,
    820000,
    2500000,
    5500000,
    11000000,
    22000000,
    41000000,
    85000000,
    950000,
    3100000,
    7200000,
    14000000,
    26000000,
    48000000,
  ];
  static Map<String, int> _jpGenreViewCountOverlayFor(List<DramaItem> items) {
    final map = <String, int>{};
    for (
      var i = 0;
      i < items.length && i < _jpGenreOverlayViewCounts.length;
      i++
    ) {
      map[items[i].id] = _jpGenreOverlayViewCounts[i];
    }
    return map;
  }

  /// 일본어 카테고리탭 2줄 선택 시: 별점 4.0 이상
  static const List<double> _jpGenreOverlayRatings = [
    4.0,
    4.2,
    4.5,
    4.1,
    4.8,
    4.3,
    4.6,
    4.0,
    4.4,
    4.9,
    4.1,
    4.7,
    4.2,
    4.5,
    4.0,
    4.6,
    4.3,
    4.8,
    4.4,
    4.2,
    4.5,
    4.0,
    4.7,
    4.3,
    4.9,
    4.1,
    4.6,
    4.4,
    4.2,
    4.8,
  ];
  static Map<String, double> _jpGenreRatingOverlayFor(List<DramaItem> items) {
    final map = <String, double>{};
    for (
      var i = 0;
      i < items.length && i < _jpGenreOverlayRatings.length;
      i++
    ) {
      map[items[i].id] = _jpGenreOverlayRatings[i];
    }
    return map;
  }

  static const _chipOrange = Color(0xFFFF4500); // 선택된 필터 칩 색상

  Widget _buildFilterChip({
    required double r,
    required ColorScheme cs,
    required bool isDark,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final bg = isSelected
        ? _chipOrange
        : (isDark ? cs.surfaceContainerLowest : cs.surfaceContainerHighest);
    final fg = isSelected ? Colors.white : cs.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * r, vertical: 6 * r),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14 * r),
          border: Border.all(
            color: isSelected ? _chipOrange : cs.outline.withOpacity(0.3),
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: (11 * r).roundToDouble(),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final country = CountryScope.maybeOf(context)?.country;
    /// 상단 헤더 세로는 `dramaFeedHeaderContentHeight` = [dramaFeedHeaderToolbarRh]+[dramaFeedHeaderTabStripRh]·rh+[dramaFeedHeaderSlopPx] 고정.
    final rh = dramaFeedHeaderScale(context);

    const headerBlue = Color(0xFF3399FF);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = theme.scaffoldBackgroundColor;
    // 다크: 홈 탭 헤더와 동일 — 순검정 대신 스캐폴드 쪽으로 살짝만 보간.
    final headerBg = isDark
        ? Color.lerp(Colors.black, pageBg, 0.45) ?? const Color(0xFF0A0A0A)
        : headerBlue;
    final headerFg = isDark ? cs.onSurface : Colors.white;
    final searchBarBg = isDark ? cs.surfaceContainerHighest : Colors.white;
    final searchBarFg = isDark ? cs.onSurfaceVariant : Colors.grey.shade600;

    final statusBarBg = isDark ? headerBg : Colors.white;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: statusBarBg,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          top: false,
          child: DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 상태바 영역만 흰색(라이트) / 헤더색(다크)
                Container(
                  height: MediaQuery.of(context).padding.top,
                  color: statusBarBg,
                ),
                // 상단 헤더: 세로는 [dramaFeedHeaderToolbarRh]/[dramaFeedHeaderTabStripRh] 슬롯만 고정(클립).
                Container(
                  decoration: BoxDecoration(color: headerBg),
                  height: dramaFeedHeaderContentHeight(context),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 검색창: 슬롯 높이만 고정. 크기·위치는 Stack 안에서만 조정.
                      SizedBox(
                        height: dramaFeedHeaderToolbarRh * rh,
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.hardEdge,
                            children: [
                              // 하단 정렬: 가운데 두면 탭과 사이가 벌어짐 → 탭에 붙여 한 덩어리처럼
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    16 * rh,
                                    4 * rh,
                                    16 * rh,
                                    5 * rh,
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        CupertinoPageRoute(
                                          builder: (_) =>
                                              const DramaSearchScreen(),
                                        ),
                                      );
                                    },
                                    borderRadius:
                                        BorderRadius.circular(8 * rh),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16 * rh,
                                        vertical: 6 * rh,
                                      ),
                                      decoration: BoxDecoration(
                                        color: searchBarBg,
                                        borderRadius:
                                            BorderRadius.circular(8 * rh),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Icon(
                                            LucideIcons.search,
                                            size: 18 * rh,
                                            color: searchBarFg,
                                          ),
                                          SizedBox(width: 10 * rh),
                                          Expanded(
                                            child: Text(
                                              s.get('dramaSearchHint'),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: (12 * rh)
                                                    .roundToDouble(),
                                                height: 1.12,
                                                color: searchBarFg,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 탭바: 슬롯 높이만 고정. 글자 크기만 바꿀 때는 안쪽 FittedBox가 넘침만 처리.
                      SizedBox(
                        height: dramaFeedHeaderTabStripRh * rh +
                            dramaFeedHeaderSlopPx,
                        child: ClipRect(
                          clipBehavior: Clip.hardEdge,
                          child: LayoutBuilder(
                            builder: (context, tabBarConstraints) {
                              const nominalTabBarHRh = 44.0;
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: tabBarConstraints.maxWidth,
                                  height: nominalTabBarHRh * rh,
                                  child: TabBar(
                                    isScrollable: true,
                                    labelColor: headerFg,
                                    unselectedLabelColor: headerFg
                                        .withValues(alpha: 0.88),
                                    indicator: const BoxDecoration(),
                                    indicatorWeight: 0,
                                    indicatorSize:
                                        TabBarIndicatorSize.label,
                                    padding: EdgeInsets.only(
                                      left: 14 * rh,
                                      right: 14 * rh,
                                      top: 1 * rh,
                                      bottom: 2 * rh,
                                    ),
                                    tabAlignment: TabAlignment.start,
                                    labelPadding: EdgeInsets.symmetric(
                                      horizontal: 8 * rh,
                                      vertical: 2 * rh,
                                    ),
                                    dividerColor: Colors.transparent,
                                    overlayColor: WidgetStateProperty.all(
                                      Colors.transparent,
                                    ),
                                    splashFactory: NoSplash.splashFactory,
                                    labelStyle: GoogleFonts.notoSansKr(
                                      fontSize: (16 * rh)
                                          .roundToDouble(),
                                      fontWeight: FontWeight.w900,
                                      height: 1.08,
                                      letterSpacing: -0.2,
                                    ),
                                    unselectedLabelStyle:
                                        GoogleFonts.notoSansKr(
                                      fontSize: (13.5 * rh)
                                          .roundToDouble(),
                                      fontWeight: FontWeight.w700,
                                      height: 1.08,
                                      letterSpacing: -0.15,
                                    ),
                                    tabs: [
                                      Tab(text: s.get('popularRanking')),
                                      Tab(text: s.get('newReleases')),
                                      Tab(text: s.get('category')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 필터: 카테고리 탭일 때만 — 필터 버튼 행만 (패널은 오버레이로 표시)
                Builder(
                    builder: (ctx) {
                      final controller = DefaultTabController.of(ctx);
                      if (controller == null) return const SizedBox.shrink();
                      return ListenableBuilder(
                        listenable: controller,
                        builder: (ctx, _) {
                          if (controller.index != 2) {
                            if (_showFilterPanel)
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => setState(() => _showFilterPanel = false),
                              );
                            return const SizedBox.shrink();
                          }
                          final scale = dramaGridScreenScale(ctx);
                          final filterFg = isDark
                              ? cs.onSurface
                              : Colors.grey.shade800;
                          return Container(
                            color: theme.scaffoldBackgroundColor,
                            padding: EdgeInsets.fromLTRB(
                              16 * scale,
                              8 * scale,
                              16 * scale,
                              0 * scale,
                            ),
                            child: InkWell(
                              onTap: () => setState(
                                () => _showFilterPanel = !_showFilterPanel,
                              ),
                              borderRadius: BorderRadius.circular(6 * scale),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 6 * scale,
                                  top: 2 * scale,
                                  bottom: 2 * scale,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      s.get('filter'),
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: (11.5 * scale).roundToDouble(),
                                        fontWeight: FontWeight.w600,
                                        color: filterFg,
                                      ),
                                    ),
                                    SizedBox(width: 4 * scale),
                                    Icon(
                                      _showFilterPanel
                                          ? LucideIcons.chevron_up
                                          : LucideIcons.chevron_down,
                                      size: 16 * scale,
                                      color: filterFg,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                ),
                Expanded(
                  child: Stack(
                    children: [
                  Positioned.fill(
                    child: FutureBuilder<Map<String, int>>(
                      future: _allViewCountsFuture,
                      builder: (context, viewSnapshot) {
                        final viewCounts = viewSnapshot.data ?? {};
                        return ValueListenableBuilder<List<DramaItem>>(
                          valueListenable:
                              DramaListService.instance.listNotifier,
                          builder: (context, _, __) {
                            final baseList = DramaListService.instance
                                .getListForCountry(country);
                            final newList = DramaListService.instance
                                .getListForCountrySortedByReleaseDate(country);
                            if (baseList.isEmpty) {
                              final scale = dramaGridScreenScale(context);
                              return Center(
                                child: Text(
                                  s.get('notReadyYet'),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: (15 * scale).roundToDouble(),
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            return TabBarView(
                              children: [
                                _PopularGrid(
                                  country: country,
                                  baseList: baseList,
                                  viewCounts: viewCounts,
                                  onTapCard: _openDetail,
                                  posterPlaceholder: _posterPlaceholder,
                                ),
                                _DramaGridWithPagination(
                                  list: newList,
                                  country: country,
                                  viewCounts: viewCounts,
                                  onTapCard: _openDetail,
                                  posterPlaceholder: _posterPlaceholder,
                                ),
                                () {
                                  final categoryList = _getCategorySortedList(
                                    _getCategoryFilteredList(baseList, country),
                                    country,
                                    viewCounts,
                                  );
                                  final isJpGenre =
                                      (country == 'jp' &&
                                      _categoryGenreFilter != null);
                                  final listToUse = isJpGenre
                                      ? categoryList
                                            .take(_dramaCardsPerPage)
                                            .toList()
                                      : categoryList;
                                  final effectiveViewCounts =
                                      isJpGenre && listToUse.isNotEmpty
                                      ? <String, int>{
                                          ...viewCounts,
                                          ..._jpGenreViewCountOverlayFor(
                                            listToUse,
                                          ),
                                        }
                                      : viewCounts;
                                  return _DramaGridWithPagination(
                                    list: listToUse,
                                    country: country,
                                    viewCounts: effectiveViewCounts,
                                    onTapCard: _openDetail,
                                    posterPlaceholder: _posterPlaceholder,
                                    ratingOverrides:
                                        isJpGenre && listToUse.isNotEmpty
                                        ? _jpGenreRatingOverlayFor(listToUse)
                                        : null,
                                  );
                                }(),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: Builder(
                      builder: (ctx) {
                        if (!_showFilterPanel) return const SizedBox.shrink();
                        final controller = DefaultTabController.of(ctx);
                        if (controller == null || controller.index != 2)
                          return const SizedBox.shrink();
                        final scale = dramaGridScreenScale(context);
                        final filterFg = isDark
                            ? cs.onSurface
                            : Colors.grey.shade800;
                        final list = DramaListService.instance
                            .getListForCountry(country);
                        final topGenres = _extractTopGenres(
                          list,
                          country,
                          n: 20,
                        );
                        // 패널은 body 영역 맨 위 = 필터 버튼 바로 아래
                        const panelTop = 0.0;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _showFilterPanel = false),
                                child: Container(color: Colors.black54),
                              ),
                            ),
                            Positioned(
                              top: panelTop,
                              left: 0,
                              right: 0,
                              child: Material(
                                color: theme.scaffoldBackgroundColor,
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(12 * scale),
                                  bottomRight: Radius.circular(12 * scale),
                                ),
                                child: SingleChildScrollView(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      16 * scale,
                                      12 * scale,
                                      16 * scale,
                                      16 * scale,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.only(
                                            left: 12 * scale,
                                          ),
                                          child: Text(
                                            s.get('target'),
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: (13 * scale)
                                                  .roundToDouble(),
                                              fontWeight: FontWeight.w600,
                                              color: filterFg,
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: 6 * scale),
                                        Wrap(
                                          spacing: 8 * scale,
                                          runSpacing: 8 * scale,
                                          children: [
                                            _buildFilterChip(
                                              r: scale,
                                              cs: cs,
                                              isDark: isDark,
                                              label: s.get('all'),
                                              isSelected:
                                                  _categoryTargetFilter == null,
                                              onTap: () => setState(
                                                () => _categoryTargetFilter =
                                                    null,
                                              ),
                                            ),
                                            ...[
                                              'Female',
                                              'Male',
                                              'BL',
                                              'GL',
                                            ].map(
                                              (target) => _buildFilterChip(
                                                r: scale,
                                                cs: cs,
                                                isDark: isDark,
                                                label: target,
                                                isSelected:
                                                    _categoryTargetFilter ==
                                                    target,
                                                onTap: () => setState(
                                                  () => _categoryTargetFilter =
                                                      _categoryTargetFilter ==
                                                          target
                                                      ? null
                                                      : target,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 14 * scale),
                                        Padding(
                                          padding: EdgeInsets.only(
                                            left: 12 * scale,
                                          ),
                                          child: Text(
                                            s.get('genre'),
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: (13 * scale)
                                                  .roundToDouble(),
                                              fontWeight: FontWeight.w600,
                                              color: filterFg,
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: 6 * scale),
                                        Wrap(
                                          spacing: 8 * scale,
                                          runSpacing: 8 * scale,
                                          children: [
                                            _buildFilterChip(
                                              r: scale,
                                              cs: cs,
                                              isDark: isDark,
                                              label: s.get('all'),
                                              isSelected:
                                                  _categoryGenreFilter == null,
                                              onTap: () => setState(
                                                () =>
                                                    _categoryGenreFilter = null,
                                              ),
                                            ),
                                            ...topGenres
                                                .where(
                                                  (g) =>
                                                      g != 'Female' &&
                                                      g != 'Male' &&
                                                      g != '여성향' &&
                                                      g != '남성향',
                                                )
                                                .map(
                                                  (genre) => _buildFilterChip(
                                                    r: scale,
                                                    cs: cs,
                                                    isDark: isDark,
                                                    label: genre,
                                                    isSelected:
                                                        _categoryGenreFilter ==
                                                        genre,
                                                    onTap: () => setState(
                                                      () => _categoryGenreFilter =
                                                          _categoryGenreFilter ==
                                                              genre
                                                          ? null
                                                          : genre,
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDetail(DramaItem item) {
    final country = CountryScope.maybeOf(context)?.country;
    final detail = DramaListService.instance.buildDetailForItem(item, country);
    Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(builder: (_) => DramaDetailPage(detail: detail)),
    );
  }

  Widget _posterPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(color: cs.surfaceContainerHighest);
  }
}

/// 인기 순위 탭: Firebase 총 조회수 기준 정렬 후 그리드 (viewCounts는 상세 페이지와 동일 소스)
class _PopularGrid extends StatelessWidget {
  const _PopularGrid({
    required this.country,
    required this.baseList,
    required this.viewCounts,
    required this.onTapCard,
    required this.posterPlaceholder,
  });

  final String? country;
  final List<DramaItem> baseList;
  final Map<String, int> viewCounts;
  final void Function(DramaItem item) onTapCard;
  final Widget Function(BuildContext context) posterPlaceholder;

  @override
  Widget build(BuildContext context) {
    final sorted = [
      ...baseList,
    ]..sort((a, b) => (viewCounts[b.id] ?? 0).compareTo(viewCounts[a.id] ?? 0));
    return _DramaGridWithPagination(
      list: sorted,
      country: country,
      viewCounts: viewCounts,
      onTapCard: onTapCard,
      posterPlaceholder: posterPlaceholder,
    );
  }
}

/// 인기/신작/카테고리 공통: 무한 스크롤 드라마 그리드
class _DramaGridWithPagination extends StatefulWidget {
  const _DramaGridWithPagination({
    required this.list,
    required this.country,
    required this.viewCounts,
    required this.onTapCard,
    required this.posterPlaceholder,
    this.ratingOverrides,
  });

  final List<DramaItem> list;
  final String? country;
  final Map<String, int> viewCounts;
  final void Function(DramaItem item) onTapCard;
  final Widget Function(BuildContext context) posterPlaceholder;
  final Map<String, double>? ratingOverrides;

  @override
  State<_DramaGridWithPagination> createState() =>
      _DramaGridWithPaginationState();
}

class _DramaGridWithPaginationState extends State<_DramaGridWithPagination> {
  static const _pageSize = 12;

  int _displayCount = _pageSize;
  bool _isLoadingMore = false;

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    if (_displayCount >= widget.list.length) return;
    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    setState(() {
      _displayCount = (_displayCount + _pageSize).clamp(0, widget.list.length);
      _isLoadingMore = false;
    });
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollUpdateNotification) {
      final m = n.metrics;
      if (m.pixels >= m.maxScrollExtent - 250) _loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    // list 레퍼런스가 바뀌어도 take()가 알아서 clamp하므로 별도 리셋 불필요
    final visibleCount = _displayCount.clamp(0, list.length);
    final visibleList = list.take(visibleCount).toList();
    final hasMore = visibleCount < list.length;

    final cs = Theme.of(context).colorScheme;
    final r = dramaGridScreenScale(context);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: CustomScrollView(
      primary: true,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(8 * r, 0, 8 * r, 6 * r),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.53,
              crossAxisSpacing: 8 * r,
              mainAxisSpacing: 0,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = visibleList[index];
              final displayTitle = DramaListService.instance.getDisplayTitle(
                item.id,
                widget.country,
              );
              final displaySubtitle = DramaListService.instance
                  .getDisplaySubtitle(item.id, widget.country);
              final imageUrl =
                  DramaListService.instance.getDisplayImageUrl(
                    item.id,
                    widget.country,
                  ) ??
                  item.imageUrl;
              final rawRating =
                  ReviewService.instance.getByDramaId(item.id)?.rating ??
                  item.rating;
              var rating = rawRating > 0 ? rawRating : 0.0;
              if (widget.ratingOverrides != null &&
                  widget.ratingOverrides!.containsKey(item.id)) {
                rating = widget.ratingOverrides![item.id]!;
              }
              return DramaGridCard(
                displayTitle: displayTitle,
                displaySubtitle: displaySubtitle,
                imageUrl: imageUrl,
                rating: rating,
                onTap: () => widget.onTapCard(item),
                posterPlaceholder: widget.posterPlaceholder(context),
              );
            }, childCount: visibleList.length),
          ),
        ),
        SliverToBoxAdapter(
          child: hasMore
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: cs.onSurfaceVariant.withOpacity(0.5),
                      ),
                    ),
                  ),
                )
              : SizedBox(height: MediaQuery.of(context).padding.bottom + 22),
        ),
      ],
      ),
    );
  }
}
