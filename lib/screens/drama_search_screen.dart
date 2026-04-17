import 'dart:async' show unawaited;
import 'dart:math' show Random;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/drama_search_stats_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/drama_grid_card.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import 'drama_detail_page.dart';

/// [WatchlistScreen] 본문 그리드와 동일 — 태그 검색(`genreTagFilter`) 본문 전용.
const double _kTagSearchWatchlistGridAspect = 0.74;
const double _kTagSearchWatchlistGridPadH = 15;
const double _kTagSearchWatchlistGridGap = 7;
const int _kTagSearchWatchlistMaxPosters = 4;

/// 리뷰(드라마) 탭 검색창 탭 시 — 실제 드라마 목록(dramas.json) 기준 제목·장르 검색
class DramaSearchScreen extends StatefulWidget {
  const DramaSearchScreen({
    super.key,
    this.pickMode = false,
    this.pickExcludeDramaIds,
    this.multiPickMax,
    this.genreTagFilter,
  });

  /// true면 행 탭 시 [DramaItem]만 반환하고 상세로 이동하지 않음 (커뮤니티 리뷰용)
  final bool pickMode;

  /// pick 모드에서 이미 목록에 넣은 드라마 id. 탭 시 반환하지 않고 안내 다이얼로그만 표시.
  final Set<String>? pickExcludeDramaIds;

  /// null이면 탭 시 1편 즉시 [Navigator.pop] · 지정 시 이 화면에서 최대 [multiPickMax]편까지 선택 후 앱바 완료로 [List] 반환.
  final int? multiPickMax;

  /// 지정 시 검색·인기 목록 풀을 [DramaListService.getDramasMatchingGenreTag] 결과로만 제한(태그 목록에서 검색).
  final String? genreTagFilter;

  @override
  State<DramaSearchScreen> createState() => _DramaSearchScreenState();
}

class _DramaSearchScreenState extends State<DramaSearchScreen> {
  static const int _kPickModeRandomCount = 32;

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

  /// [multiPickMax] 모드에서만 사용 — 선택 순서 유지
  final List<DramaItem> _multiPicked = [];
  final Set<String> _multiPickedIds = {};

  /// 뒤로가기·픽 완료·카드 선택 등 `maybePop`이 겹치면 네비게이터 히스토리가 비는 assert 방지.
  bool _navBusy = false;

  /// 검색 그리드 상단 일부 id에 대해 전체 리뷰 평균 프리패치 (상세와 동일 소스).
  String? _searchGridRatingPrefetchSig;

  Future<void> _popSelf<T extends Object?>([T? result]) async {
    if (!mounted || _navBusy) return;
    _navBusy = true;
    try {
      // 같은 프레임(제스처·그리드 빌드 직후)에서 바로 maybePop 하면 Navigator가
      // `_debugLocked` 인 채로 `build`가 돌아 `!_debugLocked` assert가 날 수 있음.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final nav = Navigator.maybeOf(context);
      if (nav == null || !nav.canPop()) return;
      await nav.maybePop<T>(result);
    } finally {
      if (mounted) _navBusy = false;
    }
  }

  /// getListForCountry / 필터 / 픽 32편 — 빌드마다 재계산 방지
  List<DramaItem>? _memListRef;
  String? _memCountry;
  List<DramaItem>? _memAllList;
  /// [_getAllListCached] — 전체 목록 vs 태그 부분집합 구분용
  String? _memTagFilter;
  String? _memFilteredQLower;
  String? _memFilteredCountry;
  Object? _memFilteredSourceRef;
  List<DramaItem>? _memFilteredList;
  Object? _memPickKey;
  List<DramaItem>? _memPickList;

