/// 드라마 목록용 간단 정보
class DramaItem {
  const DramaItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.views,
    this.rating = 0,
    this.isPopular = false,
    this.isNew = false,
    this.imageUrl,
  });
  final String id;
  final String title;
  final String subtitle;
  final String views;
  /// 평점 0~5
  final double rating;
  final bool isPopular;
  final bool isNew;
  /// 포스터 이미지 URL(네트워크) 또는 asset 경로(assets/...). null이면 플레이스홀더.
  final String? imageUrl;
}

/// 회차 정보
class DramaEpisode {
  const DramaEpisode({
    required this.number,
    required this.title,
    this.duration = '45분',
    this.rating,
  });
  final int number;
  final String title;
  final String duration;
  /// 회차별 별점 (없으면 null, UI에서 기본값 표시)
  final double? rating;
}

/// 리뷰에 대한 댓글 (대댓글)
class DramaReviewReply {
  const DramaReviewReply({
    required this.author,
    required this.text,
    required this.timeAgo,
    this.id,
    this.likeCount = 0,
    this.authorPhotoUrl,
  });
  final String author;
  final String text;
  final String timeAgo;
  /// 고유 식별자 (좋아요 추적용)
  final String? id;
  /// 좋아요 수
  final int likeCount;
  /// 작성자 프로필 사진 URL (회원 아이콘용)
  final String? authorPhotoUrl;
}

/// 평점+리뷰 (하나의 댓글이 평점 포함)
class DramaReview {
  const DramaReview({
    required this.userName,
    required this.rating,
    required this.comment,
    required this.timeAgo,
    this.id,
    this.likeCount,
    this.replies = const [],
    this.authorPhotoUrl,
    this.writtenAt,
    this.authorUid,
    /// DramaFeed `posts` 문서 id (없으면 [id]로 피드 조회 시도)
    this.feedPostId,
    /// `drama_reviews.country` (us/kr/jp/cn). null이면 레거시.
    this.appLocale,
  });
  final String userName;
  final double rating;
  final String comment;
  final String timeAgo;
  /// 고유 식별자 (정렬/좋아요 추적용)
  final String? id;
  /// 좋아요 수 (null이면 0으로 처리)
  final int? likeCount;
  /// 최신순·스포트라이트용 (없으면 timeAgo만으로는 정렬 불가)
  final DateTime? writtenAt;
  /// 리뷰에 대한 댓글 목록
  final List<DramaReviewReply> replies;
  /// 작성자 프로필 사진 URL (회원 아이콘용)
  final String? authorPhotoUrl;
  /// `drama_reviews` 문서의 `uid`
  final String? authorUid;
  /// 홈 리뷰 피드 `posts`와 1:1일 때만 채워짐
  final String? feedPostId;

  final String? appLocale;
}

/// 드라마 상세 정보
class DramaDetail {
  const DramaDetail({
    required this.item,
    required this.synopsis,
    required this.year,
    required this.genre,
    required this.averageRating,
    required this.ratingCount,
    required this.episodes,
    required this.reviews,
    required this.similar,
    this.cast = const [],
  });
  final DramaItem item;
  final String synopsis;
  final String year;
  final String genre;
  final double averageRating;
  final int ratingCount;
  final List<DramaEpisode> episodes;
  final List<DramaReview> reviews;
  final List<DramaItem> similar;
  /// 출연진 이름 목록 (Cast 섹션용)
  final List<String> cast;
}
