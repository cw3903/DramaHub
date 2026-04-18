import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/post_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';
import '../theme/app_theme.dart';
import '../screens/login_page.dart';
import 'app_delete_confirm_dialog.dart';
import 'country_scope.dart';
import 'review_body_lines_indicator.dart';

/// 드라마 상세 Watch 화면 `+` — 시청(필수) + 별·리뷰(선택) 후 피드 글 생성.
class DramaWatchActivitySheet extends StatefulWidget {
  const DramaWatchActivitySheet({
    super.key,
    required this.dramaId,
    required this.dramaTitle,
    required this.dramaItem,
  });

  final String dramaId;
  final String dramaTitle;
  final DramaItem dramaItem;

  static Future<bool?> show(
    BuildContext context, {
    required String dramaId,
    required String dramaTitle,
    required DramaItem dramaItem,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DramaWatchActivitySheet(
          dramaId: dramaId,
          dramaTitle: dramaTitle,
          dramaItem: dramaItem,
        ),
      ),
    );
  }

  @override
  State<DramaWatchActivitySheet> createState() =>
      _DramaWatchActivitySheetState();
}

class _DramaWatchActivitySheetState extends State<DramaWatchActivitySheet> {
  double _rating = 0;
  final TextEditingController _comment = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  bool _submitting = false;
  bool _confirmingClose = false;
  /// 아래 별 5개 행에 포커스(테두리) — 중앙 헤더 별 탭 시 true.
  bool _ratingStripFocused = false;
  int _ordinal = 1;

