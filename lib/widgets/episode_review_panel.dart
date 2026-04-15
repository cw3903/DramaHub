import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/episode_rating_service.dart';
import '../services/episode_review_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'optimized_network_image.dart';
import 'user_profile_nav.dart';
import 'app_delete_confirm_dialog.dart';

/// 각 화 별점 없을 때 별·숫자 색 (회색으로 통일)
Color episodeNoRatingColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : AppColors.mediumGrey;
}

/// 회차 클릭 시 리뷰·댓글 목록 + 입력 (상세 페이지 인라인 또는 전체 화면).
class EpisodeReviewPanel extends StatefulWidget {
  const EpisodeReviewPanel({
    super.key,
    required this.dramaId,
    required this.episodeNumber,
    required this.onClose,
    required this.strings,
    this.showCloseButton = true,
  });

  final String dramaId;
  final int episodeNumber;
  final VoidCallback onClose;
  final dynamic strings;
  /// 전체 화면에서는 AppBar 뒤로가기만 쓰고 패널 우측 X 숨김.
  final bool showCloseButton;

  @override
  State<EpisodeReviewPanel> createState() => _EpisodeReviewPanelState();
}

class _EpisodeReviewPanelState extends State<EpisodeReviewPanel> {
  final _commentController = TextEditingController();
  double _reviewRating = 0;
  String? _editingReviewId;

