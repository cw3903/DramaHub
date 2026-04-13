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
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.category = 'free',
    this.authorPhotoUrl,
    this.authorAvatarColorIndex,
    this.popularAt,
    this.authorUid,
    this.country = 'us',
    this.type,
    this.dramaId,
    this.dramaTitle,
    this.dramaThumbnail,
    this.rating,
    this.hasSpoiler = false,
    this.isLiked = false,
    this.isFirstWatch = true,
    this.tags = const [],
    this.allowReply = true,
    this.createdAt,
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
  /// 좋아요 수 (posts/{id}/likes 서브컬렉션과 동기화)
  final int likeCount;
  /// 싫어요 수 (posts/{id}/dislikes 서브컬렉션과 동기화)
  final int dislikeCount;
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
  /// 게시판 종류: review | trend | talk | ask (없으면 category로 폴백)
  final String? type;
  /// 리뷰 전용: 드라마 ID
  final String? dramaId;
  final String? dramaTitle;
  final String? dramaThumbnail;
  /// 리뷰 전용 별점 0.5~5.0
  final double? rating;
  final bool hasSpoiler;
  /// 리뷰: 이 드라마에 대한 좋아요(하트) 표시 (게시글 투표 likedBy와 별개)
  final bool isLiked;
  /// 리뷰: 첫 시청 여부
  final bool isFirstWatch;
  final List<String> tags;
  /// 리뷰: 댓글 허용 여부
  final bool allowReply;
  /// Firestore `createdAt` (글 상세·Letterboxd 리뷰 시청일 등)
  final DateTime? createdAt;

  Post copyWith({
    String? id,
    String? title,
    String? subreddit,
    String? author,
    String? timeAgo,
    int? votes,
    int? comments,
    int? views,
    bool? hasImage,
    List<String>? imageUrls,
    List<List<int>>? imageDimensions,
    bool? hasVideo,
    String? videoUrl,
    String? videoThumbnailUrl,
    bool? isGif,
    String? body,
    String? linkUrl,
    List<PostComment>? commentsList,
    int? authorLevel,
    List<String>? likedBy,
    List<String>? dislikedBy,
    int? likeCount,
    int? dislikeCount,
    String? category,
    String? authorPhotoUrl,
    int? authorAvatarColorIndex,
    DateTime? popularAt,
    String? authorUid,
    String? country,
    String? type,
    String? dramaId,
    String? dramaTitle,
    String? dramaThumbnail,
    double? rating,
    bool? hasSpoiler,
    bool? isLiked,
    bool? isFirstWatch,
    List<String>? tags,
    bool? allowReply,
    DateTime? createdAt,
  }) {
    return Post(
      id: id ?? this.id,
      title: title ?? this.title,
      subreddit: subreddit ?? this.subreddit,
      author: author ?? this.author,
      timeAgo: timeAgo ?? this.timeAgo,
      votes: votes ?? this.votes,
      comments: comments ?? this.comments,
      views: views ?? this.views,
      hasImage: hasImage ?? this.hasImage,
      imageUrls: imageUrls ?? this.imageUrls,
      imageDimensions: imageDimensions ?? this.imageDimensions,
      hasVideo: hasVideo ?? this.hasVideo,
      videoUrl: videoUrl ?? this.videoUrl,
      videoThumbnailUrl: videoThumbnailUrl ?? this.videoThumbnailUrl,
      isGif: isGif ?? this.isGif,
      body: body ?? this.body,
      linkUrl: linkUrl ?? this.linkUrl,
      commentsList: commentsList ?? this.commentsList,
      authorLevel: authorLevel ?? this.authorLevel,
      likedBy: likedBy ?? this.likedBy,
      dislikedBy: dislikedBy ?? this.dislikedBy,
      likeCount: likeCount ?? this.likeCount,
      dislikeCount: dislikeCount ?? this.dislikeCount,
      category: category ?? this.category,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      authorAvatarColorIndex: authorAvatarColorIndex ?? this.authorAvatarColorIndex,
      popularAt: popularAt ?? this.popularAt,
      authorUid: authorUid ?? this.authorUid,
      country: country ?? this.country,
      type: type ?? this.type,
      dramaId: dramaId ?? this.dramaId,
      dramaTitle: dramaTitle ?? this.dramaTitle,
      dramaThumbnail: dramaThumbnail ?? this.dramaThumbnail,
      rating: rating ?? this.rating,
      hasSpoiler: hasSpoiler ?? this.hasSpoiler,
      isLiked: isLiked ?? this.isLiked,
      isFirstWatch: isFirstWatch ?? this.isFirstWatch,
      tags: tags ?? this.tags,
      allowReply: allowReply ?? this.allowReply,
      createdAt: createdAt ?? this.createdAt,
    );
  }

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
      'likeCount': likeCount,
      'dislikeCount': dislikeCount,
      'category': category,
      if (authorPhotoUrl != null) 'authorPhotoUrl': authorPhotoUrl,
      if (authorAvatarColorIndex != null) 'authorAvatarColorIndex': authorAvatarColorIndex,
      if (authorUid != null) 'authorUid': authorUid,
      'country': country,
      if (type != null && type!.isNotEmpty) 'type': type,
      if (dramaId != null && dramaId!.isNotEmpty) 'dramaId': dramaId,
      if (dramaTitle != null && dramaTitle!.isNotEmpty) 'dramaTitle': dramaTitle,
      if (dramaThumbnail != null && dramaThumbnail!.isNotEmpty) 'dramaThumbnail': dramaThumbnail,
      if (rating != null) 'rating': rating,
      'hasSpoiler': hasSpoiler,
      'isLiked': isLiked,
      'isFirstWatch': isFirstWatch,
      'tags': tags,
      'allowReply': allowReply,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    };
  }

  static String _categoryFromMap(dynamic raw) {
    if (raw == null) return 'free';
    if (raw is String) {
      final s = raw.trim();
      return s.isEmpty ? 'free' : s;
    }
    final s = raw.toString().trim();
    return s.isEmpty ? 'free' : s;
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
        : (likedByRaw is Map ? likedByRaw.values.map((e) => e.toString()).toList() : <String>[]);
    final dislikedByRaw = map['dislikedBy'];
    final dislikedBy = (dislikedByRaw != null && dislikedByRaw is List<dynamic>)
        ? List<String>.from(dislikedByRaw.map((e) => e.toString()))
        : (dislikedByRaw is Map ? dislikedByRaw.values.map((e) => e.toString()).toList() : <String>[]);

    final likeCount = (map['likeCount'] as num?)?.toInt() ?? likedBy.length;
    final dislikeCount = (map['dislikeCount'] as num?)?.toInt() ?? dislikedBy.length;

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

    final createdAtRaw = map['createdAt'];
    final DateTime? createdAtParsed = createdAtRaw is Timestamp
        ? createdAtRaw.toDate()
        : null;
    return Post(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subreddit: map['subreddit'] as String? ?? '',
      author: map['author'] as String? ?? '',
      timeAgo: map['timeAgo'] as String? ?? '',
      votes: (map['votes'] as num?)?.toInt() ?? (likeCount - dislikeCount),
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
      likeCount: likeCount,
      dislikeCount: dislikeCount,
      category: _categoryFromMap(map['category']),
      authorPhotoUrl: map['authorPhotoUrl'] as String?,
      authorAvatarColorIndex: (map['authorAvatarColorIndex'] as num?)?.toInt(),
      popularAt: (map['popularAt'] is Timestamp) ? (map['popularAt'] as Timestamp).toDate() : null,
      authorUid: map['authorUid'] as String?,
      country: _normalizeCountry(map['country'] as String?),
      type: map['type'] as String?,
      dramaId: map['dramaId'] as String?,
      dramaTitle: map['dramaTitle'] as String?,
      dramaThumbnail: map['dramaThumbnail'] as String?,
      rating: (map['rating'] is num) ? (map['rating'] as num).toDouble() : null,
      hasSpoiler: map['hasSpoiler'] as bool? ?? false,
      isLiked: map['isLiked'] as bool? ?? false,
      isFirstWatch: map['isFirstWatch'] as bool? ?? true,
      tags: _tagsFromMap(map['tags']),
      allowReply: map['allowReply'] as bool? ?? true,
      createdAt: createdAtParsed,
    );
  }

  static List<String> _tagsFromMap(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  static String _normalizeCountry(String? v) {
    if (v == null || v.isEmpty) return 'us';
    final c = v.toLowerCase();
    if (c == 'kr' || c == 'jp' || c == 'cn') return c;
    return 'us';
  }

  /// Firestore 원본 [data]가 지역 피드([viewerCountry])에 포함돼야 하는지.
  /// `country`가 없거나 빈 문자열이면 레거시 문서로 보고 모든 지역에서 표시
  /// (서버 `where('country', …)`에선 잡히지 않던 글을 피드에서 복구).
  static bool documentVisibleInCountryFeed(Map<String, dynamic> data, String? viewerCountry) {
    final eq = viewerCountry?.trim();
    if (eq == null || eq.isEmpty) return true;
    final raw = data['country'];
    if (raw == null) return true;
    if (raw is String && raw.trim().isEmpty) return true;
    return _normalizeCountry(raw as String?) == eq;
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
