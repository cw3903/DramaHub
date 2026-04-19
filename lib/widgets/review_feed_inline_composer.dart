import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../services/user_profile_service.dart';
import 'optimized_network_image.dart';

/// [DramaReviewsListFeedRow] 펼침 영역·에피 리뷰 스레드 공통 — 아바타 + 알약 입력 + 우측 전송.
class ReviewFeedInlineComposer extends StatelessWidget {
  const ReviewFeedInlineComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.autofocus,
    required this.onSend,
    this.hintText,
    required this.sendSemanticLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final bool autofocus;
  final Future<void> Function() onSend;
  /// null이면 힌트 없음 — [DramaReviewsListFeedRow]와 동일.
  final String? hintText;
  final String sendSemanticLabel;

  static const Color _sendBlue = Color(0xFF0A84FF);

  Widget _defaultAvatar(int colorIdx, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UserProfileService.bgColorFromIndex(colorIdx),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.person,
          size: size * 0.55,
          color: UserProfileService.iconColorFromIndex(colorIdx),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            UserProfileService.instance.profileImageUrlNotifier,
            UserProfileService.instance.avatarColorNotifier,
            controller,
          ]),
          builder: (context, _) {
            final rawUrl = UserProfileService.instance.profileImageUrlNotifier.value;
            final url = rawUrl?.trim();
            final colorIdx = UserProfileService.instance.avatarColorNotifier.value ?? 0;
            const avatarSize = kAppUnifiedProfileAvatarSize;
            final Widget avatar = (url != null && url.isNotEmpty)
                ? ClipOval(
                    child: OptimizedNetworkImage.avatar(
                      imageUrl: url,
                      size: avatarSize,
                      errorWidget: _defaultAvatar(colorIdx, avatarSize),
                    ),
                  )
                : _defaultAvatar(colorIdx, avatarSize);
            final canSend = !isSubmitting && controller.text.trim().isNotEmpty;
            final sendBg = canSend ? _sendBlue : cs.onSurface.withValues(alpha: 0.22);
            final sendIconColor = canSend ? Colors.white : cs.onSurface.withValues(alpha: 0.38);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                avatar,
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    minLines: 1,
                    maxLines: 6,
                    style: GoogleFonts.notoSansKr(fontSize: 14, height: 1.32),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: hintText != null
                          ? GoogleFonts.notoSansKr(
                              fontSize: 14,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                            )
                          : null,
                      filled: true,
                      fillColor: theme.brightness == Brightness.dark
                          ? cs.surfaceContainerHigh
                          : cs.surface,
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.28),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.28),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.45),
                        ),
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
                        child: Material(
                          color: sendBg,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: (!canSend || isSubmitting)
                                ? null
                                : () async {
                                    // [unawaited]는 연속 탭 시 [onSend]가 겹쳐 스레드 답글 등이 이중 전송·실패할 수 있음.
                                    await onSend();
                                  },
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: Center(
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        Icons.arrow_upward,
                                        color: sendIconColor,
                                        size: 17,
                                        semanticLabel: sendSemanticLabel,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 36,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
