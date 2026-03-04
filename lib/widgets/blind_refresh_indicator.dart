import 'dart:math' as math;
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 블라인드 앱 스타일 스피너: 3/4 원호, 작은 갭, 둥근 끝, 다크 그레이.
class _BlindStyleSpinner extends StatefulWidget {
  const _BlindStyleSpinner({
    required this.isLoading,
    required this.pullProgress,
    this.size = 22,
  });

  final bool isLoading;
  final double pullProgress;
  final double size;

  @override
  State<_BlindStyleSpinner> createState() => _BlindStyleSpinnerState();
}

class _BlindStyleSpinnerState extends State<_BlindStyleSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isLoading) _controller.repeat();
  }

  @override
  void didUpdateWidget(_BlindStyleSpinner old) {
    super.didUpdateWidget(old);
    if (widget.isLoading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isLoading && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: widget.isLoading
          ? AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _BlindArcPainter(
                  progress: 0.75,
                  rotation: _controller.value * 2 * math.pi,
                  color: Theme.of(context).colorScheme.onSurface,
                  strokeWidth: 2.8,
                ),
              ),
            )
              : CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _BlindArcPainter(
                progress: math.min(widget.pullProgress, 1.0) * 0.75,
                rotation: 0,
                color: Theme.of(context).colorScheme.onSurface,
                strokeWidth: 2.8,
              ),
            ),
    );
  }
}

class _BlindArcPainter extends CustomPainter {
  _BlindArcPainter({
    required this.progress,
    required this.rotation,
    required this.color,
    this.strokeWidth = 2.8,
  });

  final double progress;
  final double rotation;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final cx = r;
    final cy = r;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // 원호: 12시 방향부터 시계방향. progress 1.0 = 거의 한 바퀴 (갭 유지)
    const startAngle = -math.pi / 2; // 12시
    final sweepAngle = progress * 2 * math.pi;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r - strokeWidth / 2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation);
    canvas.translate(-cx, -cy);
    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BlindArcPainter old) =>
      old.progress != progress || old.rotation != rotation;
}

/// 블라인드 앱 스타일의 Pull-to-Refresh 인디케이터.
/// 당길수록 회색 직사각형 영역이 커지며, 회색 영역과 게시판이 함께 내려감.
class BlindRefreshIndicator extends StatelessWidget {
  const BlindRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.spinnerOffsetDown = 0.0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  /// 스피너를 아래로 밀어넣을 픽셀. 게시판/글상세 등 레이아웃별로 다른 값 지정 가능.
  final double spinnerOffsetDown;

  static const _minHeight = 30.0;
  static const _maxHeight = 140.0;
  static const _spinnerSize = 22.0;
  /// 회색 영역 안에서 스피너 세로 중앙 (30px 기준)
  static const _spinnerTopPx = 4.0;
  static Color _greyColor(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;
  static const _offsetToArmed = 200.0;
  static const _pullFollowFactor = 0.3;

  @override
  Widget build(BuildContext context) {
    return CustomRefreshIndicator(
      onRefresh: onRefresh,
      offsetToArmed: _offsetToArmed,
      durations: const RefreshIndicatorDurations(
        settleDuration: Duration(milliseconds: 300),
        finalizeDuration: Duration(milliseconds: 300),
        cancelDuration: Duration(milliseconds: 280),
      ),
      builder: (context, child, controller) {
        final isVisible = !controller.isIdle;
        final showMinimal =
            controller.isLoading ||
            controller.isSettling ||
            controller.isComplete ||
            controller.isFinalizing;

        final pullDistance = controller.value * _offsetToArmed;
        final greyHeight = isVisible
            ? (showMinimal
                ? (controller.isFinalizing ? controller.value * _minHeight : _minHeight)
                : math.min(pullDistance * _pullFollowFactor, _maxHeight))
            : 0.0;

        final pullOffset = isVisible
            ? (showMinimal
                ? (controller.isFinalizing ? controller.value * _minHeight : _minHeight)
                : pullDistance * _pullFollowFactor)
            : 0.0;

        // 회색 영역: 항상 최소 높이 보장
        final effectiveGreyHeight = (math.max(greyHeight, greyHeight > 0 ? _minHeight : 0)).toDouble();

        return LayoutBuilder(
          builder: (context, constraints) {
            final greySection = effectiveGreyHeight > 0
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: _minHeight,
                      minWidth: double.infinity,
                    ),
                    child: SizedBox(
                      height: effectiveGreyHeight,
                      width: double.infinity,
                      child: ColoredBox(
                        color: _greyColor(context),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: _spinnerTopPx,
                              child: Center(
                                child: SizedBox(
                                  width: _spinnerSize,
                                  height: _spinnerSize,
                                  child: _BlindStyleSpinner(
                                    isLoading: showMinimal,
                                    pullProgress: math.min(controller.value, 1.0),
                                    size: _spinnerSize,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink();
            final bgColor = Theme.of(context).scaffoldBackgroundColor;
            return SizedBox(
              height: constraints.maxHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  greySection,
                  Expanded(
                    child: ColoredBox(
                      color: bgColor,
                      child: Transform.translate(
                        offset: Offset(0, pullOffset),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}