  @override
  void initState() {
    super.initState();
    _commentFocus.addListener(_onCommentFocusChanged);
    _comment.addListener(() {
      if (mounted) setState(() {});
    });
    WatchHistoryService.instance.loadIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrdinal());
  }

  void _onCommentFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOrdinal() async {
    final uid = (AuthService.instance.currentUser.value?.uid ?? '').trim();
    if (uid.isEmpty) {
      if (mounted) setState(() => _ordinal = 1);
      return;
    }
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    try {
      final list = await ReviewService.instance.getDramaReviews(
        widget.dramaId,
        country: country,
      );
      if (!mounted) return;
      final myCount = list.where((r) => r.authorUid?.trim() == uid).length;
      setState(() => _ordinal = myCount + 1);
    } catch (_) {
      if (mounted) setState(() => _ordinal = 1);
    }
  }

  @override
  void dispose() {
    _commentFocus.removeListener(_onCommentFocusChanged);
    _commentFocus.dispose();
    _comment.dispose();
    super.dispose();
  }

  String _ordinalLabel(dynamic s) {
    if (_ordinal <= 1) return s.get('dramaWatchActivityWatchOrdinal1');
    if (_ordinal == 2) return s.get('dramaWatchActivityWatchOrdinal2');
    if (_ordinal == 3) return s.get('dramaWatchActivityWatchOrdinal3');
    return s
        .get('dramaWatchActivityWatchOrdinalN')
        .replaceAll('{n}', '$_ordinal');
  }

  bool get _hasData => _rating > 0 || _comment.text.trim().isNotEmpty;

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasData) return true;
    if (_confirmingClose) return false;
    _confirmingClose = true;
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Discard entry?',
          style: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Discard entry',
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kAppDeleteActionColor,
              ),
            ),
          ),
        ],
      ),
    );
    _confirmingClose = false;
    return confirmed == true;
  }

  Future<bool> _onWillPop() async {
    if (_submitting) return false;
    return _confirmDiscardIfNeeded();
  }

  Future<void> _submit() async {
    final s = CountryScope.of(context).strings;
    final trimmed = _comment.text.trim();
    if (trimmed.isNotEmpty && _rating <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.get('ratingRequired'), style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (!AuthService.instance.isLoggedIn.value) {
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
        );
        if (!mounted) return;
        if (ok != true || !AuthService.instance.isLoggedIn.value) {
          setState(() => _submitting = false);
          return;
        }
        await _loadOrdinal();
        if (!mounted) return;
      }

      final country = CountryScope.maybeOf(context)?.country ??
          UserProfileService.instance.signupCountryNotifier.value;

      // 모든 경우: 홈탭 리뷰 게시판에 게시글 생성 (like/comment 연동 위해 항상 posts 문서 필요)
      final hasReviewText = trimmed.isNotEmpty;
      final hasRating = _rating > 0;
      final sync = await PostService.instance.addDramaWatchActivityFeedPost(
        dramaId: widget.dramaId,
        dramaTitle: widget.dramaTitle,
        rating: _rating,
        comment: trimmed,
        reviewsTabLabel: s.get('tabReviews'),
        timeSoonLabel: s.get('soon'),
      );
      if (!mounted) return;
      // 별점+리뷰 둘 다 있으면 게시글 생성 실패 시 저장 실패 처리
      if (hasReviewText && hasRating) {
        if (sync.postId == null || sync.postId!.isEmpty) {
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(s.get('postSaveFailed'), style: GoogleFonts.notoSansKr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      } else {
        // 피드 글 저장 성공 시 [PostService.addPost]가 이미
        // [ReviewService.syncDramaReviewFromFeedPost]로 drama_reviews를 맞춤.
        // 여기서 ReviewService.add를 또 호출하면 Watch 탭에 같은 사용자 2줄이 생김.
        final pid = sync.postId?.trim() ?? '';
        if (pid.isEmpty) {
          try {
            await UserProfileService.instance.loadIfNeeded();
            final rawAuthor =
                await UserProfileService.instance.getAuthorForPost();
            final authorName = rawAuthor.startsWith('u/')
                ? rawAuthor.substring(2)
                : rawAuthor;
            await ReviewService.instance.add(
              dramaId: widget.dramaId,
              dramaTitle: widget.dramaTitle,
              rating: _rating,
              comment: '',
              authorName: authorName.isNotEmpty ? authorName : '익명',
              authorPhotoUrl:
                  UserProfileService.instance.profileImageUrlNotifier.value,
              feedPostId: null,
            );
          } catch (e) {
            debugPrint('DramaWatchActivitySheet ReviewService.add: $e');
          }
          if (!mounted) return;
        }
      }

      if (!mounted) return;

      final locTitle =
          DramaListService.instance.getDisplayTitle(widget.dramaId, country);
      final title =
          locTitle.trim().isNotEmpty ? locTitle : widget.dramaItem.title;
      final imgUrl = DramaListService.instance.getDisplayImageUrl(
            widget.dramaId,
            country,
          ) ??
          widget.dramaItem.imageUrl;

      final feedId = sync.postId?.trim() ?? '';
      await WatchHistoryService.instance.add(
        id: widget.dramaId,
        title: title,
        subtitle: widget.dramaItem.subtitle,
        views: widget.dramaItem.views,
        imageUrl: imgUrl,
        rating: _rating > 0 ? _rating : null,
        comment: trimmed.isNotEmpty ? trimmed : null,
        linkedFeedPostId: feedId.isNotEmpty ? feedId : null,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        final s = CountryScope.of(context).strings;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('postSaveFailed'), style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  bool get _headerStarLit => _rating > 0;
  bool get _headerReviewLit =>
      _commentFocus.hasFocus || _comment.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = CountryScope.of(context).strings;
    final cs = theme.colorScheme;
    final bg = cs.surfaceContainerHigh;
    final onBg = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final activeLightGray = onBg.withValues(alpha: 0.9);
    final iconMuted = muted.withValues(alpha: 0.45);
    final iconLit = activeLightGray;
    final labelMuted = muted.withValues(alpha: 0.52);
    final labelLit = activeLightGray;
    final inputFocusBorder = muted.withValues(alpha: 0.62);
    final tapHighlight = onBg.withValues(alpha: 0.08);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.paddingOf(context).bottom + 20,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.linkBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            s.get('save'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // First-time watch — 터치 없음
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.eye, size: 28, color: iconLit),
                        const SizedBox(height: 4),
                        Text(
                          _ordinalLabel(s),
                          textAlign: TextAlign.center,
                          maxLines: 2,
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
                  // Rating — 아이콘+라벨 전체가 터치 영역, 탭 시 밝은 회색 하이라이트
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        splashColor: tapHighlight,
                        highlightColor: tapHighlight,
                        borderRadius: BorderRadius.circular(10),
                        onTap: _submitting
                            ? null
                            : () => setState(() => _ratingStripFocused = true),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 28,
                                color: _headerStarLit ? iconLit : iconMuted,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.get('dramaWatchActivityHeaderRating'),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: (_headerStarLit || _ratingStripFocused)
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
                  // Review — 아이콘+라벨 전체가 터치 영역
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        onTap: _submitting
                            ? null
                            : () {
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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 28,
                                child: Center(
                                  child: ReviewBodyLinesIndicator(
                                    color: _headerReviewLit
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
                                  color: _headerReviewLit
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
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
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
                        if (_submitting) return;
                        final isLeftHalf = d.localPosition.dx < slotW / 2;
                        final next = isLeftHalf ? halfValue : fullValue;
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
                controller: _comment,
                focusNode: _commentFocus,
                maxLines: 4,
                cursorColor: inputFocusBorder,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  height: 1.35,
                  color: onBg,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.35),
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
    );
  }
}
