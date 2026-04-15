import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// DramaFeed Reviews(Letterboxd)와 동일 — 채워진 별만, 0.5점은 유니코드 `½` ([FeedReviewLetterboxdTile] 구현과 동일).
class FeedReviewRatingStars extends StatelessWidget {
  const FeedReviewRatingStars({
    super.key,
    required this.rating,
    /// [FeedReviewLetterboxdTile._thumbW]와 같게 두면 홈 탭과 별·½ 크기가 일치합니다.
    this.layoutThumbWidth = 62,
  });

  final double rating;
  final double layoutThumbWidth;

  static const Color starOrange = Color(0xFFFFB020);

  @override
  Widget build(BuildContext context) {
    final r = rating.clamp(0.0, 5.0);
    final units = (r * 2).round().clamp(0, 10);
    final fullCount = units ~/ 2;
    final hasHalf = units.isOdd;
    if (fullCount == 0 && !hasHalf) return const SizedBox.shrink();

    final slotW = layoutThumbWidth / 5;
    final iconSize = (slotW * 0.82).clamp(14.0, 22.0);
    final halfLabelStyle = GoogleFonts.notoSansKr(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.0,
      color: starOrange,
    );

    final Widget starsOnly = fullCount > 0
        ? SizedBox(
            width: fullCount * slotW,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                fullCount,
                (i) => SizedBox(
                  width: slotW,
                  child: Center(
                    child: Icon(
                      Icons.star_rounded,
                      size: iconSize,
                      color: starOrange,
                    ),
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    if (!hasHalf) return starsOnly;

    final gapBeforeHalf = (iconSize * 0.1).clamp(2.0, 5.0);
    final fontSize = (iconSize * 12 / 11).clamp(11.0, 16.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (fullCount > 0) starsOnly,
        Padding(
          padding: EdgeInsets.only(left: fullCount > 0 ? gapBeforeHalf : 0),
          child: SizedBox(
            height: iconSize * 1.05,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '\u00BD',
                style: halfLabelStyle.copyWith(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  height: 1.0,
                  color: starOrange,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
