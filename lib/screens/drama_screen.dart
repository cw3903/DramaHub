import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/drama_view_service.dart';
import '../services/review_service.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';
import 'drama_search_screen.dart';

/// 360pt 기준 화면 너비 비율 (0.85~1.15). 반응형 패딩/폰트/간격용.
double _dramaScreenScale(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return (w / 360).clamp(0.85, 1.15);
}

/// 리뷰 탭 - 검색창 + 인기 순위 / 신작 / 카테고리 탭 + 그리드 드라마 카드
class DramaScreen extends StatefulWidget {
  const DramaScreen({super.key});

  @override
  State<DramaScreen> createState() => _DramaScreenState();
}

class _DramaScreenState extends State<DramaScreen> {
  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final country = CountryScope.maybeOf(context)?.country;
    final r = _dramaScreenScale(context);

    const headerBlue = Color(0xFF3399FF);
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1E5F9E) : headerBlue;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상단 헤더: 밝은 파란 배경 + 흰색 검색창 + 흰색 탭 (반응형)
              Container(
                color: headerBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16 * r, 12 * r, 16 * r, 10 * r),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                                builder: (_) => const DramaSearchScreen()),
                          );
                        },
                        borderRadius: BorderRadius.circular(6 * r),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16 * r,
                            vertical: 8 * r,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6 * r),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.search,
                                size: 20 * r,
                                color: Colors.grey.shade600,
                              ),
                              SizedBox(width: 12 * r),
                              Text(
                                s.get('dramaSearchHint'),
                                style: GoogleFonts.notoSansKr(
                                  fontSize: (15 * r).roundToDouble(),
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    TabBar(
                      isScrollable: true,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white.withOpacity(0.85),
                      indicatorColor: Colors.white,
                      indicatorWeight: (3 * r).clamp(2.0, 4.0),
                      indicatorSize: TabBarIndicatorSize.label,
                      indicatorPadding: EdgeInsets.only(top: -8 * r),
                      padding: EdgeInsets.only(left: 16 * r, right: 16 * r, bottom: 0),
                      tabAlignment: TabAlignment.start,
                      labelPadding: EdgeInsets.symmetric(horizontal: 6 * r),
                      dividerColor: Colors.transparent,
                      labelStyle: GoogleFonts.notoSansKr(
                        fontSize: (14 * r).roundToDouble(),
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: GoogleFonts.notoSansKr(
                        fontSize: (14 * r).roundToDouble(),
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: [
                        Tab(text: s.get('popularRanking')),
                        Tab(text: s.get('newReleases')),
                        Tab(text: s.get('category')),
                      ],
                    ),
                    Builder(
                      builder: (context) {
                        final controller = DefaultTabController.of(context);
                        if (controller == null) return const SizedBox.shrink();
                        return ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) {
                            if (controller.index != 2) return const SizedBox.shrink();
                            final scale = _dramaScreenScale(context);
                            return Padding(
                              padding: EdgeInsets.fromLTRB(16 * scale, 4 * scale, 16 * scale, 10 * scale),
                              child: Row(
                                children: [
                                  Text(
                                    s.get('filter'),
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: (13 * scale).roundToDouble(),
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                  SizedBox(width: 4 * scale),
                                  Icon(
                                    LucideIcons.chevron_down,
                                    size: 16 * scale,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            // 탭별 그리드
            Expanded(
              child: ValueListenableBuilder<List<DramaItem>>(
                valueListenable: DramaListService.instance.listNotifier,
                builder: (context, _, __) {
                  final baseList =
                      DramaListService.instance.getListForCountry(country);
                  final newList = DramaListService
                      .instance.getListForCountrySortedByReleaseDate(country);
                  if (baseList.isEmpty) {
                    final scale = _dramaScreenScale(context);
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
                        onTapCard: _openDetail,
                        posterPlaceholder: _posterPlaceholder,
                      ),
                      _DramaGridView(
                        list: newList,
                        country: country,
                        onTapCard: _openDetail,
                        posterPlaceholder: _posterPlaceholder,
                      ),
                      _DramaGridView(
                        list: baseList,
                        country: country,
                        onTapCard: _openDetail,
                        posterPlaceholder: _posterPlaceholder,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  void _openDetail(DramaItem item) async {
    final country = CountryScope.maybeOf(context)?.country;
    final detail =
        DramaListService.instance.buildDetailForItem(item, country);
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DramaDetailPage(detail: detail),
      ),
    );
  }

  Widget _posterPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(LucideIcons.tv, size: 28, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// 인기 순위 탭: 7일 조회수 기준 정렬 후 그리드
class _PopularGrid extends StatelessWidget {
  const _PopularGrid({
    required this.country,
    required this.baseList,
    required this.onTapCard,
    required this.posterPlaceholder,
  });

  final String? country;
  final List<DramaItem> baseList;
  final void Function(DramaItem item) onTapCard;
  final Widget Function(BuildContext context) posterPlaceholder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: DramaViewService.instance.getViewCountsLast7Days(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final viewCounts = snapshot.data!;
        final sorted = [...baseList]
          ..sort((a, b) =>
              (viewCounts[b.id] ?? 0).compareTo(viewCounts[a.id] ?? 0));
        return _DramaGridView(
          list: sorted,
          country: country,
          viewCounts: viewCounts,
          onTapCard: onTapCard,
          posterPlaceholder: posterPlaceholder,
        );
      },
    );
  }
}

/// 드라마 그리드 (3열 카드)
class _DramaGridView extends StatelessWidget {
  const _DramaGridView({
    required this.list,
    required this.country,
    required this.onTapCard,
    required this.posterPlaceholder,
    Map<String, int>? viewCounts,
  }) : viewCounts = viewCounts ?? const {};

  final List<DramaItem> list;
  final String? country;
  final Map<String, int> viewCounts;
  final void Function(DramaItem item) onTapCard;
  final Widget Function(BuildContext context) posterPlaceholder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _dramaScreenScale(context);
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16 * r, 12 * r, 16 * r, 24 * r),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.46,
        crossAxisSpacing: 2 * r,
        mainAxisSpacing: 6 * r,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final displayTitle =
            DramaListService.instance.getDisplayTitle(item.id, country);
        final displaySubtitle =
            DramaListService.instance.getDisplaySubtitle(item.id, country);
        final imageUrl = DramaListService.instance.getDisplayImageUrl(
              item.id,
              country,
            ) ??
            item.imageUrl;
        final rawRating =
            ReviewService.instance.getByDramaId(item.id)?.rating ?? item.rating;
        final rating = rawRating > 0 ? rawRating : 0.0;
        final viewsDisplay = viewCounts.isNotEmpty && viewCounts.containsKey(item.id)
            ? formatCompactCount(viewCounts[item.id]!)
            : item.views;
        return _DramaGridCard(
          displayTitle: displayTitle,
          displaySubtitle: displaySubtitle,
          imageUrl: imageUrl,
          viewsDisplay: viewsDisplay,
          rating: rating,
          onTap: () => onTapCard(item),
          posterPlaceholder: posterPlaceholder(context),
        );
      },
    );
  }
}

class _DramaGridCard extends StatelessWidget {
  const _DramaGridCard({
    required this.displayTitle,
    required this.displaySubtitle,
    required this.imageUrl,
    required this.viewsDisplay,
    required this.rating,
    required this.onTap,
    required this.posterPlaceholder,
  });

  final String displayTitle;
  final String displaySubtitle;
  final String? imageUrl;
  final String viewsDisplay;
  final double rating;
  final VoidCallback onTap;
  final Widget posterPlaceholder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? cs.onSurface : const Color(0xFF333333);
    final greyColor = isDark ? cs.onSurfaceVariant : Colors.grey.shade500;
    final r = _dramaScreenScale(context);
    final titleFontSize = (13 * r).roundToDouble();
    final metaFontSize = (12 * r).roundToDouble();
    final starSize = 14 * r;
    final genreColor = isDark ? cs.onSurfaceVariant : Colors.grey.shade600;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final posterHeight = w / (1 / 1.4);
        return GestureDetector(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: w,
                height: posterHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8 * r),
                      child: imageUrl != null && imageUrl!.isNotEmpty
                          ? OptimizedNetworkImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: posterPlaceholder,
                            )
                          : posterPlaceholder,
                    ),
                    Positioned(
                      right: 6 * r,
                      bottom: 6 * r,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.play,
                            size: 12 * r,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4 * r),
                          Text(
                            viewsDisplay,
                            style: GoogleFonts.notoSansKr(
                              fontSize: (11 * r).roundToDouble(),
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 5 * r),
              SizedBox(
                height: titleFontSize * 1.35 * 2,
                child: Text(
                  displayTitle,
                  style: GoogleFonts.notoSansKr(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: 8 * r),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: starSize,
                    color: rating > 0 ? Colors.amber : greyColor,
                  ),
                  SizedBox(width: 4 * r),
                  Text(
                    rating.toStringAsFixed(1),
                    style: GoogleFonts.notoSansKr(
                      fontSize: metaFontSize,
                      fontWeight: FontWeight.w500,
                      color: rating > 0 ? textColor : greyColor,
                    ),
                  ),
                  if (displaySubtitle.isNotEmpty) ...[
                    SizedBox(width: 8 * r),
                    Expanded(
                      child: Text(
                        displaySubtitle,
                        style: GoogleFonts.notoSansKr(
                          fontSize: metaFontSize,
                          fontWeight: FontWeight.w600,
                          color: genreColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
