import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/post.dart';
import '../models/profile_rating_histogram.dart';
import '../models/notification_item.dart';
import '../utils/format_utils.dart';
import '../utils/post_board_utils.dart';
import 'auth_service.dart';
import 'drama_list_service.dart';
import 'level_service.dart';
import 'notification_service.dart';
import 'review_service.dart';
import 'user_profile_service.dart';

/// 자유게시판 글 Firestore 저장/로드
class PostService {
  PostService._();
  static final PostService instance = PostService._();

  static const String _collection = 'posts';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      default: return 'image/jpeg';
    }
  }

  static const int _maxImageLongEdge = 1280;
  static const int _jpegQuality = 82;

  /// 한 장 압축: 긴 변 1280 이하, JPEG 품질 82. 실패 시 null (원본 업로드).
  /// XFile을 받아 content:// URI도 처리.
  Future<({List<int> bytes, int width, int height})?> _compressImage(XFile xfile) async {
    try {
      final bytes = await xfile.readAsBytes();
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return null;
      final w = decoded.width;
      final h = decoded.height;
      final maxEdge = w > h ? w : h;
      img.Image resized = decoded;
      if (maxEdge > _maxImageLongEdge) {
        if (w > h) {
          resized = img.copyResize(decoded, width: _maxImageLongEdge);
        } else {
          resized = img.copyResize(decoded, height: _maxImageLongEdge);
        }
      }
      final out = img.encodeJpg(resized, quality: _jpegQuality);
      return (bytes: out, width: resized.width, height: resized.height);
    } catch (_) {
      return null;
    }
  }

  /// Storage 업로드 1회 시도 헬퍼. 실패 시 예외.
  Future<String> _uploadBytesWithRetry(String storagePath, Uint8List bytes, String contentType) async {
    const delays = [Duration.zero, Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8)];
    Object? lastErr;
    for (var i = 0; i < delays.length; i++) {
      if (i > 0) await Future.delayed(delays[i]);
      try {
        final ref = _storage.ref().child(storagePath);
        await ref.putData(bytes, SettableMetadata(contentType: contentType));
        return await ref.getDownloadURL();
      } catch (e) {
        lastErr = e;
        debugPrint('_uploadBytesWithRetry attempt ${i + 1} fail: $e');
      }
    }
    throw lastErr ?? Exception('upload failed');
  }

  Future<String> _uploadFileWithRetry(String storagePath, File file, String contentType) async {
    const delays = [Duration.zero, Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8)];
    Object? lastErr;
    for (var i = 0; i < delays.length; i++) {
      if (i > 0) await Future.delayed(delays[i]);
      try {
        final ref = _storage.ref().child(storagePath);
        await ref.putFile(file, SettableMetadata(contentType: contentType));
        return await ref.getDownloadURL();
      } catch (e) {
        lastErr = e;
        debugPrint('_uploadFileWithRetry attempt ${i + 1} fail: $e');
      }
    }
    throw lastErr ?? Exception('upload failed');
  }

  /// 게시글 이미지 압축 후 병렬 업로드. XFile 목록을 받아 content:// URI도 처리.
  Future<({List<String> urls, List<List<int>> dimensions})> uploadPostImages(List<XFile> xfiles) async {
    if (xfiles.isEmpty) return (urls: <String>[], dimensions: <List<int>>[]);
    final prefix = 'posts/${DateTime.now().millisecondsSinceEpoch}';

    final compressed = await Future.wait(
      xfiles.map((x) => _compressImage(x)),
    );

    final uploadFutures = <Future<({String url, List<int> dims})>>[];
    for (var i = 0; i < xfiles.length; i++) {
      final idx = i;
      final c = compressed[i];
      final xfile = xfiles[i];
      uploadFutures.add(() async {
        if (c != null) {
          final url = await _uploadBytesWithRetry('${prefix}_$idx.jpg', Uint8List.fromList(c.bytes), 'image/jpeg');
          return (url: url, dims: [c.width, c.height]);
        } else {
          // 압축 실패 → XFile.readAsBytes()로 원본 업로드 (content:// URI 처리 가능)
          final bytes = await xfile.readAsBytes();
          if (bytes.isEmpty) throw Exception('empty file: ${xfile.path}');
          final name = xfile.name.isNotEmpty ? xfile.name : xfile.path.split('/').last;
          final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
          final url = await _uploadBytesWithRetry('${prefix}_$idx.$ext', Uint8List.fromList(bytes), _contentTypeForExtension(ext));
          final dims = await _getDimensionsFromBytes(bytes);
          return (url: url, dims: dims ?? [0, 0]);
        }
      }());
    }

    final results = await Future.wait(uploadFutures);
    return (
      urls: results.map((r) => r.url).toList(),
      dimensions: results.map((r) => r.dims).toList(),
    );
  }

  Future<List<int>?> _getDimensionsFromBytes(List<int> bytes) async {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      return decoded != null ? [decoded.width, decoded.height] : null;
    } catch (_) {
      return null;
    }
  }

  /// 댓글 첨부 이미지/GIF 한 장 업로드 후 다운로드 URL 반환. 실패 시 null.
  /// posts/ 경로 사용 (기존 Storage 규칙으로 허용, comment_ 접두사로 구분)
  Future<String?> uploadCommentImage(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('uploadCommentImage: file not found $filePath');
        return null;
      }
      final ext = filePath.split('.').last.toLowerCase();
      final contentType = _contentTypeForExtension(ext);
      final ref = _storage.ref().child('posts/comment_${DateTime.now().millisecondsSinceEpoch}.$ext');
      // putFile 스트리밍 방식 — putData(bytes)보다 메모리 효율적이고 빠름
      await ref.putFile(file, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (e, st) {
      debugPrint('uploadCommentImage: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// 게시글 영상 1개 업로드 후 다운로드 URL 반환. 실패 시 예외.
  Future<String> uploadPostVideo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('uploadPostVideo: file not found $filePath');
      throw Exception('영상 파일을 찾을 수 없습니다. (content URI는 앱에서 임시 파일로 복사 후 사용해 주세요.)');
    }
    final ext = filePath.split('.').last.toLowerCase();
    final contentType = ext == 'gif' ? 'image/gif' : 'video/mp4';
    return await _uploadFileWithRetry('posts/video_${DateTime.now().millisecondsSinceEpoch}.$ext', file, contentType);
  }

  /// 게시글 영상 썸네일 이미지 1개 업로드 후 다운로드 URL 반환. 실패 시 예외.
  Future<String> uploadPostVideoThumbnail(String thumbnailFilePath) async {
    final file = File(thumbnailFilePath);
    if (!await file.exists()) {
      debugPrint('uploadPostVideoThumbnail: file not found $thumbnailFilePath');
      throw Exception('썸네일 파일을 찾을 수 없습니다: $thumbnailFilePath');
    }
    return await _uploadFileWithRetry('posts/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg', file, 'image/jpeg');
  }

  /// 게시글 GIF 1개 업로드 후 다운로드 URL 반환. 실패 시 예외.
  Future<String> uploadPostGif(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('uploadPostGif: file not found $filePath');
      throw Exception('GIF 파일을 찾을 수 없습니다.');
    }
    return await _uploadFileWithRetry('posts/gif_${DateTime.now().millisecondsSinceEpoch}.gif', file, 'image/gif');
  }

  CollectionReference<Map<String, dynamic>> get _col => _firestore.collection(_collection);

  DocumentReference<Map<String, dynamic>> _postLikeDoc(String postId, String uid) =>
      _col.doc(postId).collection('likes').doc(uid);

  DocumentReference<Map<String, dynamic>> _postDislikeDoc(String postId, String uid) =>
      _col.doc(postId).collection('dislikes').doc(uid);

  /// posts/{postId}/likes|dislikes/{uid} 존재 여부로 현재 사용자 투표 상태를 [Post.likedBy]/[Post.dislikedBy]에 반영.
  Future<List<Post>> hydratePostsViewerVotes(List<Post> posts) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null || posts.isEmpty) return posts;
    const chunk = 24;
    final out = <Post>[];
    for (var i = 0; i < posts.length; i += chunk) {
      final end = min(i + chunk, posts.length);
      final slice = posts.sublist(i, end);
      final merged = await Future.wait(slice.map((p) => _mergePostWithViewerVoteDocs(p, uid)));
      out.addAll(merged);
    }
    return out;
  }

  Future<Post> _mergePostWithViewerVoteDocs(Post post, String uid) async {
    final snaps = await Future.wait([
      _postLikeDoc(post.id, uid).get(),
      _postDislikeDoc(post.id, uid).get(),
    ]);
    final likeSnap = snaps[0];
    final dislikeSnap = snaps[1];
    final likeDoc = likeSnap.exists;
    final dislikeDoc = dislikeSnap.exists;
    var hasLike = likeDoc || post.likedBy.contains(uid);
    var hasDislike = dislikeDoc || post.dislikedBy.contains(uid);
    if (hasLike && hasDislike) {
      if (likeDoc && !dislikeDoc) {
        hasDislike = false;
      } else if (!likeDoc && dislikeDoc) {
        hasLike = false;
      } else if (likeDoc && dislikeDoc) {
        hasDislike = false;
      }
    }
    var lb = post.likedBy.where((u) => u != uid).toList();
    var db = post.dislikedBy.where((u) => u != uid).toList();
    if (hasLike) lb = [...lb, uid];
    if (hasDislike) db = [...db, uid];
    return post.copyWith(likedBy: lb, dislikedBy: db);
  }

  /// Firestore에 넣을 수 있는 타입만 남기기 (직렬화 오류 방지)
  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    final out = <String, dynamic>{};
    for (final e in map.entries) {
      final k = e.key;
      final v = e.value;
      if (v == null) {
        out[k] = null;
      } else if (v is bool || v is String) {
        out[k] = v;
      } else if (v is int || v is double) {
        out[k] = v;
      } else if (v is Timestamp) {
        out[k] = v;
      } else if (v is List) {
        out[k] = v.map((x) => _sanitizeValue(x)).toList();
      } else if (v is Map) {
        out[k] = _sanitizeMap(Map<String, dynamic>.from(v));
      } else {
        // 그 외(DateTime 등)는 제외
        debugPrint('addPost: 필드 "$k" 타입 ${v.runtimeType} 제외');
      }
    }
    return out;
  }

  static dynamic _sanitizeValue(dynamic x) {
    if (x == null) return null;
    if (x is bool || x is String || x is int || x is double || x is Timestamp) return x;
    if (x is List) return x.map((e) => _sanitizeValue(e)).toList();
    if (x is Map) return _sanitizeMap(Map<String, dynamic>.from(x));
    return null;
  }

  /// 글 저장 (백엔드에 저장 후 반환된 문서 id로 Post 반환). 실패 시 (null, 오류메시지).
  Future<(Post?, String?)> addPost(Post post) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) {
      return (null, '로그인이 필요해요.');
    }
    var map = post.toMap();
    map['type'] = (post.type != null && post.type!.trim().isNotEmpty) ? post.type!.trim() : 'talk';
    map['createdAt'] = FieldValue.serverTimestamp();
    if (!map.containsKey('likedBy')) map['likedBy'] = [];
    if (!map.containsKey('dislikedBy')) map['dislikedBy'] = [];
    if (!map.containsKey('likeCount')) map['likeCount'] = 0;
    if (!map.containsKey('dislikeCount')) map['dislikeCount'] = 0;
    map['authorUid'] = uid;
    map = _sanitizeMap(map);
    map['createdAt'] = FieldValue.serverTimestamp();

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final docRef = await _col.add(map);
        final saved = post.copyWith(id: docRef.id, authorUid: uid);
        try {
          await ReviewService.instance.syncDramaReviewFromFeedPost(saved);
        } catch (e, st) {
          debugPrint('syncDramaReviewFromFeedPost: $e\n$st');
        }
        return (saved, null);
      } catch (e, st) {
        debugPrint('addPost 실패 (attempt ${attempt + 1}): $e');
        debugPrint('$st');
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }
        return (null, e.toString());
      }
    }
    return (null, null);
  }

  /// addPost를 최대 10번 재시도 (즉시, 1초, 2초, 4초, 8초, 8초…). 서버 저장 확실히 시도.
  Future<(Post?, String?)> addPostWithRetry(Post post) async {
    const delays = [
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 8),
      Duration(seconds: 8),
      Duration(seconds: 8),
      Duration(seconds: 8),
      Duration(seconds: 8),
    ];
    (Post?, String?) lastResult = (null, null);
    for (var i = 0; i < delays.length; i++) {
      if (i > 0) await Future.delayed(delays[i]);
      lastResult = await addPost(post);
      final (saved, _) = lastResult;
      if (saved != null) return lastResult;
    }
    return lastResult;
  }

  /// 글 수정. 제목·내용·미디어·게시판·리뷰 메타 등 저장 필드 업데이트.
  Future<Post?> updatePost(Post post) async {
    if (post.id.isEmpty) return null;
    try {
      final docRef = _col.doc(post.id);
      final updateData = <String, dynamic>{
        'title': post.title,
        'body': post.body,
        'imageUrls': post.imageUrls,
        'linkUrl': post.linkUrl,
        'hasImage': post.hasImage,
        'hasVideo': post.hasVideo,
        'category': post.category,
        'hasSpoiler': post.hasSpoiler,
        'isLiked': post.isLiked,
        'isFirstWatch': post.isFirstWatch,
        'tags': post.tags,
        'allowReply': post.allowReply,
      };
      if (post.type != null && post.type!.isNotEmpty) updateData['type'] = post.type;
      if (post.dramaId != null && post.dramaId!.isNotEmpty) updateData['dramaId'] = post.dramaId;
      if (post.dramaTitle != null && post.dramaTitle!.isNotEmpty) updateData['dramaTitle'] = post.dramaTitle;
      if (post.dramaThumbnail != null && post.dramaThumbnail!.isNotEmpty) {
        updateData['dramaThumbnail'] = post.dramaThumbnail;
      }
      if (post.rating != null) updateData['rating'] = post.rating;
      if (post.imageDimensions != null) updateData['imageDimensions'] = post.imageDimensions;
      if (post.videoUrl != null) updateData['videoUrl'] = post.videoUrl;
      if (post.videoThumbnailUrl != null) updateData['videoThumbnailUrl'] = post.videoThumbnailUrl;
      if (post.isGif != null) updateData['isGif'] = post.isGif;
      await docRef.update(updateData);
      try {
        await ReviewService.instance.syncDramaReviewFromFeedPost(post);
      } catch (e, st) {
        debugPrint('syncDramaReviewFromFeedPost: $e\n$st');
      }
      return post;
    } catch (e, st) {
      debugPrint('updatePost 실패: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// 글 삭제. 성공 시 true, 실패 시 false.
  Future<bool> deletePost(String postId) async {
    if (postId.isEmpty) return false;
    try {
      await _col.doc(postId).delete();
      return true;
    } catch (e, st) {
      debugPrint('deletePost 실패: $e');
      debugPrint('$st');
      return false;
    }
  }

  /// 게시판 글 전체 삭제 (Firestore posts 컬렉션). 배치 500건씩 삭제. 삭제된 문서 개수 반환.
  Future<int> deleteAllPosts() async {
    try {
      int total = 0;
      while (true) {
        final snapshot = await _col.limit(500).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        total += snapshot.docs.length;
        debugPrint('deleteAllPosts: ${snapshot.docs.length}건 삭제 (누적 $total)');
      }
      debugPrint('deleteAllPosts: 총 $total건 삭제 완료');
      return total;
    } catch (e, st) {
      debugPrint('deleteAllPosts 실패: $e');
      debugPrint('$st');
      return 0;
    }
  }

  /// 댓글에 답글 추가. parentCommentId = 댓글 id. 성공 시 null, 실패 시 에러 메시지 반환.
  Future<String?> addReply(String postId, String parentCommentId, PostComment newReply) async {
    if (postId.isEmpty || parentCommentId.isEmpty) return '글 정보를 찾을 수 없어요.';
    try {
      final docRef = _col.doc(postId);
      final docSnap = await docRef.get();
      if (!docSnap.exists) return '글이 더 이상 없어요.';
      final data = docSnap.data()!;
      data['id'] = docSnap.id;
      final post = Post.fromMap(_normalizePostMap(data));
      final parent = PostService.findCommentById(post.commentsList, parentCommentId);
      if (parent == null) return '댓글을 찾을 수 없어요.';
      final updatedParent = PostComment(
        id: parent.id,
        author: parent.author,
        timeAgo: parent.timeAgo,
        text: parent.text,
        votes: parent.votes,
        replies: [...parent.replies, newReply],
        likedBy: parent.likedBy,
        dislikedBy: parent.dislikedBy,
        authorPhotoUrl: parent.authorPhotoUrl,
        authorAvatarColorIndex: parent.authorAvatarColorIndex,
        createdAtDate: parent.createdAtDate,
        imageUrl: parent.imageUrl,
        authorUid: parent.authorUid,
      );
      final newList = PostService.replaceCommentById(post.commentsList, parentCommentId, updatedParent);
      final newCommentsList = _commentListToMapsWithCreatedAt(newList, addCreatedAtForId: newReply.id);
      await docRef.update({
        'commentsList': newCommentsList,
        'comments': FieldValue.increment(1),
      });
      // 원댓글 작성자에게 대댓글 알림
      final parentAuthorUid = await NotificationService.instance.getUidByNickname(parent.author);
      if (parentAuthorUid != null) {
        await NotificationService.instance.send(
          toUid: parentAuthorUid,
          type: NotificationType.reply,
          fromUser: newReply.author,
          postId: postId,
          postTitle: post.title,
          commentText: newReply.text,
        );
      }
      return null;
    } catch (e, st) {
      debugPrint('addReply 실패: $e');
      debugPrint('$st');
      final msg = e.toString();
      if (msg.contains('PERMISSION_DENIED') || msg.contains('permission-denied')) return '권한이 없어요.';
      return '답글 등록 실패.';
    }
  }

  /// 글에 댓글 추가. 성공 시 null, 실패 시 에러 메시지 반환.
  Future<String?> addComment(String postId, Post post, PostComment newComment) async {
    if (postId.isEmpty) {
      debugPrint('addComment: postId 비어 있음');
      return '글 정보를 찾을 수 없어요.';
    }
    try {
      final docRef = _col.doc(postId);
      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        debugPrint('addComment: 문서 없음 postId=$postId');
        return '글이 더 이상 없어요.';
      }
      final commentMap = newComment.toMap();
      commentMap['createdAt'] = Timestamp.now();
      await docRef.update({
        'commentsList': FieldValue.arrayUnion([commentMap]),
        'comments': FieldValue.increment(1),
      });
      // 글 작성자에게 댓글 알림
      final postData = docSnap.data()!;
      final postAuthorUid = postData['authorUid'] as String?;
      if (postAuthorUid != null) {
        await NotificationService.instance.send(
          toUid: postAuthorUid,
          type: NotificationType.comment,
          fromUser: newComment.author,
          postId: postId,
          postTitle: post.title,
          commentText: newComment.text,
        );
      }
      return null;
    } catch (e, st) {
      debugPrint('addComment 실패: $e');
      debugPrint('$st');
      final msg = e.toString();
      if (msg.contains('PERMISSION_DENIED') || msg.contains('permission-denied')) {
        return '권한이 없어요. (Firebase 규칙 확인)';
      }
      if (msg.contains('NOT_FOUND') || msg.contains('not-found')) {
        return '글이 없어요.';
      }
      return '등록 실패: ${msg.length > 50 ? msg.substring(0, 50) : msg}';
    }
  }

  /// 글 조회수 1 증가 (상세 진입 시 호출). 선행 read 없이 increment만 수행.
  Future<void> incrementPostViews(String postId) async {
    if (postId.isEmpty) return;
    try {
      await _col.doc(postId).update(<String, dynamic>{'views': FieldValue.increment(1)});
    } catch (e, st) {
      debugPrint('incrementPostViews 실패: $e');
      debugPrint('$st');
    }
  }

  /// 글 하나 불러오기 (최신 데이터). createdAt 있으면 timeAgo 계산. [locale]이 있으면 해당 언어로 timeAgo 표시.
  Future<Post?> getPost(String postId, [String? locale]) async {
    if (postId.isEmpty) return null;
    try {
      final doc = await _col.doc(postId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      final createdAt = data['createdAt'];
      if (createdAt is Timestamp) {
        data['timeAgo'] = formatTimeAgo(createdAt.toDate(), locale);
      }
      final post = Post.fromMap(_normalizePostMap(data));
      final hydrated = await hydratePostsViewerVotes([post]);
      return hydrated.isEmpty ? post : hydrated.first;
    } catch (e, st) {
      debugPrint('getPost 실패: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// 같은 유저·같은 드라마의 DramaFeed 리뷰 글(`posts`, type=review) 중 최신 1건.
  /// 로컬 `MyReviewItem`과 문서 id가 다르므로 `dramaId`로 조회해 글 상세 진입에 사용.
  Future<Post?> getLatestMyFeedReviewPostForDrama({
    required String authorUid,
    required String dramaId,
    String? locale,
  }) async {
    final did = dramaId.trim();
    if (authorUid.isEmpty || did.isEmpty) return null;
    try {
      final snap = await _col
          .where('authorUid', isEqualTo: authorUid)
          .where('dramaId', isEqualTo: did)
          .limit(40)
          .get();
      if (snap.docs.isEmpty) return null;
      DocumentSnapshot<Map<String, dynamic>>? best;
      var bestAt = DateTime.fromMillisecondsSinceEpoch(0);
      for (final doc in snap.docs) {
        final data = doc.data();
        final type = (data['type'] as String?)?.trim().toLowerCase();
        if (type != 'review') continue;
        final createdAt = data['createdAt'];
        final at = createdAt is Timestamp
            ? createdAt.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        if (at.isAfter(bestAt)) {
          bestAt = at;
          best = doc;
        }
      }
      if (best == null) return null;
      return getPost(best.id, locale);
    } catch (e, st) {
      debugPrint('getLatestMyFeedReviewPostForDrama: $e\n$st');
      return null;
    }
  }

  /// 드라마 상세 리뷰 탭에서 저장한 내용을 DramaFeed 리뷰 게시판(`posts`, type=review)과 동기화.
  /// [existingFeedPostId]가 있으면 해당 글만 수정.
  /// [forceNewPost]가 true이면 같은 작품에 리뷰 글이 있어도 항상 새 글을 추가 (작품당 여러 리뷰).
  /// 반환: [createdNewPost]는 새 `posts` 문서가 추가된 경우 true(레벨 점수 등), [postId]는 저장된 글 id.
  Future<({bool createdNewPost, String? postId})> syncReviewFeedPostFromDramaDetail({
    required String dramaId,
    required String dramaTitle,
    required double rating,
    required String comment,
    required String reviewsTabLabel,
    required String timeSoonLabel,
    String? existingFeedPostId,
    bool forceNewPost = false,
  }) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return (createdNewPost: false, postId: null);
    final did = dramaId.trim();
    if (did.isEmpty) return (createdNewPost: false, postId: null);
    try {
      await DramaListService.instance.loadFromAsset();
      await UserProfileService.instance.loadIfNeeded();
      await LevelService.instance.loadIfNeeded();
      final author = await UserProfileService.instance.getAuthorForPost();
      final rawCountry = UserProfileService.instance.signupCountryNotifier.value?.trim().toLowerCase();
      final countryOr = (rawCountry != null && rawCountry.isNotEmpty) ? rawCountry : 'us';
      final titleText = dramaTitle.trim().isNotEmpty
          ? dramaTitle.trim()
          : DramaListService.instance.getDisplayTitle(did, countryOr);
      final thumb = DramaListService.instance.getDisplayImageUrl(did, countryOr) ?? '';

      Post? mergeTarget;
      final byId = existingFeedPostId?.trim();
      if (byId != null && byId.isNotEmpty) {
        mergeTarget = await getPost(byId, countryOr);
      }
      if (mergeTarget == null && !forceNewPost) {
        mergeTarget = await getLatestMyFeedReviewPostForDrama(
          authorUid: uid,
          dramaId: did,
          locale: countryOr,
        );
      }
      if (mergeTarget != null) {
        final merged = mergeTarget.copyWith(
          title: titleText.isNotEmpty ? titleText : mergeTarget.title,
          body: comment,
          rating: rating,
          dramaId: did,
          dramaTitle: titleText.isNotEmpty ? titleText : mergeTarget.dramaTitle,
          dramaThumbnail: thumb.isNotEmpty ? thumb : mergeTarget.dramaThumbnail,
          type: 'review',
        );
        await updatePost(merged);
        return (createdNewPost: false, postId: mergeTarget.id);
      }

      final tempId = DateTime.now().millisecondsSinceEpoch.toString();
      final post = Post(
        id: tempId,
        title: titleText.isNotEmpty ? titleText : did,
        subreddit: reviewsTabLabel,
        author: author,
        timeAgo: timeSoonLabel,
        votes: 0,
        comments: 0,
        body: comment,
        authorLevel: LevelService.instance.currentLevel.clamp(1, 30),
        category: 'free',
        type: 'review',
        dramaId: did,
        dramaTitle: titleText.isNotEmpty ? titleText : null,
        dramaThumbnail: thumb.isNotEmpty ? thumb : null,
        rating: rating,
        hasSpoiler: false,
        isLiked: false,
        isFirstWatch: true,
        tags: const [],
        allowReply: true,
        authorPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
        authorAvatarColorIndex: UserProfileService.instance.avatarColorNotifier.value,
        country: countryOr,
      );
      final (saved, _) = await addPostWithRetry(post);
      return (createdNewPost: saved != null, postId: saved?.id);
    } catch (e, st) {
      debugPrint('syncReviewFeedPostFromDramaDetail: $e\n$st');
      return (createdNewPost: false, postId: null);
    }
  }

  /// 글 좋아요 토글 (posts/{id}/likes/{uid} 서브컬렉션 + likeCount, 트랜잭션).
  /// [currentVoteState]는 호환용(무시). 성공 시 true=좋아요 적용됨, false=좋아요 취소, 실패 시 null.
  Future<bool?> togglePostLike(
    String postId, {
    int? currentVoteState,
    String? postAuthorUid,
    String? postTitle,
  }) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null || postId.isEmpty) return null;
    bool? nowLiked;
    String? notifyUid = postAuthorUid;
    String? notifyTitle = postTitle;
    try {
      await _firestore.runTransaction((transaction) async {
        final postRef = _col.doc(postId);
        final likeRef = _postLikeDoc(postId, uid);
        final dislikeRef = _postDislikeDoc(postId, uid);
        final postSnap = await transaction.get(postRef);
        if (!postSnap.exists) {
          nowLiked = null;
          return;
        }
        final likeSnap = await transaction.get(likeRef);
        final dislikeSnap = await transaction.get(dislikeRef);
        final data = postSnap.data()!;
        notifyUid ??= data['authorUid'] as String?;
        notifyTitle ??= (data['title'] as String?) ?? '';
        final likedBy = List<String>.from((data['likedBy'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
        final dislikedBy = List<String>.from((data['dislikedBy'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
        var inLikes = likeSnap.exists || likedBy.contains(uid);
        var inDislikes = dislikeSnap.exists || dislikedBy.contains(uid);
        if (inLikes && inDislikes) {
          if (likeSnap.exists && !dislikeSnap.exists) {
            inDislikes = false;
          } else if (!likeSnap.exists && dislikeSnap.exists) {
            inLikes = false;
          } else if (likeSnap.exists && dislikeSnap.exists) {
            inDislikes = false;
          }
        }

        if (inLikes) {
          if (likeSnap.exists) transaction.delete(likeRef);
          transaction.update(postRef, <String, dynamic>{
            'likedBy': FieldValue.arrayRemove([uid]),
            'likeCount': FieldValue.increment(-1),
            'votes': FieldValue.increment(-1),
          });
          nowLiked = false;
        } else {
          transaction.set(likeRef, <String, dynamic>{
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          final updates = <String, dynamic>{
            'likedBy': FieldValue.arrayUnion([uid]),
            'likeCount': FieldValue.increment(1),
            'votes': FieldValue.increment(inDislikes ? 2 : 1),
          };
          if (inDislikes) {
            if (dislikeSnap.exists) transaction.delete(dislikeRef);
            updates['dislikedBy'] = FieldValue.arrayRemove([uid]);
            updates['dislikeCount'] = FieldValue.increment(-1);
          }
          transaction.update(postRef, updates);
          nowLiked = true;
        }
      });
      final notifyTargetUid = notifyUid;
      if (nowLiked == true && notifyTargetUid != null && notifyTargetUid.isNotEmpty) {
        final myNickname = 'u/${UserProfileService.instance.nicknameNotifier.value ?? uid}';
        unawaited(
          NotificationService.instance
              .send(
                toUid: notifyTargetUid,
                type: NotificationType.postLike,
                fromUser: myNickname,
                postId: postId,
                postTitle: notifyTitle ?? '',
              )
              .catchError((Object e, StackTrace st) {
                debugPrint('postLike notify: $e\n$st');
              }),
        );
      }
      return nowLiked;
    } catch (e, st) {
      debugPrint('togglePostLike 실패: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// 글 싫어요 토글 (posts/{id}/dislikes/{uid} + dislikeCount, 트랜잭션).
  /// 성공 시 true=싫어요 적용, false=싫어요 취소, 실패 시 null.
  Future<bool?> togglePostDislike(String postId) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null || postId.isEmpty) return null;
    bool? nowDisliked;
    try {
      await _firestore.runTransaction((transaction) async {
        final postRef = _col.doc(postId);
        final likeRef = _postLikeDoc(postId, uid);
        final dislikeRef = _postDislikeDoc(postId, uid);
        final postSnap = await transaction.get(postRef);
        if (!postSnap.exists) {
          nowDisliked = null;
          return;
        }
        final likeSnap = await transaction.get(likeRef);
        final dislikeSnap = await transaction.get(dislikeRef);
        final data = postSnap.data()!;
        final likedBy = List<String>.from((data['likedBy'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
        final dislikedBy = List<String>.from((data['dislikedBy'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
        var inLikes = likeSnap.exists || likedBy.contains(uid);
        var inDislikes = dislikeSnap.exists || dislikedBy.contains(uid);
        if (inLikes && inDislikes) {
          if (likeSnap.exists && !dislikeSnap.exists) {
            inDislikes = false;
          } else if (!likeSnap.exists && dislikeSnap.exists) {
            inLikes = false;
          } else if (likeSnap.exists && dislikeSnap.exists) {
            inDislikes = false;
          }
        }

        if (inDislikes) {
          if (dislikeSnap.exists) transaction.delete(dislikeRef);
          transaction.update(postRef, <String, dynamic>{
            'dislikedBy': FieldValue.arrayRemove([uid]),
            'dislikeCount': FieldValue.increment(-1),
            'votes': FieldValue.increment(1),
          });
          nowDisliked = false;
        } else {
          transaction.set(dislikeRef, <String, dynamic>{
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          final updates = <String, dynamic>{
            'dislikedBy': FieldValue.arrayUnion([uid]),
            'dislikeCount': FieldValue.increment(1),
            'votes': FieldValue.increment(inLikes ? -2 : -1),
          };
          if (inLikes) {
            if (likeSnap.exists) transaction.delete(likeRef);
            updates['likedBy'] = FieldValue.arrayRemove([uid]);
            updates['likeCount'] = FieldValue.increment(-1);
          }
          transaction.update(postRef, updates);
          nowDisliked = true;
        }
      });
      return nowDisliked;
    } catch (e, st) {
      debugPrint('togglePostDislike 실패: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// 댓글/대댓글 좋아요 토글. 성공 시 갱신된 Post 반환, 실패 시 null.
  Future<Post?> toggleCommentLike(String postId, String commentId) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null || postId.isEmpty || commentId.isEmpty) return null;
    try {
      final docRef = _col.doc(postId);
      final docSnap = await docRef.get();
      if (!docSnap.exists) return null;
      final data = docSnap.data()!;
      data['id'] = docSnap.id;
      final post = Post.fromMap(_normalizePostMap(Map<String, dynamic>.from(data)));
      final list = post.commentsList;
      final found = findCommentById(list, commentId);
      if (found == null) return null;
      final newLiked = !found.likedBy.contains(uid);
      final newLikedBy = List<String>.from(found.likedBy);
      final newDislikedBy = List<String>.from(found.dislikedBy);
      int voteDelta = 0;
      if (newLiked) {
        if (!newLikedBy.contains(uid)) newLikedBy.add(uid);
        voteDelta += 1;
        if (newDislikedBy.remove(uid)) voteDelta += 1;
      } else {
        newLikedBy.remove(uid);
        voteDelta -= 1;
      }
      final newComment = PostComment(
        id: found.id,
        author: found.author,
        timeAgo: found.timeAgo,
        text: found.text,
        votes: found.votes + voteDelta,
        replies: found.replies,
        likedBy: newLikedBy,
        dislikedBy: newDislikedBy,
        authorPhotoUrl: found.authorPhotoUrl,
        authorAvatarColorIndex: found.authorAvatarColorIndex,
        createdAtDate: found.createdAtDate,
        imageUrl: found.imageUrl,
        authorUid: found.authorUid,
      );
      final newList = replaceCommentById(list, commentId, newComment);
      final newCommentsList = newList.map((c) => c.toMap()).toList();
      await docRef.update({'commentsList': newCommentsList});
      // 댓글 작성자에게 좋아요 알림
      if (newLiked) {
        final commentAuthorUid = await NotificationService.instance.getUidByNickname(found.author);
        if (commentAuthorUid != null) {
          final myNickname = 'u/${UserProfileService.instance.nicknameNotifier.value ?? uid}';
          await NotificationService.instance.send(
            toUid: commentAuthorUid,
            type: NotificationType.commentLike,
            fromUser: myNickname,
            postId: postId,
            postTitle: post.title,
            commentText: found.text,
          );
        }
      }
      return post.copyWith(commentsList: newList);
    } catch (e, st) {
      debugPrint('toggleCommentLike 실패: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// 댓글/대댓글 싫어요 토글. 성공 시 갱신된 Post 반환, 실패 시 null.
  Future<Post?> toggleCommentDislike(String postId, String commentId) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null || postId.isEmpty || commentId.isEmpty) return null;
    try {
      final docRef = _col.doc(postId);
      final docSnap = await docRef.get();
      if (!docSnap.exists) return null;
      final data = docSnap.data()!;
      data['id'] = docSnap.id;
      final post = Post.fromMap(_normalizePostMap(Map<String, dynamic>.from(data)));
      final list = post.commentsList;
      final found = findCommentById(list, commentId);
      if (found == null) return null;
      final newDisliked = !found.dislikedBy.contains(uid);
      final newDislikedBy = List<String>.from(found.dislikedBy);
      final newLikedBy = List<String>.from(found.likedBy);
      int voteDelta = 0;
      if (newDisliked) {
        if (!newDislikedBy.contains(uid)) newDislikedBy.add(uid);
        voteDelta -= 1;
        if (newLikedBy.remove(uid)) voteDelta -= 1;
      } else {
        newDislikedBy.remove(uid);
        voteDelta += 1;
      }
      final newComment = PostComment(
        id: found.id,
        author: found.author,
        timeAgo: found.timeAgo,
        text: found.text,
        votes: found.votes + voteDelta,
        replies: found.replies,
        likedBy: newLikedBy,
        dislikedBy: newDislikedBy,
        authorPhotoUrl: found.authorPhotoUrl,
        authorAvatarColorIndex: found.authorAvatarColorIndex,
        createdAtDate: found.createdAtDate,
        imageUrl: found.imageUrl,
        authorUid: found.authorUid,
      );
      final newList = replaceCommentById(list, commentId, newComment);
      final newCommentsList = newList.map((c) => c.toMap()).toList();
      await docRef.update({'commentsList': newCommentsList});
      return post.copyWith(commentsList: newList);
    } catch (e, st) {
      debugPrint('toggleCommentDislike 실패: $e');
      debugPrint('$st');
      return null;
    }
  }

  static PostComment? findCommentById(List<PostComment> list, String id) {
    for (final c in list) {
      if (c.id == id) return c;
      final inReplies = findCommentById(c.replies, id);
      if (inReplies != null) return inReplies;
    }
    return null;
  }

  static List<PostComment> replaceCommentById(List<PostComment> list, String id, PostComment replacement) {
    return list.map((c) {
      if (c.id == id) return replacement;
      return PostComment(
        id: c.id,
        author: c.author,
        timeAgo: c.timeAgo,
        text: c.text,
        votes: c.votes,
        replies: replaceCommentById(c.replies, id, replacement),
        likedBy: c.likedBy,
        dislikedBy: c.dislikedBy,
        authorPhotoUrl: c.authorPhotoUrl,
        authorAvatarColorIndex: c.authorAvatarColorIndex,
        createdAtDate: c.createdAtDate,
        imageUrl: c.imageUrl,
        authorUid: c.authorUid,
      );
    }).toList();
  }

  /// 댓글 목록을 Map 리스트로 변환. 지정한 id의 댓글에 createdAt(serverTimestamp) 추가.
  static List<Map<String, dynamic>> _commentListToMapsWithCreatedAt(
    List<PostComment> list, {
    String? addCreatedAtForId,
  }) {
    return list.map((c) {
      final m = Map<String, dynamic>.from(c.toMap());
      m['replies'] = _commentListToMapsWithCreatedAt(c.replies, addCreatedAtForId: addCreatedAtForId);
      if (c.id == addCreatedAtForId) m['createdAt'] = Timestamp.now();
      return m;
    }).toList();
  }

  /// 특정 작성자의 글만 조회 (닉네임/작성자명 기준)
  Future<List<Post>> getPostsByAuthor(String author) async {
    final all = await getPostsAllPages();
    return all.where((p) => p.author == author).toList();
  }

  /// 프로필 Posts 탭: 톡·에스크 게시글만.
  Future<List<Post>> getCommunityBoardPostsByAuthor(String author) async {
    final all = await getPostsByAuthor(author);
    return all.where(postIsCommunityTalkOrAsk).toList();
  }

  /// 프로필 Posts 댓글 탭: 톡·에스크 글에 단 댓글만.
  Future<List<({Post post, PostComment comment})>>
      getCommunityBoardCommentsByAuthor(String authorNickname) async {
    final all = await getCommentsByAuthor(authorNickname);
    return all.where((e) => postIsCommunityTalkOrAsk(e.post)).toList();
  }

  /// 프로필 리뷰 탭: 리뷰 게시판(본문 있는 피드 리뷰) 글만.
  Future<List<Post>> getReviewBoardPostsByAuthor(String author) async {
    final all = await getPostsByAuthor(author);
    return all.where((p) => postMatchesFeedFilter(p, 'review')).toList();
  }

  /// 프로필 리뷰 댓글 탭: 리뷰 게시판 글에 단 댓글만.
  Future<List<({Post post, PostComment comment})>>
      getReviewBoardCommentsByAuthor(String authorNickname) async {
    final all = await getCommentsByAuthor(authorNickname);
    return all.where((e) => postMatchesFeedFilter(e.post, 'review')).toList();
  }

  /// 특정 작성자의 모든 게시글 authorPhotoUrl을 일괄 업데이트
  Future<void> updateAuthorPhotoUrl(String author, String? photoUrl) async {
    try {
      final snapshot = await _col
          .where('author', isEqualTo: author)
          .get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'authorPhotoUrl': photoUrl});
      }
      await batch.commit();
      debugPrint('updateAuthorPhotoUrl: ${snapshot.docs.length}개 게시글 업데이트 완료');
    } catch (e) {
      debugPrint('updateAuthorPhotoUrl 실패: $e');
    }
  }

  /// 프로필 별점 분포: `posts`(type=review, authorUid) + `drama_reviews`(uid). dramaId 기준 중복 제거.
  Future<ProfileRatingHistogram> aggregateReviewRatingsForUid(String uid) async {
    if (uid.isEmpty) return ProfileRatingHistogram.empty();

    final dramaIdToRating = <String, double>{};

    try {
      final postSnap = await _col.where('authorUid', isEqualTo: uid).get();
      for (final doc in postSnap.docs) {
        final data = doc.data();
        final type = (data['type'] as String?)?.toLowerCase();
        if (type != 'review') continue;
        final r = (data['rating'] as num?)?.toDouble();
        if (r == null || r <= 0) continue;
        final dramaId = (data['dramaId'] as String?)?.trim() ?? '';
        final key = dramaId.isNotEmpty ? dramaId : 'post_${doc.id}';
        dramaIdToRating[key] = r;
      }
    } catch (e, st) {
      debugPrint('aggregateReviewRatingsForUid posts: $e\n$st');
    }

    try {
      final drSnap = await _firestore.collection('drama_reviews').where('uid', isEqualTo: uid).get();
      for (final doc in drSnap.docs) {
        final data = doc.data();
        final dramaId = (data['dramaId'] as String?)?.trim() ?? '';
        if (dramaId.isEmpty) continue;
        if (dramaIdToRating.containsKey(dramaId)) continue;
        final r = (data['rating'] as num?)?.toDouble() ?? 0;
        if (r > 0) dramaIdToRating[dramaId] = r;
      }
    } catch (e, st) {
      debugPrint('aggregateReviewRatingsForUid drama_reviews: $e\n$st');
    }

    return ProfileRatingHistogram.fromRatings(dramaIdToRating.values.toList());
  }

  /// 특정 작성자가 쓴 댓글 목록 (글 정보 포함). 댓글·답글 모두 포함.
  Future<List<({Post post, PostComment comment})>> getCommentsByAuthor(String author) async {
    final posts = await getPostsAllPages();
    final result = <({Post post, PostComment comment})>[];
    for (final post in posts) {
      void collect(List<PostComment> list) {
        for (final c in list) {
          if (c.author == author) result.add((post: post, comment: c));
          collect(c.replies);
        }
      }
      collect(post.commentsList);
    }
    return result;
  }

  /// Firestore 페이지 단위 로드 (createdAt 내림차순).
  /// [type]이 있으면 클라이언트에서 [postMatchesFeedFilter] 적용 (기존과 동일).
  /// [country]가 null이거나 빈 문자열이면 국가 필터를 적용하지 않음.
  /// 값이 있으면 클라이언트에서 [Post.documentVisibleInCountryFeed]로 필터.
  /// 문서에 `country`가 없거나 비면 레거시로 간주해 해당 필터에서는 통과.
  /// createdAt 없는 문서는 이 쿼리에서 제외됨.
  Future<({List<Post> posts, DocumentSnapshot<Map<String, dynamic>>? lastDocument, bool hasMore})> getPosts({
    String? country,
    String? type,
    DocumentSnapshot<Map<String, dynamic>>? lastDocument,
    int limit = 20,
  }) async {
    try {
      final countryEq = country?.trim();
      // 국가는 클라이언트 필터만 사용. 서버 where(country)는 필드 없는 문서를 완전히 누락시킴.
      final Query<Map<String, dynamic>> q =
          _col.orderBy('createdAt', descending: true).limit(limit);
      final snapshot = await (lastDocument != null ? q.startAfterDocument(lastDocument) : q).get();
      debugPrint('getPosts: page ${snapshot.docs.length} docs (limit $limit)');
      final board = type?.trim().toLowerCase();
      final out = <Post>[];
      DocumentSnapshot<Map<String, dynamic>>? pageLast;
      for (final doc in snapshot.docs) {
        pageLast = doc;
        try {
          final data = doc.data();
          if (countryEq != null &&
              countryEq.isNotEmpty &&
              !Post.documentVisibleInCountryFeed(data, countryEq)) {
            continue;
          }
          data['id'] = doc.id;
          final createdAt = data['createdAt'];
          final sortAt = createdAt is Timestamp
              ? createdAt.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final normalized = _normalizePostMap(data);
          normalized['timeAgo'] = formatTimeAgo(sortAt, country);
          final post = Post.fromMap(normalized);
          if (board != null && board.isNotEmpty) {
            if (!postMatchesFeedFilter(post, board)) continue;
          }
          out.add(post);
        } catch (e, st) {
          debugPrint('getPosts: 문서 ${doc.id} 파싱 실패 - $e');
          debugPrint('$st');
        }
      }
      final hasMore = snapshot.docs.length >= limit;
      final hydrated = await hydratePostsViewerVotes(out);
      return (posts: hydrated, lastDocument: pageLast, hasMore: hasMore);
    } catch (e, st) {
      debugPrint('getPosts 실패: $e');
      debugPrint('$st');
      return (posts: <Post>[], lastDocument: null, hasMore: false);
    }
  }

  /// [getPosts]를 cursor로 이어 붙여 전체 목록 (검색·레거시 호환).
  Future<List<Post>> getPostsAllPages({String? country, String? type, int pageSize = 100}) async {
    final acc = <Post>[];
    final seen = <String>{};
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      final r = await getPosts(country: country, type: type, lastDocument: last, limit: pageSize);
      for (final p in r.posts) {
        if (seen.add(p.id)) acc.add(p);
      }
      if (!r.hasMore || r.lastDocument == null) break;
      last = r.lastDocument;
    }
    return acc;
  }

  static const int _likedPostsQueryLimit = 200;

  static Post _postWithLocaleTimeAgo(Post p, String? countryForTimeAgo) {
    final at = p.createdAt;
    if (at == null) return p;
    final ta = (countryForTimeAgo != null && countryForTimeAgo.trim().isNotEmpty)
        ? formatTimeAgo(at, countryForTimeAgo)
        : formatTimeAgo(at);
    return p.copyWith(timeAgo: ta);
  }

  static PostComment _commentWithLocaleTimeAgo(
    PostComment c,
    String? countryForTimeAgo,
  ) {
    final at = c.createdAtDate;
    if (at == null) return c;
    final ta = (countryForTimeAgo != null && countryForTimeAgo.trim().isNotEmpty)
        ? formatTimeAgo(at, countryForTimeAgo)
        : formatTimeAgo(at);
    return PostComment(
      id: c.id,
      author: c.author,
      timeAgo: ta,
      text: c.text,
      votes: c.votes,
      replies: c.replies,
      likedBy: c.likedBy,
      dislikedBy: c.dislikedBy,
      authorPhotoUrl: c.authorPhotoUrl,
      authorAvatarColorIndex: c.authorAvatarColorIndex,
      createdAtDate: c.createdAtDate,
      imageUrl: c.imageUrl,
      authorUid: c.authorUid,
    );
  }

  /// [commentsList] 안에서 [likedBy]에 [uid]가 포함된 댓글·답글(글 정보 포함).
  /// 전체 `posts` 문서를 읽어 클라이언트에서 수집합니다([getPostsAllPages]).
  Future<List<({Post post, PostComment comment})>> getCommentsLikedByUid(
    String uid, {
    String? countryForTimeAgo,
  }) async {
    if (uid.isEmpty) return [];
    try {
      final posts = await getPostsAllPages();
      final out = <({Post post, PostComment comment, DateTime sortAt})>[];
      void collect(Post post, List<PostComment> list) {
        for (final c in list) {
          if (c.likedBy.contains(uid)) {
            final sortAt =
                c.createdAtDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            final cc = _commentWithLocaleTimeAgo(c, countryForTimeAgo);
            out.add((
              post: _postWithLocaleTimeAgo(post, countryForTimeAgo),
              comment: cc,
              sortAt: sortAt,
            ));
          }
          collect(post, c.replies);
        }
      }
      for (final p in posts) {
        collect(p, p.commentsList);
      }
      out.sort((a, b) => b.sortAt.compareTo(a.sortAt));
      return out.map((e) => (post: e.post, comment: e.comment)).toList();
    } catch (e, st) {
      debugPrint('getCommentsLikedByUid: $e\n$st');
      return [];
    }
  }

  /// [likedBy]에 [uid]가 포함된 게시글. `array-contains`만 사용 후 클라이언트에서 `createdAt` 내림차순 정렬.
  /// 국가 피드 가리기는 적용하지 않음(내가 누른 좋아요는 모두 표시).
  Future<List<Post>> getPostsLikedByUid(
    String uid, {
    String? countryForTimeAgo,
    int limit = _likedPostsQueryLimit,
  }) async {
    if (uid.isEmpty) return [];
    try {
      final snap = await _col.where('likedBy', arrayContains: uid).limit(limit).get();
      final out = <({Post post, DateTime sortAt})>[];
      for (final doc in snap.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          final createdAt = data['createdAt'];
          final sortAt = createdAt is Timestamp
              ? createdAt.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final normalized = _normalizePostMap(data);
          normalized['timeAgo'] = formatTimeAgo(sortAt, countryForTimeAgo);
          final post = Post.fromMap(normalized);
          out.add((post: post, sortAt: sortAt));
        } catch (e, st) {
          debugPrint('getPostsLikedByUid parse fail ${doc.id}: $e\n$st');
        }
      }
      out.sort((a, b) => b.sortAt.compareTo(a.sortAt));
      final posts = out.map((e) => e.post).toList();
      return await hydratePostsViewerVotes(posts);
    } catch (e, st) {
      debugPrint('getPostsLikedByUid: $e\n$st');
      return [];
    }
  }

  /// 댓글 createdAt 마이그레이션: id(밀리초)로 createdAt 없는 댓글을 복원
  Future<int> migrateCommentCreatedAt() async {
    int fixed = 0;
    try {
      final snapshot = await _col.get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final commentsRaw = data['commentsList'];
        if (commentsRaw is! List) continue;
        bool changed = false;
        final newList = commentsRaw.map((e) {
          if (e is! Map) return e;
          final m = Map<String, dynamic>.from(e);
          return _fixCommentCreatedAt(m, changed: (v) => changed = v || changed);
        }).toList();
        if (changed) {
          await _col.doc(doc.id).update({'commentsList': newList});
          fixed++;
        }
      }
    } catch (e) {
      debugPrint('migrateCommentCreatedAt 실패: $e');
    }
    return fixed;
  }

  static Map<String, dynamic> _fixCommentCreatedAt(
    Map<String, dynamic> m, {
    required void Function(bool) changed,
  }) {
    if (m['createdAt'] == null) {
      final idMs = int.tryParse(m['id']?.toString() ?? '');
      if (idMs != null) {
        m['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(idMs);
        changed(true);
      }
    }
    final repliesRaw = m['replies'];
    if (repliesRaw is List && repliesRaw.isNotEmpty) {
      m['replies'] = repliesRaw.map((r) {
        if (r is! Map) return r;
        return _fixCommentCreatedAt(Map<String, dynamic>.from(r), changed: changed);
      }).toList();
    }
    return m;
  }

  /// Firestore가 Map으로 내려준 배열 필드를 List로 변환 (호환)
  static Map<String, dynamic> _normalizePostMap(Map<String, dynamic> map) {
    final m = Map<String, dynamic>.from(map);
    if (m['commentsList'] != null && m['commentsList'] is! List) {
      final raw = m['commentsList'] as Map;
      final keys = raw.keys.toList();
      keys.sort((a, b) => (int.tryParse(a.toString()) ?? 0).compareTo(int.tryParse(b.toString()) ?? 0));
      m['commentsList'] = keys.map((k) => raw[k]).toList();
    }
    if (m['likedBy'] != null && m['likedBy'] is! List) {
      final raw = m['likedBy'] as Map;
      m['likedBy'] = raw.values.map((e) => e.toString()).toList();
    }
    if (m['dislikedBy'] != null && m['dislikedBy'] is! List) {
      final raw = m['dislikedBy'] as Map;
      m['dislikedBy'] = raw.values.map((e) => e.toString()).toList();
    }
    return m;
  }
}
