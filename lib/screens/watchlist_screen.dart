import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../models/watchlist_item.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/locale_service.dart';
import '../services/user_profile_service.dart';
import '../services/watchlist_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';
import 'drama_search_screen.dart';
import 'login_page.dart';

bool _isFavoriteDrama(String dramaId) {
  if (dramaId.trim().isEmpty) return false;
  return UserProfileService.instance
      .favoritesVisibleForCurrentLocale()
      .any((e) => e.dramaId == dramaId);
}

List<WatchlistItem> _sortedWatchlist(List<WatchlistItem> items, bool newestFirst) {
  final copy = List<WatchlistItem>.from(items);
  copy.sort(
    (a, b) => newestFirst
        ? b.addedAt.compareTo(a.addedAt)
        : a.addedAt.compareTo(b.addedAt),
  );
  return copy;
}

/// [MainScreen] 하단 탭(`extendBody`) 위 영역 안에서 빈 화면 콘텐츠를 세로 중앙에 두기 위한 하단 예약.
double _watchlistEmptyBottomReserve(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.padding.bottom + kBottomNavigationBarHeight + 16;
}

/// List 상세(`CustomDramaListDetailScreen`) 그리드와 동일 — `childAspectRatio` = 가로/세로.
const double _kListStyleGridAspectRatio = 0.74;
/// List 상세 그리드 좌우 패딩과 동일.
const double _kListStyleGridHorizontalPadding = 15;
/// List 상세 그리드 셀 간격과 동일.
const double _kListStyleGridGap = 7;

Future<void> _openWatchlistAddDramaSearch(BuildContext context) async {
  FocusManager.instance.primaryFocus?.unfocus();
  DramaListService.instance.loadFromAsset();
  final country = CountryScope.maybeOf(context)?.country ??
      UserProfileService.instance.signupCountryNotifier.value;
  final exclude = WatchlistService.instance.itemsNotifier.value
      .map((e) => e.dramaId)
      .toSet();
  // 프로필 즐겨찾기 슬롯과 동일하게 Material 라우트 사용 (Cupertino만 쓸 때 결과 미전달 이슈 방지).
  final result = await Navigator.push<DramaItem>(
    context,
    MaterialPageRoute<DramaItem>(
      builder: (_) => DramaSearchScreen(
        pickMode: true,
        pickExcludeDramaIds: exclude.isEmpty ? null : exclude,
      ),
    ),
  );
  if (!context.mounted || result == null) return;
  await WatchlistService.instance.add(result.id, country);
}

/// 보고 싶은 드라마(Watchlist) — Letterboxd 스타일 그리드·앱바
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WatchlistService.instance.loadIfNeeded(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = CountryScope.of(context).strings;
    final titleText = s.get('tabWatchlist');
    final headerBg = listsStyleSubpageHeaderBackground(theme);
    final overlay = listsStyleSubpageSystemOverlay(theme, headerBg);

    return AnimatedBuilder(
      animation: Listenable.merge([
        LocaleService.instance.localeNotifier,
        WatchlistService.instance.itemsNotifier,
        UserProfileService.instance.favoritesNotifier,
        UserProfileService.instance.nicknameNotifier,
      ]),
      builder: (context, _) {
        return ListsStyleSwipeBack(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: PreferredSize(
              preferredSize:
                  ListsStyleSubpageHeaderBar.preferredSizeOf(context),
              child: ListsStyleSubpageHeaderBar(
                title: titleText,
                onBack: () => popListsStyleSubpage(context),
                trailing: ListsStyleSubpageHeaderAddButton(
                  onTap: () => _openWatchlistAddDramaSearch(context),
                ),
              ),
            ),
            body: _WatchlistBody(
              gridBackground: theme.scaffoldBackgroundColor,
            ),
          ),
        ),
        );
      },
    );
  }
}

class _WatchlistBody extends StatelessWidget {
  const _WatchlistBody({
    required this.gridBackground,
  });

  final Color gridBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;

    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.isLoggedIn,
      builder: (context, loggedIn, _) {
        if (!loggedIn) {
          return ColoredBox(
            color: gridBackground,
            child: Padding(
              padding: EdgeInsets.only(bottom: _watchlistEmptyBottomReserve(context)),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Icon(
                          LucideIcons.clock,
                          size: 56,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.get('watchlistLoginRequired'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.center,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                          child: Text(s.get('login')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return ValueListenableBuilder<List<WatchlistItem>>(
          valueListenable: WatchlistService.instance.itemsNotifier,
          builder: (context, items, _) {
            if (items.isEmpty) {
              return ColoredBox(
                color: gridBackground,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: _watchlistEmptyBottomReserve(context),
                  ),
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openWatchlistAddDramaSearch(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.layout_grid,
                              size: 56,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              s.get('watchlistEmptyTitle'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final country = CountryScope.maybeOf(context)?.country ??
                UserProfileService.instance.signupCountryNotifier.value;
            final sorted = _sortedWatchlist(items, true);
            const crossAxis = 4;

            return ColoredBox(
              color: gridBackground,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  _kListStyleGridHorizontalPadding,
                  10,
                  _kListStyleGridHorizontalPadding,
                  28,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxis,
                  childAspectRatio: _kListStyleGridAspectRatio,
                  crossAxisSpacing: _kListStyleGridGap,
                  mainAxisSpacing: _kListStyleGridGap,
                ),
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final w = sorted[index];
                  final dramaId = w.dramaId;
                  final imageUrl = DramaListService.instance
                          .getDisplayImageUrl(dramaId, country) ??
                      w.imageUrlSnapshot;
                  final fav = _isFavoriteDrama(dramaId);

                  return _WatchlistPosterCell(
                    key: ValueKey(dramaId),
                    imageUrl: imageUrl,
                    showFavoriteStar: fav,
                    removeTooltip: s.get('watchlistRemoveTitle'),
                    onOpen: () async {
                      final item =
                          WatchlistService.instance.resolveDramaItem(dramaId);
                      await DramaDetailPage.openFromItem(
                        context,
                        item,
                        country: country,
                      );
                    },
                    onRemove: () {
                      unawaited(WatchlistService.instance.remove(dramaId));
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _WatchlistPosterCell extends StatelessWidget {
  const _WatchlistPosterCell({
    super.key,
    required this.imageUrl,
    required this.onOpen,
    required this.onRemove,
    required this.removeTooltip,
    this.showFavoriteStar = false,
  });

  final String? imageUrl;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final String removeTooltip;
  final bool showFavoriteStar;

  /// List 상세 `_PosterCell`과 동일.
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
              onLongPress: onRemove,
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
          Positioned(
            top: 2,
            right: 2,
            child: Tooltip(
              message: removeTooltip,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onRemove,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.52),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
