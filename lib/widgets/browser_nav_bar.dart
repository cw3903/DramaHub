import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// 브라우저 스타일 하단 네비게이션 바
/// 왼쪽: 뒤로가기 / 가운데: 새로고침 / 오른쪽: 앞으로가기
class BrowserNavBar extends StatelessWidget {
  const BrowserNavBar({
    super.key,
    required this.onRefresh,
    this.canGoBack = false,
    this.canGoForward = false,
    this.onBack,
    this.onForward,
    this.isRefreshing = false,
  });

  final VoidCallback onRefresh;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: 48 + bottomPadding,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 뒤로가기
            _TextNavButton(
              label: '',
              icon: LucideIcons.chevron_left,
              iconOnLeft: true,
              enabled: canGoBack,
              onTap: canGoBack
                  ? () {
                      HapticFeedback.lightImpact();
                      onBack?.call();
                    }
                  : null,
            ),
            const SizedBox(width: 80),
            // 새로고침 버튼 - 가운데
            _RefreshButton(
              isRefreshing: isRefreshing,
              onTap: () {
                HapticFeedback.lightImpact();
                onRefresh();
              },
            ),
            const SizedBox(width: 80),
            // 앞으로가기
            _TextNavButton(
              label: '',
              icon: LucideIcons.chevron_right,
              iconOnLeft: false,
              enabled: canGoForward,
              onTap: canGoForward
                  ? () {
                      HapticFeedback.lightImpact();
                      onForward?.call();
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TextNavButton extends StatelessWidget {
  const _TextNavButton({
    required this.label,
    required this.icon,
    required this.iconOnLeft,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool iconOnLeft;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = enabled ? cs.onSurface : cs.onSurfaceVariant;
    final iconWidget = Icon(icon, size: 16, color: color);
    final hasLabel = label.isNotEmpty;
    final textWidget = hasLabel
        ? Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          )
        : null;

    // 아이콘만 있을 때(<> 버튼): 새로고침 버튼과 동일한 원형 스타일
    final isIconOnly = !hasLabel;
    final decoration = BoxDecoration(
      color: cs.surface,
      shape: isIconOnly ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: isIconOnly ? null : BorderRadius.circular(20),
      border: Border.all(color: cs.outline, width: 0.8),
      boxShadow: [
        BoxShadow(
          color: cs.shadow.withOpacity(0.10),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: isIconOnly ? 40 : null,
        height: isIconOnly ? 40 : null,
        padding: isIconOnly ? null : EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: decoration,
        child: isIconOnly
            ? Center(child: iconWidget)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: iconOnLeft
                    ? [iconWidget, if (hasLabel) ...[const SizedBox(width: 2), textWidget!]]
                    : [if (hasLabel) ...[textWidget!, const SizedBox(width: 2)], iconWidget],
              ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.isRefreshing, required this.onTap});

  final bool isRefreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.surface,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outline, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: isRefreshing
              ? _SpinningIcon(icon: LucideIcons.rotate_cw, color: cs.onSurface)
              : Icon(LucideIcons.rotate_cw, size: 18, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Icon(widget.icon, size: 18, color: widget.color),
    );
  }
}
