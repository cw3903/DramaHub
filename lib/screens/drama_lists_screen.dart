import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import 'lists_screen.dart';
import '../services/custom_drama_list_service.dart';
import '../services/drama_list_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';

/// 리스트 피드·탭 하단 구분선 (다크 테마에서 `outline` 12%는 거의 안 보임).
Color dramaListsDividerColor(ColorScheme cs) {
  return cs.brightness == Brightness.dark
      ? cs.onSurface.withValues(alpha: 0.28)
      : cs.outline.withValues(alpha: 0.42);
}

/// 드라마 상세 스탯 바「List」— 이 작품이 포함된 리스트 피드.
class DramaListsScreen extends StatefulWidget {
  const DramaListsScreen({
    super.key,
    required this.dramaId,
    required this.dramaTitle,
    this.dramaPosterUrl,
  });

  final String dramaId;
  final String dramaTitle;
  final String? dramaPosterUrl;

  @override
  State<DramaListsScreen> createState() => _DramaListsScreenState();
}

class _DramaListsScreenState extends State<DramaListsScreen> {
  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
    CustomDramaListService.instance.loadIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final country = CountryScope.maybeOf(context)?.country;
    final isDark = theme.brightness == Brightness.dark;
    final headerBarBg = listsStyleSubpageHeaderBackground(theme);
    final overlay = listsStyleSubpageSystemOverlay(theme, headerBarBg);
    final dividerColor = dramaListsDividerColor(cs);

    return ListsStyleSwipeBack(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: widget.dramaTitle,
            onBack: () => popListsStyleSubpage(context),
            trailing: ListsStyleSubpageHeaderAddButton(
              onTap: () async {
                await Navigator.push<bool>(
                  context,
                  CupertinoPageRoute<bool>(
                    builder: (_) => DramaListEditorScreen(
                      initialDramaId: widget.dramaId,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        body: ValueListenableBuilder<List>(
          valueListenable: CustomDramaListService.instance.listsNotifier,
          builder: (context, allLists, _) {
            final filtered = allLists
                .where((e) => e.dramaIds.contains(widget.dramaId))
                .toList();

            if (filtered.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.library,
                        size: 38,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.get('dramaListsEmptyFeed'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 1,
                color: dividerColor,
              ),
              itemBuilder: (context, index) {
                final list = filtered[index];
                return CustomDramaListCard(
                  data: list,
                  strings: s,
                  isDark: isDark,
                  colorScheme: cs,
                  country: country,
                );
              },
            );
          },
        ),
      ),
    ),
    );
  }
}
