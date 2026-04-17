import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/custom_drama_list.dart';
import '../models/watchlist_item.dart';
import '../services/custom_drama_list_service.dart';
import '../services/drama_list_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/optimized_network_image.dart';
import 'custom_list_navigation.dart';

/// 타 유저의 커스텀 리스트 (읽기 전용).
class UserPublicListsScreen extends StatefulWidget {
  const UserPublicListsScreen({
    super.key,
    required this.uid,
    this.ownerDisplayName,
  });

  final String uid;
  final String? ownerDisplayName;

  @override
  State<UserPublicListsScreen> createState() => _UserPublicListsScreenState();
}

class _UserPublicListsScreenState extends State<UserPublicListsScreen> {
  late Future<List<CustomDramaList>> _future;

  @override
  void initState() {
    super.initState();
    _future = CustomDramaListService.instance.fetchListsForUid(widget.uid);
    DramaListService.instance.loadFromAsset();
  }

  String _headerTitle(dynamic s) {
    final name = widget.ownerDisplayName?.trim() ?? '';
    if (name.isNotEmpty) {
      return s.get('listsTitleWithName').replaceAll('{name}', name);
    }
    return s.get('tabLists');
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = listsStyleSubpageHeaderBackground(theme);
    final country = CountryScope.maybeOf(context)?.country;

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
          ),
        ),
        body: FutureBuilder<List<CustomDramaList>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final lists = snap.data ?? [];
            if (lists.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.library,
                        size: 56,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.get('tabLists') as String,
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

            final widgets = <Widget>[];
            for (final list in lists) {
              widgets.add(
                _PublicListCard(
                  data: list,
                  strings: s,
                  isDark: isDark,
                  colorScheme: cs,
                  country: country,
                ),
              );
              widgets.add(
                Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outline.withValues(alpha: isDark ? 0.30 : 0.22),
                ),
              );
            }

            return ListView(
              padding: EdgeInsets.zero,
              children: widgets,
            );
          },
        ),
      ),
      ),
    );
  }
}

// ─── 카드 위젯 ─────────────────────────────────────────────────────────────

class _PublicListCard extends StatelessWidget {
  const _PublicListCard({
    required this.data,
    required this.strings,
    required this.isDark,
    required this.colorScheme,
    required this.country,
  });

  /// [ListsScreen] 카드와 동일: 설명/포스터 마지막 ↔ 구분선 간격.
  static const double _gapLastContentToDivider = 10;

  static const double _gapBelowPosterWhenNoDescription = 7;

  static const TextHeightBehavior _listDescriptionTextHeightBehavior =
      TextHeightBehavior(applyHeightToLastDescent: false);

  final CustomDramaList data;
  final dynamic strings;
  final bool isDark;
  final ColorScheme colorScheme;
  final String? country;

  @override
  Widget build(BuildContext context) {
    final trimmedDesc = data.description.trim();
    final hasDesc = trimmedDesc.isNotEmpty;
    final cs = colorScheme;
    final titleColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : cs.onSurface.withValues(alpha: 0.7);
    final muted = (isDark ? Colors.white : cs.onSurfaceVariant)
        .withValues(alpha: isDark ? 0.55 : 0.8);
    final items = data.dramaIds
        .take(20)
        .map(
          (id) => WatchlistItem(
            dramaId: id,
            addedAt: data.updatedAt,
            imageUrlSnapshot: DramaListService.instance
                .getDisplayImageUrl(id, country),
            titleSnapshot:
                DramaListService.instance.getDisplayTitle(id, country),
          ),
        )
        .toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => openCustomDramaListDetail(context, data),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      data.title,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                  ),
                  Text(
                    strings
                        .get('listsFilmCount')
                        .replaceAll('{n}', '${data.dramaIds.length}'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PosterStrip(
                    items: items,
                    isDark: isDark,
                    colorScheme: cs,
                  ),
                  if (!hasDesc)
                    const SizedBox(height: _gapBelowPosterWhenNoDescription),
                  if (hasDesc) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        trimmedDesc,
                        textAlign: TextAlign.start,
                        textHeightBehavior: _listDescriptionTextHeightBehavior,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          height: 1.45,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: _gapLastContentToDivider),
          ],
        ),
      ),
    );
  }
}

class _PosterStrip extends StatelessWidget {
  const _PosterStrip({
    required this.items,
    required this.isDark,
    required this.colorScheme,
  });

  final List<WatchlistItem> items;
  final bool isDark;
  final ColorScheme colorScheme;

  static const double _h = 84;
  static const double _w = _h * 2 / 3;
  static const double _r = 6;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : cs.outline.withValues(alpha: 0.42);
    final side = BorderSide(color: borderColor, width: 1);

    if (items.isEmpty) {
      return SizedBox(
        width: _w,
        height: _h,
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(_r),
          child: Container(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(side),
              borderRadius: BorderRadius.circular(_r),
              color: isDark
                  ? const Color(0xFF2C3440)
                  : cs.surfaceContainerHighest,
            ),
            child: Icon(
              LucideIcons.library,
              size: 22,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _h,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              _buildCell(items[i], i, side, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(
    WatchlistItem item,
    int index,
    BorderSide side,
    ColorScheme cs,
  ) {
    final url = item.imageUrlSnapshot?.trim();
    final hasImage =
        url != null && (url.startsWith('http://') || url.startsWith('https://'));
    final isFirst = index == 0;
    final isLast = index == items.length - 1;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? _r : 0),
      bottomLeft: Radius.circular(isFirst ? _r : 0),
      topRight: Radius.circular(isLast ? _r : 0),
      bottomRight: Radius.circular(isLast ? _r : 0),
    );

    return SizedBox(
      width: _w,
      height: _h,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: side,
              bottom: side,
              left: isFirst ? side : BorderSide.none,
              right: side,
            ),
          ),
          child: hasImage
              ? OptimizedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: _w,
                  height: _h,
                  memCacheWidth: 160,
                  memCacheHeight: 240,
                )
              : ColoredBox(
                  color: isDark
                      ? const Color(0xFF2C3440)
                      : cs.surfaceContainerHighest,
                  child: Icon(
                    LucideIcons.tv,
                    size: 20,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                  ),
                ),
        ),
      ),
    );
  }
}