  @override
  void initState() {
    super.initState();
    EpisodeRatingService.instance.loadEpisodeAverageRatings(widget.dramaId);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([
                  EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId),
                  EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId),
                ]),
                builder: (context, _) {
                  final averageRatings =
                      EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId).value;
                  final countMap =
                      EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId).value;
                  final count = countMap[widget.episodeNumber] ?? 0;
                  final avg = averageRatings[widget.episodeNumber] ?? 0.0;
                  final hasRating = avg > 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.strings.get('episodeLabel').replaceAll('%d', '${widget.episodeNumber}'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: hasRating ? AppColors.ratingStar : episodeNoRatingColor(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasRating ? avg.toStringAsFixed(1) : '0',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: hasRating
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : cs.onSurface)
                              : episodeNoRatingColor(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.strings.get('episodeReviewRaterCount').replaceAll('%d', '$count'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (widget.showCloseButton)
                IconButton(
                  icon: Icon(LucideIcons.x, size: 20, color: cs.onSurfaceVariant),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    widget.onClose();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<List<EpisodeReviewItem>>(
            valueListenable:
                EpisodeReviewService.instance.getNotifierForEpisode(widget.dramaId, widget.episodeNumber),
            builder: (context, list, _) {
              return Container(
                constraints: const BoxConstraints(minHeight: 80),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outline.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (list.isEmpty)
                      Text(
                        widget.strings.get('firstReview'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else ...[
                      ...list.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: EpisodeReviewCard(
                              item: r,
                              dramaId: widget.dramaId,
                              episodeNumber: widget.episodeNumber,
                              strings: widget.strings,
                              onEdit: (rev) {
                                setState(() {
                                  _editingReviewId = rev.id;
                                  _commentController.text = rev.comment;
                                  _reviewRating = rev.rating ?? 0;
                                });
                              },
                              onDelete: (reviewId) async {
                                await EpisodeReviewService.instance
                                    .deleteById(widget.dramaId, widget.episodeNumber, reviewId);
                                setState(() {});
                              },
                            ),
                          )),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(5, (i) {
                        final r = _reviewRating;
                        final full = r >= i + 1;
                        final half = r >= i + 0.5 && r < i + 1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  full
                                      ? Icons.star_rounded
                                      : (half ? Icons.star_half_rounded : Icons.star_border_rounded),
                                  size: 28,
                                  color: (full || half) ? AppColors.ratingStar : cs.onSurfaceVariant,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => setState(() => _reviewRating = i + 0.5),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => setState(() => _reviewRating = i + 1.0),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    EpisodeReviewInput(
                      dramaId: widget.dramaId,
                      episodeNumber: widget.episodeNumber,
                      controller: _commentController,
                      strings: widget.strings,
                      rating: _reviewRating > 0 ? _reviewRating : null,
                      editingReviewId: _editingReviewId,
                      onSubmitted: () {
                        setState(() {
                          _reviewRating = 0;
                          _editingReviewId = null;
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class EpisodeReviewCard extends StatelessWidget {
  const EpisodeReviewCard({
    super.key,
    required this.item,
    required this.dramaId,
    required this.episodeNumber,
    required this.strings,
    required this.onEdit,
    required this.onDelete,
  });

  final EpisodeReviewItem item;
  final String dramaId;
  final int episodeNumber;
  final dynamic strings;
  final ValueChanged<EpisodeReviewItem> onEdit;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUid = AuthService.instance.currentUser.value?.uid;
    final isMine = currentUid != null && item.uid == currentUid;

    Widget avatar;
    if (item.authorPhotoUrl != null && item.authorPhotoUrl!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: 14,
        backgroundColor: cs.surfaceContainerHighest,
        child: ClipOval(
          child: OptimizedNetworkImage(
            imageUrl: item.authorPhotoUrl!,
            fit: BoxFit.cover,
            width: 28,
            height: 28,
          ),
        ),
      );
    } else {
      final colorIdx = item.authorAvatarColorIndex ?? 0;
      final bg = UserProfileService.bgColorFromIndex(colorIdx);
      final iconColor = UserProfileService.iconColorFromIndex(colorIdx);
      avatar = CircleAvatar(
        radius: 14,
        backgroundColor: bg,
        child: Icon(Icons.person, size: 16, color: iconColor),
      );
    }
    avatar = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfileFromAuthorUid(context, item.uid),
      child: avatar,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        openUserProfileFromAuthorUid(context, item.uid),
                    child: Text(
                      item.authorName,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (item.rating != null && item.rating! > 0) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.star_rounded, size: 14, color: AppColors.ratingStar),
                    const SizedBox(width: 2),
                    Text(
                      item.rating!.toStringAsFixed(1),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text(
                    item.timeAgo,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (isMine) ...[
                    const Spacer(),
                    TextButton(
                      onPressed: () => onEdit(item),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '수정',
                        style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await showAppDeleteConfirmDialog(
                          context,
                          message: strings.get('deletePostConfirm'),
                          cancelText: strings.get('cancel'),
                          confirmText: strings.get('delete'),
                        );
                        if (ok == true) onDelete(item.id);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        strings.get('delete'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kAppDeleteActionColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.comment,
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    onTap: () => HapticFeedback.lightImpact(),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.favorite_border, size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '0',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  InkWell(
                    onTap: () => HapticFeedback.lightImpact(),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.message_circle,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '0',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EpisodeReviewInput extends StatefulWidget {
  const EpisodeReviewInput({
    super.key,
    required this.dramaId,
    required this.episodeNumber,
    required this.controller,
    required this.strings,
    required this.onSubmitted,
    this.rating,
    this.editingReviewId,
  });

  final String dramaId;
  final int episodeNumber;
  final TextEditingController controller;
  final dynamic strings;
  final VoidCallback onSubmitted;
  final double? rating;
  final String? editingReviewId;

  @override
  State<EpisodeReviewInput> createState() => _EpisodeReviewInputState();
}

class _EpisodeReviewInputState extends State<EpisodeReviewInput> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant EpisodeReviewInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final hasRating = widget.rating != null && widget.rating! > 0;
    final canSubmit = hasText && hasRating;
    final borderColor = cs.outline.withValues(alpha: 0.4);
    final radius = BorderRadius.circular(8);
    return SizedBox(
      height: 72,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          TextField(
            focusNode: _focusNode,
            onTapOutside: (_) => _focusNode.unfocus(),
            controller: widget.controller,
            decoration: InputDecoration(
              hintText: widget.strings.get('reviewPlaceholder'),
              hintStyle: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant),
              filled: true,
              fillColor: cs.surface,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(8, 12, 44, 12),
              border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
            ),
            style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurface),
            maxLines: 3,
            textAlignVertical: TextAlignVertical.top,
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton(
              onPressed: canSubmit
                  ? () async {
                      final text = widget.controller.text.trim();
                      final rating = widget.rating;
                      if (text.isEmpty || rating == null || rating <= 0) return;
                      final id = widget.editingReviewId;
                      if (id != null && id.isNotEmpty) {
                        await EpisodeReviewService.instance.update(
                          id: id,
                          dramaId: widget.dramaId,
                          episodeNumber: widget.episodeNumber,
                          comment: text,
                          rating: rating,
                        );
                      } else {
                        final err = await EpisodeReviewService.instance.add(
                          dramaId: widget.dramaId,
                          episodeNumber: widget.episodeNumber,
                          comment: text,
                          rating: rating,
                        );
                        if (!context.mounted) return;
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(widget.strings.get(err), style: GoogleFonts.notoSansKr()),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                      }
                      if (!context.mounted) return;
                      widget.controller.clear();
                      widget.onSubmitted();
                    }
                  : null,
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: canSubmit ? AppColors.accent : cs.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(32, 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
