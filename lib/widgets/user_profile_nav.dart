import 'package:flutter/cupertino.dart';

import '../screens/profile_screen.dart';

/// 작성자 UID가 있으면 해당 유저 공개 프로필로 이동 (본인 포함).
/// [authorUid]가 비어 있으면 아무 것도 하지 않음.
void openUserProfileFromAuthorUid(BuildContext context, String? authorUid) {
  final u = authorUid?.trim();
  if (u == null || u.isEmpty) return;
  Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      builder: (_) => ProfileScreen(viewedUserUid: u),
    ),
  );
}
