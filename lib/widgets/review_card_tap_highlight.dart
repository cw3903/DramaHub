import 'package:flutter/material.dart';

/// [ReviewCardTapHighlight] 내부에서 특정 자식이 눌렸을 때 상위 탭을 무시하기 위한 스코프.
class ReviewCardTapSuppressInherited extends InheritedWidget {
  const ReviewCardTapSuppressInherited({
    required this.onPress,
    required super.child,
    super.key,
  });

  final VoidCallback onPress;

  static ReviewCardTapSuppressInherited? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReviewCardTapSuppressInherited>();

  @override
  bool updateShouldNotify(ReviewCardTapSuppressInherited old) => false;
}

/// 하트·프로필 등 — 부모 [ReviewCardTapHighlight]의 탭이 겹치지 않게 한다.
class ReviewCardSuppressParentTap extends StatelessWidget {
  const ReviewCardSuppressParentTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = ReviewCardTapSuppressInherited.maybeOf(context);
    if (scope == null) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => scope.onPress(),
      child: child,
    );
  }
}

/// 카드 빈 곳 탭 → 댓글 펼침 등. [ReviewCardSuppressParentTap]으로 예외 영역을 감싼다.
class ReviewCardTapHighlight extends StatefulWidget {
  const ReviewCardTapHighlight({
    super.key,
    required this.onTap,
    required this.pressColor,
    required this.child,
  });

  final VoidCallback onTap;
  final Color pressColor;
  final Widget child;

  @override
  State<ReviewCardTapHighlight> createState() => _ReviewCardTapHighlightState();
}

class _ReviewCardTapHighlightState extends State<ReviewCardTapHighlight> {
  bool _pressed = false;
  bool _suppressed = false;
  Offset? _downPosition;

  void _suppress() => _suppressed = true;

  @override
  Widget build(BuildContext context) {
    return ReviewCardTapSuppressInherited(
      onPress: _suppress,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _downPosition = e.localPosition;
          setState(() => _pressed = true);
        },
        onPointerUp: (e) {
          final down = _downPosition;
          final wasPressed = _pressed;
          final wasSuppressed = _suppressed;
          setState(() {
            _pressed = false;
            _suppressed = false;
          });
          _downPosition = null;
          if (wasPressed && !wasSuppressed && down != null) {
            final dist = (e.localPosition - down).distance;
            if (dist < 18) widget.onTap();
          }
        },
        onPointerCancel: (_) {
          setState(() {
            _pressed = false;
            _suppressed = false;
          });
          _downPosition = null;
        },
        child: ColoredBox(
          color: (_pressed && !_suppressed)
              ? widget.pressColor
              : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}
