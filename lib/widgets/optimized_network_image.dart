import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 네트워크 이미지 - 캐싱 + 썸네일용 메모리 최적화
/// [memCacheWidth]/[memCacheHeight]로 디코딩 크기 제한 → 스크롤 시 메모리·속도 개선
class OptimizedNetworkImage extends StatelessWidget {
  const OptimizedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    /// 썸네일용: 화면에 보이는 크기 기준. null이면 원본 디코딩 (풀화면용)
    this.memCacheWidth,
    this.memCacheHeight,
    this.borderRadius,
    this.errorWidget,
    this.placeholder,
    this.onTap,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;
  final Widget? placeholder;
  final VoidCallback? onTap;

  /// 리스트 썸네일용 (220px 높이, 가로 전체) - 디스크 캐싱 + 메모리 캐시 크기 제한
  factory OptimizedNetworkImage.thumbnail({
    Key? key,
    required String imageUrl,
    double height = 220,
    double? width,
    BorderRadius? borderRadius,
    Widget? errorWidget,
    VoidCallback? onTap,
  }) =>
      OptimizedNetworkImage(
        key: key,
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: width ?? double.infinity,
        height: height,
        memCacheWidth: 480,
        memCacheHeight: 480,
        borderRadius: borderRadius,
        errorWidget: errorWidget,
        onTap: onTap,
      );

  /// 프로필/아바타용 (작은 원형) - 메모리 캐시 120px
  factory OptimizedNetworkImage.avatar({
    Key? key,
    required String imageUrl,
    double size = 80,
    Widget? errorWidget,
  }) =>
      OptimizedNetworkImage(
        key: key,
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: size,
        height: size,
        memCacheWidth: 120,
        memCacheHeight: 120,
        errorWidget: errorWidget,
      );

  @override
  Widget build(BuildContext context) {
    Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      placeholder: (_, __) =>
          placeholder ??
          Container(
            width: width,
            height: height,
            color: const Color(0xFFE8E8E8),
          ),
      errorWidget: (_, __, ___) =>
          errorWidget ??
          SizedBox(
            width: width,
            height: height,
            child: Icon(Icons.broken_image_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
          ),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    if (onTap != null) {
      image = GestureDetector(onTap: onTap, child: image);
    }
    return image;
  }
}
