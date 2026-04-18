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

/// DramaFeed 리뷰 탭: 본문도 없고 별점도 없으면 제외.
bool reviewFeedPostHasWrittenBody(Post post) {
  final b = post.body?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  final r = post.rating ?? 0;
  if (b.isEmpty && r <= 0) return false; // ← && 로 수정
  return true;
}

/// DramaFeed 탭 필터: review / trend / talk / ask
bool postMatchesFeedFilter(Post post, String board) {
  final t = _postFeedFilterToken(post);

  switch (board) {
    case 'review':
      return t == 'review' && reviewFeedPostHasWrittenBody(post);
    case 'trend':
      return postInTrendFeed(post);
    case 'talk':
      // t.isEmpty(레거시 필드 없는 글)는 review가 아닌 경우만 talk으로 처리
      return t == 'talk' ||
          t == 'free' ||
          t == 'general' ||
          (t.isEmpty && post.type?.trim().isEmpty != false);
    case 'ask':
      return t == 'ask' || t == 'question';
    default:
      return true;
  }
}

/// 프로필 Posts(톡·에스크): 리뷰 게시판·트렌드 전용 글 제외.
bool postIsCommunityTalkOrAsk(Post p) {
  final t = postDisplayType(p);
  return t == 'talk' || t == 'ask';
}
