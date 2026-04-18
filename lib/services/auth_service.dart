import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// 로그인 상태 관리 (Firebase Auth + Google Sign-In)
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// Firebase Auth 네트워크 호출 상한(무한 대기 방지).
  static const Duration authNetworkTimeout = Duration(seconds: 22);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  final ValueNotifier<bool> isLoggedIn = ValueNotifier<bool>(false);
  final ValueNotifier<User?> currentUser = ValueNotifier<User?>(null);

  void setLoggedIn(bool value) {
    isLoggedIn.value = value;
    if (!value) currentUser.value = null;
  }

  /// 앱 시작 시 저장된 세션 복원
  Future<void> restoreSession() async {
    final user = _auth.currentUser;
    isLoggedIn.value = user != null;
    currentUser.value = user;
  }

  /// 해당 이메일로 가입된 로그인 수단 조회 (invalid-credential 시 원인 구분용)
  Future<List<String>> fetchSignInMethodsForEmail(String email) async {
    return _auth
        .fetchSignInMethodsForEmail(email)
        .timeout(const Duration(seconds: 12));
  }

  /// 이메일/비밀번호 로그인
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final result = await _auth
          .signInWithEmailAndPassword(
            email: email,
            password: password,
          )
          .timeout(authNetworkTimeout);
      isLoggedIn.value = true;
      currentUser.value = result.user;
      return result.user;
    } catch (e) {
      if (kDebugMode) print('Email sign-in error: $e');
      rethrow;
    }
  }

  /// 이메일/비밀번호 회원가입
  Future<User?> signUpWithEmailAndPassword(String email, String password) async {
    try {
      final result = await _auth
          .createUserWithEmailAndPassword(
            email: email,
            password: password,
          )
          .timeout(authNetworkTimeout);
      isLoggedIn.value = true;
      currentUser.value = result.user;
      return result.user;
    } catch (e) {
      if (kDebugMode) print('Email sign-up error: $e');
      rethrow;
    }
  }

  /// 구글 로그인
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential result = await _auth
          .signInWithCredential(credential)
          .timeout(authNetworkTimeout);
      isLoggedIn.value = true;
      currentUser.value = result.user;
      return result.user;
    } catch (e) {
      if (kDebugMode) print('Google sign-in error: $e');
      rethrow;
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
    setLoggedIn(false);
  }
}
