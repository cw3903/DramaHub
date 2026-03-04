import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/format_utils.dart';

/// 커뮤니티 게시글
class Post {
  const Post({
    required this.id,
    required this.title,
    required this.subreddit,
    required this.author,
    required this.timeAgo,
    required this.votes,
    required this.comments,
    this.views = 0,
    this.hasImage = false,
    this.imageUrls = const [],
    this.imageDimensions,
    this.hasVideo = false,
    this.videoUrl,
    this.videoThumbnailUrl,
    this.isGif,
    this.body,
    this.linkUrl,
    this.commentsList = const [],
    this.authorLevel = 1,
    this.likedBy = const [],
    this.dislikedBy = const [],
    this.category = 'free',
    this.authorPhotoUrl,
    this.authorAvatarColorIndex,
    this.popularAt,
    this.authorUid,
    this.country = 'us',
  });
  final String id;
  final String title;
  final String subreddit;
  final String author;
  final String timeAgo;
  final int votes;
  final int comments;
  final int views;
  final bool hasImage;
  /// Firebase Storage에 업로드된 이미지 URL 목록
  final List<String> imageUrls;
  /// 각 이미지의 [width, height]. null이거나 개수 불일치 시 기본 비율 사용
  final List<List<int>>? imageDimensions;
  final bool hasVideo;
  /// Firebase Storage에 업로드된 영상/GIF URL (단일)
  final String? videoUrl;
  /// 리스트/미리보기용 썸네일 URL (선택)
  final String? videoThumbnailUrl;
  /// GIF로 게시 시 true, 재생 시 루프·음소거 등에 활용
  final bool? isGif;
  final String? body;
  final String? linkUrl;
  final List<PostComment> commentsList;
  final int authorLevel; // 1~30
  /// 좋아요 누른 사용자 uid 목록 (Firestore 저장/복원용)
  final List<String> likedBy;
  /// 싫어요 누른 사용자 uid 목록
  final List<String> dislikedBy;
  /// 게시판 구분: 'free' = 자유게시판, 'question' = 질문게시판
  final String category;
  /// 작성자 프로필 사진 URL (없으면 null)
  final String? authorPhotoUrl;
  /// 작성자 아바타 색 인덱스 (없으면 null → 해시 fallback)
  final int? authorAvatarColorIndex;
  /// 인기글 조건 최초 달성 시각 (좋아요 10↑ 또는 조회수 100↑). null이면 미달성.
  final DateTime? popularAt;
  /// 작성자 Firebase uid (알림 전송용)
  final String? authorUid;
  /// 지역: 'kr' 한국, 'us' US, 'jp' 일본, 'cn' 중국 (따로 보기용)
  final String country;

  /// Firestore 저장/복원용
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subreddit': subreddit,
      'author': author,
      'timeAgo': timeAgo,
      'votes': votes,
      'comments': comments,
      'views': views,
      'hasImage': hasImage,
      'imageUrls': imageUrls,
      if (imageDimensions != null) 'imageDimensions': imageDimensions!
          .map((d) => {'width': d[0], 'height': d[1]}).toList(),
      'hasVideo': hasVideo,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (videoThumbnailUrl != null) 'videoThumbnailUrl': videoThumbnailUrl,
      if (isGif != null) 'isGif': isGif,
      'body': body,
      'linkUrl': linkUrl,
      'authorLevel': authorLevel,
      'commentsList': commentsList.map((c) => c.toMap()).toList(),
      'likedBy': likedBy,
      'dislikedBy': dislikedBy,
      'category': category,
      if (authorPhotoUrl != null) 'authorPhotoUrl': authorPhotoUrl,
      if (authorAvatarColorIndex != null) 'authorAvatarColorIndex': authorAvatarColorIndex,
      if (authorUid != null) 'authorUid': authorUid,
      'country': country,
    };
  }

  /// Firestore에서 로드한 Map → Post (createdAt은 toMap 시 사용)
  static Post fromMap(Map<String, dynamic> map) {
    final commentsRaw = map['commentsList'];
    final commentsListRaw = commentsRaw is List<dynamic>
        ? commentsRaw
        : (commentsRaw is Map
            ? (commentsRaw.keys.toList()..sort((a, b) => (int.tryParse(a.toString()) ?? 0).compareTo(int.tryParse(b.toString()) ?? 0)))
                .map((k) => commentsRaw[k])
                .toList()
            : <dynamic>[]);
    final commentsList = commentsListRaw
        .map((e) => PostComment.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final likedByRaw = map['likedBy'];
    final likedBy = (likedByRaw != null && likedByRaw is List<dynamic>)
        ? List<String>.from(likedByRaw.map((e) => e.toString()))
        : (likedByRaw is Map ? (likedByRaw as Map).values.map((e) => e.toString()).toList() : <String>[]);
    final dislikedByRaw = map['dislikedBy'];
    final dislikedBy = (dislikedByRaw != null && dislikedByRaw is List<dynamic>)
        ? List<String>.from(dislikedByRaw.map((e) => e.toString()))
        : (dislikedByRaw is Map ? (dislikedByRaw as Map).values.map((e) => e.toString()).toList() : <String>[]);

    final imageUrlsRaw = map['imageUrls'];
    final imageUrls = (imageUrlsRaw is List<dynamic>)
        ? List<String>.from(imageUrlsRaw.map((e) => e.toString()))
        : <String>[];
    final dimRaw = map['imageDimensions'];
    final imageDimensions = (dimRaw is List<dynamic>)
        ? dimRaw
            .map((e) {
              if (e is List<dynamic>) return List<int>.from(e.map((x) => (x as num).toInt()));
              if (e is Map) {
                final w = (e['width'] as num?)?.toInt();
                final h = (e['height'] as num?)?.toInt();
                if (w != null && h != null) return [w, h];
              }
              return null;
            })
            .whereType<List<int>>()
            .toList()
        : null;

    return Post(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subreddit: map['subreddit'] as String? ?? '',
      author: map['author'] as String? ?? '',
      timeAgo: map['timeAgo'] as String? ?? '',
      votes: (map['votes'] as num?)?.toInt() ?? 0,
      comments: (map['comments'] as num?)?.toInt() ?? 0,
      views: (map['views'] as num?)?.toInt() ?? 0,
      hasImage: map['hasImage'] as bool? ?? false,
      imageUrls: imageUrls,
      imageDimensions: imageDimensions?.isNotEmpty == true ? imageDimensions : null,
      hasVideo: map['hasVideo'] as bool? ?? false,
      videoUrl: map['videoUrl'] as String?,
      videoThumbnailUrl: map['videoThumbnailUrl'] as String?,
      isGif: map['isGif'] as bool?,
      body: map['body'] as String?,
      linkUrl: map['linkUrl'] as String?,
      commentsList: commentsList,
      authorLevel: (map['authorLevel'] as num?)?.toInt() ?? 1,
      likedBy: likedBy,
      dislikedBy: dislikedBy,
      category: map['category'] as String? ?? 'free',
      authorPhotoUrl: map['authorPhotoUrl'] as String?,
      authorAvatarColorIndex: (map['authorAvatarColorIndex'] as num?)?.toInt(),
      popularAt: (map['popularAt'] is Timestamp) ? (map['popularAt'] as Timestamp).toDate() : null,
      authorUid: map['authorUid'] as String?,
      country: _normalizeCountry(map['country'] as String?),
    );
  }

  static String _normalizeCountry(String? v) {
    if (v == null || v.isEmpty) return 'us';
    final c = v.toLowerCase();
    if (c == 'kr' || c == 'jp' || c == 'cn') return c;
    return 'us';
  }
}

