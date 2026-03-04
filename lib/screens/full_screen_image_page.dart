import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../widgets/optimized_network_image.dart';

/// 이미지 URL 목록을 전체 화면으로 보여주는 페이지.
/// 탭 시 닫기, 핀치 줌, 여러 장일 경우 좌우 스와이프.
/// 위아래 드래그로 닫기 (인스타그램 스타일).
class FullScreenImagePage extends StatefulWidget {
  const FullScreenImagePage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  static Future<void> show(BuildContext context, List<String> urls, {int initialIndex = 0}) {
    if (urls.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => FullScreenImagePage(
          imageUrls: urls,
          initialIndex: initialIndex.clamp(0, urls.length - 1),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

  @override
  State<FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<FullScreenImagePage> with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  late PageController _pageController;
  late int _currentIndex;

  // 드래그-투-디스미스 상태
  double _dragOffset = 0;
  bool _isDragging = false;
  bool _isZoomed = false;

  // 닫힘 임계값 (px)
  static const double _dismissThreshold = 120;
  // 배경 불투명도 최소값
  static const double _minBackgroundOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _transformController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
    _isZoomed = false;
  }

  bool get _isAtIdentityScale {
    final scale = _transformController.value.getMaxScaleOnAxis();
    return scale <= 1.01;
  }

  double get _backgroundOpacity {
    if (!_isDragging) return 1.0;
    final progress = (_dragOffset.abs() / _dismissThreshold).clamp(0.0, 1.0);
    return (1.0 - progress * 0.85).clamp(_minBackgroundOpacity, 1.0);
  }

  void _onVerticalDragStart(DragStartDetails details) {
    // 줌 상태면 드래그-투-디스미스 비활성화
    if (!_isAtIdentityScale) return;
    setState(() => _isDragging = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        _dragOffset.abs() > _dismissThreshold || velocity.abs() > 800;

    if (shouldDismiss) {
      Navigator.of(context).pop();
    } else {
      // 원위치로 복귀
      setState(() {
        _dragOffset = 0;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedContainer(
        duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
        color: Colors.black.withOpacity(_backgroundOpacity),
        child: Stack(
          children: [
            // 이미지 영역 (드래그 오프셋 적용)
            GestureDetector(
              onTap: _isAtIdentityScale ? () => Navigator.of(context).pop() : null,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.imageUrls.length,
                  onPageChanged: (i) {
                    setState(() => _currentIndex = i);
                    _resetZoom();
                  },
                  itemBuilder: (context, index) {
                    return InteractiveViewer(
                      transformationController:
                          index == _currentIndex ? _transformController : TransformationController(),
                      minScale: 0.5,
                      maxScale: 4.0,
                      onInteractionUpdate: (_) {
                        final zoomed = !_isAtIdentityScale;
                        if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
                      },
                      child: Center(
                        child: OptimizedNetworkImage(
                          imageUrl: widget.imageUrls[index],
                          fit: BoxFit.contain,
                          placeholder: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                          errorWidget: const Icon(
                            LucideIcons.image_off,
                            size: 64,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 상단: X 닫기 버튼
            AnimatedOpacity(
              opacity: _isDragging ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        icon: const Icon(LucideIcons.x, color: Colors.white, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 하단: 페이지 인디케이터 (2장 이상일 때)
            if (widget.imageUrls.length > 1)
              AnimatedOpacity(
                opacity: _isDragging ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(widget.imageUrls.length, (i) {
                          final isActive = i == _currentIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: isActive ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.white : Colors.white38,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
