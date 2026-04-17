import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'optimized_network_image.dart';

/// 드라마 탭·검색 등 그리드 카드 공통 (포스터 + 제목 + 별·장르).
double dramaGridScreenScale(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return (w / 360).clamp(0.85, 1.15);
}

/// 홈 DramaFeed `AppBar`와 동일한 스케일 (`community_screen` 의 [shortSide] 기준).
double dramaFeedHeaderScale(BuildContext context) {
  final shortSide = MediaQuery.sizeOf(context).shortestSide;
  return (shortSide / 360).clamp(0.85, 1.25);
}

/// 홈 `CommunityScreen` DramaFeed `AppBar.toolbarHeight` — **rh 곱한 값이 검색 슬롯 세로 고정값**.
const double dramaFeedHeaderToolbarRh = 52;

/// 홈 DramaFeed 탭줄 `PreferredSize` 높이 — **rh 곱한 값이 탭바 슬롯 세로 고정값**.
const double dramaFeedHeaderTabStripRh = 38;

/// 위 두 슬롯 합에 더하는 고정 px (소수 픽셀 오버플로 방지). 슬롯 높이 식에만 쓰고 내용은 넣지 않음.
const double dramaFeedHeaderSlopPx = 1;

/// 드라마 리스트 탭 상단 헤더 전체 높이 = [dramaFeedHeaderToolbarRh]·[dramaFeedHeaderTabStripRh]·슬롯만 (가변 불가).
double dramaFeedHeaderContentHeight(BuildContext context) {
  final rh = dramaFeedHeaderScale(context);
  return dramaFeedHeaderToolbarRh * rh +
      dramaFeedHeaderTabStripRh * rh +
      dramaFeedHeaderSlopPx;
}

class DramaGridCard extends StatelessWidget {
  const DramaGridCard({
    super.key,
    required this.displayTitle,
    required this.displaySubtitle,
    required this.imageUrl,
    required this.rating,
    required this.onTap,
    required this.posterPlaceholder,

    /// true면 포스터 아래 **제목만**(별·장르 줄 없음). 즐겨찾기 픽 등.
    this.titleOnly = false,

    /// 리스트 다중 픽 등 — 포스터 위 선택 표시
    this.pickMultiSelected = false,

    /// true면 4열 등 좁은 셀용으로 제목·별·장르 줄 글자·간격을 약간 줄임.
    this.denseTypography = false,
  });

  final String displayTitle;
  final String displaySubtitle;
  final String? imageUrl;
  final double rating;
  final VoidCallback onTap;
  final Widget posterPlaceholder;
  final bool titleOnly;
  final bool pickMultiSelected;
  final bool denseTypography;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? cs.onSurface : const Color(0xFF333333);
    final greyColor = isDark ? cs.onSurfaceVariant : Colors.grey.shade500;
    final r = dramaGridScreenScale(context);
    final titleFontSize = (denseTypography ? 11 * r : 12 * r).roundToDouble();
    final metaFontSize = (denseTypography ? 8 * r : 9 * r).roundToDouble();
    final starSize = denseTypography ? 10 * r : 11 * r;
    final genreColor = cs.onSurfaceVariant;
    return RepaintBoundary(
      child: LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final posterHeight = w / (1 / 1.4);
        final posterRadius = BorderRadius.circular(8 * r);
        return GestureDetector(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: w,
                height: posterHeight,
                child: ClipRRect(
                  borderRadius: posterRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageUrl != null && imageUrl!.isNotEmpty
                          ? OptimizedNetworkImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: denseTypography ? 140 : 160,
                              memCacheHeight: denseTypography ? 196 : 224,
                              placeholder: posterPlaceholder,
                              errorWidget: posterPlaceholder,
                            )
                          : posterPlaceholder,
                      if (pickMultiSelected)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.58),
                            ),
                          ),
                        ),
                      if (pickMultiSelected)
                        Positioned(
                          right: 5 * r,
                          top: 5 * r,
                          child: CustomPaint(
                            size: Size(22 * r, 22 * r),
                            painter: const _PickChunkyCheckPainter(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: denseTypography ? 0 : 1 * r),
              SizedBox(
                height: titleFontSize * 2,
                child: Text(
                  displayTitle,
                  strutStyle: StrutStyle(
                    fontSize: titleFontSize,
                    height: 1.0,
                    leading: 0,
                    forceStrutHeight: true,
                    fontWeight: FontWeight.w700,
                  ),
                  style: GoogleFonts.notoSansKr(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    height: 1.0,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!titleOnly) ...[
                SizedBox(height: denseTypography ? 0 : 0.5 * r),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: starSize,
                      color: rating > 0 ? AppColors.ratingStar : greyColor,
                    ),
                    Transform.translate(
                      offset: Offset(0 * r, 0),
                      child: Text(
                        rating == 0 ? '0' : rating.toStringAsFixed(1),
                        style: GoogleFonts.notoSansKr(
                          fontSize: metaFontSize,
                          fontWeight: FontWeight.w500,
                          color: isDark ? cs.onSurface : Colors.black,
                        ),
                      ),
                    ),
                    if (displaySubtitle.isNotEmpty) ...[
                      SizedBox(width: denseTypography ? 3 * r : 4 * r),
                      Expanded(
                        child: Text(
                          displaySubtitle,
                          style: GoogleFonts.notoSansKr(
                            fontSize: metaFontSize,
                            fontWeight: FontWeight.w600,
                            color: genreColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    ),
    );
  }
}

/// Add drama 다중 선택 — 흰 원 + 작은 검은 체크(각진 스트로크)
class _PickChunkyCheckPainter extends CustomPainter {
  const _PickChunkyCheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = d / 2 - 0.5;
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final stroke = (d * 0.1).clamp(1.5, 2.8);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final w = size.width;
    final h = size.height;
    // 중앙에 작게 모인 짧은 체크
    final path = Path()
      ..moveTo(w * 0.36, h * 0.56)
      ..lineTo(w * 0.46, h * 0.66)
      ..lineTo(w * 0.66, h * 0.42);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
