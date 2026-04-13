/// 프로필 별점 분포 (0.5 단위 10구간).
class ProfileRatingHistogram {
  const ProfileRatingHistogram({
    required this.countsPerHalfStar,
    required this.total,
    required this.average,
  });

  /// 인덱스 0 = ★0.5, …, 9 = ★5.0
  final List<int> countsPerHalfStar;
  final int total;
  final double average;

  static ProfileRatingHistogram empty() => ProfileRatingHistogram(
        countsPerHalfStar: List<int>.filled(10, 0),
        total: 0,
        average: 0,
      );

  factory ProfileRatingHistogram.fromRatings(List<double> ratings) {
    final counts = List<int>.filled(10, 0);
    if (ratings.isEmpty) {
      return ProfileRatingHistogram(countsPerHalfStar: counts, total: 0, average: 0);
    }
    var sum = 0.0;
    for (final r in ratings) {
      sum += r;
      final idx = bucketIndexForRating(r);
      if (idx >= 0 && idx < 10) counts[idx]++;
    }
    return ProfileRatingHistogram(
      countsPerHalfStar: counts,
      total: ratings.length,
      average: sum / ratings.length,
    );
  }

  /// 0.5~5.0 구간 인덱스 (0..9), 유효하지 않으면 -1
  static int bucketIndexForRating(double r) {
    if (r <= 0) return -1;
    final rounded = ((r * 2).round() / 2).clamp(0.5, 5.0);
    return ((rounded * 2).toInt() - 1).clamp(0, 9);
  }

  int get maxCount {
    var m = 0;
    for (final c in countsPerHalfStar) {
      if (c > m) m = c;
    }
    return m;
  }
}
