import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/user_profile_service.dart';
import '../services/watchlist_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/optimized_network_image.dart';
import 'login_page.dart';

/// 드라마 상세 스탯 바「워치리스트」— 프로필 워치리스트와 동일 데이터, + 로 추가 확인.
class DramaWatchlistScreen extends StatefulWidget {
  const DramaWatchlistScreen({
    super.key,
    required this.dramaId,
    required this.dramaTitle,
    required this.dramaItem,
  });

  final String dramaId;
  final String dramaTitle;
  final DramaItem dramaItem;

  @override
  State<DramaWatchlistScreen> createState() => _DramaWatchlistScreenState();
}

class _DramaWatchlistScreenState extends State<DramaWatchlistScreen> {
  @override
  void initState() {
    super.initState();
    WatchlistService.instance.loadIfNeeded();
  }

  Future<void> _showAddDialog() async {
    final s = CountryScope.of(context).strings;
    await WatchlistService.instance.loadIfNeeded();
    if (!mounted) return;
    final onList = WatchlistService.instance.isInWatchlist(widget.dramaId);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          s.get('dramaSubpageConfirmWatchlistTitle'),
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
        ),
        content: Text(
          onList
              ? s.get('dramaSubpageConfirmWatchlistAlready')
              : s.get('dramaSubpageConfirmWatchlistBody'),
          style: GoogleFonts.notoSansKr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
          ),
          if (!onList)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.get('ok'), style: GoogleFonts.notoSansKr()),
            ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    if (!AuthService.instance.isLoggedIn.value) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
      if (!mounted || !AuthService.instance.isLoggedIn.value) return;
      await WatchlistService.instance.loadIfNeeded(force: true);
      if (!mounted) return;
    }

    if (WatchlistService.instance.isInWatchlist(widget.dramaId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.get('dramaSubpageConfirmWatchlistAlready'),
            style: GoogleFonts.notoSansKr(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    await WatchlistService.instance.add(widget.dramaId, country);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.get('watchlistToastAdded'),
          style: GoogleFonts.notoSansKr(),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final headerBarBg = listsStyleSubpageHeaderBackground(theme);
    final overlay = listsStyleSubpageSystemOverlay(theme, headerBarBg);
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final poster = DramaListService.instance.getDisplayImageUrl(
          widget.dramaId,
          country,
        ) ??
        widget.dramaItem.imageUrl;

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
            trailing: ListsStyleSubpageHeaderAddButton(onTap: _showAddDialog),
          ),
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            AuthService.instance.isLoggedIn,
            WatchlistService.instance.itemsNotifier,
          ]),
          builder: (context, _) {
            final on = WatchlistService.instance.isInWatchlist(widget.dramaId);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 72,
                        height: 72 * 1.45,
                        child: poster != null && poster.trim().startsWith('http')
                            ? OptimizedNetworkImage(
                                imageUrl: poster.trim(),
                                fit: BoxFit.cover,
                                width: 72,
                                height: 72 * 1.45,
                                memCacheWidth: 200,
                                memCacheHeight: 290,
                                errorWidget: ColoredBox(
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.movie_outlined,
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                                  ),
                                ),
                              )
                            : ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          on
                              ? s.get('dramaWatchlistSubpageBodyOn')
                              : s.get('dramaWatchlistSubpageBodyOff'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            height: 1.45,
                            color: cs.onSurface.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}
