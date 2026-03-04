import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import 'drama_detail_page.dart';
import 'shorts_search_screen.dart';

/// 태그별 드라마 목록 화면 (참고: 사랑과 증오)
class TagDramaListScreen extends StatelessWidget {
  const TagDramaListScreen({
    super.key,
    required this.tag,
  });

  final String tag;

  static final Map<String, List<DramaItem>> _dramasByTag = {
    '인기': [
      DramaItem(id: 't1', title: '선배님, 모두 우연인가요', subtitle: '인기', views: '206.1K', rating: 4.5, isPopular: true),
      DramaItem(id: 't2', title: '경비원의 숨겨진 정체', subtitle: '인기', views: '192.0K', rating: 4.3, isPopular: true),
      DramaItem(id: 't3', title: '가짜 죽음 뒤, 집착남들이 미쳐버렸다', subtitle: '인기', views: '49.0K', rating: 4.6, isPopular: true),
      DramaItem(id: 't4', title: '보스의 부인은 시골 출신', subtitle: '인기', views: '481.7K', rating: 4.2, isPopular: true),
      DramaItem(id: 't5', title: '그녀가 제우스의 딸이었어?', subtitle: '인기', views: '20.1K', rating: 4.4, isPopular: true),
      DramaItem(id: 't6', title: '사심폭발 로망스', subtitle: '인기', views: '227.8K', rating: 4.5, isPopular: true),
    ],
    '비밀신분': [
      DramaItem(id: 's1', title: '사랑은 시간 뒤에 서다', subtitle: '비밀신분', views: '9.1M', rating: 4.5, isPopular: true),
      DramaItem(id: 's2', title: '청소부의 두번째 결혼', subtitle: '비밀신분', views: '222K', rating: 4.7, isPopular: true),
      DramaItem(id: 's3', title: '경비원의 숨겨진 정체', subtitle: '비밀신분', views: '192.0K', rating: 4.3),
      DramaItem(id: 's4', title: '신분을 숨긴 재벌 2세', subtitle: '비밀신분', views: '156.2K', rating: 4.4),
      DramaItem(id: 's5', title: '그의 숨겨진 정체', subtitle: '비밀신분', views: '89.3K', rating: 4.2),
      DramaItem(id: 's6', title: '말 못할 비밀', subtitle: '비밀신분', views: '312.5K', rating: 4.6),
    ],
    '전쟁의 신': [
      DramaItem(id: 'w1', title: '전쟁의 신', subtitle: '전쟁의 신', views: '15.2M', rating: 4.8, isPopular: true),
      DramaItem(id: 'w2', title: '천계의 전쟁', subtitle: '전쟁의 신', views: '892K', rating: 4.4),
      DramaItem(id: 'w3', title: '신들의 전쟁', subtitle: '전쟁의 신', views: '445K', rating: 4.3),
      DramaItem(id: 'w4', title: '올림포스의 전쟁', subtitle: '전쟁의 신', views: '256K', rating: 4.5),
      DramaItem(id: 'w5', title: '아레스의 후예', subtitle: '전쟁의 신', views: '178K', rating: 4.2),
      DramaItem(id: 'w6', title: '전쟁과 사랑', subtitle: '전쟁의 신', views: '521K', rating: 4.6),
    ],
    '사랑과 증오': [
      DramaItem(id: 'lh1', title: '선배님, 모두 우연인가요', subtitle: '사랑과 증오', views: '206.1K', rating: 4.5),
      DramaItem(id: 'lh2', title: '경비원의 숨겨진 정체', subtitle: '사랑과 증오', views: '192.0K', rating: 4.3),
      DramaItem(id: 'lh3', title: '가짜 죽음 뒤, 집착남들이 미쳐버렸다', subtitle: '사랑과 증오', views: '49.0K', rating: 4.6),
      DramaItem(id: 'lh4', title: '보스의 부인은 시골 출신', subtitle: '사랑과 증오', views: '481.7K', rating: 4.2),
      DramaItem(id: 'lh5', title: '그녀가 제우스의 딸이었어?', subtitle: '사랑과 증오', views: '20.1K', rating: 4.4),
      DramaItem(id: 'lh6', title: '사심폭발 로망스', subtitle: '사랑과 증오', views: '227.8K', rating: 4.5),
    ],
  };

  List<DramaItem> _getDramasForTag() {
    return _dramasByTag[tag] ??
        _dramasByTag['사랑과 증오']!.map((d) {
          return DramaItem(
            id: '${d.id}-$tag',
            title: d.title,
            subtitle: tag,
            views: d.views,
            rating: d.rating,
            isPopular: d.isPopular,
          );
        }).toList();
  }

  DramaDetail _buildDramaDetail(DramaItem item) {
    const reviews = <DramaReview>[];
    final episodes = List.generate(12, (i) => DramaEpisode(number: i + 1, title: '${i + 1}화', duration: '45분'));
    final list = _getDramasForTag();
    final similar = list.where((d) => d.id != item.id).take(4).toList();
    return DramaDetail(
      item: item,
      synopsis: '${item.title}의 줄거리입니다. 비밀과 진실, 사랑과 증오가 교차하는 드라마틱한 스토리를 경험하세요.',
      year: '2024',
      genre: tag,
      averageRating: item.rating,
      ratingCount: 1200,
      episodes: episodes,
      reviews: reviews,
      similar: similar,
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF121212);
    final dramas = _getDramasForTag();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단: 검색 아이콘
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(LucideIcons.arrow_left, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(LucideIcons.search, color: Colors.white, size: 24),
                    onPressed: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(builder: (_) => const ShortsSearchScreen()),
                      );
                    },
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            // 태그 제목
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text(
                tag,
                style: GoogleFonts.notoSansKr(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            // 2열 그리드
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.6,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                itemCount: dramas.length,
                itemBuilder: (context, index) {
                  final item = dramas[index];
                  return _DramaGridCard(
                    item: item,
                    tag: tag,
                    onTap: () {
                      final detail = _buildDramaDetail(item);
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => DramaDetailPage(detail: detail),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DramaGridCard extends StatelessWidget {
  const _DramaGridCard({
    required this.item,
    required this.tag,
    required this.onTap,
  });

  final DramaItem item;
  final String tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(LucideIcons.image, size: 40, color: Colors.white38),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.play, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          item.views,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            tag,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
