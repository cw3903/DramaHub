import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post.dart';
import 'country_scope.dart';
import 'optimized_network_image.dart';
import 'user_profile_nav.dart';

/// 리뷰 피드 전용 카드 (썸네일 60×80, 제목·별점·2줄 미리보기, 하단 닉네임·시간)
class FeedReviewPostCard extends StatelessWidget {
  const FeedReviewPostCard({
    super.key,
    required this.post,
    this.currentUserAuthor,
    this.onPostUpdated,
    this.onPostDeleted,
    this.tabName,
    this.onTap,
    this.onUserBlocked,
  });

  final Post post;
  final String? currentUserAuthor;
  final void Function(Post)? onPostUpdated;
  final void Function(Post)? onPostDeleted;
  final String? tabName;
  final VoidCallback? onTap;
  final VoidCallback? onUserBlocked;

  static const Color _starOrange = Color(0xFFFFB020);

  /// 0.5점: 반쪽 채움만(오른쪽 빈 윤곽 없음).
  static Widget _filledHalfStarOnly(double iconSize, Color color) {
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 0.5,
        child: Icon(Icons.star_rounded, size: iconSize, color: color),
      ),
    );
  }

  static Widget _starRow(
    double rating, {
    double iconSize = 17,
    /// 인덱스 i마다 왼쪽으로 i배만큼 이동(겹침으로 간격 축소, 레이아웃 폭은 유지).
    double cumulativeShiftXPerIndex = 0,
    double translateY = 0,
  }) {
    final units = (rating.clamp(0.0, 5.0) * 2).round().clamp(0, 10);
    final fullCount = units ~/ 2;
    final hasHalf = units.isOdd;
    final starCount = fullCount + (hasHalf ? 1 : 0);
    if (starCount == 0) return const SizedBox.shrink();
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(starCount, (i) {
        final isHalf = hasHalf && i == fullCount;
        final Widget raw = isHalf
            ? _filledHalfStarOnly(iconSize, _starOrange)
            : Icon(Icons.star_rounded, size: iconSize, color: _starOrange);
        if (cumulativeShiftXPerIndex == 0 && translateY == 0) return raw;
        return Transform.translate(
          offset: Offset(-cumulativeShiftXPerIndex * i, translateY),
          child: raw,
        );
      }),
    );
    return row;
  }

  /// 홈 탭 리뷰 피드 카드와 동일 — 17px, 0.5점 단위는 반쪽 클립(4.5 → 별4 + 반개).
  static Widget homeFeedStyleStarRow(
    double rating, {
    double iconSize = 17,
    double cumulativeShiftXPerIndex = 0,
    double translateY = 0,
  }) =>
      _starRow(
        rating,
        iconSize: iconSize,
        cumulativeShiftXPerIndex: cumulativeShiftXPerIndex,
        translateY: translateY,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    final thumb = post.dramaThumbnail?.trim();
    final hasHttpThumb = thumb != null && thumb.startsWith('http');
    final dramaTitle = post.dramaTitle?.trim().isNotEmpty == true ? post.dramaTitle! : post.title;
    final body = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final r = (post.rating ?? 0).clamp(0.0, 5.0);
    final isMyReview = currentUserAuthor != null && post.author == currentUserAuthor;

    Widget previewCore = Text(
      body.isEmpty ? ' ' : body,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.notoSansKr(
        fontSize: 13,
        height: 1.35,
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w400,
      ),
    );

    final Widget preview = post.hasSpoiler
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: previewCore,
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    s.get('spoilerBadge'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: cs.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
          )
        : previewCore;

    Widget previewBlock = preview;
    if (isMyReview) {
      previewBlock = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.secondary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                s.get('myPostBadge'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondary,
                ),
              ),
            ),
          ),
          Expanded(child: preview),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: hasHttpThumb
                          ? OptimizedNetworkImage(
                              imageUrl: thumb!,
                              width: 60,
                              height: 80,
                              fit: BoxFit.cover,
                              memCacheWidth: 120,
                              memCacheHeight: 160,
                            )
                          : Container(
                              width: 60,
                              height: 80,
                              color: cs.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant, size: 28),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dramaTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              homeFeedStyleStarRow(r),
                            ],
                          ),
                          const SizedBox(height: 6),
                          previewBlock,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final u = post.authorUid?.trim();
                          if (u != null && u.isNotEmpty) {
                            openUserProfileFromAuthorUid(context, u);
                          }
                        },
                        child: Text(
                          post.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      post.timeAgo,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
