import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../widgets/country_scope.dart';

/// 다른 유저 프로필용: `users/{me}/following/{targetUid}` 존재 여부로 Follow / Following 전환.
class UserFollowButton extends StatelessWidget {
  const UserFollowButton({
    super.key,
    required this.targetUid,
    this.dense = false,
  });

  final String targetUid;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    final me = AuthService.instance.currentUser.value?.uid;
    if (me == null || me == targetUid) return const SizedBox.shrink();

    return StreamBuilder<bool>(
      stream: FollowService.instance.isFollowingStream(me, targetUid),
      builder: (context, snap) {
        final following = snap.data ?? false;
        final style = GoogleFonts.notoSansKr(
          fontSize: dense ? 12 : 13,
          fontWeight: FontWeight.w700,
        );
        if (following) {
          return OutlinedButton(
            onPressed: () => FollowService.instance.unfollowUser(targetUid),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 6 : 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: cs.onSurfaceVariant,
              side: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
            ),
            child: Text(s.get('followButtonFollowing'), style: style),
          );
        }
        return FilledButton(
          onPressed: () => FollowService.instance.followUser(targetUid),
          style: FilledButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 6 : 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(s.get('followButtonFollow'), style: style.copyWith(color: cs.onPrimary)),
        );
      },
    );
  }
}
