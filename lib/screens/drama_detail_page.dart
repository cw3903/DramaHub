import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../utils/format_utils.dart';
import 'package:flutter/services.dart';
import '../services/play_to_shorts_service.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../widgets/write_review_sheet.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/drama_view_service.dart';
import '../services/episode_rating_service.dart';
import '../services/episode_review_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';
import '../models/drama.dart';
import 'login_page.dart';
import '../widgets/share_sheet.dart';
import '../widgets/optimized_network_image.dart';
import 'tag_drama_list_screen.dart';

/// 드라마 상세 페이지 - 평점 & 리뷰 통합
class DramaDetailPage extends StatefulWidget {
  const DramaDetailPage({
    super.key,
    required this.detail,
    this.scrollToRatings = false,
  });

  final DramaDetail detail;
  final bool scrollToRatings;

  @override
  State<DramaDetailPage> createState() => _DramaDetailPageState();
}

class _DramaDetailPageState extends State<DramaDetailPage> {
  final _ratingsKey = GlobalKey();
  double? _liveAverage;
  int? _liveCount;
  List<DramaReview>? _liveReviews;
  int? _liveViews;

  /// 조회수: 낙관적 +1 즉시 표시 → 백그라운드에서 increment. 8초 타임아웃.
  Future<void> _updateViewCount() async {
    final dramaId = widget.detail.item.id;
    try {
      final current = await DramaViewService.instance
          .getViewCount(dramaId)
          .timeout(const Duration(seconds: 8), onTimeout: () => 0);
      if (mounted) setState(() => _liveViews = current + 1);
      DramaViewService.instance.increment(dramaId); // 백그라운드 (await 없음)
    } catch (_) {}
  }

  /// 뒤로 갈 때 목록에 갱신된 조회수 전달용 (dramaId, viewCount).
  Map<String, int>? _buildViewCountResult() {
    if (_liveViews == null) return null;
    return {widget.detail.item.id: _liveViews!};
  }

