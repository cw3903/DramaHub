import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 삭제 액션 라벨·아이콘 색 — 리뷰 Letterboxd 인라인 삭제와 동일.
const Color kAppDeleteActionColor = Colors.redAccent;

/// 삭제 확인 모달 — 리뷰 게시판 Letterboxd 타일과 동일 UX.
Future<bool?> showAppDeleteConfirmDialog(
  BuildContext context, {
  required String message,
  required String cancelText,
  required String confirmText,
}) {
  final barrierLabel =
      MaterialLocalizations.of(context).modalBarrierDismissLabel;
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: Duration.zero,
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final theme = Theme.of(dialogContext);
      final cs = theme.colorScheme;
      final gray = cs.onSurfaceVariant;
      final bg =
          theme.dialogTheme.backgroundColor ?? cs.surfaceContainerHighest;
      final btnStyleBase = TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
      return AlertDialog(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.35,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  style: btnStyleBase.copyWith(
                    foregroundColor: WidgetStatePropertyAll(gray),
                  ),
                  child: Text(
                    cancelText,
                    style: GoogleFonts.notoSansKr(color: gray),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: btnStyleBase.copyWith(
                    foregroundColor:
                        const WidgetStatePropertyAll(kAppDeleteActionColor),
                  ),
                  child: Text(
                    confirmText,
                    style: GoogleFonts.notoSansKr(
                      color: kAppDeleteActionColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