/// 댓글 (중첩 가능, 좋아요/싫어요는 likedBy/dislikedBy로 저장)
class PostComment {
  const PostComment({
    required this.id,
    required this.author,
    required this.timeAgo,
    required this.text,
    required this.votes,
    this.replies = const [],
    this.likedBy = const [],
    this.dislikedBy = const [],
    this.authorPhotoUrl,
    this.authorAvatarColorIndex,
    this.createdAtDate,
    this.imageUrl,
  });
  final String id;
  final String author;
  final String timeAgo;
  final String text;
  final int votes;
  final List<PostComment> replies;
  final List<String> likedBy;
  final List<String> dislikedBy;
  final String? authorPhotoUrl;
  final int? authorAvatarColorIndex;
  /// Firestore에서 읽어온 실제 작성 시각 (있으면 timeAgo를 동적으로 계산 가능)
  final DateTime? createdAtDate;
  /// 댓글 첨부 이미지/GIF URL (없으면 null)
  final String? imageUrl;

  /// 실제 작성 시각 기준으로 상대 시간 반환. createdAtDate가 없으면 저장된 timeAgo 반환.
  String get displayTimeAgo =>
      createdAtDate != null ? formatTimeAgo(createdAtDate!) : timeAgo;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'author': author,
      'timeAgo': timeAgo,
      'text': text,
      'votes': votes,
      'replies': replies.map((r) => r.toMap()).toList(),
      'likedBy': likedBy,
      'dislikedBy': dislikedBy,
      if (authorPhotoUrl != null) 'authorPhotoUrl': authorPhotoUrl,
      if (authorAvatarColorIndex != null) 'authorAvatarColorIndex': authorAvatarColorIndex,
      if (createdAtDate != null) 'createdAt': Timestamp.fromDate(createdAtDate!),
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }

  static List<dynamic> _toList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List<dynamic>) return raw;
    if (raw is Map) {
      final keys = raw.keys.toList();
      keys.sort((a, b) => (int.tryParse(a.toString()) ?? 0).compareTo(int.tryParse(b.toString()) ?? 0));
      return keys.map((k) => raw[k]).toList();
    }
    return [];
  }

  static List<String> _toStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List<dynamic>) return raw.map((e) => e.toString()).toList();
    if (raw is Map) return raw.values.map((e) => e.toString()).toList();
    return [];
  }

  static PostComment fromMap(Map<String, dynamic> map) {
    final repliesList = _toList(map['replies']);
    final replies = repliesList
        .map((e) => PostComment.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final likedBy = _toStringList(map['likedBy']);
    final dislikedBy = _toStringList(map['dislikedBy']);
    final createdAt = map['createdAt'];
    final createdAtDate = createdAt is Timestamp ? createdAt.toDate() : null;
    final timeAgoStr = createdAtDate != null
        ? formatTimeAgo(createdAtDate)
        : (map['timeAgo'] as String? ?? '');
    return PostComment(
      id: map['id'] as String? ?? '',
      author: map['author'] as String? ?? '',
      timeAgo: timeAgoStr,
      text: map['text'] as String? ?? '',
      votes: (map['votes'] as num?)?.toInt() ?? 0,
      replies: replies,
      likedBy: likedBy,
      dislikedBy: dislikedBy,
      authorPhotoUrl: map['authorPhotoUrl'] as String?,
      authorAvatarColorIndex: (map['authorAvatarColorIndex'] as num?)?.toInt(),
      createdAtDate: createdAtDate,
      imageUrl: map['imageUrl'] as String?,
    );
  }
}