  Future<void> _loadRatingStats() async {
    final dramaId = widget.detail.item.id;
    try {
      final results = await Future.wait([
        ReviewService.instance.getDramaRatingStats(dramaId)
            .timeout(const Duration(seconds: 8), onTimeout: () => (average: 0.0, count: 0)),
        ReviewService.instance.getDramaReviews(dramaId)
            .timeout(const Duration(seconds: 8), onTimeout: () => <DramaReview>[]),
      ]);
      if (mounted) {
        final stats = results[0] as ({double average, int count});
        final reviews = results[1] as List<DramaReview>;
        setState(() {
          _liveAverage = stats.average;
          _liveCount = stats.count;
          _liveReviews = reviews;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    // 첫 프레임 그린 뒤 각 작업을 독립적으로 실행 (순차 await 체인 제거 → ANR 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 세 작업 완전히 독립 실행 - 서로 기다리지 않음
      _updateViewCount().catchError((_) {});
      _loadRatingStats().catchError((_) {});
      final item = widget.detail.item;
      WatchHistoryService.instance.add(
        id: item.id,
        title: item.title,
        subtitle: item.subtitle,
        views: item.views,
        imageUrl: item.imageUrl,
      ).catchError((_) {});
    });
    if (widget.scrollToRatings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          _ratingsKey.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  Future<void> _handleWriteReviewTap(BuildContext context, dynamic s) async {
    final dramaId = widget.detail.item.id;
    final dramaTitle = widget.detail.item.title;
    if (AuthService.instance.isLoggedIn.value) {
      await WriteReviewSheet.show(context, dramaId: dramaId, dramaTitle: dramaTitle);
      if (mounted) _loadRatingStats();
    } else {
      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      if (result == true && mounted) {
        await WriteReviewSheet.show(context, dramaId: dramaId, dramaTitle: dramaTitle);
        if (mounted) _loadRatingStats();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final detail = widget.detail;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // 뒤로가기 시 콜백 스택에서 바로 pop 하면 ANR 유발 가능 → 다음 프레임으로 연기
          final resultToPass = _buildViewCountResult();
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Navigator.of(context).pop(resultToPass);
          });
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: CustomScrollView(
        slivers: [
          // 상단: 포스터 + 제목 + 조회수 한 덩어리 (로드 전에는 아이템 기본 조회수 표시, 로드 후 서버 값)
          SliverToBoxAdapter(
            child: _HeaderSection(
              detail: widget.detail,
              strings: s,
              viewsDisplay: _liveViews != null ? formatCompactCount(_liveViews!) : (detail.item.views.isNotEmpty ? detail.item.views : '0'),
              onBack: () {
                final resultToPass = _buildViewCountResult();
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  Navigator.of(context).pop(resultToPass);
                });
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 줄거리 (가입 국가별 언어, 위에 장르 태그 pill)
                  _SynopsisSection(detail: detail, strings: s),
                  const SizedBox(height: 24),
                  // 회차 (구간 탭 + 에피소드 버튼)
                  _EpisodesSection(dramaId: detail.item.id, episodes: detail.episodes, strings: s),
                  const SizedBox(height: 28),
                  // Cast
                  _CastSection(castNames: detail.cast, strings: s),
                  const SizedBox(height: 28),
                  // 평점 & 리뷰
                  KeyedSubtree(
                    key: _ratingsKey,
                    child: _RatingsAndReviewsSection(
                    dramaId: detail.item.id,
                    dramaTitle: detail.item.title,
                    averageRating: _liveAverage ?? detail.averageRating,
                    ratingCount: _liveCount ?? detail.ratingCount,
                    reviews: _liveReviews ?? detail.reviews,
                    strings: s,
                    onWriteReviewTap: () => _handleWriteReviewTap(context, s),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 비슷한 작품
                  _SimilarSection(similar: detail.similar, strings: s),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

Widget _posterPlaceholder(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    width: 80,
    height: 80 * 1.3,
    color: cs.surfaceContainerHighest,
    child: Center(
      child: Icon(LucideIcons.tv, size: 28, color: cs.onSurfaceVariant),
    ),
  );
}

/// 각 화 별점 없을 때 별·숫자 색 (회색으로 통일)
Color _episodeNoRatingColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : AppColors.mediumGrey;
}

/// 포스터 크게 보기 (전체 화면)
class _FullScreenPosterPage extends StatelessWidget {
  const _FullScreenPosterPage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: imageUrl.startsWith('http')
                    ? OptimizedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : Image.asset(
                        imageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Icon(LucideIcons.tv, size: 80, color: cs.onSurfaceVariant),
                      ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: Icon(Icons.close, size: 28, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 상단: 포스터 + 제목 + 조회수 한 덩어리 (화이트 테마)
class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.detail, required this.strings, this.viewsDisplay, this.onBack});

  final DramaDetail detail;
  final dynamic strings;
  final String? viewsDisplay;
  /// null이면 기본 Navigator.pop(context). 있으면 호출 (pop 시 조회수 결과 전달용).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = cs.surface;
    final surfaceDim = isDark ? cs.surface.withOpacity(0.6) : cs.surface.withOpacity(0.75);
    final iconColor = cs.onSurface;

    // 설정 언어(앱 locale) 기준으로 제목·이미지 표시
    final country = CountryScope.maybeOf(context)?.country
        ?? UserProfileService.instance.signupCountryNotifier.value;
    final displayTitle = () {
      final t = DramaListService.instance.getDisplayTitle(detail.item.id, country);
      return t.isNotEmpty ? t : detail.item.title;
    }();
    final displayImageUrl = DramaListService.instance.getDisplayImageUrl(detail.item.id, country)
        ?? detail.item.imageUrl;

    return Stack(
      children: [
        // 줄거리 위: 드라마 사진 옅게 배경
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 140,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.outline.withOpacity(isDark ? 0.2 : 0.18),
                  cs.outline.withOpacity(isDark ? 0.1 : 0.08),
                  surfaceColor,
                ],
              ),
            ),
            child: Center(
              child: Icon(
                LucideIcons.tv,
                size: 120,
                color: cs.outline.withOpacity(0.2),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 56, 20, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [surfaceDim, surfaceColor],
              stops: const [0.0, 0.5],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 포스터 (탭 시 크게 보기)
              GestureDetector(
                onTap: () {
                  if (displayImageUrl != null && displayImageUrl.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => _FullScreenPosterPage(imageUrl: displayImageUrl),
                      ),
                    );
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 80,
                    height: 80 * 1.3,
                    child: displayImageUrl != null && displayImageUrl.isNotEmpty
                        ? (displayImageUrl.startsWith('http')
                            ? OptimizedNetworkImage(
                                imageUrl: displayImageUrl,
                                fit: BoxFit.cover,
                                width: 80,
                                height: 80 * 1.3,
                              )
                            : Image.asset(
                                displayImageUrl,
                                fit: BoxFit.cover,
                                width: 80,
                                height: 80 * 1.3,
                                errorBuilder: (_, __, ___) => _posterPlaceholder(context),
                              ))
                        : _posterPlaceholder(context),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${viewsDisplay ?? detail.item.views} 조회수',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(LucideIcons.arrow_left, color: iconColor),
                onPressed: () {
                if (onBack != null) {
                  onBack!();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              ),
              IconButton(
                icon: Icon(LucideIcons.share_2, color: iconColor),
                onPressed: () => ShareSheet.show(context, title: detail.item.title, type: 'drama'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 줄거리: 위에 장르 태그 pill (가로 스크롤) + 본문. 가입 국가별 언어로 표시.
class _SynopsisSection extends StatelessWidget {
  const _SynopsisSection({required this.detail, required this.strings});

  final DramaDetail detail;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: UserProfileService.instance.signupCountryNotifier,
      builder: (context, countryCode, _) {
        // 설정 언어 기준으로 장르·줄거리 표시
        final country = CountryScope.maybeOf(context)?.country ?? countryCode;
        final genre = DramaListService.instance.getDisplaySubtitle(detail.item.id, country);
        final displayGenre = genre.isNotEmpty ? genre : detail.genre;
        var genreTags = displayGenre.split(RegExp(r'[·,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (genreTags.isEmpty) genreTags = [displayGenre];

        final synopsis = DramaListService.instance.getDisplaySynopsis(detail.item.id, country);
        final displaySynopsis = synopsis.isNotEmpty ? synopsis : detail.synopsis;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.get('synopsis'),
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: genreTags.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (context, i) {
                  final tag = genreTags[i];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TagDramaListScreen(tag: tag),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 14,
                            child: Center(
                              child: Text(
                                tag,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurfaceVariant,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 0),
                          SizedBox(
                            width: 12,
                            height: 14,
                            child: Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 0.5),
                                child: Icon(LucideIcons.chevron_right, size: 14, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              displaySynopsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}

const int _episodesPerRange = 30;

Future<void> _showEpisodeRatingPicker(
  BuildContext context,
  String dramaId,
  int episodeNumber,
  double currentRating,
) async {
  final cs = Theme.of(context).colorScheme;
  double selected = currentRating > 0 ? currentRating : 1.0;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(
            '${episodeNumber}화 별점',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
          ),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (i) {
              final value = (i + 1).toDouble();
              final filled = selected >= value;
              return GestureDetector(
                onTap: () => setDialogState(() => selected = value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.star_rounded,
                    size: 36,
                    color: filled ? Colors.amber : cs.onSurfaceVariant,
                  ),
                ),
              );
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            FilledButton(
              onPressed: () async {
                await EpisodeRatingService.instance.setRating(
                  dramaId: dramaId,
                  episodeNumber: episodeNumber,
                  rating: selected,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    ),
  );
}

/// 회차 클릭 시 밑에 나오는 리뷰·댓글 목록 + 입력
class _EpisodeReviewPanel extends StatefulWidget {
  const _EpisodeReviewPanel({
    required this.dramaId,
    required this.episodeNumber,
    required this.onClose,
    required this.strings,
  });

  final String dramaId;
  final int episodeNumber;
  final VoidCallback onClose;
  final dynamic strings;

  @override
  State<_EpisodeReviewPanel> createState() => _EpisodeReviewPanelState();
}

class _EpisodeReviewPanelState extends State<_EpisodeReviewPanel> {
  final _commentController = TextEditingController();
  /// 0.5 ~ 5.0 (0.5 단위). 0 = 미선택
  double _reviewRating = 0;
  /// 수정 중인 댓글 id. null이면 새 댓글 등록
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
                  final averageRatings = EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId).value;
                  final countMap = EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId).value;
                  final count = countMap[widget.episodeNumber] ?? 0;
                  final avg = averageRatings[widget.episodeNumber] ?? 0.0;
                  final hasRating = avg > 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.episodeNumber}화',
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
                        color: hasRating ? Colors.amber : _episodeNoRatingColor(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasRating ? avg.toStringAsFixed(1) : '0',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: hasRating
                              ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : cs.onSurface)
                              : _episodeNoRatingColor(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${count}명 참여)',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
              IconButton(
                icon: Icon(LucideIcons.x, size: 20, color: cs.onSurfaceVariant),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<List<EpisodeReviewItem>>(
            valueListenable: EpisodeReviewService.instance.getNotifierForEpisode(widget.dramaId, widget.episodeNumber),
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
                        child: _EpisodeReviewCard(
                          item: r,
                          dramaId: widget.dramaId,
                          episodeNumber: widget.episodeNumber,
                          onEdit: (rev) {
                            setState(() {
                              _editingReviewId = rev.id;
                              _commentController.text = rev.comment;
                              _reviewRating = rev.rating ?? 0;
                            });
                          },
                          onDelete: (reviewId) async {
                            await EpisodeReviewService.instance.deleteById(widget.dramaId, widget.episodeNumber, reviewId);
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
                                  full ? Icons.star_rounded : (half ? Icons.star_half_rounded : Icons.star_border_rounded),
                                  size: 28,
                                  color: (full || half) ? Colors.amber : cs.onSurfaceVariant,
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
                    _EpisodeReviewInput(
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

class _EpisodeReviewCard extends StatelessWidget {
  const _EpisodeReviewCard({
    required this.item,
    required this.dramaId,
    required this.episodeNumber,
    required this.onEdit,
    required this.onDelete,
  });

  final EpisodeReviewItem item;
  final String dramaId;
  final int episodeNumber;
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
                  Text(
                    item.authorName,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (item.rating != null && item.rating! > 0) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.star_rounded, size: 14, color: Colors.amber),
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
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('삭제', style: GoogleFonts.notoSansKr()),
                            content: Text('이 댓글을 삭제할까요?', style: GoogleFonts.notoSansKr()),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text('취소', style: GoogleFonts.notoSansKr()),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text('삭제', style: GoogleFonts.notoSansKr(color: cs.error)),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) onDelete(item.id);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '삭제',
                        style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.error),
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

class _EpisodeReviewInput extends StatefulWidget {
  const _EpisodeReviewInput({
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
  State<_EpisodeReviewInput> createState() => _EpisodeReviewInputState();
}

class _EpisodeReviewInputState extends State<_EpisodeReviewInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _EpisodeReviewInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final hasRating = widget.rating != null && widget.rating! > 0;
    final canSubmit = hasText && hasRating;
    return SizedBox(
      height: 72,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          TextField(
            controller: widget.controller,
            decoration: InputDecoration(
              hintText: '리뷰를 입력하세요',
              hintStyle: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(8, 12, 44, 12),
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
                        await EpisodeReviewService.instance.add(
                          dramaId: widget.dramaId,
                          episodeNumber: widget.episodeNumber,
                          comment: text,
                          rating: rating,
                        );
                      }
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

class _EpisodesSection extends StatefulWidget {
  const _EpisodesSection({
    required this.dramaId,
    required this.episodes,
    required this.strings,
  });

  final String dramaId;
  final List<DramaEpisode> episodes;
  final dynamic strings;

  @override
  State<_EpisodesSection> createState() => _EpisodesSectionState();
}

class _EpisodesSectionState extends State<_EpisodesSection> {
  int _rangeIndex = 0;
  int? _selectedEpisodeNumber;
  int? _pendingEpisodeNumber;

  @override
  void initState() {
    super.initState();
    EpisodeRatingService.instance.getMyRatingsForDrama(widget.dramaId);
    EpisodeRatingService.instance.loadEpisodeAverageRatings(widget.dramaId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final episodes = widget.episodes;
    final strings = widget.strings;
    if (episodes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.get('episodes'),
            style: GoogleFonts.notoSansKr(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '회차 정보가 없습니다.',
            style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    final rangeCount = (episodes.length / _episodesPerRange).ceil();
    final ranges = <({int start, int end})>[];
    for (var r = 0; r < rangeCount; r++) {
      final start = r * _episodesPerRange;
      final end = (start + _episodesPerRange).clamp(0, episodes.length);
      if (start < episodes.length) ranges.add((start: start + 1, end: end));
    }
    if (ranges.isEmpty) ranges.add((start: 1, end: episodes.length));

    final selectedRange = _rangeIndex < ranges.length ? ranges[_rangeIndex] : ranges.first;
    final rangeEpisodes = episodes.sublist(
      selectedRange.start - 1,
      selectedRange.end.clamp(0, episodes.length),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _showEpisodesBottomSheet(context, episodes, strings),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings.get('episodes'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.get('totalEpisodes').replaceAll('%d', '${episodes.length}'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(LucideIcons.chevron_right, size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (ranges.length > 1)
          Row(
            children: List.generate(ranges.length, (i) {
              final r = ranges[i];
              final isSelected = _rangeIndex == i;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => setState(() => _rangeIndex = i),
                  child: Text(
                    '${r.start}-${r.end}',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }),
          ),
        if (ranges.length > 1) const SizedBox(height: 12),
        ListenableBuilder(
          listenable: Listenable.merge([
            EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId),
            EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId),
          ]),
          builder: (context, _) {
            final averageRatings = EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId).value;
            final countMap = EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId).value;
            return SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: rangeEpisodes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, i) {
                  final ep = rangeEpisodes[i];
                  final avg = averageRatings[ep.number] ?? 0.0;
                  final count = countMap[ep.number] ?? 0;
                  final hasRating = avg > 0;
                  final myRating = EpisodeRatingService.instance.getMyRating(widget.dramaId, ep.number);
                  return GestureDetector(
                    onTap: () {
                      if (_selectedEpisodeNumber == ep.number) {
                        setState(() => _selectedEpisodeNumber = null);
                      } else if (_selectedEpisodeNumber != null) {
                        setState(() {
                          _selectedEpisodeNumber = null;
                          _pendingEpisodeNumber = ep.number;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          final num = _pendingEpisodeNumber;
                          setState(() {
                            _selectedEpisodeNumber = num;
                            _pendingEpisodeNumber = null;
                          });
                          if (num != null) {
                            EpisodeReviewService.instance.loadReviews(widget.dramaId, num);
                          }
                        });
                      } else {
                        setState(() => _selectedEpisodeNumber = ep.number);
                        EpisodeReviewService.instance.loadReviews(widget.dramaId, ep.number);
                      }
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outline.withOpacity(0.4), width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            strings.get('episodeLabel').replaceAll('%d', '${ep.number}'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Transform.translate(
                                offset: const Offset(0, 1.5),
                                child: Icon(
                                  Icons.star_rounded,
                                  size: 12,
                                  color: hasRating ? Colors.amber : _episodeNoRatingColor(context),
                                ),
                              ),
                              SizedBox(width: 12 * 0.25),
                              Text(
                                hasRating ? avg.toStringAsFixed(1) : '0',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: hasRating
                                      ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : cs.onSurface)
                                      : _episodeNoRatingColor(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        AnimatedSize(
          duration: _pendingEpisodeNumber != null ? Duration.zero : const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _selectedEpisodeNumber != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _EpisodeReviewPanel(
                      dramaId: widget.dramaId,
                      episodeNumber: _selectedEpisodeNumber!,
                      onClose: () => setState(() => _selectedEpisodeNumber = null),
                      strings: widget.strings,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _showEpisodesBottomSheet(BuildContext context, List<DramaEpisode> episodes, dynamic strings) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EpisodesBottomSheet(
        dramaId: widget.dramaId,
        episodes: episodes,
        strings: strings,
        onEpisodeSelected: (num) {
          Navigator.pop(ctx);
          setState(() => _selectedEpisodeNumber = num);
          EpisodeReviewService.instance.loadReviews(widget.dramaId, num);
        },
      ),
    );
  }
}

/// 회차 하단 슬라이드: 구간 탭 + 정사각형 그리드
class _EpisodesBottomSheet extends StatefulWidget {
  const _EpisodesBottomSheet({
    required this.dramaId,
    required this.episodes,
    required this.strings,
    this.onEpisodeSelected,
  });

  final String dramaId;
  final List<DramaEpisode> episodes;
  final dynamic strings;
  final ValueChanged<int>? onEpisodeSelected;

  @override
  State<_EpisodesBottomSheet> createState() => _EpisodesBottomSheetState();
}

class _EpisodesBottomSheetState extends State<_EpisodesBottomSheet> {
  int _rangeIndex = 0;

  @override
  void initState() {
    super.initState();
    EpisodeRatingService.instance.getMyRatingsForDrama(widget.dramaId);
    EpisodeRatingService.instance.loadEpisodeAverageRatings(widget.dramaId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final episodes = widget.episodes;
    final strings = widget.strings;
    final rangeCount = (episodes.length / _episodesPerRange).ceil();
    final ranges = <({int start, int end})>[];
    for (var r = 0; r < rangeCount; r++) {
      final start = r * _episodesPerRange;
      final end = (start + _episodesPerRange).clamp(0, episodes.length);
      if (start < episodes.length) ranges.add((start: start + 1, end: end));
    }
    if (ranges.isEmpty) ranges.add((start: 1, end: episodes.length));
    final selectedRange = _rangeIndex < ranges.length ? ranges[_rangeIndex] : ranges.first;
    final rangeEpisodes = episodes.sublist(
      selectedRange.start - 1,
      selectedRange.end.clamp(0, episodes.length),
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  strings.get('episodes'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                IconButton(
                  icon: Icon(LucideIcons.x, size: 22, color: cs.onSurfaceVariant),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (ranges.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: List.generate(ranges.length, (i) {
                  final r = ranges[i];
                  final isSelected = _rangeIndex == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _rangeIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? cs.primary : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${r.start}-${r.end}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId),
                  EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId),
                ]),
                builder: (context, _) {
                  final averageRatings = EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId).value;
                  final countMap = EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId).value;
                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 1,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: rangeEpisodes.length,
                    itemBuilder: (context, i) {
                      final ep = rangeEpisodes[i];
                      final avg = averageRatings[ep.number] ?? 0.0;
                      final count = countMap[ep.number] ?? 0;
                      final hasRating = avg > 0;
                      final myRating = EpisodeRatingService.instance.getMyRating(widget.dramaId, ep.number);
                      return GestureDetector(
                        onTap: () {
                          if (widget.onEpisodeSelected != null) {
                            widget.onEpisodeSelected!(ep.number);
                          } else {
                            _showEpisodeRatingPicker(context, widget.dramaId, ep.number, myRating ?? 0.0);
                          }
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.outline.withOpacity(0.4), width: 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${ep.number}',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Transform.translate(
                                    offset: const Offset(0, 1.5),
                                    child: Icon(
                                      Icons.star_rounded,
                                      size: 10,
                                      color: hasRating ? Colors.amber : _episodeNoRatingColor(context),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    hasRating ? avg.toStringAsFixed(1) : '0',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: hasRating
                                          ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : cs.onSurface)
                                          : _episodeNoRatingColor(context),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 배우 섹션 (출연진)
class _CastSection extends StatelessWidget {
  const _CastSection({required this.castNames, required this.strings});

  final List<String> castNames;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.get('cast'),
          style: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            height: 3.5,
          ),
        ),
        if (castNames.isEmpty)
          Text(
            strings.get('noCastInfo'),
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          )
        else
          Transform.translate(
            offset: const Offset(0, -6),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: castNames.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: Icon(LucideIcons.user, size: 22, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        castNames[i],
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Icon(LucideIcons.chevron_right, size: 18, color: cs.onSurfaceVariant),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 평점 & 리뷰 통합 섹션 - UX 극대화
class _RatingsAndReviewsSection extends StatefulWidget {
  const _RatingsAndReviewsSection({
    required this.dramaId,
    required this.dramaTitle,
    required this.averageRating,
    required this.ratingCount,
    required this.reviews,
    required this.strings,
    required this.onWriteReviewTap,
  });

  final String dramaId;
  final String dramaTitle;
  final double averageRating;
  final int ratingCount;
  final List<DramaReview> reviews;
  final dynamic strings;
  final VoidCallback onWriteReviewTap;

  @override
  State<_RatingsAndReviewsSection> createState() => _RatingsAndReviewsSectionState();
}

class _RatingsAndReviewsSectionState extends State<_RatingsAndReviewsSection> {
  bool _sortByLikes = true;
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    ReviewService.instance.loadIfNeeded();
  }

  int _displayLikeCount(DramaReview r) {
    final base = r.likeCount ?? 0;
    final id = r.id ?? '${r.userName}_${r.timeAgo}';
    return base + (_likedIds.contains(id) ? 1 : 0);
  }

  void _toggleLike(DramaReview r) {
    final id = r.id ?? '${r.userName}_${r.timeAgo}';
    setState(() {
      if (_likedIds.contains(id)) {
        _likedIds.remove(id);
      } else {
        _likedIds.add(id);
      }
    });
  }

  List<DramaReview> get _displayReviews {
    final myReview = ReviewService.instance.getByDramaId(widget.dramaId);
    List<DramaReview> list = List<DramaReview>.from(widget.reviews);
    if (myReview != null) {
      final timeAgo = myReview.modifiedAt != null
          ? '${formatTimeAgo(myReview.modifiedAt!)} (${widget.strings.get('edited')})'
          : formatTimeAgo(myReview.writtenAt);
      final myPhotoUrl = UserProfileService.instance.profileImageUrlNotifier.value;
      final myDramaReview = DramaReview(
        id: myReview.id,
        userName: myReview.authorName ?? '나',
        rating: myReview.rating,
        comment: myReview.comment,
        timeAgo: timeAgo,
        likeCount: 0,
        replies: const [],
        authorPhotoUrl: myPhotoUrl,
      );
      list = list.where((r) => r.id != myReview.id).toList();
      list.insert(0, myDramaReview);
    }
    return list;
  }

  List<DramaReview> get _sortedReviews {
    final list = _displayReviews;
    if (_sortByLikes) {
      final sorted = List<DramaReview>.from(list);
      sorted.sort((a, b) => _displayLikeCount(b).compareTo(_displayLikeCount(a)));
      return sorted;
    }
    return list;
  }

  bool _isMyReview(DramaReview r) {
    final myReview = ReviewService.instance.getByDramaId(widget.dramaId);
    return myReview != null && r.id == myReview.id;
  }

  /// 평균 평점 (사용자 리뷰 반영)
  double get _computedAverageRating {
    final myReview = ReviewService.instance.getByDramaId(widget.dramaId);
    if (myReview == null) return widget.averageRating;
    final baseSum = widget.averageRating * widget.ratingCount;
    final newSum = baseSum + myReview.rating;
    final newCount = widget.ratingCount + 1;
    return newSum / newCount;
  }

  /// 참여 수 (사용자 리뷰 반영)
  int get _computedRatingCount {
    final myReview = ReviewService.instance.getByDramaId(widget.dramaId);
    return myReview != null ? widget.ratingCount + 1 : widget.ratingCount;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              s.get('ratingsAndComments'),
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            TextButton(
              onPressed: widget.onWriteReviewTap,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.get('writeReview'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevron_right,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 종합 평점 요약 (새 리뷰 반영)
        ValueListenableBuilder<List<MyReviewItem>>(
          valueListenable: ReviewService.instance.listNotifier,
          builder: (context, _, __) {
            final cs = Theme.of(context).colorScheme;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onWriteReviewTap();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 6),
                        // 왼쪽 블록: 별 + 평점 + 참여 수
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 60, color: Colors.amber),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _computedAverageRating.toStringAsFixed(1),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${formatCompactCount(_computedRatingCount)} ${s.get('participants')}',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // 오른쪽: 유도 문구 (탭 시 리뷰 작성)
                        Expanded(
                          child: Center(
                            child: Text(
                              s.get('ratingHint'),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                color: cs.onSurfaceVariant,
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // 정렬 탭: 하나의 pill 안에 두 세그먼트 (좋아요순 | 최신순)
        _SortTabsPill(
          sortByLikes: _sortByLikes,
          onSortChanged: (v) => setState(() => _sortByLikes = v),
          strings: s,
        ),
        const SizedBox(height: 16),
        // 리뷰 목록 (없으면 빈 상태: 가장 먼저 리뷰를 작성해 보세요!)
        ValueListenableBuilder<List<MyReviewItem>>(
          valueListenable: ReviewService.instance.listNotifier,
          builder: (context, _, __) {
            final list = _sortedReviews;
            if (list.isEmpty) {
              return _ReviewsEmptyState(onTap: widget.onWriteReviewTap, strings: widget.strings);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: list.map((r) {
                final isMine = _isMyReview(r);
                return _ReviewCard(
                  review: r,
                  likeCount: _displayLikeCount(r),
                  isLiked: _likedIds.contains(r.id ?? '${r.userName}_${r.timeAgo}'),
                  onLikeTap: () => _toggleLike(r),
                  strings: s,
                  isMine: isMine,
                  onEdit: isMine
                      ? () async {
                          final my = ReviewService.instance.getByDramaId(widget.dramaId);
                          if (my != null) {
                            await WriteReviewSheet.show(
                              context,
                              dramaId: widget.dramaId,
                              dramaTitle: widget.dramaTitle,
                              initialRating: my.rating,
                              initialComment: my.comment,
                            );
                            if (context.mounted) setState(() {});
                          }
                        }
                      : null,
                  onDelete: isMine
                      ? () async {
                          final s = CountryScope.of(context).strings;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(s.get('delete'), style: GoogleFonts.notoSansKr()),
                              content: Text(
                                s.get('deleteReviewConfirm'),
                                style: GoogleFonts.notoSansKr(),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(s.get('ok'), style: GoogleFonts.notoSansKr()),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await ReviewService.instance.delete(widget.dramaId);
                            if (context.mounted) setState(() {});
                          }
                        }
                      : null,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

/// 리뷰 0개일 때 빈 상태: 사진처럼 깔끔한 레이아웃 + 리뷰 작성 유도
class _ReviewsEmptyState extends StatelessWidget {
  const _ReviewsEmptyState({required this.onTap, required this.strings});

  final VoidCallback onTap;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EEF5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.pen_line,
                size: 40,
                color: const Color(0xFF5B7FA3),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              strings.get('firstReview'),
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Material(
              color: const Color(0xFF0A84FF),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Text(
                    strings.get('leaveReview'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 정렬 탭: 하나의 pill 컨테이너 안에 두 세그먼트 (좋아요순 | 최신순)
class _SortTabsPill extends StatelessWidget {
  const _SortTabsPill({
    required this.sortByLikes,
    required this.onSortChanged,
    required this.strings,
  });

  final bool sortByLikes;
  final ValueChanged<bool> onSortChanged;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = strings;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicWidth(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 좋아요순 (왼쪽)
            GestureDetector(
              onTap: () => onSortChanged(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sortByLikes ? AppColors.linkBlue : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.thumbs_up,
                      size: 14,
                      color: sortByLikes ? Colors.white : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.get('sortByLikes'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: sortByLikes ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 최신순 (오른쪽)
            GestureDetector(
              onTap: () => onSortChanged(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: !sortByLikes ? AppColors.linkBlue : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 14,
                      color: !sortByLikes ? Colors.white : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.get('sortByLatest'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: !sortByLikes ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 별 1개 + 숫자 (4.5, 5.0 등)
class _StarRow extends StatelessWidget {
  const _StarRow({this.rating = 0, this.size = 16});

  final double? rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = rating ?? 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size, color: Colors.amber),
        SizedBox(width: size * 0.25),
        Text(
          r.toStringAsFixed(1),
          style: GoogleFonts.notoSansKr(
            fontSize: size * 0.875,
            fontWeight: FontWeight.w600,
            color: Colors.amber,
          ),
        ),
      ],
    );
  }
}

/// 눌린 하트 아이콘 - 그라데이션(아래→위) + 테두리
class _LikedHeartIcon extends StatelessWidget {
  const _LikedHeartIcon({this.size = 18});

  final double size;

  static const _colorBottom = Color(0xFFef6682);
  static const _colorTop = Color(0xFFfdaab0);
  static const _colorBorder = Color(0xFFd95d75);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 테두리 (약간 확대)
          Transform.scale(
            scale: 1.12,
            child: Icon(Icons.favorite, size: size, color: _colorBorder),
          ),
          // 그라데이션 (아래→위)
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [_colorBottom, _colorTop],
            ).createShader(bounds),
            child: Icon(Icons.favorite, size: size, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// 답글 입력창 (리뷰 카드 하단)
class _ReplyInput extends StatefulWidget {
  const _ReplyInput({
    required this.strings,
    required this.onSubmitted,
  });

  final dynamic strings;
  final ValueChanged<String> onSubmitted;

  @override
  State<_ReplyInput> createState() => _ReplyInputState();
}

class _ReplyInputState extends State<_ReplyInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final hasText = _controller.text.trim().isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '답글을 입력하세요',
                hintStyle: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: hasText
                ? () {
                    final text = _controller.text.trim();
                    if (text.isEmpty) return;
                    widget.onSubmitted(text);
                    _controller.clear();
                    _focusNode.unfocus();
                  }
                : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              s.get('submit'),
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasText ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 답글 행용 아바타: 프로필 사진 등록되어 있으면 프로필 사진, 없으면 회원 색깔 아이콘 (크기 동일)
class _ReplyRowAvatar extends StatelessWidget {
  const _ReplyRowAvatar({required this.reply});

  static const double _size = 20;

  final DramaReviewReply reply;

  static Widget _greyIconAvatar(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: CircleAvatar(
        radius: _size / 2,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, size: 14, color: Colors.white),
      ),
    );
  }

  static Widget _coloredMemberIcon(int colorIndex) {
    final bg = UserProfileService.bgColorFromIndex(colorIndex);
    final iconColor = UserProfileService.iconColorFromIndex(colorIndex);
    return SizedBox(
      width: _size,
      height: _size,
      child: CircleAvatar(
        radius: _size / 2,
        backgroundColor: bg,
        child: Icon(Icons.person, size: 14, color: iconColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = reply.authorPhotoUrl;
    if (url != null && url.isNotEmpty) {
      return SizedBox(
        width: _size,
        height: _size,
        child: ClipOval(
          child: OptimizedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 40,
            memCacheHeight: 40,
            errorWidget: ValueListenableBuilder<int?>(
              valueListenable: UserProfileService.instance.avatarColorNotifier,
              builder: (_, colorIdx, __) {
                final isMine = reply.author == (UserProfileService.instance.nicknameNotifier.value ?? '나');
                if (isMine && colorIdx != null) return _coloredMemberIcon(colorIdx);
                return _greyIconAvatar(context);
              },
            ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<int?>(
      valueListenable: UserProfileService.instance.avatarColorNotifier,
      builder: (_, colorIdx, __) {
        final isMine = reply.author == (UserProfileService.instance.nicknameNotifier.value ?? '나');
        if (isMine && colorIdx != null) return _coloredMemberIcon(colorIdx);
        return _greyIconAvatar(context);
      },
    );
  }
}

/// 리뷰 아바타: 프로필 사진 등록되어 있으면 프로필 사진, 없으면 회원 색깔 아이콘 (크기 동일)
class _ReviewAvatar extends StatelessWidget {
  const _ReviewAvatar({required this.review, required this.isMine});

  static const double _size = 28;

  final DramaReview review;
  final bool isMine;

  static Widget _greyMemberIcon(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: CircleAvatar(
        radius: _size / 2,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, size: 20, color: Colors.white),
      ),
    );
  }

  static Widget _coloredMemberIcon(int colorIndex) {
    final bg = UserProfileService.bgColorFromIndex(colorIndex);
    final iconColor = UserProfileService.iconColorFromIndex(colorIndex);
    return SizedBox(
      width: _size,
      height: _size,
      child: CircleAvatar(
        radius: _size / 2,
        backgroundColor: bg,
        child: Icon(Icons.person, size: 20, color: iconColor),
      ),
    );
  }

  /// 프로필 사진 있으면 사진 표시, 없으면 회원 색깔 아이콘(또는 타인은 회색 아이콘). 크기 동일.
  Widget _buildWithUrl(BuildContext context, String? url, int? colorIndex) {
    final hasProfilePhoto = url != null && url.trim().isNotEmpty;
    if (hasProfilePhoto) {
      return SizedBox(
        width: _size,
        height: _size,
        child: ClipOval(
          child: OptimizedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            memCacheWidth: 56,
            memCacheHeight: 56,
            errorWidget: colorIndex != null
                ? _coloredMemberIcon(colorIndex)
                : _greyMemberIcon(context),
          ),
        ),
      );
    }
    // 프로필 사진 미등록 → 회원 색깔 아이콘(내 계정) 또는 회색 아이콘(타인)
    if (colorIndex != null) return _coloredMemberIcon(colorIndex);
    return _greyMemberIcon(context);
  }

  @override
  Widget build(BuildContext context) {
    if (isMine) {
      return ValueListenableBuilder<String?>(
        valueListenable: UserProfileService.instance.profileImageUrlNotifier,
        builder: (_, myPhotoUrl, __) {
          final url = review.authorPhotoUrl?.isNotEmpty == true
              ? review.authorPhotoUrl
              : myPhotoUrl;
          return ValueListenableBuilder<int?>(
            valueListenable: UserProfileService.instance.avatarColorNotifier,
            builder: (ctx, colorIdx, __) => _buildWithUrl(ctx, url, colorIdx),
          );
        },
      );
    }
    return _buildWithUrl(context, review.authorPhotoUrl, null);
  }
}

/// 개별 리뷰 카드 - 평점 + 댓글 통합 + 좋아요 + 댓글 아이콘
class _ReviewCard extends StatefulWidget {
  const _ReviewCard({
    required this.review,
    required this.likeCount,
    required this.isLiked,
    required this.onLikeTap,
    required this.strings,
    this.isMine = false,
    this.onEdit,
    this.onDelete,
  });

  final DramaReview review;
  final int likeCount;
  final bool isLiked;
  final VoidCallback onLikeTap;
  final dynamic strings;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _showReplies = false;
  final Set<String> _likedReplyIds = {};
  final List<DramaReviewReply> _localReplies = [];

  int _replyDisplayLikeCount(DramaReviewReply r) {
    final id = r.id ?? '${r.author}_${r.timeAgo}';
    return r.likeCount + (_likedReplyIds.contains(id) ? 1 : 0);
  }

  void _toggleReplyLike(DramaReviewReply r) {
    final id = r.id ?? '${r.author}_${r.timeAgo}';
    setState(() {
      if (_likedReplyIds.contains(id)) {
        _likedReplyIds.remove(id);
      } else {
        _likedReplyIds.add(id);
      }
    });
    HapticFeedback.lightImpact();
  }

  void _addReply(String text) {
    final author = UserProfileService.instance.nicknameNotifier.value ?? '나';
    final photoUrl = UserProfileService.instance.profileImageUrlNotifier.value;
    setState(() {
      _localReplies.add(DramaReviewReply(
        author: author,
        text: text,
        timeAgo: '방금 전',
        likeCount: 0,
        authorPhotoUrl: photoUrl,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final replies = [...review.replies, ..._localReplies];
    final hasReplies = replies.isNotEmpty;

    return GestureDetector(
      onTap: () {
        if (hasReplies) {
          setState(() => _showReplies = !_showReplies);
          HapticFeedback.lightImpact();
        } else {
          setState(() => _showReplies = true);
          HapticFeedback.lightImpact();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ReviewAvatar(
                  review: review,
                  isMine: widget.isMine,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.userName,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _StarRow(rating: review.rating, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            review.timeAgo,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.isMine && (widget.onEdit != null || widget.onDelete != null))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onEdit != null)
                        TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.onEdit!();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            widget.strings.get('edit'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (widget.onDelete != null)
                        TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.onDelete!();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            widget.strings.get('delete'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onLikeTap();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        widget.isLiked
                            ? const _LikedHeartIcon(size: 16)
                            : Icon(Icons.favorite_border, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          widget.likeCount > 0 ? formatCompactCount(widget.likeCount) : '0',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: widget.isLiked ? const Color(0xFFd95d75) : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                InkWell(
                  onTap: () {
                    if (hasReplies) {
                      setState(() => _showReplies = !_showReplies);
                      HapticFeedback.lightImpact();
                    } else {
                      setState(() => _showReplies = true);
                      HapticFeedback.lightImpact();
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.message_circle,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${replies.length}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_showReplies) ...[
              if (hasReplies) ...[
                const SizedBox(height: 10),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: replies.asMap().entries.map((entry) {
                      final r = entry.value;
                      final isLast = entry.key == replies.length - 1;
                      final replyId = r.id ?? '${r.author}_${r.timeAgo}';
                      final isLiked = _likedReplyIds.contains(replyId);
                      final displayCount = _replyDisplayLikeCount(r);
                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ReplyRowAvatar(reply: r),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        r.author,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        r.timeAgo,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 10,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r.text,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _toggleReplyLike(r),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    isLiked
                                        ? const _LikedHeartIcon(size: 14)
                                        : Icon(Icons.favorite_border, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 2),
                                    Text(
                                      displayCount > 0 ? formatCompactCount(displayCount) : '0',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        color: isLiked ? const Color(0xFFd95d75) : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _ReplyInput(strings: widget.strings, onSubmitted: _addReply),
            ],
          ],
        ),
      ),
    );
  }
}

class _SimilarSection extends StatelessWidget {
  const _SimilarSection({required this.similar, required this.strings});

  final List<DramaItem> similar;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    // 설정 언어 기준으로 비슷한 작품 제목·장르·이미지 표시
    final country = CountryScope.maybeOf(context)?.country
        ?? UserProfileService.instance.signupCountryNotifier.value;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.get('similarDramas'),
          style: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: similar.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = similar[i];
              final imageUrl = DramaListService.instance.getDisplayImageUrl(item.id, country);
              final genre = DramaListService.instance.getDisplaySubtitle(item.id, country);
              final rating = item.rating;
              return GestureDetector(
                onTap: () {
                  final detail = DramaListService.instance.buildDetailForItem(item, country);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DramaDetailPage(detail: detail),
                    ),
                  );
                },
                child: SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: 1 / 1.3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: imageUrl != null && imageUrl.isNotEmpty
                              ? OptimizedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: colorScheme.surfaceContainerHighest,
                                    border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                                  ),
                                  child: Center(
                                    child: Icon(LucideIcons.tv, size: 32, color: colorScheme.onSurfaceVariant),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        () {
                          final t = DramaListService.instance.getDisplayTitle(item.id, country);
                          return t.isNotEmpty ? t : item.title;
                        }(),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Transform.translate(
                            offset: const Offset(0, 1.5),
                            child: Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: rating > 0 ? Colors.amber : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            rating > 0 ? rating.toStringAsFixed(1) : '0',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 10,
                              color: rating > 0
                                  ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : colorScheme.onSurface)
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (genre.isNotEmpty) ...[
                            Text(
                              '  ·  ',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 10,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? colorScheme.onSurfaceVariant
                                    : const Color(0xFF424242),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                genre,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? colorScheme.onSurfaceVariant
                                      : const Color(0xFF424242),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
