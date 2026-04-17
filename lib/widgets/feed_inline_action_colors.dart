import 'package:flutter/material.dart';

/// 홈(리뷰·톡·에스크) / 레이팅스&리뷰 / 리뷰 목록 인라인 액션 — 빈 하트·댓글 아이콘·숫자.
///
/// 좋아요 누른 하트는 [Colors.redAccent] 등 별도 처리.
Color feedInlineActionMutedForeground(ColorScheme cs) =>
    cs.onSurfaceVariant.withValues(alpha: 0.68);
