import 'package:cloud_firestore/cloud_firestore.dart';

class CustomDramaList {
  const CustomDramaList({
    required this.id,
    required this.title,
    required this.description,
    required this.dramaIds,
    required this.createdAt,
    required this.updatedAt,
    this.coverDramaId,
    this.coverImageUrl,
    this.likeCount = 0,
    this.likedBy = const [],
    this.appLocale,
  });

  final String id;
  final String title;
  final String description;
  final List<String> dramaIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 리스트 상단 히어로에 쓸 드라마 id. null이면 히어로 없음(첫 편 자동 사용 안 함).
  final String? coverDramaId;

  /// 갤러리 등에서 올린 커스텀 표지 URL. 있으면 [coverDramaId]보다 우선.
  final String? coverImageUrl;

  /// 좋아요 수(문서 `likeCount`, 없으면 likedBy 길이로 보정).
  final int likeCount;
  final List<String> likedBy;

  /// 저장 시 앱 언어(us/kr/jp/cn). null이면 레거시.
  final String? appLocale;

  static CustomDramaList fromDoc(String docId, Map<String, dynamic> data) {
    DateTime parseTs(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final rawIds = data['dramaIds'];
    final ids = rawIds is List
        ? rawIds.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    final rawImg = (data['coverImageUrl'] as String?)?.trim();
    final coverImageUrl =
        rawImg != null && rawImg.isNotEmpty && _isHttpUrl(rawImg)
            ? rawImg
            : null;
    final rawCover = (data['coverDramaId'] as String?)?.trim();
    final cover =
        rawCover != null && rawCover.isNotEmpty && ids.contains(rawCover)
            ? rawCover
            : null;
    final likedBy = (data['likedBy'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    var likeCount = (data['likeCount'] as num?)?.toInt() ?? 0;
    if (likeCount < likedBy.length) likeCount = likedBy.length;
    final loc = (data['country'] as String?)?.trim();
    return CustomDramaList(
      id: docId,
      title: (data['title'] as String? ?? '').trim(),
      description: (data['description'] as String? ?? '').trim(),
      dramaIds: ids,
      createdAt: parseTs(data['createdAt']),
      updatedAt: parseTs(data['updatedAt']),
      coverDramaId: cover,
      coverImageUrl: coverImageUrl,
      likeCount: likeCount,
      likedBy: likedBy,
      appLocale: loc != null && loc.isNotEmpty ? loc : null,
    );
  }

  static bool _isHttpUrl(String s) =>
      s.startsWith('https://') || s.startsWith('http://');
}
