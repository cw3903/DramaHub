import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/watchlist_item.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/user_profile_service.dart';
import '../services/watchlist_service.dart';
import '../widgets/app_bar_back_icon_button.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';
import 'login_page.dart';

String _watchlistOwnerDisplayName() {
  final n = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (n != null && n.isNotEmpty) return n;
  final d = AuthService.instance.currentUser.value?.displayName?.trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('@')) return d.split('@').first;
    return d;
  }
  return 'Member';
}

bool _isFavoriteDrama(String dramaId) {
  if (dramaId.trim().isEmpty) return false;
  return UserProfileService.instance.favoritesNotifier.value
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

/// 보고 싶은 드라마(Watchlist) — Letterboxd 스타일 그리드·앱바
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  bool _newestFirst = true;
  /// true: 4열 촘촘 그리드, false: 3열(포스터 조금 큼)
  bool _fourColumns = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WatchlistService.instance.loadIfNeeded(force: true);
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final isDark = theme.brightness == Brightness.dark;
    final barBg = theme.scaffoldBackgroundColor;
    final name = _watchlistOwnerDisplayName();
    final titleText =
        s.get('watchlistTitleWithName').replaceAll('{name}', name);

    return AnimatedBuilder(
      animation: Listenable.merge([
        WatchlistService.instance.itemsNotifier,
        UserProfileService.instance.favoritesNotifier,
        UserProfileService.instance.nicknameNotifier,
      ]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            toolbarHeight: kToolbarHeight,
            centerTitle: true,
            title: Text(
              titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.12,
                color: isDark ? Colors.white : cs.onSurface,
              ),
            ),
            backgroundColor: barBg,
            foregroundColor: isDark ? Colors.white : cs.onSurface,
            elevation: 0,
            iconTheme: IconThemeData(
              color: isDark ? Colors.white : cs.onSurface,
            ),
            leading: AppBarBackIconButton(
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _fourColumns ? Icons.view_week_outlined : Icons.grid_view_rounded,
                  size: 22,
                ),
                onPressed: () =>
                    setState(() => _fourColumns = !_fourColumns),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _openSortSheet(context, s),
                      child: Ink(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.sliders_horizontal,
                          size: 18,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: _WatchlistBody(
            newestFirst: _newestFirst,
            fourColumns: _fourColumns,
            gridBackground: theme.scaffoldBackgroundColor,
          ),
        );
      },
    );
  }
}

class _WatchlistBody extends StatelessWidget {
  const _WatchlistBody({
    required this.newestFirst,
    required this.fourColumns,
    required this.gridBackground,
  });

  final bool newestFirst;
  final bool fourColumns;
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
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 56,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
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
                    FilledButton(
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
                  ],
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
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.layout_grid,
                          size: 56,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.get('watchlistEmptyTitle'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.get('watchlistEmptyHint'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final country = CountryScope.maybeOf(context)?.country ??
                UserProfileService.instance.signupCountryNotifier.value;
            final sorted = _sortedWatchlist(items, newestFirst);
            final crossAxis = fourColumns ? 4 : 3;
            const spacing = 6.0;
            final ratio = fourColumns ? 0.62 : 0.64;

            return ColoredBox(
              color: gridBackground,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 28),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxis,
                  childAspectRatio: ratio,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
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
                    onOpen: () {
                      final item =
                          WatchlistService.instance.resolveDramaItem(dramaId);
                      final detail = DramaListService.instance
                          .buildDetailForItem(item, country);
                      Navigator.push<void>(
                        context,
                        CupertinoPageRoute<void>(
                          builder: (_) => DramaDetailPage(detail: detail),
                        ),
                      );
                    },
                    onLongPressRemove: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(
                            s.get('watchlistRemoveTitle'),
                            style: GoogleFonts.notoSansKr(),
                          ),
                          content: Text(
                            s.get('watchlistRemoveMessage'),
                            style: GoogleFonts.notoSansKr(),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(
                                s.get('cancel'),
                                style: GoogleFonts.notoSansKr(),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                s.get('ok'),
                                style: GoogleFonts.notoSansKr(),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await WatchlistService.instance.remove(dramaId);
                      }
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
    required this.onLongPressRemove,
    this.showFavoriteStar = false,
  });

  final String? imageUrl;
  final VoidCallback onOpen;
  final VoidCallback onLongPressRemove;
  final bool showFavoriteStar;

  static const _radius = 4.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = imageUrl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPressRemove,
        borderRadius: BorderRadius.circular(_radius),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: cs.surfaceContainerHighest.withValues(alpha: 0.5)),
              if (url != null && url.startsWith('http'))
                OptimizedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  memCacheHeight: 300,
                )
              else if (url != null && url.isNotEmpty)
                Image.asset(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      LucideIcons.tv,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                  ),
                )
              else
                Center(
                  child: Icon(
                    LucideIcons.tv,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.35),
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
        ),
      ),
    );
  }
}
