import 'package:flutter/material.dart';

/// 리뷰 본문 있음 표시 — 다이어리 행 별 옆과 동일한 3줄 마크.
class ReviewBodyLinesIndicator extends StatelessWidget {
  const ReviewBodyLinesIndicator({super.key, required this.color});

  final Color color;

  static const double _w = 12;
  static const double _stroke = 1.65;
  static const double _gap = 2.35;

  @override
  Widget build(BuildContext context) {
    Widget line(double width) => Container(
          width: width,
          height: _stroke,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_stroke / 2),
          ),
        );
    return SizedBox(
      height: 15,
      child: Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line(_w),
            SizedBox(height: _gap),
            line(_w * 0.9),
            SizedBox(height: _gap),
            line(_w * 0.75),
          ],
        ),
      ),
    );
  }
}
