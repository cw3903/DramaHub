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

/// DramaFeed 탭 필터: review / trend / talk / ask
bool postMatchesFeedFilter(Post p, String board) {
  switch (board) {
    case 'review':
      return postDisplayType(p) == 'review';
    case 'trend':
      return postInTrendFeed(p);
    case 'talk':
      return postDisplayType(p) == 'talk';
    case 'ask':
      return postDisplayType(p) == 'ask';
    default:
      return true;
  }
}