  bool get _multiPickActive =>
      widget.pickMode &&
      widget.multiPickMax != null &&
      widget.multiPickMax! > 0;

  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
    // 즐겨찾기 등 pick 모드는 들어가자마자 키보드 올리지 않음.
    if (!widget.pickMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<DramaItem> _getAllListCached(String? country) {
    final ref = DramaListService.instance.listNotifier.value;
    final tag = widget.genreTagFilter?.trim();
    if (identical(_memListRef, ref) &&
        _memCountry == country &&
        _memTagFilter == tag &&
        _memAllList != null) {
      return _memAllList!;
    }
    _memListRef = ref;
    _memCountry = country;
    _memTagFilter = tag;
    _memAllList = (tag != null && tag.isNotEmpty)
        ? DramaListService.instance.getDramasMatchingGenreTag(tag, country)
        : DramaListService.instance.getListForCountry(country);
    _memFilteredQLower = null;
    _memFilteredCountry = null;
    _memPickKey = null;
    return _memAllList!;
  }

  List<DramaItem> _filteredCached(
    List<DramaItem> all,
    String? country,
    String qLower,
  ) {
    if (qLower.isEmpty) return all;
    final srcRef = DramaListService.instance.listNotifier.value;
    if (_memFilteredQLower == qLower &&
        _memFilteredCountry == country &&
        identical(_memFilteredSourceRef, srcRef) &&
        _memFilteredList != null) {
      return _memFilteredList!;
    }
    _memFilteredQLower = qLower;
    _memFilteredCountry = country;
    _memFilteredSourceRef = srcRef;
    _memFilteredList = all.where((item) {
      final title = DramaListService.instance
          .getDisplayTitle(item.id, country)
          .toLowerCase();
      final subtitle = DramaListService.instance
          .getDisplaySubtitle(item.id, country)
          .toLowerCase();
      return title.contains(qLower) || subtitle.contains(qLower);
    }).toList();
    return _memFilteredList!;
  }

  /// 즐겨찾기 픽: 시드 고정, **O(32)** 인덱스 샘플 (전체 shuffle 없음).
  List<DramaItem> _pickModeRandomDisplay(List<DramaItem> all) {
    if (all.isEmpty) return [];
    if (all.length <= _kPickModeRandomCount) return List<DramaItem>.of(all);
    final seed = Object.hash(
      all.length,
      all.first.id,
      all.length > 1 ? all.last.id : '',
    );
    final rng = Random(seed);
    final indices = <int>{};
    while (indices.length < _kPickModeRandomCount) {
      indices.add(rng.nextInt(all.length));
    }
    return [for (final i in indices) all[i]];
  }

  List<DramaItem> _pickDisplayCached(List<DramaItem> all, String? country) {
    final srcRef = DramaListService.instance.listNotifier.value;
    final key = Object.hash(
      all.length,
      all.isNotEmpty ? all.first.id : '',
      all.length > 1 ? all.last.id : '',
      country,
      identityHashCode(srcRef),
    );
    if (_memPickKey == key && _memPickList != null) {
      return _memPickList!;
    }
    _memPickKey = key;
    _memPickList = _pickModeRandomDisplay(all);
    return _memPickList!;
  }

  Future<void> _showPickDuplicateDialog(
    BuildContext navigatorContext,
    dynamic s,
  ) async {
    if (!mounted || !navigatorContext.mounted) return;
    await showDialog<void>(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          s.get('listCreateDuplicateDialogTitle'),
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
        ),
        content: Text(
          s.get('listCreateErrorDuplicateDrama'),
          style: GoogleFonts.notoSansKr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.get('ok')),
          ),
        ],
      ),
    );
  }

  void _toggleMultiPick(DramaItem item, dynamic s) {
    final max = widget.multiPickMax!;
    if (_multiPickedIds.contains(item.id)) {
      setState(() {
        _multiPickedIds.remove(item.id);
        _multiPicked.removeWhere((e) => e.id == item.id);
      });
      return;
    }
    if (_multiPicked.length >= max) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.get('listMultiPickStepLimit').replaceAll('{n}', '$max'),
          ),
        ),
      );
      return;
    }
    setState(() {
      _multiPicked.add(item);
      _multiPickedIds.add(item.id);
    });
  }

  void _completeMultiPick() {
    if (!mounted) return;
    unawaited(_popSelf<List<DramaItem>>(List<DramaItem>.from(_multiPicked)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final headerBg = listsStyleSubpageHeaderBackground(theme);
    final leadingMuted = listsStyleSubpageLeadingMuted(theme, cs);
    final overlay = listsStyleSubpageSystemOverlay(theme, headerBg);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: headerBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        // 리스트 서브페이지(46)보다 낮게 — 검색 필만 얇게
        toolbarHeight: 40,
        // 뒤로만 있으면 108px 슬롯 불필요 → 검색창 가로 확보
        leadingWidth: 56,
        titleSpacing: 0,
        leading: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_popSelf()),
          child: Padding(
            padding: const EdgeInsets.only(
              left: kListsStyleSubpageLeadingEdgeInset,
              right: 4,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 14,
                color: leadingMuted,
              ),
            ),
          ),
        ),
        actions: [
          if (_multiPickActive)
            Padding(
              padding: const EdgeInsets.only(right: kListsStyleSubpageLeadingEdgeInset),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurface.withValues(alpha: 0.55),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _completeMultiPick,
                child: Text(
                  s
                      .get('listMultiPickApply')
                      .replaceAll('{n}', '${_multiPicked.length}'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          // 픽 모드 등 trailing 없을 때 108px 비우지 않음 — 우측 여백만
          if (!_multiPickActive)
            const SizedBox(width: kListsStyleSubpageLeadingEdgeInset),
        ],
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            final q = value.trim();
            setState(() => _submittedQuery = q);
            if (q.isNotEmpty) {
              final country = CountryScope.maybeOf(context)?.country;
              final tag = widget.genreTagFilter?.trim();
              final list = (tag != null && tag.isNotEmpty)
                  ? DramaListService.instance.getDramasMatchingGenreTag(
                      tag,
                      country,
                    )
                  : DramaListService.instance.getListForCountry(country);
              final lower = q.toLowerCase();
              final statCap = (widget.genreTagFilter?.trim().isNotEmpty == true)
                  ? _kTagSearchWatchlistMaxPosters
                  : 10;
              final ids = list
                  .where((item) {
                    final t = DramaListService.instance.getDisplayTitle(item.id, country).toLowerCase();
                    final sub = DramaListService.instance.getDisplaySubtitle(item.id, country).toLowerCase();
                    return t.contains(lower) || sub.contains(lower);
                  })
                  .take(statCap)
                  .map((e) => e.id)
                  .toList();
              DramaSearchStatsService.instance.incrementSearch(ids);
            }
          },
          style: GoogleFonts.notoSansKr(
            fontSize: 15,
            height: 1.2,
            color: cs.onSurface,
          ),
          decoration: InputDecoration(
            hintText: s.get('dramaSearchHint'),
            hintStyle: GoogleFonts.notoSansKr(
              fontSize: 15,
              height: 1.2,
              color: cs.onSurfaceVariant,
            ),
            isDense: true,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            prefixIcon: Icon(LucideIcons.search, size: 18, color: cs.onSurfaceVariant),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 32,
            ),
          ),
        ),
      ),
      body: ValueListenableBuilder<List<DramaItem>>(
        valueListenable: DramaListService.instance.listNotifier,
        builder: (context, _, __) {
          final country = CountryScope.maybeOf(context)?.country;
          final allList = _getAllListCached(country);
          final q = _submittedQuery.toLowerCase();
          final filteredList = _filteredCached(allList, country, q);
          // 태그 목록에서 연 검색은 `genreTagFilter` 인자를 항상 넘김(빈 문자열일 수 있음).
          // `trim().isNotEmpty`만 쓰면 인기 검색·기간 탭 UI로 떨어져 버림.
          if (widget.genreTagFilter != null && !widget.pickMode) {
            final theme = Theme.of(context);
            if (_submittedQuery.isNotEmpty && filteredList.isEmpty) {
              return Center(
                child: Text(
                  s.get('searchNoResults').replaceAll('%s', _submittedQuery),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (allList.isEmpty) {
              return Center(
                child: Text(
                  s.get('tagDramaListEmpty'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }
            final displayList = (_submittedQuery.isNotEmpty
                    ? filteredList
                    : allList)
                .take(_kTagSearchWatchlistMaxPosters)
                .toList();
            return _buildTagGenreWatchlistGrid(
              context,
              displayList,
              country,
              theme.scaffoldBackgroundColor,
            );
          }
          if (_submittedQuery.isNotEmpty && filteredList.isEmpty) {
            // 워치리스트 등 pick 모드: 목록 로드 전 안내 문구 대신 빈 화면(곧 그리드 표시)
            if (widget.pickMode) {
              return const SizedBox.expand();
            }
            return Center(
              child: Text(
                s.get('searchNoResults').replaceAll('%s', _submittedQuery),
                style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            );
          }
          // 검색어 있음: 필터 결과(일반 10개 / 픽 모드 최대 32개)
          if (_submittedQuery.isNotEmpty) {
            final cap = widget.pickMode ? _kPickModeRandomCount : 10;
            final displayList = filteredList.take(cap).toList();
            return _buildDramaGrid(
              context,
              displayList,
              country,
              cs,
              s,
              sectionTitle: s.get('searchResults'),
              onReturnFromDetail: null,
              titleOnly: widget.pickMode,
            );
          }
          // 즐겨찾기 픽 + 검색어 없음: 인기 API 없이 카탈로그에서 랜덤 32편.
          if (widget.pickMode) {
            final displayList = _pickDisplayCached(allList, country);
            return _buildDramaGrid(
              context,
              displayList,
              country,
              cs,
              s,
              sectionTitle: null,
              onReturnFromDetail: null,
              titleOnly: true,
              gridChildAspectRatio: 0.58,
            );
          }
          return FutureBuilder<List<String>>(
            future: _topIdsFuture,
            builder: (context, snap) {
              final topIds = snap.data ?? [];
              final idSet = topIds.toSet();
              final byId = {for (final e in allList) e.id: e};
              final ordered = <DramaItem>[];
              for (final id in topIds) {
                final found = byId[id];
                if (found != null) ordered.add(found);
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
                    child: _buildDramaGrid(
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

  Widget _searchGridPosterPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(LucideIcons.tv, size: 24, color: cs.onSurfaceVariant),
      ),
    );
  }

  void _prefetchSearchGridRatings(List<DramaItem> displayList) {
    final capped =
        displayList.length > 60 ? displayList.sublist(0, 60) : displayList;
    if (capped.isEmpty) return;
    final sig =
        '${displayList.length}\u001f${capped.map((e) => e.id).join('\u001f')}';
    if (sig == _searchGridRatingPrefetchSig) return;
    _searchGridRatingPrefetchSig = sig;
    unawaited(
      ReviewService.instance
          .prefetchDramaRatingStats(capped.map((e) => e.id))
          .then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  /// 드라마 탭 그리드와 동일 카드 — 검색 화면만 **4열**.
  Widget _buildDramaGrid(
    BuildContext navigatorContext,
    List<DramaItem> displayList,
    String? country,
    ColorScheme cs,
    dynamic s, {
    String? sectionTitle,
    VoidCallback? onReturnFromDetail,
    bool titleOnly = false,
    double? gridChildAspectRatio,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchSearchGridRatings(displayList);
    });

    final title = sectionTitle ?? s.get('popularSearch');
    final r = dramaGridScreenScale(navigatorContext);
    final gap = 8 * r;
    final aspect = gridChildAspectRatio ?? (titleOnly ? 0.58 : 0.47);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sectionTitle != null && sectionTitle.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16 * r, 8 * r, 16 * r, 10 * r),
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
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
              gap,
              sectionTitle != null && sectionTitle.isNotEmpty ? 0 : 8 * r,
              gap,
              24 +
                  MediaQuery.of(navigatorContext).padding.bottom,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              // 제목+별+장르 줄이면 0.47, 제목만이면 세로 여유로 0.58 근처.
              childAspectRatio: aspect,
              crossAxisSpacing: gap,
              mainAxisSpacing: 6 * r,
            ),
            itemCount: displayList.length,
            itemBuilder: (cellContext, index) {
              final item = displayList[index];
              final displayTitle =
                  DramaListService.instance.getDisplayTitle(item.id, country);
              final displaySubtitle =
                  DramaListService.instance.getDisplaySubtitle(item.id, country);
              final imageUrl = DramaListService.instance
                      .getDisplayImageUrl(item.id, country) ??
                  item.imageUrl;
              final rating = ReviewService.instance.ratingForListCard(
                item.id,
                catalogRating: item.rating,
              );
              return DramaGridCard(
                displayTitle:
                    displayTitle.isNotEmpty ? displayTitle : item.title,
                displaySubtitle: displaySubtitle,
                imageUrl: imageUrl,
                rating: rating,
                posterPlaceholder:
                    _searchGridPosterPlaceholder(cellContext),
                titleOnly: titleOnly,
                pickMultiSelected:
                    _multiPickActive && _multiPickedIds.contains(item.id),
                onTap: () async {
                  if (widget.pickMode) {
                    final blocked =
                        widget.pickExcludeDramaIds?.contains(item.id) ??
                            false;
                    if (blocked) {
                      if (!mounted) return;
                      await _showPickDuplicateDialog(context, s);
                      return;
                    }
                    if (_multiPickActive) {
                      _toggleMultiPick(item, s);
                      unawaited(
                        DramaSearchStatsService.instance.incrementClick(
                          item.id,
                        ),
                      );
                      return;
                    }
                    if (!mounted) return;
                    await _popSelf<DramaItem>(item);
                    if (mounted) {
                      unawaited(
                        DramaSearchStatsService.instance.incrementClick(
                          item.id,
                        ),
                      );
                    }
                    return;
                  }
                  unawaited(
                    DramaSearchStatsService.instance.incrementClick(item.id),
                  );
                  final detail =
                      DramaListService.instance.buildDetailForItem(item, country);
                  if (!mounted) return;
                  await Navigator.push<void>(
                    context,
                    CupertinoPageRoute<void>(
                      builder: (_) => DramaDetailPage(detail: detail),
                    ),
                  );
                  if (mounted) {
                    onReturnFromDetail?.call();
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isFavoriteDrama(String dramaId) {
    if (dramaId.trim().isEmpty) return false;
    return UserProfileService.instance.favoritesNotifier.value
        .any((e) => e.dramaId == dramaId);
  }

  /// 태그 검색: [WatchlistScreen]과 동일 4열·포스터만·최대 4편.
  Widget _buildTagGenreWatchlistGrid(
    BuildContext context,
    List<DramaItem> displayList,
    String? country,
    Color gridBg,
  ) {
    return AnimatedBuilder(
      animation: UserProfileService.instance.favoritesNotifier,
      builder: (context, _) {
        return ColoredBox(
          color: gridBg,
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              _kTagSearchWatchlistGridPadH,
              10,
              _kTagSearchWatchlistGridPadH,
              28,
            ),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: _kTagSearchWatchlistGridAspect,
              crossAxisSpacing: _kTagSearchWatchlistGridGap,
              mainAxisSpacing: _kTagSearchWatchlistGridGap,
            ),
            itemCount: displayList.length,
            itemBuilder: (gridContext, index) {
              final item = displayList[index];
              final dramaId = item.id;
              final imageUrl = DramaListService.instance
                      .getDisplayImageUrl(dramaId, country) ??
                  item.imageUrl;
              return _TagSearchWatchlistPosterCell(
                key: ValueKey(dramaId),
                imageUrl: imageUrl,
                showFavoriteStar: _isFavoriteDrama(dramaId),
                onOpen: () async {
                  unawaited(
                    DramaSearchStatsService.instance.incrementClick(dramaId),
                  );
                  final detail =
                      DramaListService.instance.buildDetailForItem(item, country);
                  if (!mounted) return;
                  await Navigator.push<void>(
                    gridContext,
                    CupertinoPageRoute<void>(
                      builder: (_) => DramaDetailPage(detail: detail),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// [WatchlistScreen] `_WatchlistPosterCell`과 동일 포스터만(제거 버튼 없음).
class _TagSearchWatchlistPosterCell extends StatelessWidget {
  const _TagSearchWatchlistPosterCell({
    super.key,
    required this.imageUrl,
    required this.onOpen,
    this.showFavoriteStar = false,
  });

  final String? imageUrl;
  final VoidCallback onOpen;
  final bool showFavoriteStar;

  static const double _radius = 4.5;
  static const double _borderWidth = 0.6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final url = imageUrl;
    final borderColor = isDark
        ? const Color(0xFF4A5568)
        : cs.outline.withValues(alpha: 0.38);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: borderColor, width: _borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF1E252E)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(_radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null &&
                      (url.startsWith('http://') || url.startsWith('https://')))
                    OptimizedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  else if (url != null && url.isNotEmpty)
                    Image.asset(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          LucideIcons.tv,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Icon(
                        LucideIcons.tv,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showFavoriteStar)
            Positioned(
              top: 3,
              left: 3,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 13,
                  color: Color(0xFFFFB020),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
