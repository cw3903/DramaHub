import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/review_service.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import 'drama_detail_page.dart';

/// 리뷰 탭에서 작성한 리뷰 목록
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  @override
  void initState() {
    super.initState();
    ReviewService.instance.refresh();
    DramaListService.instance.loadFromAsset();
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.get('myReviews'),
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<List<MyReviewItem>>(
        valueListenable: ReviewService.instance.listNotifier,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.star,
                    size: 64,
                    color: cs.onSurfaceVariant.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '아직 작성한 리뷰가 없어요',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '리뷰 탭의 드라마 상세에서\n리뷰를 작성해보세요',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: cs.onSurfaceVariant.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              return _ReviewCard(item: item);
            },
          );
        },
      ),
    );
  }
}

DramaDetail _detailFromReview(BuildContext context, MyReviewItem item) {
  const similarList = [
    DramaItem(id: 's1', title: '사랑은 시간 뒤에 서다', subtitle: '비밀신분', views: '9.1M', rating: 4.5, isPopular: true),
    DramaItem(id: 's2', title: '폭풍같은 결혼생활', subtitle: '대여주', views: '45.3M', rating: 4.3, isNew: true),
    DramaItem(id: 's3', title: '동생이 훔친 사랑', subtitle: '로맨스', views: '2.1M', rating: 4.6, isPopular: true),
    DramaItem(id: 's4', title: '후회·집착남', subtitle: '독립적인 여성', views: '567K', rating: 3.5, isPopular: true),
  ];
  final locale = CountryScope.maybeOf(context)?.country;
  final displayTitle = item.dramaId.isNotEmpty
      ? (DramaListService.instance.getDisplayTitle(item.dramaId, locale).isNotEmpty
          ? DramaListService.instance.getDisplayTitle(item.dramaId, locale)
          : item.dramaTitle)
      : DramaListService.instance.getDisplayTitleByTitle(item.dramaTitle, locale);
  final dramaItem = DramaItem(
    id: item.dramaId,
    title: displayTitle,
    subtitle: '',
    views: '0',
    rating: item.rating,
    isPopular: false,
  );
  const fullSynopsis = '태성바이오 창립자 박창욱은 신분을 숨긴 채 청소부로 살아가고, 아들 정훈은 만삭의 아내 미연과 장차 이어질 가족의 행복을 꿈꾼다.';
  final userName = AuthService.instance.currentUser.value?.displayName?.split('@').first ?? '나';
  final myReview = DramaReview(
    id: item.id,
    userName: userName,
    rating: item.rating,
    comment: item.comment,
    timeAgo: formatTimeAgo(item.writtenAt, locale),
    likeCount: 0,
    replies: const [],
  );
  final reviews = [myReview];
  final episodes = [const DramaEpisode(number: 1, title: '1화', duration: '45분')];
  return DramaDetail(
    item: dramaItem,
    synopsis: fullSynopsis,
    year: '2024',
    genre: '',
    averageRating: item.rating,
    ratingCount: 1,
    episodes: episodes,
    reviews: reviews,
    similar: similarList,
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item});

  final MyReviewItem item;

  String _displayTitle(BuildContext context) {
    final locale = CountryScope.maybeOf(context)?.country;
    if (item.dramaId.isNotEmpty) {
      final t = DramaListService.instance.getDisplayTitle(item.dramaId, locale);
      if (t.isNotEmpty) return t;
    }
    return DramaListService.instance.getDisplayTitleByTitle(item.dramaTitle, locale);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = CountryScope.maybeOf(context)?.country;
    final detail = _detailFromReview(context, item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => DramaDetailPage(detail: detail, scrollToRatings: true),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _displayTitle(context),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final starValue = i + 1.0;
                        final isFull = item.rating >= starValue;
                        final isHalf = item.rating >= starValue - 0.5 && item.rating < starValue;
                        return Icon(
                          isFull ? Icons.star_rounded : (isHalf ? Icons.star_half_rounded : Icons.star_border_rounded),
                          size: 18,
                          color: (isFull || isHalf) ? Colors.amber : cs.onSurfaceVariant,
                        );
                      }),
                    ),
                  ],
                ),
                if (item.comment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.comment,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  formatTimeAgo(item.writtenAt, locale),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
