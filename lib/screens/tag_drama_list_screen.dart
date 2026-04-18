import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/locale_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';
import 'drama_search_screen.dart';

/// [WatchlistScreen] 본문 그리드와 동일 — 4열·포스터만·최대 4편.
const double _kTagListGridAspect = 0.74;
const double _kTagListGridPadH = 15;
const double _kTagListGridGap = 7;
const int _kTagListMaxPosters = 4;

bool _isFavoriteDrama(String dramaId) {
  if (dramaId.trim().isEmpty) return false;
  return UserProfileService.instance
      .favoritesVisibleForCurrentLocale()
      .any((e) => e.dramaId == dramaId);
}

/// 시놉시스 아래 장르·태그 탭 시 — 카탈로그에서 해당 태그가 부제에 포함된 작품만 표시.
class TagDramaListScreen extends StatefulWidget {
  const TagDramaListScreen({super.key, required this.tag});

  final String tag;

  @override
  State<TagDramaListScreen> createState() => _TagDramaListScreenState();
}

class _TagDramaListScreenState extends State<TagDramaListScreen> {
  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
  }

  Future<void> _openDrama(
    BuildContext context,
    DramaItem item,
    String? country,
  ) async {
    await DramaDetailPage.openFromItem(context, item, country: country);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final strings = CountryScope.of(context).strings;
    final bodyBg = theme.scaffoldBackgroundColor;
    final headerBarBg = listsStyleSubpageHeaderBackground(theme);
    final listAppBarOverlay = listsStyleSubpageSystemOverlay(theme, headerBarBg);
    final barFg = listsStyleSubpageBarForeground(theme, cs);

    return ListsStyleSwipeBack(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: listAppBarOverlay,
      child: Scaffold(
        backgroundColor: bodyBg,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: widget.tag,
            centerTitle: _DramaDetailSynopsisTagPill(label: widget.tag),
            onBack: () => popListsStyleSubpage(context),
            trailing: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Navigator.push<void>(
                    context,
                    CupertinoPageRoute<void>(
                      builder: (_) =>
                          DramaSearchScreen(genreTagFilter: widget.tag),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(LucideIcons.search, size: 22, color: barFg),
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ValueListenableBuilder<List<DramaItem>>(
            valueListenable: DramaListService.instance.listNotifier,
            builder: (context, value, _) {
              final dramas = DramaListService.instance
                  .getDramasMatchingGenreTag(widget.tag, country)
                  .take(_kTagListMaxPosters)
                  .toList();
              if (dramas.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      strings.get('tagDramaListEmpty'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                );
              }
              return AnimatedBuilder(
                animation: Listenable.merge([
                  LocaleService.instance.localeNotifier,
                  UserProfileService.instance.favoritesNotifier,
                ]),
                builder: (context, _) {
                  return ColoredBox(
                    color: bodyBg,
                    child: GridView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        _kTagListGridPadH,
                        10,
                        _kTagListGridPadH,
                        28,
                      ),
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: _kTagListGridAspect,
                        crossAxisSpacing: _kTagListGridGap,
                        mainAxisSpacing: _kTagListGridGap,
                      ),
                      itemCount: dramas.length,
                      itemBuilder: (context, index) {
                        final item = dramas[index];
                        final dramaId = item.id;
                        final imageUrl = DramaListService.instance
                                .getDisplayImageUrl(dramaId, country) ??
                            item.imageUrl;
                        return _TagDramaListPosterCell(
                          key: ValueKey(dramaId),
                          imageUrl: imageUrl,
                          showFavoriteStar: _isFavoriteDrama(dramaId),
                          onOpen: () => _openDrama(context, item, country),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

/// [WatchlistScreen] `_WatchlistPosterCell` / 태그 검색과 동일 — 포스터만.
class _TagDramaListPosterCell extends StatelessWidget {
  const _TagDramaListPosterCell({
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

/// [DramaDetailPage] 줄거리 장르 태그 pill과 동일 스타일(헤더 제목).
class _DramaDetailSynopsisTagPill extends StatelessWidget {
  const _DramaDetailSynopsisTagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 14,
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                  height: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 0),
          SizedBox(
            width: 12,
            height: 14,
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 0.5),
                child: Icon(
                  LucideIcons.chevron_right,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
