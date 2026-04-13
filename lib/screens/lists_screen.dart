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
import 'watchlist_screen.dart';

const Color _kListsBodyBg = Color(0xFF14181C);
const Color _kListsBarBg = Color(0xFF14181C);

String _listsOwnerDisplayName() {
  final n = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (n != null && n.isNotEmpty) return n;
  final d = AuthService.instance.currentUser.value?.displayName?.trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('@')) return d.split('@').first;
    return d;
  }
  return 'Member';
}

/// Letterboxd 스타일 Lists — 상단 닉네임 + 가운데 Lists + 필터, 카드마다 제목·편수·포스터(무간격)·설명
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WatchlistService.instance.loadIfNeeded(force: true);
    });
  }

  void _openFilterSheet(BuildContext context, dynamic s) {
    final sheetCs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: sheetCs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Text(
            s.get('listsFilterSoon'),
            style: GoogleFonts.notoSansKr(
              fontSize: 15,
              height: 1.45,
              color: sheetCs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final isDark = theme.brightness == Brightness.dark;
    final barBg = isDark ? _kListsBarBg : theme.scaffoldBackgroundColor;
    final bodyBg = isDark ? _kListsBodyBg : theme.scaffoldBackgroundColor;
    final onBar = isDark ? Colors.white : cs.onSurface;
    final name = _listsOwnerDisplayName();

    return Scaffold(
      backgroundColor: bodyBg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Material(
          color: barBg,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 0,
                    right: 48,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        AppBarBackIconButton(
                          iconColor: onBar,
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: onBar.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IgnorePointer(
                    child: Text(
                      s.get('tabLists'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: onBar,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 0,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        LucideIcons.sliders_horizontal,
                        size: 20,
                        color: onBar.withValues(alpha: 0.9),
                      ),
                      onPressed: () => _openFilterSheet(context, s),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          WatchlistService.instance.itemsNotifier,
          DramaListService.instance.extraNotifier,
          UserProfileService.instance.nicknameNotifier,
        ]),
        builder: (context, _) {
          final country = CountryScope.maybeOf(context)?.country ??
              UserProfileService.instance.signupCountryNotifier.value;
          final items = WatchlistService.instance.itemsNotifier.value;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outline.withValues(alpha: isDark ? 0.18 : 0.12),
              ),
              _WatchlistListCard(
                count: items.length,
                items: items,
                country: country,
                strings: s,
                isDark: isDark,
                colorScheme: cs,
                onTap: () {
                  Navigator.push<void>(
                    context,
                    CupertinoPageRoute<void>(
                      builder: (_) => const WatchlistScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outline.withValues(alpha: isDark ? 0.18 : 0.12),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Text(
                  s.get('listsCustomHint'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    height: 1.5,
                    color: (isDark ? Colors.white : cs.onSurface)
                        .withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WatchlistListCard extends StatelessWidget {
  const _WatchlistListCard({
    required this.count,
    required this.items,
    required this.country,
    required this.strings,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  final int count;
  final List<WatchlistItem> items;
  final String? country;
  final dynamic strings;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final titleColor = isDark ? Colors.white : cs.onSurface;
    final muted = (isDark ? Colors.white : cs.onSurfaceVariant)
        .withValues(alpha: isDark ? 0.55 : 0.8);
    final countLabel =
        strings.get('listsFilmCount').replaceAll('{n}', '$count');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      strings.get('tabWatchlist'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                  ),
                  Text(
                    countLabel,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FlushPosterStrip(
                items: items,
                country: country,
                isDark: isDark,
                colorScheme: cs,
              ),
              const SizedBox(height: 12),
              Text(
                strings.get('listsWatchlistDescription'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  height: 1.45,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 포스터를 가로로 이어 붙임(간격 0). 많으면 가로 스크롤.
class _FlushPosterStrip extends StatelessWidget {
  const _FlushPosterStrip({
    required this.items,
    required this.country,
    required this.isDark,
    required this.colorScheme,
  });

  final List<WatchlistItem> items;
  final String? country;
  final bool isDark;
  final ColorScheme colorScheme;

  static const double _h = 72;
  static const double _w = _h * 2 / 3;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final placeholder = ColoredBox(
      color: isDark
          ? const Color(0xFF2C3440)
          : cs.surfaceContainerHighest,
      child: Icon(
        LucideIcons.clock,
        size: 22,
        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    );

    if (items.isEmpty) {
      return ClipRect(
        child: SizedBox(
          width: _w,
          height: _h,
          child: placeholder,
        ),
      );
    }

    return SizedBox(
      height: _h,
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final w in items)
                SizedBox(
                  width: _w,
                  height: _h,
                  child: _stripCell(w, country, cs, placeholder),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stripCell(
    WatchlistItem w,
    String? country,
    ColorScheme cs,
    Widget placeholder,
  ) {
    final id = w.dramaId;
    final url = DramaListService.instance.getDisplayImageUrl(id, country) ??
        w.imageUrlSnapshot;
    if (url != null && url.startsWith('http')) {
      return OptimizedNetworkImage(
        imageUrl: url,
        width: _w,
        height: _h,
        fit: BoxFit.cover,
        memCacheWidth: 160,
        memCacheHeight: 240,
        errorWidget: placeholder,
      );
    }
    if (url != null && url.isNotEmpty) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        width: _w,
        height: _h,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }
    return placeholder;
  }
}
