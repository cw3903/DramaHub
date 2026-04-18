/// 프로필 `users/{uid}.favorites` 배열 항목.
class ProfileFavorite {
  const ProfileFavorite({
    required this.dramaId,
    required this.dramaTitle,
    this.dramaThumbnail,
    this.appLocale,
  });

  final String dramaId;
  final String dramaTitle;
  final String? dramaThumbnail;

  /// 저장 시 앱 언어(us/kr/jp/cn). Firestore `country`와 동일.
  final String? appLocale;

  /// [appLocale]과 동일 — 피드·리뷰와 맞춤.
  String? get country => appLocale;

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'dramaId': dramaId,
      'dramaTitle': dramaTitle,
    };
    final t = dramaThumbnail?.trim();
    if (t != null && t.isNotEmpty) m['dramaThumbnail'] = t;
    final c = appLocale?.trim();
    if (c != null && c.isNotEmpty) m['country'] = c;
    return m;
  }

  static ProfileFavorite? fromDynamic(dynamic e) {
    if (e is! Map) return null;
    final m = Map<String, dynamic>.from(e);
    final id = m['dramaId']?.toString();
    if (id == null || id.isEmpty) return null;
    final loc = (m['country'] as String?)?.trim();
    return ProfileFavorite(
      dramaId: id,
      dramaTitle: m['dramaTitle']?.toString() ?? '',
      dramaThumbnail: m['dramaThumbnail']?.toString(),
      appLocale: loc != null && loc.isNotEmpty ? loc : null,
    );
  }
}
