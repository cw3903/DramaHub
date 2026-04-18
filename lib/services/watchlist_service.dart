import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/drama.dart';
import '../models/post.dart';
import '../models/watchlist_item.dart';
import 'auth_service.dart';
import 'drama_list_service.dart';
import 'locale_service.dart';

/// Letterboxd 스타일 보고 싶은 드라마 — `users/{uid}/watchlist/{dramaId}`.
class WatchlistService {
  WatchlistService._();
  static final WatchlistService instance = WatchlistService._();

  final ValueNotifier<List<WatchlistItem>> itemsNotifier = ValueNotifier<List<WatchlistItem>>([]);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _loaded = false;
  String? _lastUid;
  String? _lastLocaleForFilter;

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
    final loc = LocaleService.instance.locale;
    if (uid != _lastUid) {
      _loaded = false;
      _lastUid = uid;
    }
    if (_lastLocaleForFilter != null && _lastLocaleForFilter != loc) {
      _loaded = false;
    }
    if (force) _loaded = false;

    if (uid == null) {
      itemsNotifier.value = [];
      _loaded = true;
      _lastLocaleForFilter = loc;
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
          .where((d) => Post.userScopedFirestoreDocVisibleForLocale(d.data(), loc))
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
    _lastLocaleForFilter = loc;
  }

  void clearForLogout() {
    itemsNotifier.value = [];
    _loaded = false;
    _lastUid = null;
    _lastLocaleForFilter = null;
  }

  /// 타 유저 워치리스트 조회.
  Future<List<WatchlistItem>> fetchForUid(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return [];
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection('users')
            .doc(u)
            .collection('watchlist')
            .orderBy('addedAt', descending: true)
            .get();
      } catch (_) {
        snap = await _firestore
            .collection('users')
            .doc(u)
            .collection('watchlist')
            .get();
      }
      final loc = LocaleService.instance.locale;
      final items = snap.docs
          .where((d) => Post.userScopedFirestoreDocVisibleForLocale(d.data(), loc))
          .map((d) => WatchlistItem.fromDoc(d.id, d.data()))
          .where((e) => e.dramaId.isNotEmpty)
          .toList();
      items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return items;
    } catch (e, st) {
      debugPrint('WatchlistService.fetchForUid: $e\n$st');
      return [];
    }
  }

  /// 타 유저 프로필 메뉴 카운트용. Firestore `count()` 집계 사용.
  Future<int> countWatchlistForUid(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return 0;
    try {
      final agg = await _firestore
          .collection('users')
          .doc(u)
          .collection('watchlist')
          .count()
          .get();
      return agg.count ?? 0;
    } catch (e, st) {
      debugPrint('WatchlistService.countWatchlistForUid: $e\n$st');
      return 0;
    }
  }

  /// 드라마 상세에서 호출. [country]는 `CountryScope` / 가입 국가 코드.
  Future<void> add(String dramaId, String? country) async {
    final uid = _uid;
    if (uid == null || dramaId.isEmpty) return;
    if (isInWatchlist(dramaId)) return;

    final svc = DramaListService.instance;
    final title = svc.getDisplayTitle(dramaId, country).trim();
    final imageUrl = svc.getDisplayImageUrl(dramaId, country);
    final loc = LocaleService.instance.locale;
    final item = WatchlistItem(
      dramaId: dramaId,
      addedAt: DateTime.now(),
      titleSnapshot: title.isNotEmpty ? title : null,
      imageUrlSnapshot: imageUrl,
      appLocale: loc,
    );

    // Optimistic update first — UI responds immediately (same as remove())
    itemsNotifier.value = [item, ...itemsNotifier.value.where((e) => e.dramaId != dramaId)];

    try {
      await _watchlistCol.doc(dramaId).set(item.toFirestoreMap());
    } catch (e, st) {
      debugPrint('WatchlistService.add: $e\n$st');
      // Rollback on Firestore failure
      itemsNotifier.value = itemsNotifier.value.where((e) => e.dramaId != dramaId).toList();
    }
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

  /// 모든 유저 중 이 드라마를 워치리스트에 둔 인원 수 (`dramaId` 필드 기준).
  ///
  /// collection group에서 [FieldPath.documentId]에 작품 ID만 넣는 질의는
  /// Firestore가 허용하지 않아(전체 문서 경로 필요) 네이티브 단언 크래시가 난다.
  /// `null`이면 집계 실패 — UI에서 기존 숫자를 유지할 것.
  Future<int?> countUsersIncludingDrama(String dramaId) async {
    final did = dramaId.trim();
    if (did.isEmpty) return 0;
    try {
      final snap = await _firestore
          .collectionGroup('watchlist')
          .where('dramaId', isEqualTo: did)
          .count()
          .get();
      return snap.count ?? 0;
    } catch (e, st) {
      debugPrint('WatchlistService.countUsersIncludingDrama: $e\n$st');
      return null;
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
