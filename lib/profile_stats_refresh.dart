import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

/// 프로필 상단 Posts 칩(글·내 댓글 합) 등 통계를 서버 기준으로 다시 불러오게 하는 신호.
///
/// 프로필 화면 통계 행이 리스닝하며, 값이 바뀔 때마다 `forceServerFetch: true`로 재조회한다.
final ValueNotifier<int> profileStatsRefreshNotifier = ValueNotifier<int>(0);

void bumpProfileStatsRefresh() {
  profileStatsRefreshNotifier.value++;
}

/// 글 저장 직후 Firestore `where(authorUid)` 결과가 한 박자 늦게 잡히는 경우가 있어
/// 즉시 + 지연 재조회로 Posts 칩이 곧바로 맞도록 한다.
void bumpProfileStatsRefreshAfterNewPost() {
  bumpProfileStatsRefresh();
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      bumpProfileStatsRefresh();
    }),
  );
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      bumpProfileStatsRefresh();
    }),
  );
}
