import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../widgets/review_body_lines_indicator.dart';
import '../services/drama_list_service.dart';
import '../services/level_service.dart';
import '../services/post_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';

/// 리뷰 작성 바텀시트
class WriteReviewSheet extends StatefulWidget {
  const WriteReviewSheet({
    super.key,
    this.dramaId,
    this.dramaTitle,
    this.editingReviewId,
    this.initialRating,
    this.initialComment,
  });

  final String? dramaId;
  final String? dramaTitle;
  /// 수정 시 `drama_reviews` 문서 id
  final String? editingReviewId;
  final double? initialRating;
  final String? initialComment;

  static Future<void> show(
    BuildContext context, {
    String? dramaId,
    String? dramaTitle,
    String? editingReviewId,
    double? initialRating,
    String? initialComment,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: WriteReviewSheet(
          dramaId: dramaId,
          dramaTitle: dramaTitle,
          editingReviewId: editingReviewId,
          initialRating: initialRating,
          initialComment: initialComment,
        ),
      ),
    );
  }

  @override
  State<WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<WriteReviewSheet>
    with SingleTickerProviderStateMixin {
  late double _rating;
  late final TextEditingController _controller;
  final FocusNode _commentFocus = FocusNode();
  bool _ratingStripFocused = false;

  bool get _isEditMode => widget.editingReviewId != null;
  String? _validationMessage;
  late AnimationController _toastAnimController;
  late Animation<Offset> _toastSlideAnim;
  static const _dismissDuration = Duration(milliseconds: 280);
  static const _toastDisplayDuration = Duration(seconds: 2);
  /// 별점만 있어도 저장 가능 (본문은 선택).
  bool get _canSave => _rating > 0;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating ?? 0;
    _controller = TextEditingController(text: widget.initialComment ?? '');
    _commentFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _toastAnimController = AnimationController(
      vsync: this,
      duration: _dismissDuration,
    );
    _toastSlideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1),
    ).animate(CurvedAnimation(
      parent: _toastAnimController,
      curve: Curves.easeInCubic,
    ));
  }

  @override
  void dispose() {
    _toastAnimController.dispose();
    _commentFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showValidationMessage(String message) {
    _toastAnimController.reset();
    setState(() => _validationMessage = message);
    Future.delayed(_toastDisplayDuration, () {
      if (mounted && _validationMessage != null) _hideValidationMessage();
    });
  }

  void _hideValidationMessage() {
    if (_validationMessage != null && !_toastAnimController.isAnimating) {
      _toastAnimController.forward().then((_) {
        if (mounted) setState(() => _validationMessage = null);
      });
    }
  }

  void _submit() async {
    final s = CountryScope.of(context).strings;
    if (_rating <= 0) {
      _showValidationMessage(s.get('ratingRequired'));
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    final country = CountryScope.maybeOf(context)?.country;
    Navigator.pop(context);

    final dramaId = widget.dramaId;
    final dramaTitle = widget.dramaTitle ?? '';
    if (dramaId != null && dramaId.isNotEmpty) {
      if (_isEditMode) {
        final rid = widget.editingReviewId!;
        await ReviewService.instance.updateById(
          id: rid,
          rating: _rating,
          comment: _controller.text.trim(),
        );
        final item = ReviewService.instance.getById(rid);
        await _syncDiaryAfterReviewSave(
          dramaId: dramaId,
          dramaTitle: dramaTitle,
          rating: _rating,
          comment: _controller.text.trim(),
          country: country,
        );
        await PostService.instance.syncReviewFeedPostFromDramaDetail(
          dramaId: dramaId,
          dramaTitle: dramaTitle,
          rating: _rating,
          comment: _controller.text.trim(),
          reviewsTabLabel: s.get('tabReviews'),
          timeSoonLabel: s.get('soon'),
          existingFeedPostId: item?.feedPostId,
          forceNewPost: false,
        );
      } else {
        final authorName = await UserProfileService.instance.getAuthorBaseName();
        final reviewId = await ReviewService.instance.add(
          dramaId: dramaId,
          dramaTitle: dramaTitle,
          rating: _rating,
          comment: _controller.text.trim(),
          authorName: authorName,
          authorPhotoUrl:
              UserProfileService.instance.profileImageUrlNotifier.value,
        );
        await _syncDiaryAfterReviewSave(
          dramaId: dramaId,
          dramaTitle: dramaTitle,
          rating: _rating,
          comment: _controller.text.trim(),
          country: country,
        );
        final sync = await PostService.instance.syncReviewFeedPostFromDramaDetail(
          dramaId: dramaId,
          dramaTitle: dramaTitle,
          rating: _rating,
          comment: _controller.text.trim(),
          reviewsTabLabel: s.get('tabReviews'),
          timeSoonLabel: s.get('soon'),
          forceNewPost: true,
        );
        final pid = sync.postId;
        if (pid != null && pid.isNotEmpty) {
          await ReviewService.instance.setFeedPostId(
            reviewId: reviewId,
            feedPostId: pid,
          );
        }
        if (sync.createdNewPost) {
          LevelService.instance.addPoints(5);
        }
      }
    }

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          _isEditMode ? s.get('reviewUpdated') : s.get('reviewSubmitted'),
          style: GoogleFonts.notoSansKr(),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.accent,
      ),
    );
  }

  /// 드라마 상세·리뷰 목록에서 리뷰 저장 시 다이어리(시청 기록)에도 같은 작품이 오늘 본 것으로 쌓임.
  Future<void> _syncDiaryAfterReviewSave({
    required String dramaId,
    required String dramaTitle,
    double? rating,
    String? comment,
    String? country,
  }) async {
    var title = dramaTitle.trim();
    if (dramaId.isNotEmpty && !dramaId.startsWith('short-')) {
      final t = DramaListService.instance.getDisplayTitle(dramaId, country);
      if (t.isNotEmpty) title = t;
    } else if (title.isEmpty) {
      final t = DramaListService.instance.getDisplayTitleByTitle(
        dramaTitle,
        country,
      );
      if (t.isNotEmpty) title = t;
    }
    if (title.isEmpty) title = dramaTitle;

    String? imageUrl;
    if (dramaId.isNotEmpty && !dramaId.startsWith('short-')) {
      imageUrl = DramaListService.instance.getDisplayImageUrl(dramaId, country);
    } else {
      imageUrl = DramaListService.instance.getDisplayImageUrlByTitle(
        dramaTitle,
        country,
      );
    }

    var subtitle = '';
    var views = '0';
    if (dramaId.isNotEmpty && !dramaId.startsWith('short-')) {
      subtitle = DramaListService.instance.getDisplaySubtitle(dramaId, country);
      for (final e in DramaListService.instance.listNotifier.value) {
        if (e.id == dramaId) {
          views = e.views;
          break;
        }
      }
    }

    await WatchHistoryService.instance.add(
      id: dramaId,
      title: title,
      subtitle: subtitle,
      views: views,
      imageUrl: imageUrl,
      rating: (rating != null && rating > 0) ? rating : null,
      comment: (comment != null && comment.trim().isNotEmpty) ? comment.trim() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = cs.surfaceContainerHigh;
    final onBg = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final labelLit = onBg.withValues(alpha: 0.9);
    final labelMuted = muted.withValues(alpha: 0.52);
    final iconMuted = muted.withValues(alpha: 0.45);
    final iconLit = labelLit;
    final inputFocusBorder = muted.withValues(alpha: 0.62);
    final tapHighlight = onBg.withValues(alpha: 0.08);
    final headerStarLit = _rating > 0;
    final headerReviewLit =
        _commentFocus.hasFocus || _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _hideValidationMessage();
                Navigator.pop(context);
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _hideValidationMessage(),
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.deferToChild,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 12,
                      bottom: MediaQuery.of(context).viewInsets.bottom +
                          MediaQuery.of(context).padding.bottom +
                          20,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.get('dramaWatchActivitySheetTitle'),
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: labelLit,
                                ),
                              ),
                            ),
                            FilledButton(
                              onPressed: _canSave ? _submit : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.linkBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                              ),
                              child: Text(
                                'Save',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(LucideIcons.eye, size: 28, color: iconLit),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.get('dramaWatchActivityWatchLabel'),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                      color: labelLit,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  splashColor: tapHighlight,
                                  highlightColor: tapHighlight,
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () =>
                                      setState(() => _ratingStripFocused = true),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.star_rounded,
                                          size: 28,
                                          color: headerStarLit
                                              ? iconLit
                                              : iconMuted,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          s.get('dramaWatchActivityHeaderRating'),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: (headerStarLit ||
                                                    _ratingStripFocused)
                                                ? labelLit
                                                : labelMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (_commentFocus.canRequestFocus) {
                                        _commentFocus.requestFocus();
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 28,
                                          child: Center(
                                            child: ReviewBodyLinesIndicator(
                                              color: headerReviewLit
                                                  ? iconLit
                                                  : iconMuted,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          s.get('dramaWatchActivityHeaderReview'),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: headerReviewLit
                                                ? labelLit
                                                : labelMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (i) {
                              const slotW = 30.0;
                              final halfValue = i + 0.5;
                              final fullValue = i + 1.0;
                              final isFull = _rating >= fullValue;
                              final isHalf =
                                  _rating >= halfValue && _rating < fullValue;
                              final emptyOutlineColor =
                                  _ratingStripFocused ? iconLit : iconMuted;
                              return GestureDetector(
                                onTapDown: (d) {
                                  final isLeftHalf = d.localPosition.dx < slotW / 2;
                                  final next =
                                      isLeftHalf ? halfValue : fullValue;
                                  setState(() {
                                    _rating = _rating == next ? 0 : next;
                                    _ratingStripFocused = false;
                                  });
                                },
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  width: slotW,
                                  child: Icon(
                                    isFull
                                        ? Icons.star_rounded
                                        : (isHalf
                                            ? Icons.star_half_rounded
                                            : Icons.star_border_rounded),
                                    size: 30,
                                    color: isFull || isHalf
                                        ? AppColors.ratingStar
                                        : emptyOutlineColor,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _controller,
                          focusNode: _commentFocus,
                          maxLines: 4,
                          cursorColor: inputFocusBorder,
                          style: GoogleFonts.notoSansKr(color: onBg, fontSize: 15),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: inputFocusBorder,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_validationMessage != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: SlideTransition(
                position: _toastSlideAnim,
                child: GestureDetector(
                  onTap: _hideValidationMessage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _validationMessage!,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
