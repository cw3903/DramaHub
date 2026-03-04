import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/drama_search_stats_service.dart';
import '../services/review_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';

/// 리뷰(드라마) 탭 검색창 탭 시 — 실제 드라마 목록(dramas.json) 기준 제목·장르 검색
class DramaSearchScreen extends StatefulWidget {
  const DramaSearchScreen({super.key});

  @override
  State<DramaSearchScreen> createState() => _DramaSearchScreenState();
}

class _DramaSearchScreenState extends State<DramaSearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  /// 입력(엔터) 눌렀을 때만 반영되는 검색어. 글자 입력만으로는 검색 안 함.
  String _submittedQuery = '';
  /// 인기 순위 기간: 오늘/이번 주/이번 달/올해
  SearchStatsPeriod _period = SearchStatsPeriod.day;
  /// 검색어 없을 때 보여줄 '인기 검색' 상위 10개. 기간 선택·상세 복귀 시 다시 불러오기 위해 state로 보관.
  Future<List<String>> _topIdsFuture = DramaSearchStatsService.instance.getTopDramaIds(SearchStatsPeriod.day, 10);
  /// 탭 전환 시 로딩 중에도 이전 목록을 보여줘서 흰 화면이 안 뜨게 함.
  List<DramaItem>? _displayListCache;

  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final country = CountryScope.maybeOf(context)?.country;
    final allList = DramaListService.instance.getListForCountry(country);
    final q = _submittedQuery.toLowerCase();
    final filteredList = q.isEmpty
        ? allList
        : allList.where((item) {
            final title = DramaListService.instance.getDisplayTitle(item.id, country).toLowerCase();
            final subtitle = DramaListService.instance.getDisplaySubtitle(item.id, country).toLowerCase();
            return title.contains(q) || subtitle.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 44,
        titleSpacing: 4,
        leading: IconButton(
          icon: Icon(LucideIcons.arrow_left, size: 24, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            final q = value.trim();
            setState(() => _submittedQuery = q);
            if (q.isNotEmpty) {
              final country = CountryScope.maybeOf(context)?.country;
              final list = DramaListService.instance.getListForCountry(country);
              final lower = q.toLowerCase();
              final ids = list
                  .where((item) {
                    final t = DramaListService.instance.getDisplayTitle(item.id, country).toLowerCase();
                    final sub = DramaListService.instance.getDisplaySubtitle(item.id, country).toLowerCase();
                    return t.contains(lower) || sub.contains(lower);
                  })
                  .take(10)
                  .map((e) => e.id)
                  .toList();
              DramaSearchStatsService.instance.incrementSearch(ids);
            }
          },
          style: GoogleFonts.notoSansKr(fontSize: 16, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: s.get('dramaSearchHint'),
            hintStyle: GoogleFonts.notoSansKr(fontSize: 16, color: cs.onSurfaceVariant),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            prefixIcon: Icon(LucideIcons.search, size: 20, color: cs.onSurfaceVariant),
          ),
        ),
      ),
      body: ValueListenableBuilder<List<DramaItem>>(
        valueListenable: DramaListService.instance.listNotifier,
        builder: (context, _, __) {
          if (_submittedQuery.isNotEmpty && filteredList.isEmpty) {
            return Center(
              child: Text(
                s.get('searchNoResults').replaceAll('%s', _submittedQuery),
                style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            );
          }
          if (_submittedQuery.isEmpty && allList.isEmpty) {
            return Center(
              child: Text(
                s.get('searchEnterQuery'),
                style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            );
          }
          // 검색어 있음: 필터 결과 상위 10개 / 검색어 없음: 선택 기간별 인기 순위 상위 10개
          if (_submittedQuery.isNotEmpty) {
            final displayList = filteredList.take(10).toList();
            return _buildRankList(
              context,
              displayList,
              country,
              cs,
              s,
              sectionTitle: s.get('searchResults'),
              onReturnFromDetail: null,
            );
          }
          return FutureBuilder<List<String>>(
            future: _topIdsFuture,
            builder: (context, snap) {
              final topIds = snap.data ?? [];
              final idSet = topIds.toSet();
              final ordered = <DramaItem>[];
              for (final id in topIds) {
                final found = allList.where((e) => e.id == id).toList();
                if (found.isNotEmpty) ordered.add(found.first);
              }
              for (final item in allList) {
                if (ordered.length >= 10) break;
                if (!idSet.contains(item.id)) ordered.add(item);
              }
              final List<DramaItem> displayList = snap.connectionState == ConnectionState.waiting && _displayListCache != null
                  ? _displayListCache!
                  : ordered.take(10).toList();
              if (snap.hasData && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _displayListCache = displayList);
                });
              }
              final onRefresh = () => setState(() {
                _topIdsFuture = DramaSearchStatsService.instance.getTopDramaIds(_period, 10, fromServer: true);
              });
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPeriodSelector(cs, s),
                  Expanded(
                    child: _buildRankList(
                      context,
                      displayList,
                      country,
                      cs,
                      s,
                      sectionTitle: s.get('popularSearch'),
                      onReturnFromDetail: onRefresh,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPeriodSelector(ColorScheme cs, dynamic s) {
    const periods = [
      SearchStatsPeriod.day,
      SearchStatsPeriod.week,
      SearchStatsPeriod.month,
      SearchStatsPeriod.year,
    ];
    final labels = [
      s.get('periodDay'),
      s.get('periodWeek'),
      s.get('periodMonth'),
      s.get('periodYear'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: List.generate(periods.length, (i) {
          final isSelected = _period == periods[i];
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _period = periods[i];
                  _topIdsFuture = DramaSearchStatsService.instance.getTopDramaIds(_period, 10);
                });
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    labels[i],
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRankList(
    BuildContext context,
    List<DramaItem> displayList,
    String? country,
    ColorScheme cs,
    dynamic s, {
    String? sectionTitle,
    VoidCallback? onReturnFromDetail,
  }) {
    final title = sectionTitle ?? s.get('popularSearch');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            title,
            style: GoogleFonts.notoSansKr(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              24 + MediaQuery.of(context).padding.bottom,
            ),
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              final item = displayList[index];
              final rank = index + 1;
              final displayTitle = DramaListService.instance.getDisplayTitle(item.id, country);
              final displaySubtitle = DramaListService.instance.getDisplaySubtitle(item.id, country);
              final imageUrl = DramaListService.instance.getDisplayImageUrl(item.id, country) ?? item.imageUrl;
              final rating = ReviewService.instance.getByDramaId(item.id)?.rating ?? item.rating;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await DramaSearchStatsService.instance.incrementClick(item.id);
                    if (!mounted) return;
                    final detail = DramaListService.instance.buildDetailForItem(item, country);
                    await Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => DramaDetailPage(detail: detail),
                      ),
                    );
                    if (mounted && onReturnFromDetail != null) onReturnFromDetail();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '$rank',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith('http')
                              ? OptimizedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 72,
                                  height: 96,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 72,
                                  height: 96,
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(LucideIcons.tv, size: 28, color: cs.onSurfaceVariant),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayTitle.isNotEmpty ? displayTitle : item.title,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (displaySubtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  displaySubtitle,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(LucideIcons.chevron_right, size: 20, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
