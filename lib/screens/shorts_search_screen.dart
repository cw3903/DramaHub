import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../widgets/country_scope.dart';
import 'drama_detail_page.dart';

const _searchPlaceholder = '제목, 테마로 검색...';

final _trendingItems = [
  _SearchItem(
    title: '인생 실패 후 코인대박',
    genre: '자기 성장',
    description: '주식으로 인생이 망한 남자. 우연히 코인으로 역전의 기회를 잡는다. 현실과 판타지가 교차하는 성장 드라마.',
  ),
  _SearchItem(
    title: '자만추 클럽 하우스',
    genre: '운명적 사랑',
    description: '클럽 하우스에서 운명처럼 만난 두 사람. 숨겨진 비밀과 감춰진 사랑이 밝혀지는 로맨스.',
  ),
  _SearchItem(
    title: '[더빙]나는 용왕이고 의성이다',
    genre: '하렘',
    description: '용왕이 되어 이세계에서 펼치는 대모험. 다양한 히로인들과의 추억을 쌓아가는 판타지.',
    isBookmarked: true,
  ),
  _SearchItem(
    title: '그는 당신에게 반하지 않았다',
    genre: '삼각관계',
    description: '한 남자를 사이에 둔 두 여자의 이야기. 사랑과 우정 사이에서 흔들리는 선택.',
  ),
  _SearchItem(
    title: '닥터 루시퍼',
    genre: '의료',
    description: '천재 의사의 비밀과 진실. 병원 안에서 펼쳐지는 권력과 정의의 대결.',
  ),
];

class _SearchItem {
  const _SearchItem({
    required this.title,
    required this.genre,
    required this.description,
    this.isBookmarked = false,
  });
  final String title;
  final String genre;
  final String description;
  final bool isBookmarked;
}

/// 숏폼 검색 화면 - 제목/테마 검색 + 추천 목록
class ShortsSearchScreen extends StatefulWidget {
  const ShortsSearchScreen({super.key});

  @override
  State<ShortsSearchScreen> createState() => _ShortsSearchScreenState();
}

class _ShortsSearchScreenState extends State<ShortsSearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<_SearchItem> _filteredItems = _trendingItems;
  final Set<String> _bookmarkedTitles = {'[더빙]나는 용왕이고 의성이다'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _trendingItems;
      } else {
        final q = query.toLowerCase();
        _filteredItems = _trendingItems
            .where((e) =>
                e.title.toLowerCase().contains(q) ||
                e.genre.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  DramaDetail _buildDramaDetail(_SearchItem item) {
    final dramaItem = DramaItem(
      id: 'search-${item.title}',
      title: item.title,
      subtitle: item.genre,
      views: '1M',
      rating: 4.5,
    );
    final similarList = [
      DramaItem(id: 's1', title: '사랑은 시간 뒤에 서다', subtitle: '비밀신분', views: '9.1M', rating: 4.5, isPopular: true),
      DramaItem(id: 's2', title: '폭풍같은 결혼생활', subtitle: '대여주', views: '45.3M', rating: 4.3, isNew: true),
    ];
    return DramaDetail(
      item: dramaItem,
      synopsis: item.description,
      year: '2024',
      genre: item.genre,
      averageRating: 4.3,
      ratingCount: 1200,
      episodes: List.generate(12, (i) => DramaEpisode(number: i + 1, title: '${i + 1}화', duration: '45분')),
      reviews: const [],
      similar: similarList,
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF1A1A1A);
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단: 뒤로가기 + 검색바
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(LucideIcons.arrow_left, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearchChanged,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText: _searchPlaceholder,
                          hintStyle: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            color: Colors.white54,
                          ),
                          prefixIcon: Icon(LucideIcons.search, size: 20, color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 섹션 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                CountryScope.of(context).strings.get('popularSearch'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            // 목록
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: GoogleFonts.notoSansKr(fontSize: 15, color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  final isBookmarked = _bookmarkedTitles.contains(item.title);
                  return _SearchResultTile(
                    rank: index + 1,
                    item: item,
                    isBookmarked: isBookmarked,
                    onTap: () {
                      final detail = _buildDramaDetail(item);
Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => DramaDetailPage(detail: detail),
                        ),
                      );
                    },
                    onBookmarkTap: () {
                      setState(() {
                        if (_bookmarkedTitles.contains(item.title)) {
                          _bookmarkedTitles.remove(item.title);
                        } else {
                          _bookmarkedTitles.add(item.title);
                        }
                      });
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


class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.rank,
    required this.item,
    required this.isBookmarked,
    required this.onTap,
    required this.onBookmarkTap,
  });

  final int rank;
  final _SearchItem item;
  final bool isBookmarked;
  final VoidCallback onTap;
  final VoidCallback onBookmarkTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 순위 + 썸네일
            SizedBox(
              width: 100,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 80,
                    height: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(LucideIcons.image, size: 32, color: Colors.white38),
                    ),
                  ),
                  Positioned(
                    left: -8,
                    top: 0,
                    child: Text(
                      '$rank',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // 제목, 장르, 설명
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.genre,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.description,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: Colors.white60,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 북마크
            GestureDetector(
              onTap: onBookmarkTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  LucideIcons.bookmark,
                  size: 24,
                  color: isBookmarked ? const Color(0xFFFFD54F) : Colors.white54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
