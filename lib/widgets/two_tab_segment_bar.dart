import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 즐겨찾기 활동(리뷰/다이어리)과 동일한 2칸 세그먼트 — 트랙 안 칩, 28px 높이, 좌우 16·상 10·하 4 패딩.
class TwoTabSegmentBar extends StatelessWidget {
  const TwoTabSegmentBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.labelLeft,
    required this.labelRight,
    required this.colorScheme,
    required this.brightness,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String labelLeft;
  final String labelRight;
  final ColorScheme colorScheme;
  final Brightness brightness;

  static const double segmentTrackRadius = 7;
  static const double innerCornerRadius = 6;
  static const Color trackDark = Color(0xFF1C1C1E);
  static const Color trackBorderDark = Color(0xFF2C2C2E);
  static const Color selectedBlueGray = Color(0xFF5D6D7E);
  static const double barHeight = 28;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final trackBg = brightness == Brightness.dark
        ? trackDark
        : cs.surfaceContainerHighest.withValues(alpha: 0.92);
    final trackBorder = brightness == Brightness.dark
        ? trackBorderDark
        : cs.outline.withValues(alpha: 0.22);
    final selectedBg = brightness == Brightness.dark
        ? selectedBlueGray
        : Color.lerp(selectedBlueGray, cs.surface, 0.25) ?? selectedBlueGray;
    final dimLabel = brightness == Brightness.dark
        ? const Color(0xFF8E8E93)
        : cs.onSurfaceVariant.withValues(alpha: 0.72);

    BorderRadius chipRadius(bool on, int index) {
      if (!on) return BorderRadius.zero;
      if (index == 0) {
        return const BorderRadius.only(
          topLeft: Radius.circular(innerCornerRadius),
          bottomLeft: Radius.circular(innerCornerRadius),
        );
      }
      return const BorderRadius.only(
        topRight: Radius.circular(innerCornerRadius),
        bottomRight: Radius.circular(innerCornerRadius),
      );
    }

    Widget chip(String label, int index) {
      final on = selectedIndex == index;
      final radius = chipRadius(on, index);
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? selectedBg : Colors.transparent,
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(index),
              borderRadius: radius,
              splashColor: cs.primary.withValues(alpha: 0.1),
              highlightColor: Colors.transparent,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    height: 1,
                    fontWeight: on ? FontWeight.w900 : FontWeight.w800,
                    color: on ? Colors.white : dimLabel,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: SizedBox(
        height: barHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: trackBg,
            borderRadius: BorderRadius.circular(segmentTrackRadius),
            border: Border.all(color: trackBorder, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(segmentTrackRadius),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [chip(labelLeft, 0), chip(labelRight, 1)],
            ),
          ),
        ),
      ),
    );
  }
}

/// [TwoTabSegmentBar]와 동일 트랙 스타일 — 3칩(Posts / Reviews / Comments 등).
class ThreeTabSegmentBar extends StatelessWidget {
  const ThreeTabSegmentBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.labelLeft,
    required this.labelMiddle,
    required this.labelRight,
    required this.colorScheme,
    required this.brightness,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String labelLeft;
  final String labelMiddle;
  final String labelRight;
  final ColorScheme colorScheme;
  final Brightness brightness;

  static const double segmentTrackRadius = TwoTabSegmentBar.segmentTrackRadius;
  static const double innerCornerRadius = TwoTabSegmentBar.innerCornerRadius;
  static const Color trackDark = TwoTabSegmentBar.trackDark;
  static const Color trackBorderDark = TwoTabSegmentBar.trackBorderDark;
  static const Color selectedBlueGray = TwoTabSegmentBar.selectedBlueGray;
  static const double barHeight = TwoTabSegmentBar.barHeight;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final trackBg = brightness == Brightness.dark
        ? trackDark
        : cs.surfaceContainerHighest.withValues(alpha: 0.92);
    final trackBorder = brightness == Brightness.dark
        ? trackBorderDark
        : cs.outline.withValues(alpha: 0.22);
    final selectedBg = brightness == Brightness.dark
        ? selectedBlueGray
        : Color.lerp(selectedBlueGray, cs.surface, 0.25) ?? selectedBlueGray;
    final dimLabel = brightness == Brightness.dark
        ? const Color(0xFF8E8E93)
        : cs.onSurfaceVariant.withValues(alpha: 0.72);

    BorderRadius chipRadius(bool on, int index) {
      if (!on) return BorderRadius.zero;
      if (index == 0) {
        return const BorderRadius.only(
          topLeft: Radius.circular(innerCornerRadius),
          bottomLeft: Radius.circular(innerCornerRadius),
        );
      }
      if (index == 2) {
        return const BorderRadius.only(
          topRight: Radius.circular(innerCornerRadius),
          bottomRight: Radius.circular(innerCornerRadius),
        );
      }
      return BorderRadius.zero;
    }

    Widget chip(String label, int index) {
      final on = selectedIndex == index;
      final radius = chipRadius(on, index);
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? selectedBg : Colors.transparent,
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(index),
              borderRadius: radius,
              splashColor: cs.primary.withValues(alpha: 0.1),
              highlightColor: Colors.transparent,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    height: 1,
                    fontWeight: on ? FontWeight.w900 : FontWeight.w800,
                    color: on ? Colors.white : dimLabel,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: SizedBox(
        height: barHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: trackBg,
            borderRadius: BorderRadius.circular(segmentTrackRadius),
            border: Border.all(color: trackBorder, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(segmentTrackRadius),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chip(labelLeft, 0),
                chip(labelMiddle, 1),
                chip(labelRight, 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
