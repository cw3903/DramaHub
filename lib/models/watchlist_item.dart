import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/watchlist/{dramaId}` 문서 모델.
class WatchlistItem {
  const WatchlistItem({
    required this.dramaId,
    required this.addedAt,
    this.titleSnapshot,
    this.imageUrlSnapshot,
  });

  final String dramaId;
  final DateTime addedAt;
  final String? titleSnapshot;
  final String? imageUrlSnapshot;

  static WatchlistItem fromDoc(String docId, Map<String, dynamic> data) {
    final id = (data['dramaId'] as String?)?.trim().isNotEmpty == true ? data['dramaId'] as String : docId;
    final ts = data['addedAt'];
    DateTime added;
    if (ts is Timestamp) {
      added = ts.toDate();
    } else if (ts is int) {
      added = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      added = DateTime.fromMillisecondsSinceEpoch((ts as num?)?.toInt() ?? 0);
    }
    return WatchlistItem(
      dramaId: id,
      addedAt: added,
      titleSnapshot: data['title'] as String?,
      imageUrlSnapshot: data['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'dramaId': dramaId,
      'addedAt': FieldValue.serverTimestamp(),
      if (titleSnapshot != null && titleSnapshot!.trim().isNotEmpty) 'title': titleSnapshot!.trim(),
      if (imageUrlSnapshot != null && imageUrlSnapshot!.trim().isNotEmpty) 'imageUrl': imageUrlSnapshot!.trim(),
    };
  }
}
