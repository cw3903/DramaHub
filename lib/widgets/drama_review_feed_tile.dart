import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../theme/app_theme.dart';
import '../models/drama.dart';
import 'drama_row_profile_avatar.dart';
import 'feed_review_star_row.dart'
    show FeedReviewRatingStars, kFeedReviewRatingThumbWidth;
import 'review_card_tap_highlight.dart';
import 'user_profile_nav.dart';

/// 별점 행 ↔ 본문, 본문 ↔ 하트·댓글 행(상세·목록). 리뷰 게시판 레터박드와도 동일 간격.
const double kDramaReviewFeedVerticalGap = 8;

/// 드라마 리뷰 목록 화면·상세 Ratings & Reviews 공통 — 별(좌) / 닉·아바타(우), 본문은 아래 줄.
class DramaReviewFeedTile extends StatelessWidget {
  const DramaReviewFeedTile({
    super.key,
    required this.review,
    this.displayLikeCount,
    this.padding = const EdgeInsets.fromLTRB(14, 9, 14, 9),
    this.onOpenProfile,
    /// null이면 [ColorScheme.surface] (리뷰 목록). 상세 카드 안에서는 `Colors.transparent`.
    this.materialColor,
    /// 지정 시 별·본문 탭은 프로필로 가지 않고 이 콜백만 호출 (닉·아바타는 계속 프로필).
    this.onMainTap,
    /// true면 별·본문은 터치를 부모([ReviewCardTapHighlight])로 넘김. 닉·아바타만 프로필.
    this.expandViaParentTap = false,
    /// false면 별 줄 오른쪽 하트 장식 숨김(하단 액션바 등과 중복 방지).
    this.showLikeCountIndicator = true,
  });

  final DramaReview review;
  final int? displayLikeCount;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onOpenProfile;
  final Color? materialColor;
  final VoidCallback? onMainTap;
  final bool expandViaParentTap;
  final bool showLikeCountIndicator;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = review.userName.trim().isEmpty ? '—' : review.userName;
    final body = review.comment.trim();
    final likes = displayLikeCount ?? (review.likeCount ?? 0);
    final liked = likes > 0;
    final showStars = review.rating > 0;
    void openProfile() {
      if (onOpenProfile != null) {
        onOpenProfile!();
        return;
      }
      final u = review.authorUid?.trim();
      if (u != null && u.isNotEmpty) {
        openUserProfileFromAuthorUid(context, u);
      }
    }

    void mainTap() {
      if (onMainTap != null) {
        onMainTap!();
      } else {
        openProfile();
      }
    }

    final profileCell = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openProfile,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: appUnifiedNicknameStyle(cs),
              ),
            ),
            const SizedBox(width: 8),
            DramaRowProfileAvatar(
              imageUrl: review.authorPhotoUrl,
              authorUid: review.authorUid,
              colorScheme: cs,
              size: kAppUnifiedProfileAvatarSize,
            ),
          ],
        ),
      ),
    );

    final Widget profileTrailing = expandViaParentTap
        ? ReviewCardSuppressParentTap(child: profileCell)
        : profileCell;

    final Widget starRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showStars)
          FeedReviewRatingStars(
            rating: review.rating,
            layoutThumbWidth: kFeedReviewRatingThumbWidth,
          ),
        if (showLikeCountIndicator && liked) ...[
          if (showStars) const SizedBox(width: 5),
          Icon(
            LucideIcons.heart,
            size: 15,
            color: const Color(0xFFFF8A34),
          ),
        ],
      ],
    );

    final Widget bodyWidget = Text(
      body,
      style: GoogleFonts.notoSansKr(
        fontSize: 13,
        height: 1.45,
        color: cs.onSurface.withValues(alpha: 0.9),
      ),
    );

    return Material(
      color: materialColor ?? cs.surface,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: expandViaParentTap
                        ? starRow
                        : InkWell(
                            onTap: mainTap,
                            child: starRow,
                          ),
                  ),
                ),
                profileTrailing,
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: kDramaReviewFeedVerticalGap),
              expandViaParentTap
                  ? bodyWidget
                  : InkWell(
                      onTap: mainTap,
                      child: bodyWidget,
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
