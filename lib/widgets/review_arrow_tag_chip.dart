import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 참고 이미지(화살/책갈피형) 스타일: 왼쪽 둥근 모서리, 오른쪽 뾰족한 끝.
class ReviewArrowTagChip extends StatelessWidget {
  const ReviewArrowTagChip({
    super.key,
    required this.label,
    this.compact = false,
    this.maxLabelWidth = 140,
    this.onRemove,
  });

  final String label;
  final bool compact;
  final double maxLabelWidth;
  /// 지정 시 글자 오른쪽에 X를 두고 탭하면 호출 (피드 등 읽기 전용에서는 null).
  final VoidCallback? onRemove;

  static const _slateBlue = Color(0xFF2C3440);
  static const _textLight = Color(0xFFB8C0CC);

  @override
  Widget build(BuildContext context) {
    final h = compact ? 22.0 : 30.0;
    final fontSize = compact ? 10.0 : 12.0;
    final radius = compact ? 5.0 : 7.0;
    final tip = compact ? 6.0 : 8.0;
    final horizPad = compact ? 7.0 : 11.0;
    final rightPad = onRemove != null
        ? horizPad + tip + (compact ? 2.0 : 4.0)
        : horizPad + tip * 0.4;

    return IntrinsicWidth(
      child: ClipPath(
        clipper: _ArrowTagClipper(radius: radius, tipWidth: tip),
        child: Container(
          height: h,
          padding: EdgeInsets.fromLTRB(horizPad, 0, rightPad, 0),
          color: _slateBlue,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  label.toLowerCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: _textLight,
                    height: 1.0,
                  ),
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 2),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onRemove,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 2 : 4, 0, compact ? 0 : 2, 0),
                      child: Icon(
                        Icons.close_rounded,
                        size: compact ? 13 : 16,
                        color: _textLight.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowTagClipper extends CustomClipper<Path> {
  _ArrowTagClipper({required this.radius, required this.tipWidth});

  final double radius;
  final double tipWidth;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final r = radius.clamp(0.0, h / 2 - 0.01);
    final tw = tipWidth.clamp(2.0, w * 0.45);
    final xBody = w - tw;

    return Path()
      ..moveTo(r, 0)
      ..lineTo(xBody, 0)
      ..lineTo(w, h / 2)
      ..lineTo(xBody, h)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r), clockwise: true)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r), clockwise: true)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ArrowTagClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.tipWidth != tipWidth;
}
