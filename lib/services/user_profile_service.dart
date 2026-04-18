import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/profile_favorite.dart';
import '../models/post.dart';
import 'auth_service.dart';
import 'follow_service.dart';
import 'locale_service.dart';
import 'post_service.dart';

/// 다른 유저 프로필 조회용 (Firestore `users/{uid}` 공개 필드만).
class PublicUserProfile {
  const PublicUserProfile({
    required this.uid,
    required this.displayNickname,
    this.profileImageUrl,
    this.avatarColorIndex,
    this.favorites = const [],
  });

  final String uid;
  final String displayNickname;
  final String? profileImageUrl;
  final int? avatarColorIndex;
  final List<ProfileFavorite> favorites;
}

/// 프로필(닉네임, 프로필 사진) Firestore users/{uid} + Storage profile/{uid}
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  final ValueNotifier<String?> nicknameNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> profileImageUrlNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<int?> avatarColorNotifier = ValueNotifier<int?>(null);
  /// 가입 시 선택한 국가 코드 (us, kr, cn, jp). 프로필 표시용.
  final ValueNotifier<String?> signupCountryNotifier = ValueNotifier<String?>(null);
  /// Letterboxd 스타일 프로필 즐겨찾기 (`users/{uid}.favorites` 배열).
  /// 항목마다 `country`가 있으면 해당 언어에서만 표시. 저장 상한 [_kFavoritesMaxStored],
  /// 현재 언어당 표시·추가 상한 [_kFavoritesMaxPerLocale].
  final ValueNotifier<List<ProfileFavorite>> favoritesNotifier = ValueNotifier<List<ProfileFavorite>>([]);

  static const int _kFavoritesMaxStored = 24;
  static const int _kFavoritesMaxPerLocale = 4;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  bool _loaded = false;
  String? _lastLoadedUid;
  String? _lastAuthorLabelNormalizedUid;
  String? _lastAuthorLabelNormalizedValue;

  // 타 유저 프로필 캐시 (uid → profile). 앱 세션 동안 유효. 최대 100개 유지.
  static const int _publicProfileCacheMax = 100;
  final Map<String, PublicUserProfile> _publicProfileCache = {};

  void invalidatePublicProfileCache(String uid) {
    _publicProfileCache.remove(uid);
  }

  /// 아바타 배경색 팔레트 (ARGB int 값)
  static const List<int> avatarPalette = [
    0xFFFFF0F0, 0xFFFFF4EE, 0xFFFFFDE8, 0xFFEDF7ED,
    0xFFEAF8FB, 0xFFEDF4FE, 0xFFF3EFFE, 0xFFFEEFF5,
    0xFFEAF6F5, 0xFFF4F9EC,
  ];

  /// 아바타 아이콘색 팔레트
  static const List<int> avatarIconPalette = [
    0xFFCFA8A8, 0xFFCFB09A, 0xFFCFCA8A, 0xFFA0C4A0,
    0xFF8ABFC7, 0xFF8AB3D4, 0xFFAA9DC4, 0xFFCFA3B5,
    0xFF8ABBBA, 0xFFAABC8A,
  ];

  /// avatarColorIndex로부터 배경색/아이콘색 반환
  static Color bgColorFromIndex(int index) => Color(avatarPalette[index % avatarPalette.length]);
  static Color iconColorFromIndex(int index) => Color(avatarIconPalette[index % avatarIconPalette.length]);

  static String _normalizeNickname(String nickname) =>
      nickname.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  DocumentReference<Map<String, dynamic>> get _userDoc {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return _firestore.collection('_').doc('_');
    return _firestore.collection('users').doc(uid);
  }

  /// 닉네임 사용 가능 여부 (가입 전 호출). true=사용가능, false=사용중, null=확인 실패(네트워크/권한 등)
  Future<bool?> isNicknameAvailable(String nickname) async {
    final normalized = _normalizeNickname(nickname);
    if (normalized.isEmpty) return false;
    try {
      final doc = await _firestore.collection('nicknames').doc(normalized).get();
      debugPrint('닉네임 검사: "$normalized" → exists=${doc.exists} (프로젝트: ${_firestore.app.options.projectId})');
      return !doc.exists;
    } catch (e, st) {
      debugPrint('닉네임 검사 실패: $e');
      debugPrint('스택: $st');
      return null;
    }
  }

  /// 회원가입 직후 호출: users/{uid} 생성 + 닉네임 예약. [country]는 가입 시 선택한 국가 코드(us, kr, cn, jp).
  Future<String?> createUserProfileAfterSignup(String nickname, String email, {String? country}) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return '로그인 상태가 아니에요.';
    final normalized = _normalizeNickname(nickname);
    if (normalized.isEmpty) return '닉네임을 입력해 주세요.';
    try {
      final colorIndex = Random().nextInt(avatarPalette.length);
      await _firestore.runTransaction((tx) async {
        final nickRef = _firestore.collection('nicknames').doc(normalized);
        final nickSnap = await tx.get(nickRef);
        if (nickSnap.exists) throw Exception('nickname_taken');
        tx.set(nickRef, {'uid': uid});
        final userData = {
          'nickname': nickname.trim(),
          'email': email.trim(),
          'totalPoints': 0,
          'avatarColorIndex': colorIndex,
        };
        if (country != null && country.isNotEmpty) userData['country'] = country;
        tx.set(_firestore.collection('users').doc(uid), userData, SetOptions(merge: true));
      });
      nicknameNotifier.value = nickname.trim();
      avatarColorNotifier.value = colorIndex;
      signupCountryNotifier.value = country;
      _loaded = true;
      return null;
    } catch (e) {
      if (e.toString().contains('nickname_taken')) return '이미 사용 중인 닉네임이에요.';
      debugPrint('createUserProfileAfterSignup: $e');
      return '회원정보 저장에 실패했어요.';
    }
  }

  Future<void> loadIfNeeded() async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid != _lastLoadedUid) _loaded = false;
    _lastLoadedUid = uid;
    if (uid == null) {
      nicknameNotifier.value = null;
      profileImageUrlNotifier.value = null;
      signupCountryNotifier.value = null;
      favoritesNotifier.value = [];
      FollowService.instance.stopFollowingCountListener();
      _loaded = true;
      return;
    }
    if (_loaded) return;
    try {
      final doc = await _userDoc.get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        nicknameNotifier.value = data['nickname'] as String?;
        profileImageUrlNotifier.value = data['profileImageUrl'] as String?;
        signupCountryNotifier.value = data['country'] as String?;
        final colorIdx = data['avatarColorIndex'];
        if (colorIdx == null) {
          // 기존 회원: 색 미부여 → 랜덤 부여 후 저장
          final newIdx = Random().nextInt(avatarPalette.length);
          avatarColorNotifier.value = newIdx;
          _userDoc.set({'avatarColorIndex': newIdx}, SetOptions(merge: true));
        } else {
          avatarColorNotifier.value = (colorIdx as num).toInt();
        }
        favoritesNotifier.value = _parseFavoritesList(data['favorites']);
      } else {
        nicknameNotifier.value = null;
        profileImageUrlNotifier.value = null;
        avatarColorNotifier.value = null;
        favoritesNotifier.value = [];
      }
    } catch (_) {
      nicknameNotifier.value = null;
      profileImageUrlNotifier.value = null;
      avatarColorNotifier.value = null;
      favoritesNotifier.value = [];
    }
    FollowService.instance.startFollowingCountListener(uid);
    final nick = nicknameNotifier.value?.trim();
    if (nick != null && nick.isNotEmpty) {
      final normalized = 'u/$nick';
      if (_lastAuthorLabelNormalizedUid != uid ||
          _lastAuthorLabelNormalizedValue != normalized) {
        _lastAuthorLabelNormalizedUid = uid;
        _lastAuthorLabelNormalizedValue = normalized;
        unawaited(PostService.instance.normalizeAuthorLabelForUid(uid, normalized));
      }
    }
    _loaded = true;
  }

  /// 커뮤니티 피드 등에서 가입 국가·프로필을 먼저 채운 뒤 호출할 때 사용. [loadIfNeeded]와 동일.
  Future<void> loadUserProfile() => loadIfNeeded();

  static String _stripLeadingAuthorPrefix(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    return s.startsWith('u/') ? s.substring(2) : s;
  }

  /// `users/{uid}`에 닉네임이 없을 때(구 계정 등) 글·리뷰에 디노멀된 작성자명으로 보완.
  Future<String?> _displayNameFromAuthorActivity(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    try {
      final postsSnap = await _firestore
          .collection('posts')
          .where('authorUid', isEqualTo: u)
          .limit(1)
          .get();
      if (postsSnap.docs.isNotEmpty) {
        final author = (postsSnap.docs.first.data()['author'] as String?)?.trim();
        if (author != null && author.isNotEmpty) {
          return _stripLeadingAuthorPrefix(author);
        }
      }
    } catch (e, st) {
      debugPrint('_displayNameFromAuthorActivity posts: $e\n$st');
    }
    try {
      final revSnap = await _firestore
          .collection('drama_reviews')
          .where('uid', isEqualTo: u)
          .limit(1)
          .get();
      if (revSnap.docs.isNotEmpty) {
        final name = (revSnap.docs.first.data()['authorName'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          return _stripLeadingAuthorPrefix(name);
        }
      }
    } catch (e, st) {
      debugPrint('_displayNameFromAuthorActivity drama_reviews: $e\n$st');
    }
    return null;
  }

  /// 커뮤니티 등에서 타 유저 프로필 화면용. [users/{uid}] 읽기 전용.
  /// 결과는 세션 캐시에 보관 — 같은 UID 재방문 시 Firestore 호출 없음.
  Future<PublicUserProfile?> fetchPublicUserProfile(
    String uid, {
    bool forceRefresh = false,
  }) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    if (!forceRefresh && _publicProfileCache.containsKey(u)) {
      return _publicProfileCache[u];
    }
    try {
      final doc = await _firestore.collection('users').doc(u).get();
      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;
      final nick = (data['nickname'] as String?)?.trim();
      String? display = nick != null && nick.isNotEmpty ? nick : null;
      display ??= (data['email'] as String?)?.split('@').first.trim();
      if (display == null || display.isEmpty) {
        display = await _displayNameFromAuthorActivity(u);
      }
      if (display == null || display.isEmpty) {
        display = 'Member';
      }
      final photo = data['profileImageUrl'] as String?;
      final colorIdx = data['avatarColorIndex'];
      final favorites = _parseFavoritesList(data['favorites']);
      final profile = PublicUserProfile(
        uid: u,
        displayNickname: display,
        profileImageUrl: photo,
        avatarColorIndex: colorIdx is num ? colorIdx.toInt() : null,
        favorites: favorites,
      );
      // LRU-lite: 100개 초과 시 가장 먼저 들어온 것부터 제거
      if (_publicProfileCache.length >= _publicProfileCacheMax) {
        _publicProfileCache.remove(_publicProfileCache.keys.first);
      }
      _publicProfileCache[u] = profile;
      return profile;
    } catch (e, st) {
      debugPrint('fetchPublicUserProfile: $e\n$st');
      return null;
    }
  }

  Future<void> setNickname(String nickname) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return;
    nicknameNotifier.value = nickname;
    try {
      await _userDoc.set({'nickname': nickname}, SetOptions(merge: true));
    } catch (_) {}
  }

  void clearForLogout() {
    nicknameNotifier.value = null;
    profileImageUrlNotifier.value = null;
    avatarColorNotifier.value = null;
    favoritesNotifier.value = [];
    FollowService.instance.stopFollowingCountListener();
    _loaded = false;
    _lastLoadedUid = null;
    _lastAuthorLabelNormalizedUid = null;
    _lastAuthorLabelNormalizedValue = null;
  }

  static List<ProfileFavorite> _parseFavoritesList(dynamic raw) {
    if (raw is! List) return [];
    final out = <ProfileFavorite>[];
    for (final e in raw) {
      final fav = ProfileFavorite.fromDynamic(e);
      if (fav != null) out.add(fav);
      if (out.length >= _kFavoritesMaxStored) break;
    }
    return out;
  }

  static bool favoriteVisibleInLocale(ProfileFavorite e, String viewerLocale) {
    final m = <String, dynamic>{};
    final c = e.appLocale?.trim();
    if (c != null && c.isNotEmpty) m['country'] = c;
    return Post.documentVisibleInCountryFeed(m, viewerLocale);
  }

  static List<ProfileFavorite> favoritesVisibleInLocale(
    List<ProfileFavorite> all,
    String viewerLocale,
  ) {
    return all
        .where((e) => favoriteVisibleInLocale(e, viewerLocale))
        .take(_kFavoritesMaxPerLocale)
        .toList();
  }

  /// 현재 앱 언어에서 보이는 즐겨찾기만 (슬롯 4개 UI용).
  List<ProfileFavorite> favoritesVisibleForCurrentLocale() =>
      favoritesVisibleInLocale(
        favoritesNotifier.value,
        LocaleService.instance.locale,
      );

  static int _visibleFavoriteCount(List<ProfileFavorite> cur, String loc) =>
      cur.where((e) => favoriteVisibleInLocale(e, loc)).length;

  /// 동일 작품·동일 `country` 버킷(둘 다 레거시면 동일)이면 중복으로 간주.
  static bool _favoriteSameLocaleBucket(ProfileFavorite a, ProfileFavorite b) {
    if (a.dramaId != b.dramaId) return false;
    final ca = (a.appLocale ?? '').trim();
    final cb = (b.appLocale ?? '').trim();
    if (ca.isEmpty && cb.isEmpty) return true;
    if (ca.isEmpty || cb.isEmpty) return false;
    return ca == cb;
  }

  /// `favorites` 배열 전체 저장 (최대 [_kFavoritesMaxStored]개까지 보관).
  Future<void> saveFavorites(List<ProfileFavorite> list) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return;
    final trimmed = list.take(_kFavoritesMaxStored).toList();
    try {
      await _userDoc.set(
        {'favorites': trimmed.map((e) => e.toMap()).toList()},
        SetOptions(merge: true),
      );
      favoritesNotifier.value = trimmed;
    } catch (e, st) {
      debugPrint('saveFavorites: $e\n$st');
    }
  }

  Future<void> addFavorite(ProfileFavorite fav) async {
    await loadIfNeeded();
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return;
    final loc = LocaleService.instance.locale;
    final scoped = ProfileFavorite(
      dramaId: fav.dramaId,
      dramaTitle: fav.dramaTitle,
      dramaThumbnail: fav.dramaThumbnail,
      appLocale: (fav.appLocale != null && fav.appLocale!.trim().isNotEmpty)
          ? fav.appLocale!.trim()
          : loc,
    );
    final cur = List<ProfileFavorite>.from(favoritesNotifier.value);
    if (cur.length >= _kFavoritesMaxStored) return;
    if (_visibleFavoriteCount(cur, loc) >= _kFavoritesMaxPerLocale) return;
    if (cur.any((e) => _favoriteSameLocaleBucket(e, scoped))) return;
    cur.add(scoped);
    await saveFavorites(cur);
  }

  Future<void> removeFavoriteByDramaId(String dramaId) async {
    final cur = favoritesNotifier.value.where((e) => e.dramaId != dramaId).toList();
    await saveFavorites(cur);
  }

  /// 글/댓글 작성 및 조회 시 사용하는 작성자 이름.
  /// 메모리 → Firestore 로컬 캐시 → 서버 순. 없으면 `익명`.
  Future<String> getAuthorBaseName() async {
    final cached = nicknameNotifier.value?.trim();
    if (cached != null && cached.isNotEmpty) return cached;

    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return '익명';

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      final name = (doc.data()?['nickname'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        nicknameNotifier.value = name;
        return name;
      }
    } catch (_) {}

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      final name = (doc.data()?['nickname'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        nicknameNotifier.value = name;
        return name;
      }
    } catch (_) {}

    return nicknameNotifier.value?.trim().isNotEmpty == true
        ? nicknameNotifier.value!
        : '익명';
  }

  /// `익명` / `u/익명` / 공백 — 피드에서 본인 표시 보강용.
  bool isAnonymousAuthorLabel(String author) {
    final t = author.trim();
    if (t.isEmpty) return true;
    return t == '익명' || t == 'u/익명';
  }

  /// 내 글([isMineByUid])인데 [currentUserAuthor]나 글의 [postAuthor]가 익명으로 남았을 때
  /// [nicknameNotifier]에 닉이 있으면 `u/닉네임`을 쓴다. (프로필 로드가 피드보다 늦을 때)
  String? effectiveAuthorLabelForMyPost({
    required bool isMineByUid,
    required String? currentUserAuthor,
    required String postAuthor,
  }) {
    if (!isMineByUid) return null;
    final nick = nicknameNotifier.value?.trim();
    if (nick == null || nick.isEmpty) return currentUserAuthor;
    final fromProfile = 'u/$nick';
    if (currentUserAuthor == null || isAnonymousAuthorLabel(currentUserAuthor)) {
      return fromProfile;
    }
    if (isAnonymousAuthorLabel(postAuthor)) {
      return fromProfile;
    }
    return currentUserAuthor;
  }

  /// 글 작성자 (u/ 접두사)
  Future<String> getAuthorForPost() async {
    // 프로필이 이미 로드된 경우 Firestore 왕복 없이 즉시 반환
    if (_loaded) {
      final n = nicknameNotifier.value?.trim();
      if (n != null && n.isNotEmpty) return 'u/$n';
    }
    final base = await getAuthorBaseName();
    return 'u/$base';
  }

  /// 프로필 사진 업로드 (갤러리에서 선택한 이미지 바이트). 성공 시 URL 반환, 실패 시 에러 메시지.
  Future<String?> uploadProfileImage(Uint8List bytes) async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return '로그인이 필요해요.';
    try {
      final ref = _storage.ref().child('profile').child('$uid.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await _userDoc.set({'profileImageUrl': url}, SetOptions(merge: true));
      profileImageUrlNotifier.value = url;
      // 내가 쓴 모든 게시글의 프로필 사진도 업데이트
      final author = await getAuthorForPost();
      await PostService.instance.updateAuthorPhotoUrl(author, url);
      return null;
    } catch (e) {
      debugPrint('uploadProfileImage: $e');
      return '사진 업로드에 실패했어요.';
    }
  }

  /// 프로필 사진 제거
  Future<String?> removeProfileImage() async {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return '로그인이 필요해요.';
    try {
      final ref = _storage.ref().child('profile').child('$uid.jpg');
      try {
        await ref.delete();
      } catch (_) {}
      await _userDoc.set({'profileImageUrl': null}, SetOptions(merge: true));
      profileImageUrlNotifier.value = null;
      // 내가 쓴 모든 게시글의 프로필 사진도 제거
      final author = await getAuthorForPost();
      await PostService.instance.updateAuthorPhotoUrl(author, null);
      return null;
    } catch (e) {
      debugPrint('removeProfileImage: $e');
      return '사진 삭제에 실패했어요.';
    }
  }
}
