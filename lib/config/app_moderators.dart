import '../services/auth_service.dart';

/// 앱 내 운영자(모더레이터) Firebase Auth **UID** 목록.
///
/// 여기에 본인 계정 UID를 추가하면, **본인이 쓴 글이 아니어도** 피드·상세에서
/// 삭제 메뉴가 나오고 `PostService.deletePost`로 글을 지울 수 있습니다.
///
/// UID 확인: Firebase Console → Authentication → 사용자 행에서 복사,
/// 또는 디버그 로그로 `AuthService.instance.currentUser.value?.uid` 출력.
///
/// ⚠️ 나중에 Firestore 규칙을 `작성자만 삭제`로 바꾸면, 규칙에 운영자 UID
/// 예외를 넣거나 Custom Claims를 써야 클라이언트와 서버가 일치합니다.
const Set<String> kAppModeratorAuthUids = <String>{
  'Oz4aYwiFyIdin2UMs01LUAiEEMs1',
};

/// 현재 로그인 사용자가 운영자 UID 목록에 포함되는지.
bool isAppModerator() {
  final uid = AuthService.instance.currentUser.value?.uid;
  return uid != null && kAppModeratorAuthUids.contains(uid);
}
