import 'dart:async' show unawaited;
import 'dart:math' show Random;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/drama_search_stats_service.dart';
import '../services/review_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/drama_grid_card.dart';
import 'drama_detail_page.dart';

/// 리뷰(드라마) 탭 검색창 탭 시 — 실제 드라마 목록(dramas.json) 기준 제목·장르 검색
class DramaSearchScreen extends StatefulWidget {
  const DramaSearchScreen({
    super.key,
    this.pickMode = false,
    this.pickExcludeDramaIds,
    this.multiPickMax,
  });

  /// true면 행 탭 시 [DramaItem]만 반환하고 상세로 이동하지 않음 (커뮤니티 리뷰용)
  final bool pickMode;

  /// pick 모드에서 이미 목록에 넣은 드라마 id. 탭 시 반환하지 않고 안내 다이얼로그만 표시.
  final Set<String>? pickExcludeDramaIds;

  /// null이면 탭 시 1편 즉시 [Navigator.pop] · 지정 시 이 화면에서 최대 [multiPickMax]편까지 선택 후 앱바 완료로 [List] 반환.
  final int? multiPickMax;

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

  /// getListForCountry / 필터 / 픽 32편 — 빌드마다 재계산 방지
  List<DramaItem>? _memListRef;
  String? _memCountry;
  List<DramaItem>? _memAllList;
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
    if (identical(_memListRef, ref) &&
        _memCountry == country &&
        _memAllList != null) {
      return _memAllList!;
    }
    _memListRef = ref;
    _memCountry = country;
    _memAllList = DramaListService.instance.getListForCountry(country);
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
    Navigator.pop(context, List<DramaItem>.from(_multiPicked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
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
        actions: [
          if (_multiPickActive)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurface.withValues(alpha: 0.55),
                ),
                onPressed: _completeMultiPick,
                child: Text(
                  s
                      .get('listMultiPickApply')
                      .replaceAll('{n}', '${_multiPicked.length}'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
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
          final country = CountryScope.maybeOf(context)?.country;
          final allList = _getAllListCached(country);
          final q = _submittedQuery.toLowerCase();
          final filteredList = _filteredCached(allList, country, q);
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
              final rating =
                  ReviewService.instance.getByDramaId(item.id)?.rating ??
                      item.rating;
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
                      if (!mounted || !navigatorContext.mounted) return;
                      await _showPickDuplicateDialog(navigatorContext, s);
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
                    if (!mounted || !navigatorContext.mounted) return;
                    Navigator.pop(navigatorContext, item);
                    unawaited(
                      DramaSearchStatsService.instance.incrementClick(item.id),
                    );
                    return;
                  }
                  unawaited(
                    DramaSearchStatsService.instance.incrementClick(item.id),
                  );
                  final detail =
                      DramaListService.instance.buildDetailForItem(item, country);
                  if (!mounted || !navigatorContext.mounted) return;
                  await Navigator.push<void>(
                    navigatorContext,
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
}
