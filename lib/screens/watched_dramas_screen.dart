import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/watch_history_service.dart';
import '../services/country_service.dart';
import '../services/drama_list_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';

/// 숏폼에서 시청한 드라마 목록 화면
class WatchedDramasScreen extends StatefulWidget {
  const WatchedDramasScreen({super.key});

  @override
  State<WatchedDramasScreen> createState() => _WatchedDramasScreenState();
}

class _WatchedDramasScreenState extends State<WatchedDramasScreen> {
  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.refresh(); // Firestore + 로컬에서 최신 시청 기록 로드
    DramaListService.instance.loadFromAsset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.get('watchedDramas'),
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<List<WatchedDramaItem>>(
        valueListenable: WatchHistoryService.instance.listNotifier,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.clapperboard,
                    size: 64,
                    color: cs.onSurfaceVariant.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.get('noWatchedDramas'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          return ValueListenableBuilder<List<DramaItem>>(
            valueListenable: DramaListService.instance.listNotifier,
            builder: (context, _, __) {
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  return _WatchedDramaCard(item: item);
                },
              );
            },
          );
        },
      ),
    );
  }
}

DramaDetail _detailFromWatched(WatchedDramaItem item) {
  const similarList = [
    DramaItem(id: 's1', title: '사랑은 시간 뒤에 서다', subtitle: '비밀신분', views: '9.1M', rating: 4.5, isPopular: true),
    DramaItem(id: 's2', title: '폭풍같은 결혼생활', subtitle: '대여주', views: '45.3M', rating: 4.3, isNew: true),
    DramaItem(id: 's3', title: '동생이 훔친 사랑', subtitle: '로맨스', views: '2.1M', rating: 4.6, isPopular: true),
    DramaItem(id: 's4', title: '후회·집착남', subtitle: '독립적인 여성', views: '567K', rating: 3.5, isPopular: true),
  ];
  final dramaItem = DramaItem(
    id: item.id,
    title: item.title,
    subtitle: item.subtitle,
    views: item.views,
    rating: 4.7,
    isPopular: false,
  );
  const fullSynopsis = '태성바이오 창립자 박창욱은 신분을 숨긴 채 청소부로 살아가고, 아들 정훈은 만삭의 아내 미연과 장차 이어질 가족의 행복을 꿈꾼다. 그러나 한 순간의 실수로 모든 것이 바뀌고, 박창욱은 숨겨왔던 진실을 마주하게 된다. 비밀과 진실, 사랑과 복수가 교차하는 드라마틱한 스토리.';
  const reviews = <DramaReview>[];
  final episodes = [
    const DramaEpisode(number: 1, title: '1화', duration: '45분'),
  ];
  return DramaDetail(
    item: dramaItem,
    synopsis: fullSynopsis,
    year: '2024',
    genre: item.subtitle,
    averageRating: 4.7,
    ratingCount: 8500,
    episodes: episodes,
    reviews: reviews,
    similar: similarList,
  );
}

class _WatchedDramaCard extends StatelessWidget {
  const _WatchedDramaCard({required this.item});

  final WatchedDramaItem item;

  static const _placeholderGradient = [
    Color(0xFF616161),
    Color(0xFF424242),
  ];

  String? _resolveImageUrl(BuildContext context) {
    final country = CountryScope.maybeOf(context)?.country ?? CountryService.instance.countryNotifier.value;
    if (!item.id.startsWith('short-')) {
      final byId = DramaListService.instance.getDisplayImageUrl(item.id, country);
      if (byId != null && byId.isNotEmpty) return byId;
    }
    final byTitle = DramaListService.instance.getDisplayImageUrlByTitle(item.title, country);
    if (byTitle != null && byTitle.isNotEmpty) return byTitle;
    final url = item.imageUrl?.trim();
    if (url != null && url.isNotEmpty) return url;
    return null;
  }

  String _displayTitle(BuildContext context) {
    final country = CountryScope.maybeOf(context)?.country ?? CountryService.instance.countryNotifier.value;
    if (!item.id.startsWith('short-')) {
      final t = DramaListService.instance.getDisplayTitle(item.id, country);
      if (t.isNotEmpty) return t;
    }
    return DramaListService.instance.getDisplayTitleByTitle(item.title, country);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final detail = _detailFromWatched(item);
    final imageUrl = _resolveImageUrl(context);
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    Widget imageWidget;
    if (hasImage && imageUrl!.startsWith('http')) {
      imageWidget = OptimizedNetworkImage(
        imageUrl: imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        memCacheWidth: null,
        memCacheHeight: null,
        errorWidget: _placeholderBox(),
      );
    } else if (hasImage && imageUrl!.startsWith('assets/')) {
      imageWidget = Image.asset(
        imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderBox(),
      );
    } else {
      imageWidget = _placeholderBox();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => DramaDetailPage(detail: detail),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1 / 1.35,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [imageWidget],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                  child: Text(
                    _displayTitle(context),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderBox() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _placeholderGradient,
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.tv,
          size: 32,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}
