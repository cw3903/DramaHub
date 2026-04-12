import '../models/post.dart';

/// Firestore `type` 없을 때: 질문 게시판 → ask, 그 외 → talk
String postDisplayType(Post p) {
  final t = p.type?.trim().toLowerCase();
  if (t == 'review' || t == 'trend' || t == 'talk' || t == 'ask') return t!;
  if (p.category == 'question') return 'ask';
  return 'talk';
}

bool postInTrendFeed(Post p) =>
    p.votes >= 10 || p.views >= 100 || postDisplayType(p) == 'trend';

/// type 없을 때 탭 필터용 토큰: type → category → subreddit (레거시 Firestore 대응)
String _postFeedFilterToken(Post post) {
  if (post.type != null && post.type!.trim().isNotEmpty) {
    return post.type!.trim().toLowerCase();
  }
  final cat = post.category.trim().toLowerCase();
  if (cat.isNotEmpty) return cat;
  return post.subreddit.trim().toLowerCase();
}

/// DramaFeed 탭 필터: review / trend / talk / ask
bool postMatchesFeedFilter(Post post, String board) {
  final t = _postFeedFilterToken(post);

  switch (board) {
    case 'review':
      return t == 'review';
    case 'trend':
      return postInTrendFeed(post);
    case 'talk':
      return t == 'talk' ||
          t == 'free' ||
          t == 'general' ||
          t.isEmpty;
    case 'ask':
      return t == 'ask' || t == 'question';
    default:
      return true;
  }
}
