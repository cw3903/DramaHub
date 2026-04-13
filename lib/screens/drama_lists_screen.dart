import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/drama_list_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';

/// 리스트 피드·탭 하단 구분선 (다크 테마에서 `outline` 12%는 거의 안 보임).
Color dramaListsDividerColor(ColorScheme cs) {
  return cs.brightness == Brightness.dark
      ? cs.onSurface.withValues(alpha: 0.28)
      : cs.outline.withValues(alpha: 0.42);
}

/// 드라마 상세 스탯 바「List」— 이 작품이 포함된 리스트 피드(샘플 UI).
/// 실제 리스트 API 연동 전까지 로컬 데이터로 레이아웃만 제공.
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

class _ListFeedEntry {
  const _ListFeedEntry({
    required this.title,
    required this.userName,
    this.userPhotoUrl,
    required this.posterUrls,
    this.blurb,
    required this.likes,
  });

  final String title;
  final String userName;
  final String? userPhotoUrl;
  final List<String> posterUrls;
  final String? blurb;
  final int likes;
}

class _DramaListsScreenState extends State<DramaListsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<_ListFeedEntry> _all = [];
  bool _didLoadFeed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadFeed) return;
    _didLoadFeed = true;
    final country = CountryScope.maybeOf(context)?.country;
    _all = _computeFeed(country);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static const _mockUsernames = [
    'cinephile_k',
    'shortdrama_fan',
    'letterboxd_kr',
    'midnight_list',
    'poster_hunter',
    'neo_streamer',
    'bluray_shelf',
    'drama_hub_user',
  ];

  static const _mockTitles = [
    'Weekend binge picks',
    'Twists & revenge essentials',
    'Romance that hits different',
    'CEO dramas & power plays',
    'Hidden gems under 40 eps',
    'Fan-favorite cliffhangers',
    'One-sitting watches',
    'Trending this month',
  ];

  static const _mockBlurbs = [
    'A tight rotation of titles I revisit when I need comfort or chaos.',
    'Updated whenever I find a new obsession worth sharing.',
    null,
    'Mostly revenge arcs and satisfying payoffs.',
    null,
    'Ordered loosely by how hard the finale hits.',
    'Short episodes only — perfect for commutes.',
    null,
  ];

  List<_ListFeedEntry> _computeFeed(String? country) {
    final list = DramaListService.instance.getListForCountry(country);
    final urls = <String>[];
    final current = widget.dramaPosterUrl?.trim();
    if (current != null && current.startsWith('http')) urls.add(current);
    for (final it in list) {
      final u = DramaListService.instance.getDisplayImageUrl(it.id, country) ??
          it.imageUrl?.trim();
      if (u != null && u.startsWith('http') && !urls.contains(u)) {
        urls.add(u);
      }
      if (urls.length >= 32) break;
    }
    if (urls.isEmpty) {
      return const [];
    }
    while (urls.length < 7) {
      urls.add(urls.first);
    }
    final seed = widget.dramaId.hashCode.abs();
    final out = <_ListFeedEntry>[];
    for (var i = 0; i < 8; i++) {
      final start = (seed + i * 3) % urls.length;
      final slice = <String>[];
      for (var j = 0; j < 7; j++) {
        slice.add(urls[(start + j) % urls.length]);
      }
      out.add(
        _ListFeedEntry(
          title: _mockTitles[i % _mockTitles.length],
          userName: _mockUsernames[(seed + i) % _mockUsernames.length],
          userPhotoUrl: null,
          posterUrls: slice,
          blurb: _mockBlurbs[i % _mockBlurbs.length],
          likes: 120 - i * 13 + (seed % 40),
        ),
      );
    }
    return out;
  }

  List<_ListFeedEntry> get _popular =>
      [..._all]..sort((a, b) => b.likes.compareTo(a.likes));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    const tabGreen = Color(0xFF00C46C);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.dramaTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.get('statsBarComingSoon'),
            icon: Icon(LucideIcons.list_filter, size: 22, color: cs.onSurfaceVariant),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.get('statsBarComingSoon'), style: GoogleFonts.notoSansKr()),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                controller: _tabController,
                labelColor: tabGreen,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: tabGreen,
                indicatorWeight: 2.5,
                labelStyle: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  Tab(text: s.get('dramaReviewsTabPopular')),
                  Tab(text: s.get('dramaReviewsTabAll')),
                ],
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: dramaListsDividerColor(cs),
              ),
            ],
          ),
        ),
      ),
      body: _all.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.get('dramaListsEmptyFeed'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _ListFeedView(entries: _popular, cs: cs),
                _ListFeedView(entries: _all, cs: cs),
              ],
            ),
    );
  }
}

class _ListFeedView extends StatelessWidget {
  const _ListFeedView({required this.entries, required this.cs});

  final List<_ListFeedEntry> entries;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: dramaListsDividerColor(cs),
      ),
      itemBuilder: (context, i) => _ListFeedCard(entry: entries[i], cs: cs),
    );
  }
}

class _ListFeedCard extends StatelessWidget {
  const _ListFeedCard({required this.entry, required this.cs});

  final _ListFeedEntry entry;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final initial = entry.userName.isNotEmpty
        ? entry.userName.substring(0, 1).toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.userName,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (entry.userPhotoUrl != null &&
                      entry.userPhotoUrl!.trim().startsWith('http'))
                    ClipOval(
                      child: OptimizedNetworkImage.avatar(
                        imageUrl: entry.userPhotoUrl!.trim(),
                        size: 28,
                        errorWidget: CircleAvatar(
                          radius: 14,
                          backgroundColor: cs.surfaceContainerHighest,
                          child: Text(
                            initial,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: Text(
                        initial,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entry.posterUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, j) {
                final url = entry.posterUrls[j];
                return SizedBox(
                  width: 64,
                  height: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: url.isNotEmpty
                        ? OptimizedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            width: 64,
                            height: 96,
                            memCacheWidth: 180,
                            memCacheHeight: 270,
                            errorWidget: ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                LucideIcons.film,
                                size: 22,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                            ),
                          )
                        : ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              LucideIcons.film,
                              size: 22,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
          if (entry.blurb != null && entry.blurb!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              entry.blurb!,
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurfaceVariant.withValues(alpha: 0.9),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
