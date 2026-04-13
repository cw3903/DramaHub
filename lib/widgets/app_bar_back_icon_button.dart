import 'package:flutter/material.dart';

/// Favorites 상단 등과 동일한 `<` 뒤로가기 — 크기·패딩·터치 영역 통일.
class AppBarBackIconButton extends StatelessWidget {
  const AppBarBackIconButton({
    super.key,
    required this.onPressed,
    this.iconColor,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final Color? iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? IconTheme.of(context).color;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(Icons.arrow_back_ios_new, size: 15, color: color),
      iconSize: 15,
      padding: const EdgeInsetsDirectional.only(start: 10),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
      onPressed: onPressed,
    );
  }
}
