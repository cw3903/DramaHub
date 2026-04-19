import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_profile_avatar_size.dart';
import '../services/auth_service.dart';
import '../services/episode_rating_service.dart';
import '../services/episode_review_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import 'user_profile_nav.dart';
import 'app_delete_confirm_dialog.dart';
import 'episode_review_thread_sheet.dart';
import 'drama_review_feed_tile.dart' show kDramaReviewFeedVerticalGap;
import 'drama_row_profile_avatar.dart';
import 'feed_inline_action_colors.dart';
import 'feed_review_star_row.dart'
    show FeedReviewRatingStars, kFeedReviewRatingThumbWidth;

/// 하단 고정 리뷰 시트 — 화면 좌우와 띄워 모서리·그림자·세로 테두리가 보이게.
const double _kPinnedComposerSheetHorizontalMargin = 6;

/// [MainScreen] `_BottomNavContent` 한 줄 높이: `EdgeInsets`(top 6, bottom 18) + max(아이콘 26, +버튼 40) = 64.
/// ([main_screen.dart] `SafeArea` 아래 Row와 동일 기준)
const double _kMainScreenBottomNavContentHeight = 64.0;

/// [MainScreen] `extendBody`일 때 보디·시트가 피해야 할 하단 오버레이.
///
/// - 탭 행 자체는 [_kMainScreenBottomNavContentHeight].
/// - 그 아래 홈 인디케이터·제스처 바는 [MediaQuery.viewPadding]·[MediaQuery.padding] 중 큰 값.
///   (`viewPadding.bottom`만 0인 안드로이드 제스처 내비 대응)
double _episodeReviewPinnedComposerBottomPad(BuildContext context) {
  final mq = MediaQuery.of(context);
  final systemBottom = math.max(mq.viewPadding.bottom, mq.padding.bottom);
  const hairlineSafety = 2.0;
  return systemBottom +
      _kMainScreenBottomNavContentHeight +
      hairlineSafety +
      mq.viewInsets.bottom;
}

/// [community_board_tabs.reviewInlineActionHitTarget]과 동일 — 스플래시 없이 터치만 확장.
Widget _episodeReviewActionHitTarget({
  required VoidCallback onTap,
  required Widget visual,
  EdgeInsets outsets = const EdgeInsets.fromLTRB(18, 0, 18, 8),
}) {
  return Stack(
    clipBehavior: Clip.none,
    fit: StackFit.passthrough,
    alignment: Alignment.center,
    children: [
      Positioned(
        left: -outsets.left,
        top: -outsets.top,
        right: -outsets.right,
        bottom: -outsets.bottom,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: const SizedBox.expand(),
        ),
      ),
      IgnorePointer(child: visual),
    ],
  );
}

/// 각 화 별점 없을 때 별·숫자 색 (회색으로 통일)
Color episodeNoRatingColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : AppColors.mediumGrey;
}

/// 에피소드 리뷰 패널: 상세 인라인(카드형) / 전체 화면(구분선 리스트).
enum EpisodeReviewListStyle {
  card,
  divider,
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
    this.listStyle = EpisodeReviewListStyle.card,
    this.onViewAll,
    this.maxVisibleReviews,
    /// 전체 화면 등: 상단 Ep·별·평점 줄은 앱바에만 두고 패널 안 중복 제거.
    this.hideSummaryHeader = false,
    /// 리뷰 카드에서 `timeAgo` 숨김.
    this.hideReviewCardTimestamp = false,
    /// 별·입력란을 스크롤 밖 하단에 고정 (전체 회차 리뷰 화면).
    this.pinComposerToBottom = false,
  });

  final String dramaId;
  final int episodeNumber;
  final VoidCallback onClose;
  final dynamic strings;
  /// 전체 화면에서는 AppBar 뒤로가기만 쓰고 패널 우측 X 숨김.
  final bool showCloseButton;
  final EpisodeReviewListStyle listStyle;
  /// 상세 인라인에서만: 입력란 아래 "전체 보기" 탭 시 호출 (전체 화면으로 이동).
  final VoidCallback? onViewAll;
  /// null이면 전부 표시. 드라마 상세 인라인 등에서 최대 개수만 보일 때 설정 (예: 3).
  final int? maxVisibleReviews;
  final bool hideSummaryHeader;
  final bool hideReviewCardTimestamp;
  final bool pinComposerToBottom;

  @override
  State<EpisodeReviewPanel> createState() => _EpisodeReviewPanelState();
}

