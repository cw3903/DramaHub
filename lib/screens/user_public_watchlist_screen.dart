import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../models/watchlist_item.dart';
import '../services/drama_list_service.dart';
import '../services/watchlist_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';
const double kListStyleGridAspectRatio = 0.74;
const double kListStyleGridHorizontalPadding = 15;
const double kListStyleGridGap = 7;

/// 타 유저의 워치리스트 (읽기 전용).
class UserPublicWatchlistScreen extends StatefulWidget {
  const UserPublicWatchlistScreen({
    super.key,
    required this.uid,
    this.ownerDisplayName,
  });

  final String uid;
  final String? ownerDisplayName;

  @override
  State<UserPublicWatchlistScreen> createState() =>
      _UserPublicWatchlistScreenState();
}

class _UserPublicWatchlistScreenState
    extends State<UserPublicWatchlistScreen> {
  late Future<List<WatchlistItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = WatchlistService.instance.fetchForUid(widget.uid);
    DramaListService.instance.loadFromAsset();
  }

  String _headerTitle(dynamic s) {
    final name = widget.ownerDisplayName?.trim() ?? '';
    if (name.isNotEmpty) {
      return s.get('watchlistTitleWithName').replaceAll('{name}', name);
    }
    return s.get('tabWatchlist');
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
        body: FutureBuilder<List<WatchlistItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.clock,
                        size: 56,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.get('watchlistEmptyPublic') as String,
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

            const crossAxis = 4;
            return ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  kListStyleGridHorizontalPadding,
                  10,
                  kListStyleGridHorizontalPadding,
                  28,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxis,
                  childAspectRatio: kListStyleGridAspectRatio,
                  crossAxisSpacing: kListStyleGridGap,
                  mainAxisSpacing: kListStyleGridGap,
                ),
                itemCount: items.length,
                  itemBuilder: (ctx, i) {
                  final w = items[i];
                  final dramaId = w.dramaId;
                  final imageUrl = DramaListService.instance
                          .getDisplayImageUrl(dramaId, country) ??
                      w.imageUrlSnapshot;
                  return _PosterCell(
                    key: ValueKey(dramaId),
                    imageUrl: imageUrl,
                    onTap: () async {
                      final DramaItem item =
                          WatchlistService.instance.resolveDramaItem(dramaId);
                      await DramaDetailPage.openFromItem(
                        ctx,
                        item,
                        country: country ?? '',
                      );
                    },
                    cs: cs,
                  );
                },
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}

class _PosterCell extends StatelessWidget {
  const _PosterCell({
    super.key,
    required this.imageUrl,
    required this.onTap,
    required this.cs,
  });

  final String? imageUrl;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final u = imageUrl?.trim();
    final hasImage =
        u != null && (u.startsWith('http://') || u.startsWith('https://'));
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: hasImage
            ? OptimizedNetworkImage(
                imageUrl: u,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              )
            : ColoredBox(
                color: isDark
                    ? const Color(0xFF2C3440)
                    : cs.surfaceContainerHighest,
                child: Icon(
                  LucideIcons.tv,
                  size: 28,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
      ),
    );
  }
}
