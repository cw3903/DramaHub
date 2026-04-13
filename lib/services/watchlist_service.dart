import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/drama.dart';
import '../models/watchlist_item.dart';
import 'auth_service.dart';
import 'drama_list_service.dart';

/// Letterboxd 스타일 보고 싶은 드라마 — `users/{uid}/watchlist/{dramaId}`.
class WatchlistService {
  WatchlistService._();
  static final WatchlistService instance = WatchlistService._();

  final ValueNotifier<List<WatchlistItem>> itemsNotifier = ValueNotifier<List<WatchlistItem>>([]);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _loaded = false;
  String? _lastUid;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  CollectionReference<Map<String, dynamic>> get _watchlistCol {
    final uid = _uid;
    if (uid == null) return _firestore.collection('_').doc('_').collection('_');
    return _firestore.collection('users').doc(uid).collection('watchlist');
  }

  bool isInWatchlist(String dramaId) =>
      itemsNotifier.value.any((e) => e.dramaId == dramaId);

  Future<void> loadIfNeeded({bool force = false}) async {
    final uid = _uid;
    if (uid != _lastUid) {
      _loaded = false;
      _lastUid = uid;
    }
    if (force) _loaded = false;

    if (uid == null) {
      itemsNotifier.value = [];
      _loaded = true;
      return;
    }
    if (_loaded) return;
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _watchlistCol.orderBy('addedAt', descending: true).get();
      } catch (_) {
        snapshot = await _watchlistCol.get();
      }
      final list = snapshot.docs
          .map((d) => WatchlistItem.fromDoc(d.id, d.data()))
          .where((e) => e.dramaId.isNotEmpty)
          .toList();
      list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      itemsNotifier.value = list;
    } catch (e, st) {
      debugPrint('WatchlistService.loadIfNeeded: $e\n$st');
      itemsNotifier.value = [];
    }
    _loaded = true;
  }

  void clearForLogout() {
    itemsNotifier.value = [];
    _loaded = false;
    _lastUid = null;
  }

  /// 드라마 상세에서 호출. [country]는 `CountryScope` / 가입 국가 코드.
  Future<void> add(String dramaId, String? country) async {
    final uid = _uid;
    if (uid == null || dramaId.isEmpty) return;
    await loadIfNeeded();
    if (isInWatchlist(dramaId)) return;

    final svc = DramaListService.instance;
    final title = svc.getDisplayTitle(dramaId, country).trim();
    final imageUrl = svc.getDisplayImageUrl(dramaId, country);
    final item = WatchlistItem(
      dramaId: dramaId,
      addedAt: DateTime.now(),
      titleSnapshot: title.isNotEmpty ? title : null,
      imageUrlSnapshot: imageUrl,
    );

    try {
      await _watchlistCol.doc(dramaId).set(item.toFirestoreMap());
    } catch (e, st) {
      debugPrint('WatchlistService.add: $e\n$st');
      return;
    }

    itemsNotifier.value = [item, ...itemsNotifier.value.where((e) => e.dramaId != dramaId)];
  }

  Future<void> remove(String dramaId) async {
    final uid = _uid;
    if (uid == null || dramaId.isEmpty) return;
    itemsNotifier.value = itemsNotifier.value.where((e) => e.dramaId != dramaId).toList();
    try {
      await _watchlistCol.doc(dramaId).delete();
    } catch (e, st) {
      debugPrint('WatchlistService.remove: $e\n$st');
      await loadIfNeeded(force: true);
    }
  }

  Future<void> toggle(String dramaId, String? country) async {
    if (isInWatchlist(dramaId)) {
      await remove(dramaId);
    } else {
      await add(dramaId, country);
    }
  }

  /// 저장 화면 등에서 [dramaId]로 [DramaItem] 복원 (로컬 카탈로그 + 스냅샷 폴백).
  DramaItem resolveDramaItem(String dramaId) {
    for (final it in DramaListService.instance.list) {
      if (it.id == dramaId) return it;
    }
    WatchlistItem? snap;
    for (final e in itemsNotifier.value) {
      if (e.dramaId == dramaId) {
        snap = e;
        break;
      }
    }
    final title = snap?.titleSnapshot?.trim().isNotEmpty == true
        ? snap!.titleSnapshot!.trim()
        : dramaId;
    return DramaItem(
      id: dramaId,
      title: title,
      subtitle: '',
      views: '0',
      imageUrl: snap?.imageUrlSnapshot,
    );
  }
}
