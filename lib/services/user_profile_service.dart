import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'post_service.dart';

/// 프로필(닉네임, 프로필 사진) Firestore users/{uid} + Storage profile/{uid}
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  final ValueNotifier<String?> nicknameNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> profileImageUrlNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<int?> avatarColorNotifier = ValueNotifier<int?>(null);
  /// 가입 시 선택한 국가 코드 (us, kr, cn, jp). 프로필 표시용.
  final ValueNotifier<String?> signupCountryNotifier = ValueNotifier<String?>(null);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  bool _loaded = false;
  String? _lastLoadedUid;

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
      } else {
        nicknameNotifier.value = null;
        profileImageUrlNotifier.value = null;
        avatarColorNotifier.value = null;
      }
    } catch (_) {
      nicknameNotifier.value = null;
      profileImageUrlNotifier.value = null;
      avatarColorNotifier.value = null;
    }
    _loaded = true;
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
    _loaded = false;
    _lastLoadedUid = null;
  }

  /// 글/댓글 작성 및 조회 시 사용하는 작성자 이름 (닉네임 > displayName > 이메일앞 > 익명)
  Future<String> getAuthorBaseName() async {
    await loadIfNeeded();
    final nickname = nicknameNotifier.value?.trim();
    if (nickname != null && nickname.isNotEmpty) return nickname;
    final displayName = AuthService.instance.currentUser.value?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = AuthService.instance.currentUser.value?.email;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return '익명';
  }

  /// 글 작성자 (u/ 접두사)
  Future<String> getAuthorForPost() async {
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
