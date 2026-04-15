import 'package:flutter/material.dart';

/// 가장 가까운 0.5점 단위로 표시. 예: 3.5 → 꽉 찬 별 3개 + 반별 1개 (빈 테두리 별 없음).
class GreenRatingStars extends StatelessWidget {
  const GreenRatingStars({
    super.key,
    required this.rating,
    this.size = 14,
    this.color = const Color(0xFFFFB020),
  });

  final double rating;
  final double size;
  final Color color;

  /// [0, 5]로 자른 뒤 가장 가까운 0.5 배수.
  static double displayValue(double rating) {
    final c = rating.clamp(0.0, 5.0);
    return (c * 2).round() / 2.0;
  }

  @override
  Widget build(BuildContext context) {
    final r = displayValue(rating);
    final full = r.floor();
    final hasHalf = (r - full) >= 0.5;
    final children = <Widget>[];

    for (var i = 0; i < full; i++) {
      children.add(
        Padding(
          padding: EdgeInsets.only(left: children.isEmpty ? 0 : 0.5),
          child: Icon(Icons.star_rounded, size: size, color: color),
        ),
      );
    }
    if (hasHalf) {
      children.add(
        Padding(
          padding: EdgeInsets.only(left: children.isEmpty ? 0 : 0.5),
          child: Icon(Icons.star_half_rounded, size: size, color: color),
        ),
      );
    }
    if (children.isEmpty) {
      return SizedBox(height: size);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
