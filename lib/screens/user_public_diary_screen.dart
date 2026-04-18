import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/watch_history_service.dart';
import '../services/drama_list_service.dart';
import '../services/country_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import 'drama_detail_page.dart';
import 'diary_screen.dart' show
    DiaryEntryRow,
    DiaryMonthHeaderDelegate,
    dramaItemForDiaryEntry,
    diaryMonthHeaderLabel,
    groupDiaryByMonth;

/// 타 유저의 다이어리 (읽기 전용).
class UserPublicDiaryScreen extends StatefulWidget {
  const UserPublicDiaryScreen({
    super.key,
    required this.uid,
    this.ownerDisplayName,
  });

  final String uid;
  final String? ownerDisplayName;

  @override
  State<UserPublicDiaryScreen> createState() => _UserPublicDiaryScreenState();
}

class _UserPublicDiaryScreenState extends State<UserPublicDiaryScreen> {
  late Future<List<WatchedDramaItem>> _future;
  bool _newestFirst = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _future = WatchHistoryService.instance.fetchForUid(widget.uid);
    DramaListService.instance.loadFromAsset();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _headerTitle(dynamic s) {
    final name = widget.ownerDisplayName?.trim() ?? '';
    if (name.isNotEmpty) {
      return s.get('diaryTitleWithName').replaceAll('{name}', name);
    }
    return s.get('diary');
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

  Future<void> _openDrama(BuildContext context, WatchedDramaItem item) async {
    final country = CountryScope.maybeOf(context)?.country ??
        CountryService.instance.countryNotifier.value;
    final dramaItem = dramaItemForDiaryEntry(item, country);
    await DramaDetailPage.openFromItem(context, dramaItem, country: country);
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headerBg = listsStyleSubpageHeaderBackground(theme);
    final country = CountryScope.maybeOf(context)?.country ??
        CountryService.instance.countryNotifier.value;
    final appCountry = CountryScope.of(context).country;
    final sortIconColor = cs.onSurfaceVariant.withValues(alpha: 0.78);

    return ListsStyleSwipeBack(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: listsStyleSubpageSystemOverlay(theme, headerBg),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: _headerTitle(s),
            onBack: () => popListsStyleSubpage(context),
            trailing: Tooltip(
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
          ),
        ),
        body: FutureBuilder<List<WatchedDramaItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data ?? [];
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

            // 내 다이어리와 동일: 월·년 섹션 헤더 + 그룹 내 일(day) 표시
            final groups = groupDiaryByMonth(list, _newestFirst);
            final scaffoldBg = theme.scaffoldBackgroundColor;
            final monthBarBg = Color.lerp(
                  cs.surfaceContainerHighest,
                  scaffoldBg,
                  0.35,
                ) ??
                cs.surfaceContainerHighest;
            final monthBarFg = cs.onSurfaceVariant.withValues(alpha: 0.88);
            final divAlpha =
                theme.brightness == Brightness.dark ? 0.30 : 0.22;

            final slivers = <Widget>[];
            for (var gi = 0; gi < groups.length; gi++) {
              final g = groups[gi];
              final label = diaryMonthHeaderLabel(appCountry, g.year, g.month);
              slivers.add(
                SliverPersistentHeader(
                  pinned: true,
                  delegate: DiaryMonthHeaderDelegate(
                    label: label,
                    background: monthBarBg,
                    foreground: monthBarFg,
                  ),
                ),
              );
              final children = <Widget>[];
              for (var ii = 0; ii < g.items.length; ii++) {
                final item = g.items[ii];
                final showDayNumber = ii == 0 ||
                    (g.items[ii - 1].watchedAt.year != item.watchedAt.year ||
                        g.items[ii - 1].watchedAt.month !=
                            item.watchedAt.month ||
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

            return CustomScrollView(
              primary: false,
              controller: _scrollController,
              slivers: slivers,
            );
          },
        ),
      ),
    ),
    );
  }
}