class _EpisodeReviewPanelState extends State<EpisodeReviewPanel> {
  final _commentController = TextEditingController();
  double _reviewRating = 0;
  String? _editingReviewId;
  /// [pinComposerToBottom] 전용: 별·입력 시트 접기(기본 펼침).
  bool _composerSheetExpanded = true;
  /// 핸들 세로 드래그 누적 — [onVerticalDragEnd]에서 접기/펼치기 판별.
  double _composerHandleDragDy = 0;

  void _toggleComposerSheetExpanded() {
    setState(() {
      _composerSheetExpanded = !_composerSheetExpanded;
      if (!_composerSheetExpanded) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _onComposerHandleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final dy = _composerHandleDragDy;
    _composerHandleDragDy = 0;
    const dist = 26.0;
    const vel = 420.0;
    if (_composerSheetExpanded) {
      if (dy > dist || velocity > vel) {
        setState(() {
          _composerSheetExpanded = false;
          FocusManager.instance.primaryFocus?.unfocus();
        });
      }
    } else {
      if (dy < -dist || velocity < -vel) {
        setState(() => _composerSheetExpanded = true);
      }
    }
  }

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

  Widget _buildStarRatingRow(ColorScheme cs) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final r = _reviewRating;
          final full = r >= i + 1;
          final half = r >= i + 0.5 && r < i + 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    full
                        ? Icons.star_rounded
                        : (half ? Icons.star_half_rounded : Icons.star_border_rounded),
                    size: 26,
                    color: (full || half) ? AppColors.ratingStar : cs.onSurfaceVariant,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            final v = i + 0.5;
                            _reviewRating = _reviewRating == v ? 0 : v;
                          }),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            final v = i + 1.0;
                            _reviewRating = _reviewRating == v ? 0 : v;
                          }),
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
    );
  }

  Widget _buildComposerBlock(ColorScheme cs, {bool belowSheetHeader = false}) {
    final input = EpisodeReviewInput(
      dramaId: widget.dramaId,
      episodeNumber: widget.episodeNumber,
      controller: _commentController,
      strings: widget.strings,
      rating: _reviewRating > 0 ? _reviewRating : null,
      editingReviewId: _editingReviewId,
      compact: belowSheetHeader,
      onSubmitted: () {
        setState(() {
          _reviewRating = 0;
          _editingReviewId = null;
        });
      },
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: belowSheetHeader ? 2 : 10),
        _buildStarRatingRow(cs),
        SizedBox(height: belowSheetHeader ? 4 : 8),
        if (belowSheetHeader)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: input,
          )
        else
          input,
      ],
    );
  }

  Widget _buildPinnedComposerSheet(BuildContext context, ColorScheme cs) {
    final bottomPad = _episodeReviewPinnedComposerBottomPad(context);
    final sheetOutline = cs.outline.withValues(alpha: 0.28);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPinnedComposerSheetHorizontalMargin),
      child: Material(
        color: cs.surface,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: sheetOutline, width: 1),
              left: BorderSide(color: sheetOutline, width: 1),
              right: BorderSide(color: sheetOutline, width: 1),
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleComposerSheetExpanded,
                    onVerticalDragStart: (_) {
                      _composerHandleDragDy = 0;
                    },
                    onVerticalDragUpdate: (details) {
                      _composerHandleDragDy += details.delta.dy;
                    },
                    onVerticalDragEnd: _onComposerHandleVerticalDragEnd,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                      child: SizedBox(
                        height: 28,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.38),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.hardEdge,
                  child: _composerSheetExpanded
                      ? _buildComposerBlock(cs, belowSheetHeader: true)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildViewAllCta(ColorScheme cs) {
    if (widget.onViewAll == null) return null;
    final ctaColor = cs.onSurfaceVariant.withValues(alpha: 0.55);
    // [drama_detail_page] 레이팅스&리뷰 통합 카드 `dramaAllReviewsCta`와 동일 패딩·터치.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Center(
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: ctaColor),
          onPressed: widget.onViewAll,
          child: Text(
            widget.strings.get('dramaAllReviewsCta'),
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: ctaColor,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _scrollableReviewBlocks(
    ColorScheme cs,
    List<EpisodeReviewItem> list,
    Divider dividerLine,
    bool isDivider,
  ) {
    final out = <Widget>[];
    final cap = widget.maxVisibleReviews;
    final visibleList = (cap != null && cap > 0)
        ? (list.length > cap ? list.sublist(0, cap) : list)
        : list;

    if (visibleList.isEmpty) {
      out.add(
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: isDivider ? 20 : 18,
            horizontal: 4,
          ),
          child: Center(
            child: Text(
              widget.strings.get('firstReview'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    } else {
      for (var i = 0; i < visibleList.length; i++) {
        final r = visibleList[i];
        if (isDivider && i > 0) {
          out.add(dividerLine);
        } else if (!isDivider && i > 0) {
          out.add(
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: cs.outline.withValues(alpha: 0.22),
            ),
          );
        }
        out.add(
          Padding(
            padding: EdgeInsets.only(
              bottom: 0,
              top: isDivider ? 10 : 0,
            ),
            child: EpisodeReviewCard(
              item: r,
              dramaId: widget.dramaId,
              episodeNumber: widget.episodeNumber,
              strings: widget.strings,
              hideTimestamp: widget.hideReviewCardTimestamp,
              embedInLightCard: !isDivider,
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
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDivider = widget.listStyle == EpisodeReviewListStyle.divider;
    final dividerLine = Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: cs.outline.withValues(alpha: 0.28),
    );

    final episodeHeaderTitle = ListenableBuilder(
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              hasRating ? avg.toStringAsFixed(1) : '0',
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: hasRating ? cs.onSurface : episodeNoRatingColor(context),
                height: 1.0,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.strings.get('episodeReviewRaterCount').replaceAll('%d', '$count'),
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
                height: 1.0,
              ),
            ),
          ],
        );
      },
    );

    final Widget header = widget.showCloseButton
        ? Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Center(child: episodeHeaderTitle),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: IconButton(
                  icon: Icon(LucideIcons.x, size: 20, color: cs.onSurfaceVariant),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    widget.onClose();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            ],
          )
        : Center(child: episodeHeaderTitle);

    final episodeNotifier =
        EpisodeReviewService.instance.getNotifierForEpisode(widget.dramaId, widget.episodeNumber);

    if (widget.pinComposerToBottom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.hideSummaryHeader) ...[
            header,
            if (isDivider) ...[
              const SizedBox(height: 10),
              dividerLine,
            ],
            const SizedBox(height: 12),
          ] else if (isDivider)
            const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder<List<EpisodeReviewItem>>(
              valueListenable: episodeNotifier,
              builder: (context, list, _) {
                final blocks = _scrollableReviewBlocks(cs, list, dividerLine, isDivider);
                final withCta = <Widget>[...blocks];
                final cta = _buildViewAllCta(cs);
                if (cta != null) withCta.add(cta);
                return ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: withCta,
                );
              },
            ),
          ),
          _buildPinnedComposerSheet(context, cs),
        ],
      );
    }

    final headerDivider = Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: cs.outline.withValues(alpha: 0.26),
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.hideSummaryHeader) ...[
          Padding(
            // [drama_detail_page] 레이팅스 통합 카드: 요약 `Padding.vertical: 24` → 별 아래·구분선 사이 24.
            // 에피 카드는 제목만 있으므로 하단만 동일하게 맞춤.
            padding: isDivider
                ? const EdgeInsets.fromLTRB(20, 14, 20, 0)
                // 인라인 카드: 카드 위끝↔제목 = 제목↔구분선(24)과 동일 — 레이팅스 요약 세로 24와 맞춤.
                : const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: header,
          ),
          if (isDivider) ...[
            const SizedBox(height: 10),
            dividerLine,
          ] else
            headerDivider,
        ],
        // 레이팅스 통합 카드: 요약 구분선 바로 아래 첫 리뷰 — [DramaReviewFeedTile] 상단 9만.
        // 인라인 에피 카드(!isDivider)에서는 여기 추가 세로 간격 없음.
        SizedBox(
          height: widget.hideSummaryHeader
              ? 6
              : (isDivider ? 12 : 0),
        ),
        ValueListenableBuilder<List<EpisodeReviewItem>>(
          valueListenable: episodeNotifier,
          builder: (context, list, _) {
            final reviewBody = <Widget>[..._scrollableReviewBlocks(cs, list, dividerLine, isDivider)];

            final inlineEpisodeCard = !isDivider && !widget.pinComposerToBottom;
            if (inlineEpisodeCard) {
              // 드라마 상세 에피 카드: 레이팅스&리뷰와 같이 기본 입력 없음. 편집 중일 때만 별·입력.
              if (_editingReviewId != null) {
                reviewBody.add(const SizedBox(height: 10));
                reviewBody.add(_buildStarRatingRow(cs));
                reviewBody.add(const SizedBox(height: 8));
                reviewBody.add(
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
                );
              }
            } else {
              reviewBody.add(const SizedBox(height: 10));
              reviewBody.add(_buildStarRatingRow(cs));
              reviewBody.add(const SizedBox(height: 8));
              reviewBody.add(
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
              );
            }
            final cta = _buildViewAllCta(cs);
            if (cta != null) reviewBody.add(cta);

            final inner = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: reviewBody,
            );

            if (isDivider) {
              return inner;
            }
            // 첫 댓글 ↔ 구분선: [DramaReviewsListFeedRow]의 [DramaReviewFeedTile] 상단 9와 동일하게만 둠.
            return inner;
          },
        ),
      ],
    );

    if (isDivider) {
      return column;
    }
    // [drama_detail_page] 레이팅스&리뷰 통합 카드와 동일: surfaceContainerHighest + 20r + 그림자·테두리.
    // 가로 여백은 상세 본문 [Padding] 20과 중복하지 않음. 리뷰 행 14는 [DramaReviewFeedTile]과 동일.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: cs.outline.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        // CTA는 [_buildViewAllCta] 안 `EdgeInsets.fromLTRB(8, 4, 8, 12)`만 쓰고,
        // 레이팅스 통합 카드와 같이 여기서 하단 패딩을 또 주지 않음.
        child: column,
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
    this.hideTimestamp = false,
    /// 드라마 상세 **에피 리뷰 카드** 안: 배경을 카드와 같게 두고 구분선만으로 행 구분.
    this.embedInLightCard = false,
  });

  final EpisodeReviewItem item;
  final String dramaId;
  final int episodeNumber;
  final dynamic strings;
  final ValueChanged<EpisodeReviewItem> onEdit;
  final ValueChanged<String> onDelete;
  final bool hideTimestamp;
  final bool embedInLightCard;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUid = AuthService.instance.currentUser.value?.uid;
    final isMine = currentUid != null && item.uid == currentUid;
    const hPad = 14.0;
    final rowBg = cs.surfaceContainerHighest;

    final name = item.authorName.trim().isEmpty ? '—' : item.authorName;
    final body = item.comment.trim();
    final rating = (item.rating ?? 0).clamp(0.0, 5.0);
    final showStars = rating > 0;

    void openProfile() {
      openUserProfileFromAuthorUid(context, item.uid);
    }

    final profileCell = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openProfile,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: appUnifiedNicknameStyle(cs),
              ),
            ),
            const SizedBox(width: 8),
            DramaRowProfileAvatar(
              imageUrl: item.authorPhotoUrl,
              authorUid: item.uid,
              colorScheme: cs,
              size: kAppUnifiedProfileAvatarSize,
            ),
          ],
        ),
      ),
    );

    final starRow = showStars
        ? FeedReviewRatingStars(
            rating: rating,
            layoutThumbWidth: kFeedReviewRatingThumbWidth,
          )
        : const SizedBox.shrink();

    final bodyWidget = Text(
      body,
      style: GoogleFonts.notoSansKr(
        fontSize: 13,
        height: 1.45,
        color: cs.onSurface.withValues(alpha: 0.9),
      ),
    );

    const actionIconSize = 13.0;
    final actionFg = feedInlineActionMutedForeground(cs);
    final liked = item.likedByUid(currentUid);
    final likeCount = item.likeCount;
    final replyCount = item.replyCount;

    void onLikeTap() {
      HapticFeedback.lightImpact();
      unawaited(() async {
        final err = await EpisodeReviewService.instance.toggleEpisodeReviewLike(
          reviewId: item.id,
          dramaId: dramaId,
          episodeNumber: episodeNumber,
        );
        if (!context.mounted) return;
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings.get(err), style: GoogleFonts.notoSansKr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }());
    }

    void onCommentTap() {
      HapticFeedback.lightImpact();
      unawaited(
        EpisodeReviewThreadSheet.show(
          context: context,
          reviewId: item.id,
          dramaId: dramaId,
          episodeNumber: episodeNumber,
          strings: strings,
        ),
      );
    }

    final column = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 9, hPad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: starRow,
                      ),
                    ),
                    profileCell,
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: kDramaReviewFeedVerticalGap),
                  bodyWidget,
                ],
              ],
            ),
          ),
          const SizedBox(height: kDramaReviewFeedVerticalGap),
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 6),
            child: Row(
              children: [
                _episodeReviewActionHitTarget(
                  onTap: onLikeTap,
                  visual: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          size: actionIconSize,
                          color: liked ? Colors.redAccent : actionFg,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatCompactCount(likeCount),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                            color: actionFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _episodeReviewActionHitTarget(
                  onTap: onCommentTap,
                  visual: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.message_circle,
                          size: actionIconSize,
                          color: actionFg,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatCompactCount(replyCount),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                            color: actionFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 6),
                  _episodeReviewActionHitTarget(
                    onTap: () => onEdit(item),
                    outsets: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    visual: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
                      child: Text(
                        strings.get('edit'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          color: actionFg,
                        ),
                      ),
                    ),
                  ),
                  _episodeReviewActionHitTarget(
                    onTap: () async {
                      final ok = await showAppDeleteConfirmDialog(
                        context,
                        message: strings.get('deletePostConfirm'),
                        cancelText: strings.get('cancel'),
                        confirmText: strings.get('delete'),
                      );
                      if (ok == true) onDelete(item.id);
                    },
                    outsets: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    visual: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 2, 0, 2),
                      child: Text(
                        strings.get('delete'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          color: kAppDeleteActionColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
    );

    if (embedInLightCard) {
      return column;
    }
    return Material(
      color: rowBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: column,
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
    /// 하단 고정 시트: 세로·패딩 축소.
    this.compact = false,
  });

  final String dramaId;
  final int episodeNumber;
  final TextEditingController controller;
  final dynamic strings;
  final VoidCallback onSubmitted;
  final double? rating;
  final String? editingReviewId;
  final bool compact;

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
    final compact = widget.compact;
    final fieldHeight = compact ? 58.0 : 72.0;
    final contentPad = EdgeInsets.fromLTRB(
      8,
      compact ? 7 : 12,
      compact ? 42 : 52,
      compact ? 7 : 12,
    );
    return SizedBox(
      height: fieldHeight,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          TextField(
            focusNode: _focusNode,
            onTapOutside: (_) => _focusNode.unfocus(),
            controller: widget.controller,
            decoration: InputDecoration(
              hintText: widget.strings.get('reviewPlaceholder'),
              hintStyle: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
              ),
              filled: true,
              fillColor: cs.surface,
              isDense: true,
              contentPadding: contentPad,
              border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
            ),
            style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurface),
            maxLines: compact ? 2 : 3,
            textAlignVertical: TextAlignVertical.top,
          ),
          Positioned(
            right: compact ? 4 : 6,
            bottom: compact ? 4 : 6,
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
              icon: Icon(Icons.arrow_upward_rounded, size: compact ? 16 : 18),
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.all(compact ? 6 : 8),
                minimumSize: Size(compact ? 32 : 36, compact ? 32 : 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor:
                    canSubmit ? AppColors.linkBlue : cs.surfaceContainerHighest,
                foregroundColor:
                    canSubmit ? Colors.white : cs.onSurfaceVariant.withValues(alpha: 0.5),
                disabledBackgroundColor: cs.surfaceContainerHighest,
                disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
