import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 숫자 글리프를 박스 위·아래에 더 붙임 (별 끝선과 맞추기).
const TextHeightBehavior _kTightDigitHeight = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

/// [FeedReviewLetterboxdTile] 포스터 가로와 동일. 홈 리뷰 별·다른 화면에서 [FeedReviewRatingStars]와 맞출 때 사용.
const double kFeedReviewRatingThumbWidth = 62;

/// DramaFeed Reviews(Letterboxd)와 동일 — 채워진 별만, 0.5점은 `1/2` 텍스트.
class FeedReviewRatingStars extends StatelessWidget {
  const FeedReviewRatingStars({
    super.key,
    required this.rating,
    /// [kFeedReviewRatingThumbWidth]와 같게 두면 홈 탭과 별·½ 크기가 일치합니다.
    this.layoutThumbWidth = kFeedReviewRatingThumbWidth,
    /// 슬롯 한 칸 대비 별 아이콘 가로 비율. 클수록 별 사이 간격이 줄어듭니다 (기본 0.82).
    this.slotIconFraction = 0.82,
    /// 각 별(인덱스 1…)마다 왼쪽으로 당겨 겹침 — [slotIconFraction] 상한 이후 간격 추가 축소용.
    this.starOverlapPx = 0,
  });

  final double rating;
  final double layoutThumbWidth;
  final double slotIconFraction;
  final double starOverlapPx;

  static const Color starOrange = Color(0xFFFFB020);

  @override
  Widget build(BuildContext context) {
    final r = rating.clamp(0.0, 5.0);
    final units = (r * 2).round().clamp(0, 10);
    final fullCount = units ~/ 2;
    final hasHalf = units.isOdd;
    if (fullCount == 0 && !hasHalf) return const SizedBox.shrink();

    final frac = slotIconFraction.clamp(0.5, 0.98);
    final slotW = layoutThumbWidth / 5;
    final iconSize = (slotW * frac).clamp(14.0, 22.0);
    final overlap = starOverlapPx.clamp(0.0, 8.0);

    final Widget starsOnly = fullCount > 0
        ? SizedBox(
            width: fullCount * slotW,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                fullCount,
                (i) {
                  final slot = SizedBox(
                    width: slotW,
                    height: iconSize,
                    child: Align(
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.star_rounded,
                        size: iconSize,
                        color: starOrange,
                      ),
                    ),
                  );
                  if (overlap <= 0) return slot;
                  return Transform.translate(
                    offset: Offset(-overlap * i, 0),
                    child: slot,
                  );
                },
              ),
            ),
          )
        : const SizedBox.shrink();

    if (!hasHalf) return starsOnly;

    final gapBeforeHalf = (iconSize * 0.07).clamp(1.5, 4.0);
    final halfShift = overlap > 0 ? -overlap * fullCount : 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fullCount > 0) starsOnly,
        Transform.translate(
          offset: Offset(halfShift, 0),
          child: Padding(
            padding: EdgeInsets.only(left: fullCount > 0 ? gapBeforeHalf : 0),
            child: _VulgarFractionOneHalf(
              color: starOrange,
              starIconSize: iconSize,
            ),
          ),
        ),
      ],
    );
  }
}

/// 43 스타일: `1` 좌상 · `/` 좌하→우상 · `2` 우하 (한 줄 `Text('1/2')`로는 재현 불가).
class _VulgarFractionOneHalf extends StatelessWidget {
  const _VulgarFractionOneHalf({
    required this.color,
    required this.starIconSize,
  });

  final Color color;
  final double starIconSize;

  @override
  Widget build(BuildContext context) {
    // 별 [Icon] 박스와 세로 동일 — 1 위·2 아래·슬래시 끝 = 별 위·아래.
    final h = starIconSize;
    const theta = 65 * math.pi / 180;
    final tanTheta = math.tan(theta);
    final stroke = (starIconSize * 0.048).clamp(0.8, 1.2);
    final inset = stroke * 0.48;
    final baseDy = math.max(1.0, h - 2 * inset);
    // 슬래시 실제 길이(화면에서 확실히 짧게)
    final targetDy = baseDy * 0.74;
    final dxNeed = targetDy / tanTheta;
    final w = (dxNeed + starIconSize * 0.22).clamp(11.0, 20.0);
    final numSize = (starIconSize * 0.26).clamp(6.2, 8.8);
    final base = GoogleFonts.notoSansKr(
      fontWeight: FontWeight.w800,
      height: 1.0,
      color: color,
    );
    final digitStyle = base.copyWith(fontSize: numSize);

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FractionForwardSlashPainter(
                color: color,
                strokeWidth: stroke,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Align(
              alignment: Alignment.topLeft,
              child: _FauxBoldDigit('1', digitStyle),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.bottomRight,
              child: _FauxBoldDigit('2', digitStyle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Noto KR에 w900이 없으면 동일하게 보이므로, 아주 작은 오프셋 이중 그리기로 굵게.
class _FauxBoldDigit extends StatelessWidget {
  const _FauxBoldDigit(this.digit, this.style);

  final String digit;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    const o = 0.32;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Transform.translate(
          offset: const Offset(o, o * 0.35),
          child: Text(
            digit,
            style: style,
            textHeightBehavior: _kTightDigitHeight,
          ),
        ),
        Text(
          digit,
          style: style,
          textHeightBehavior: _kTightDigitHeight,
        ),
      ],
    );
  }
}

/// 분수용 포워드 슬래시: 좌하 → 우상, 수평 기준 **65°** (`|Δy|/Δx = tan 65°`).
class _FractionForwardSlashPainter extends CustomPainter {
  _FractionForwardSlashPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    // 좌하 → 우상, 수평 기준 65°. 세로는 살짝 짧게(별 끝보다 아주 안쪽).
    const theta = 65 * math.pi / 180;
    final tanTheta = math.tan(theta);
    final inset = strokeWidth * 0.48;
    final baseDy = math.max(1.0, h - 2 * inset);
    final targetDy = baseDy * 0.74;
    var dx = targetDy / tanTheta;
    final maxDx = math.max(1.0, w - 2 * inset);
    if (dx > maxDx) {
      dx = maxDx;
    }
    // dx가 잘려도 항상 65°: 실제 세로 = dx * tan(θ)
    final actualDy = dx * tanTheta;
    final cx = w / 2;
    final cy = h / 2;
    canvas.drawLine(
      Offset(cx - dx / 2, cy + actualDy / 2),
      Offset(cx + dx / 2, cy - actualDy / 2),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _FractionForwardSlashPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
