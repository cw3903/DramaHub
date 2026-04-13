/// 프로필 `users/{uid}.favorites` 배열 항목 (최대 4개).
class ProfileFavorite {
  const ProfileFavorite({
    required this.dramaId,
    required this.dramaTitle,
    this.dramaThumbnail,
  });

  final String dramaId;
  final String dramaTitle;
  final String? dramaThumbnail;

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'dramaId': dramaId,
      'dramaTitle': dramaTitle,
    };
    final t = dramaThumbnail?.trim();
    if (t != null && t.isNotEmpty) m['dramaThumbnail'] = t;
    return m;
  }

  static ProfileFavorite? fromDynamic(dynamic e) {
    if (e is! Map) return null;
    final m = Map<String, dynamic>.from(e);
    final id = m['dramaId']?.toString();
    if (id == null || id.isEmpty) return null;
    return ProfileFavorite(
      dramaId: id,
      dramaTitle: m['dramaTitle']?.toString() ?? '',
      dramaThumbnail: m['dramaThumbnail']?.toString(),
    );
  }
}
