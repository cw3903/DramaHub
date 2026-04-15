import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 참고 이미지(화살/책갈피형) 스타일: 왼쪽 둥근 모서리, 오른쪽 뾰족한 끝.
class ReviewArrowTagChip extends StatelessWidget {
  const ReviewArrowTagChip({
    super.key,
    required this.label,
    this.compact = false,
    /// [compact]보다 우선. 지정 시 **높이만** 바꿈(글자·모서리·화살·가로 패딩은 30px 칩과 동일).
    this.height,
    this.maxLabelWidth = 140,
    this.onRemove,
    /// 피드 등에서 탭 시 (예: 통합 검색). [onRemove]와 동시 사용하지 않음.
    this.onTap,
  });

  final String label;
  final bool compact;
  /// null이면 [compact]에 따라 19 또는 30. 지정 시 높이만 바뀜(비율 축소 없음).
  final double? height;
  final double maxLabelWidth;
  /// 지정 시 글자 오른쪽에 X를 두고 탭하면 호출 (피드 등 읽기 전용에서는 null).
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  static const _slateBlue = Color(0xFF2C3440);
  static const _textLight = Color(0xFFB8C0CC);

  @override
  Widget build(BuildContext context) {
    final double h;
    final double fontSize;
    final double radius;
    final double tip;
    final double horizPad;
    final bool tightClose;

    if (height != null) {
      h = height!.clamp(16.0, 30.0);
      fontSize = 12.0;
      radius = 7.0;
      tip = 8.0;
      horizPad = 11.0;
      tightClose = false;
    } else if (compact) {
      h = 19.0;
      fontSize = 10.0;
      radius = 5.0;
      tip = 6.0;
      horizPad = 7.0;
      tightClose = true;
    } else {
      h = 30.0;
      fontSize = 12.0;
      radius = 7.0;
      tip = 8.0;
      horizPad = 11.0;
      tightClose = false;
    }

    final rightPad = onRemove != null
        ? horizPad + tip + (tightClose ? 2.0 : 4.0)
        : horizPad + tip * 0.4;

    final chip = IntrinsicWidth(
      child: ClipPath(
        clipper: _ArrowTagClipper(radius: radius, tipWidth: tip),
        child: Container(
          height: h,
          padding: EdgeInsets.fromLTRB(horizPad, 0, rightPad, 0),
          color: _slateBlue,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
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
                      padding: EdgeInsets.fromLTRB(tightClose ? 2 : 4, 0, tightClose ? 0 : 2, 0),
                      child: Icon(
                        Icons.close_rounded,
                        size: tightClose ? 13 : 16,
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

    if (onTap != null) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.14),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(radius),
          canRequestFocus: false,
          child: chip,
        ),
      );
    }
    return chip;
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
