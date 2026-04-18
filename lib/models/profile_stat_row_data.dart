import 'post.dart';

/// 프로필 상단 Posts / Reviews / Follow 통계 행용 (record 대신 클래스로 핫 리로드 시 타입 꼬임 방지).
class ProfileStatRowData {
  const ProfileStatRowData({
    required this.postAuthor,
    required this.commentAuthor,
    required this.postCount,
    required this.commentCount,
    required this.reviewCount,
    this.followCountOverride,
    this.viewAuthorUid,
    this.posts,
    this.commentItems,
  });

  final String postAuthor;
  final String commentAuthor;
  final int postCount;
  final int commentCount;
  final int reviewCount;
  final int? followCountOverride;
  /// 타인 프로필: [UserPostsScreen]에서 `authorUid`로 글·댓글 로드.
  final String? viewAuthorUid;
  /// Posts 탭 즉시 표시용 — 프로필 통계 로드 시 함께 받은 게시글 목록.
  final List<Post>? posts;
  /// Comments 탭 즉시 표시용 — 프로필 통계 로드 시 함께 받은 댓글 목록.
  final List<({Post post, PostComment comment})>? commentItems;

  /// 프로필 Posts 칩에 표시: Posts 탭 건수 + Comments 탭 건수 ([UserPostsScreen] 합계와 맞춤).
  int get postsStatChipCount => postCount + commentCount;
}
