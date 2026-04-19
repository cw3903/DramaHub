import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import 'user_profile_nav.dart';

Widget _reviewFeedCommentAuthorNameLine({
  required BuildContext context,
  required String? authorUid,
  required String authorText,
  required TextStyle authorLineStyle,
}) {
  final uid = authorUid?.trim();
  final textWidget = Text(
    authorText,
    style: authorLineStyle,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
  if (uid == null || uid.isEmpty) return textWidget;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => openUserProfileFromAuthorUid(context, uid),
    child: textWidget,
  );
}

/// [DramaReviewsListFeedRow] `_commentRow`와 동일한 레이아웃·색·픽셀 배치.
///
/// 화살표 → 아바타 → 닉·본문·Reply → 오른쪽 하트·카운트.
class ReviewFeedCommentRow extends StatelessWidget {
  const ReviewFeedCommentRow({
    super.key,
    required this.colorScheme,
    required this.depth,
    required this.showReplyIcon,
    required this.authorName,
    required this.comment,
    required this.avatar,
    required this.likeCount,
    required this.isLiked,
    required this.onReplyTap,
    required this.replyLabel,
    this.onLikeTap,
    this.authorUid,
  });

  final ColorScheme colorScheme;
  final int depth;
  final bool showReplyIcon;
  final String authorName;
  /// 비어 있지 않으면 닉네임 탭 시 프로필로 이동.
  final String? authorUid;
  final String comment;
  final Widget avatar;
  final int likeCount;
  final bool isLiked;
  final VoidCallback onReplyTap;
  final String replyLabel;
  final VoidCallback? onLikeTap;

  bool get _isReply => depth > 0;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final isReply = _isReply;
    final metaColor = cs.onSurface.withValues(alpha: 0.44);
    final bodyFontSize = isReply ? 12.0 : 13.0;
    final bodyTextStyle = GoogleFonts.notoSansKr(
      fontSize: bodyFontSize,
      color: cs.onSurface,
      height: 1.38,
    );
    const talkAskBodyTextHeightBehavior = TextHeightBehavior(
      applyHeightToLastDescent: false,
    );
    final replyStyle = appUnifiedNicknameStyle(cs).copyWith(
      fontWeight: FontWeight.w500,
      color: cs.onSurface.withValues(alpha: 0.30),
      height: 1.2,
    );
    final countStyle = appUnifiedNicknameStyle(cs).copyWith(
      fontWeight: FontWeight.w500,
      color: isLiked ? Colors.redAccent : metaColor,
      height: 1.2,
    );

    const talkAskLikeColW = 40.0;
    const talkAskLikeCountDownNudge = 1.0;
    const talkAskBodyVisualUpNudge = 1.5;
    const heartIconSize = 16.0;
    const heartVPad = 4.0;
    final heartBlockH = heartVPad + heartIconSize + heartVPad;
    const gapNameToBody = 1.0;
    const bodyMicroUpPx = 1.0;
    final gapTalkAskNameBodyReply = gapNameToBody - bodyMicroUpPx;

