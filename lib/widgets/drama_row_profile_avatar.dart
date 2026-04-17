import 'package:flutter/material.dart';

import '../constants/app_profile_avatar_size.dart';
import '../services/user_profile_service.dart';
import 'optimized_network_image.dart';

/// Watch / 드라마 리뷰 목록용 — URL 우선, 없으면 [authorUid]로 프로필 조회, 글자 이니셜 대신 실루엣.
class DramaRowProfileAvatar extends StatelessWidget {
  const DramaRowProfileAvatar({
    super.key,
    required this.imageUrl,
    required this.authorUid,
    required this.colorScheme,
    this.size = kAppUnifiedProfileAvatarSize,
  });

  final String? imageUrl;
  final String? authorUid;
  final ColorScheme colorScheme;
  final double size;

  Widget _silhouette() {
    final fill = Color.alphaBlend(
      colorScheme.surface.withValues(alpha: 0.62),
      colorScheme.surfaceContainerHighest,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.52,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.48),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = imageUrl?.trim();
    if (u != null && u.startsWith('http')) {
      return ClipOval(
        child: OptimizedNetworkImage.avatar(
          imageUrl: u,
          size: size,
          errorWidget: _silhouette(),
        ),
      );
    }
    final uid = authorUid?.trim();
    if (uid != null && uid.isNotEmpty) {
      return FutureBuilder<PublicUserProfile?>(
        future: UserProfileService.instance.fetchPublicUserProfile(uid),
        builder: (context, snap) {
          final url = snap.data?.profileImageUrl?.trim();
          if (url != null && url.startsWith('http')) {
            return ClipOval(
              child: OptimizedNetworkImage.avatar(
                imageUrl: url,
                size: size,
                errorWidget: _silhouette(),
              ),
            );
          }
          return _silhouette();
        },
      );
    }
    return _silhouette();
  }
}
