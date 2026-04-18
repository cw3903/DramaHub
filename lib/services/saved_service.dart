import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import 'auth_service.dart';
import 'locale_service.dart';

/// 저장 항목 종류: 콘텐츠(숏폼/리뷰), 글(게시판)
enum SavedItemType { content, post }

/// 저장한 항목 (콘텐츠 또는 게시글)
class SavedItem {
  const SavedItem({
    required this.id,
    required this.title,
    this.views = '0',
    this.type = SavedItemType.content,
    this.post,
    this.appLocale,
  });

  final String id;
  final String title;
  final String views;
  final SavedItemType type;
  /// type == post 일 때 게시글 상세/목록 표시용
  final Post? post;

  /// Firestore `country` (us/kr/jp/cn). null이면 레거시.
  final String? appLocale;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'views': views,
      'type': type.name,
      'post': post?.toMap(),
      if (appLocale != null && appLocale!.isNotEmpty) 'country': appLocale,
    };
  }

  static SavedItem fromMap(Map<String, dynamic> map) {
    final type = map['type'] == 'post' ? SavedItemType.post : SavedItemType.content;
    final postMap = map['post'] as Map<String, dynamic>?;
    return SavedItem(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      views: map['views'] as String? ?? '0',
      type: type,
      post: postMap != null ? Post.fromMap(postMap) : null,
      appLocale: (map['country'] as String?)?.trim(),
    );
  }
}

/// 저장 목록 관리 (Firestore 연동)
class SavedService {
  SavedService._();

  static final SavedService instance = SavedService._();

  final ValueNotifier<List<SavedItem>> savedList = ValueNotifier<List<SavedItem>>([]);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _loaded = false;
  String? _lastLocaleForFilter;

  String? get _uid => AuthService.instance.currentUser.value?.uid;

  CollectionReference<Map<String, dynamic>> get _savedCol {
    final uid = _uid;
    if (uid == null) return _firestore.collection('_').doc('_').collection('_');
    return _firestore.collection('users').doc(uid).collection('saved');
  }

  bool isSaved(String id) => savedList.value.any((e) => e.id == id);

  List<SavedItem> get savedContent =>
      savedList.value.where((e) => e.type == SavedItemType.content).toList();

  List<SavedItem> get savedPosts =>
      savedList.value.where((e) => e.type == SavedItemType.post && e.post != null).toList();

  /// Firestore에서 저장 목록 로드 (로그인 시 호출)
  Future<void> loadIfNeeded() async {
    final uid = _uid;
    final loc = LocaleService.instance.locale;
    if (_lastLocaleForFilter != null && _lastLocaleForFilter != loc) {
      _loaded = false;
    }
    if (uid == null) {
      savedList.value = [];
      _loaded = true;
      _lastLocaleForFilter = loc;
      return;
    }
    if (_loaded) return;
    try {
      final snapshot = await _savedCol.get();
      final list = snapshot.docs
          .map((d) => SavedItem.fromMap(d.data()))
          .where((e) => e.id.isNotEmpty)
          .where(
            (e) => Post.documentVisibleInCountryFeed(
              e.appLocale != null ? {'country': e.appLocale} : {},
              loc,
            ),
          )
          .toList();
      savedList.value = list;
    } catch (_) {
      savedList.value = [];
    }
    _loaded = true;
    _lastLocaleForFilter = loc;
  }

  /// 로그아웃 시 호출 (목록 초기화 후 다음 로그인 시 다시 로드)
  void clearForLogout() {
    savedList.value = [];
    _loaded = false;
    _lastLocaleForFilter = null;
  }

  Future<void> toggle(SavedItem item) async {
    final list = List<SavedItem>.from(savedList.value);
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      list.removeAt(idx);
      final uid = _uid;
      if (uid != null) {
        try {
          await _savedCol.doc(item.id).delete();
        } catch (_) {}
      }
    } else {
      final itemToSave = (item.appLocale != null &&
              item.appLocale!.trim().isNotEmpty)
          ? item
          : SavedItem(
              id: item.id,
              title: item.title,
              views: item.views,
              type: item.type,
              post: item.post,
              appLocale: LocaleService.instance.locale,
            );
      list.add(itemToSave);
      final uid = _uid;
      if (uid != null) {
        try {
          await _savedCol.doc(itemToSave.id).set(itemToSave.toMap());
        } catch (_) {}
      }
    }
    savedList.value = list;
  }

  Future<void> add(SavedItem item) async {
    if (isSaved(item.id)) return;
    final itemToSave = (item.appLocale != null &&
            item.appLocale!.trim().isNotEmpty)
        ? item
        : SavedItem(
            id: item.id,
            title: item.title,
            views: item.views,
            type: item.type,
            post: item.post,
            appLocale: LocaleService.instance.locale,
          );
    savedList.value = [...savedList.value, itemToSave];
    final uid = _uid;
    if (uid != null) {
      try {
        await _savedCol.doc(itemToSave.id).set(itemToSave.toMap());
      } catch (_) {}
    }
  }

  Future<void> remove(String id) async {
    savedList.value = savedList.value.where((e) => e.id != id).toList();
    final uid = _uid;
    if (uid != null) {
      try {
        await _savedCol.doc(id).delete();
      } catch (_) {}
    }
  }
}