    Widget heartHitTarget() {
      final icon = Padding(
        padding: const EdgeInsets.symmetric(vertical: heartVPad),
        child: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          size: heartIconSize,
          color: isLiked ? Colors.redAccent : metaColor,
        ),
      );
      final tap = onLikeTap;
      if (tap == null) {
        return icon;
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: icon,
      );
    }

    const replyArrowW = 18.0;
    const avatarSize = kAppUnifiedProfileAvatarSize;
    final commentBody = LayoutBuilder(
      builder: (context, cons) {
        final innerMaxW = cons.maxWidth;
        final textColumnMaxW =
            (innerMaxW -
                    avatarSize -
                    8 -
                    talkAskLikeColW -
                    ((isReply || showReplyIcon) ? replyArrowW : 0.0))
                .clamp(1.0, 9999.0);
        final textScaler = MediaQuery.textScalerOf(context);
        final textDir = Directionality.of(context);

        final authorLineStyle = appUnifiedNicknameStyle(cs);
        final authorText = authorName.trim().isEmpty ? ' ' : authorName.trim();

        final tpAuthorLine = TextPainter(
          text: TextSpan(
            text: authorText,
            style: authorLineStyle,
          ),
          textDirection: textDir,
          maxLines: 1,
          textScaler: textScaler,
        )..layout(maxWidth: textColumnMaxW);
        final nameBlockH = tpAuthorLine.height;

        final tpReply = TextPainter(
          text: TextSpan(text: replyLabel, style: replyStyle),
          textDirection: textDir,
          maxLines: 1,
          textScaler: textScaler,
        )..layout();
        final replyRowH = math.max(tpReply.height + 2.0, 18.0);

        final tpCountSlot = TextPainter(
          text: TextSpan(
            text: '0',
            style: appUnifiedNicknameStyle(cs).copyWith(
              fontWeight: FontWeight.w500,
              color: metaColor,
              height: 1.2,
            ),
          ),
          textDirection: textDir,
          maxLines: 1,
          textScaler: textScaler,
        )..layout();
        final countSlotH = tpCountSlot.height;

        final yBodyTop = nameBlockH + gapTalkAskNameBodyReply;
        final hasText = comment.trim().isNotEmpty;

        double bodyH = 0;
        List<LineMetrics>? bodyLineMetrics;
        if (hasText) {
          final tpBody = TextPainter(
            text: TextSpan(text: comment, style: bodyTextStyle),
            textDirection: textDir,
            maxLines: null,
            textScaler: textScaler,
            textHeightBehavior: talkAskBodyTextHeightBehavior,
          )..layout(maxWidth: textColumnMaxW);
          bodyH = tpBody.height;
          bodyLineMetrics = tpBody.computeLineMetrics();
        }

        double countH = countSlotH;
        if (likeCount > 0) {
          final tpC = TextPainter(
            text: TextSpan(
              text: formatCompactCount(likeCount),
              style: countStyle,
            ),
            textDirection: textDir,
            maxLines: 1,
            textScaler: textScaler,
          )..layout();
          countH = math.max(countSlotH, tpC.height);
        }

        final double heartTop;
        final double countTop;
        final double replyRowTop;

        if (hasText && bodyH > 0 && bodyLineMetrics != null) {
          final lines = bodyLineMetrics;
          if (lines.length >= 2) {
            final h0 = lines[0].height;
            final h1 = lines[1].height;
            final line0CenterY = yBodyTop + h0 / 2;
            final line1CenterY = yBodyTop + h0 + h1 / 2;
            heartTop = line0CenterY - heartBlockH / 2;
            countTop =
                line1CenterY - countH / 2 + talkAskLikeCountDownNudge;
            replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
          } else {
            replyRowTop = yBodyTop + bodyH + gapTalkAskNameBodyReply;
            heartTop = yBodyTop + bodyH / 2 - heartBlockH / 2;
            final countCenterY = replyRowTop + replyRowH / 2;
            final ct =
                countCenterY - countH / 2 + talkAskLikeCountDownNudge;
            final replyBandMin = replyRowTop;
            final replyBandMax = replyRowTop + replyRowH - countH;
            countTop = replyBandMax >= replyBandMin
                ? ct.clamp(replyBandMin, replyBandMax)
                : replyBandMin;
          }
        } else {
          replyRowTop =
              hasText ? yBodyTop + bodyH + gapTalkAskNameBodyReply : yBodyTop;
          heartTop = yBodyTop + replyRowH / 2 - heartBlockH / 2;
          final countCenterY = replyRowTop + replyRowH / 2;
          final ct =
              countCenterY - countH / 2 + talkAskLikeCountDownNudge;
          final replyBandMin = replyRowTop;
          final replyBandMax = replyRowTop + replyRowH - countH;
          countTop = replyBandMax >= replyBandMin
              ? ct.clamp(replyBandMin, replyBandMax)
              : replyBandMin;
        }

        final contentBottom = math.max(
          hasText
              ? yBodyTop + bodyH + gapTalkAskNameBodyReply
              : replyRowTop,
          replyRowTop + replyRowH,
        );
        var stackH = math.max(
          contentBottom,
          math.max(heartTop + heartBlockH, countTop + countH),
        );
        stackH = math.max(stackH, avatarSize.toDouble());

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isReply || showReplyIcon) ...[
              Padding(
                padding: EdgeInsets.only(
                  left: showReplyIcon && !isReply ? 2 : 0,
                  top: 2,
                ),
                child: Transform.rotate(
                  angle: math.pi,
                  child: Icon(
                    LucideIcons.reply,
                    size: 14,
                    color: metaColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            avatar,
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: stackH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: talkAskLikeColW,
                      top: 0,
                      child: Transform.translate(
                        offset: const Offset(0, -1.5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: _reviewFeedCommentAuthorNameLine(
                                context: context,
                                authorUid: authorUid,
                                authorText: authorText,
                                authorLineStyle: authorLineStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (hasText)
                      Positioned(
                        left: 0,
                        right: talkAskLikeColW,
                        top: yBodyTop,
                        child: Transform.translate(
                          offset: const Offset(0, -talkAskBodyVisualUpNudge),
                          child: Text(
                            comment,
                            style: bodyTextStyle,
                            textHeightBehavior: talkAskBodyTextHeightBehavior,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: talkAskLikeColW,
                      top: replyRowTop,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onReplyTap,
                        child: Text(replyLabel, style: replyStyle),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: heartTop,
                      width: talkAskLikeColW,
                      height: heartBlockH,
                      child: Center(child: heartHitTarget()),
                    ),
                    Positioned(
                      right: 0,
                      top: countTop,
                      width: talkAskLikeColW,
                      height: countH,
                      child: Center(
                        child: likeCount > 0
                            ? Text(
                                formatCompactCount(likeCount),
                                textAlign: TextAlign.center,
                                style: countStyle,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!isReply) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: commentBody,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: commentBody,
    );
  }
}
