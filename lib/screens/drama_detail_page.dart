import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../utils/format_utils.dart';
import 'package:flutter/services.dart';
import '../services/play_to_shorts_service.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../services/country_service.dart';
import '../widgets/write_review_sheet.dart';
import '../services/auth_service.dart';
import '../services/drama_list_service.dart';
import '../services/drama_view_service.dart';
import '../services/episode_rating_service.dart';
import '../services/episode_review_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';
import '../services/watchlist_service.dart';
import '../models/drama.dart';
import 'login_page.dart';
import '../widgets/share_sheet.dart';
import '../widgets/review_share_card.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/episode_review_panel.dart';
import 'drama_episode_reviews_screen.dart';
import 'tag_drama_list_screen.dart';
import 'drama_watchers_screen.dart';
import 'drama_reviews_list_screen.dart';
import 'drama_lists_screen.dart';

/// 스탯 바 우측: 워치리스트 토글 (하단 CTA와 동일 동작).
Future<void> _dramaDetailToggleWatchlist(
  BuildContext context,
  String dramaId,
  dynamic strings,
) async {
  if (!AuthService.instance.isLoggedIn.value) {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    if (!context.mounted || !AuthService.instance.isLoggedIn.value) {
      return;
    }
    await WatchlistService.instance.loadIfNeeded(force: true);
    if (!context.mounted) return;
  }
  final country = CountryScope.maybeOf(context)?.country ??
      UserProfileService.instance.signupCountryNotifier.value;
  final wasOn = WatchlistService.instance.isInWatchlist(dramaId);
  await WatchlistService.instance.toggle(dramaId, country);
  if (!context.mounted) return;
  final nowOn = WatchlistService.instance.isInWatchlist(dramaId);
  if (wasOn == nowOn) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        nowOn
            ? strings.get('watchlistToastAdded')
            : strings.get('watchlistToastRemoved'),
        style: GoogleFonts.notoSansKr(),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _StatsBarWatchlistButton extends StatelessWidget {
  const _StatsBarWatchlistButton({
    required this.dramaId,
    required this.strings,
  });

  final String dramaId;
  final dynamic strings;

  /// surfaceContainerHighest 대비 구분되는 선명한 인디고 슬레이트.
  static const Color _kBackground = Color(0xFF404B63);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([
        AuthService.instance.isLoggedIn,
        WatchlistService.instance.itemsNotifier,
      ]),
      builder: (context, _) {
        final on = WatchlistService.instance.isInWatchlist(dramaId);
        final color = on ? AppColors.accent : Colors.white.withValues(alpha: 0.92);
        return Material(
          color: _kBackground,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            splashColor: cs.primary.withValues(alpha: 0.12),
            highlightColor: cs.primary.withValues(alpha: 0.06),
            onTap: () => _dramaDetailToggleWatchlist(context, dramaId, strings),
            child: SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.clock, size: 22, color: color),
                            const SizedBox(height: 3),
                            Text(
                              strings.get('dramaBottomActionWatchlist'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: color,
                                height: 1.12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatsBarSlot extends StatelessWidget {
  const _StatsBarSlot({
    required this.icon,
    this.iconWhenHasCount,
    required this.backgroundColor,
    required this.count,
    required this.labelKey,
    required this.zeroHintKey,
    required this.strings,
    required this.onTap,
  });

  /// 빈 상태·CTA 문구용 (예: 연필, 리스트).
  final IconData icon;

  /// 숫자가 있을 때만 교체 (예: 문서형 리뷰, 레이어형 리스트).
  final IconData? iconWhenHasCount;
  final Color backgroundColor;
  final int count;
  final String labelKey;
  final String zeroHintKey;
  final dynamic strings;
  final VoidCallback onTap;

  static final Color _onCard = Colors.white;
  static final Color _onCardMuted =
      Colors.white.withValues(alpha: 0.9);
  static final Color _onCardHint =
      Colors.white.withValues(alpha: 0.92);

  @override
  Widget build(BuildContext context) {
    final hasCount = count > 0;
    final resolvedIcon =
        hasCount && iconWhenHasCount != null ? iconWhenHasCount! : icon;
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
        onTap: onTap,
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          resolvedIcon,
                          size: 22,
                          color: _onCard.withValues(alpha: 0.96),
                        ),
                        const SizedBox(height: 4),
                        if (hasCount)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                strings.get(labelKey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _onCard,
                                  height: 1.1,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatCompactCount(count),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: _onCardMuted,
                                  height: 1.05,
                                  letterSpacing: -0.15,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            strings.get(zeroHintKey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: _onCardHint,
                              height: 1.15,
                              letterSpacing: -0.1,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 시놉시스 위: 시청(별점 인원)·리뷰 수·리스트·워치리스트 요약.
class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.detail,
    required this.strings,
    required this.onReviewsTap,
    required this.onWatchedTap,
    required this.onListsTap,
    required this.reviewCount,
    required this.watcherCount,
  });

  final DramaDetail detail;
  final dynamic strings;
  final VoidCallback onReviewsTap;
  final VoidCallback onWatchedTap;
  final VoidCallback onListsTap;
  final int reviewCount;
  final int watcherCount;

  static const int _listsCount = 0;

  /// Letterboxd-style stat 타일 — 선명한 채도, 리뷰만 웜 코랄로 슬레이트(워치리스트)와 구분.
  static const Color _kWatchersGreen = Color(0xFF1FA65A);
  static const Color _kReviewsCoral = Color(0xFFFF5C45);
  static const Color _kListsBlue = Color(0xFF2D8CED);

  /// 네 칸 동일 너비·타일 높이(아이콘·한 줄 라벨에 맞춤).
  static const double _rowHeight = 62;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatsBarSlot(
              icon: LucideIcons.eye,
              backgroundColor: _kWatchersGreen,
              count: watcherCount,
              labelKey: 'statsBarWatchersLabel',
              zeroHintKey: 'statsBarFirstWatcher',
              strings: strings,
              onTap: onWatchedTap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatsBarSlot(
              icon: LucideIcons.pencil,
              iconWhenHasCount: LucideIcons.file_text,
              backgroundColor: _kReviewsCoral,
              count: reviewCount,
              labelKey: 'statsBarReviewsLabel',
              zeroHintKey: 'statsBarWriteReview',
              strings: strings,
              onTap: onReviewsTap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatsBarSlot(
              icon: LucideIcons.square_stack,
              backgroundColor: _kListsBlue,
              count: _listsCount,
              labelKey: 'statsBarListsLabel',
              zeroHintKey: 'statsBarMakeList',
              strings: strings,
              onTap: onListsTap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatsBarWatchlistButton(
              dramaId: detail.item.id,
              strings: strings,
            ),
          ),
        ],
      ),
    );
  }
}

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
      WatchHistoryService.instance.loadIfNeeded();
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

  void _openDramaLists(BuildContext context, DramaDetail detail) {
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final locTitle =
        DramaListService.instance.getDisplayTitle(detail.item.id, country);
    final title =
        locTitle.trim().isNotEmpty ? locTitle : detail.item.title;
    final poster = DramaListService.instance.getDisplayImageUrl(
          detail.item.id,
          country,
        ) ??
        detail.item.imageUrl;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DramaListsScreen(
          dramaId: detail.item.id,
          dramaTitle: title,
          dramaPosterUrl: poster,
        ),
      ),
    );
  }

  void _openDramaReviewsList(BuildContext context, DramaDetail detail) {
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final locTitle =
        DramaListService.instance.getDisplayTitle(detail.item.id, country);
    final title =
        locTitle.trim().isNotEmpty ? locTitle : detail.item.title;
    final reviews = _liveReviews ?? detail.reviews;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DramaReviewsListScreen(
          dramaId: detail.item.id,
          dramaTitle: title,
          initialReviews: reviews,
        ),
      ),
    );
  }

  void _openDramaWatchers(BuildContext context, DramaDetail detail) {
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final locTitle =
        DramaListService.instance.getDisplayTitle(detail.item.id, country);
    final title =
        locTitle.trim().isNotEmpty ? locTitle : detail.item.title;
    final reviews = _liveReviews ?? detail.reviews;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DramaWatchersScreen(
          dramaId: detail.item.id,
          dramaTitle: title,
          dramaItem: detail.item,
          initialReviews: reviews,
        ),
      ),
    );
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  _StatsBar(
                    detail: detail,
                    strings: s,
                    onReviewsTap: () => _openDramaReviewsList(context, detail),
                    onWatchedTap: () => _openDramaWatchers(context, detail),
                    onListsTap: () => _openDramaLists(context, detail),
                    reviewCount: (_liveReviews ?? detail.reviews).length,
                    watcherCount: _liveCount ?? detail.ratingCount,
                  ),
                  const SizedBox(height: 24),
                  // 줄거리 (가입 국가별 언어, 위에 장르 태그 pill)
                  _SynopsisSection(detail: detail, strings: s),
                  const SizedBox(height: 24),
                  // 회차 (구간 탭 + 에피소드 버튼)
                  _EpisodesSection(dramaId: detail.item.id, episodes: detail.episodes, strings: s),
                  const SizedBox(height: 24),
                  if (detail.cast.any((n) => n.trim().isNotEmpty)) ...[
                    _CastSection(
                      castNames: detail.cast
                          .map((n) => n.trim())
                          .where((n) => n.isNotEmpty)
                          .toList(),
                      strings: s,
                    ),
                    const SizedBox(height: 28),
                  ],
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
                    onReviewsListTap: () => _openDramaReviewsList(context, detail),
                    onReviewsChanged: () {
                      if (mounted) _loadRatingStats();
                    },
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 비슷한 작품
                  _SimilarSection(
                    dramaId: detail.item.id,
                    genreDisplay: detail.genre,
                    country: CountryScope.maybeOf(context)?.country
                        ?? CountryService.instance.countryNotifier.value,
                    preloadedSimilar: detail.similar,
                    strings: s,
                  ),
                  const SizedBox(height: 32),
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
    final viewsLine = viewsDisplay ?? detail.item.views;

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
                      strings.get('dramaViewCount').replaceAll('%s', viewsLine),
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
              const Spacer(),
              IconButton(
                icon: Icon(LucideIcons.share_2, color: iconColor),
                onPressed: () async {
                  final my = ReviewService.instance.getByDramaId(detail.item.id);
                  if (my != null) {
                    final country = CountryScope.maybeOf(context)?.country
                        ?? UserProfileService.instance.signupCountryNotifier.value;
                    final locTitle = DramaListService.instance.getDisplayTitle(detail.item.id, country);
                    final displayTitle = locTitle.trim().isNotEmpty ? locTitle : detail.item.title;
                    final displayImageUrl =
                        DramaListService.instance.getDisplayImageUrl(detail.item.id, country) ?? detail.item.imageUrl;
                    String? posterUrl;
                    String? posterAsset;
                    if (displayImageUrl != null && displayImageUrl.isNotEmpty) {
                      if (displayImageUrl.startsWith('http')) {
                        posterUrl = displayImageUrl;
                      } else {
                        posterAsset = displayImageUrl;
                      }
                    }
                    final nickRaw = UserProfileService.instance.nicknameNotifier.value?.trim();
                    final nick = (nickRaw != null && nickRaw.isNotEmpty)
                        ? nickRaw
                        : (my.authorName?.trim().isNotEmpty == true ? my.authorName! : 'DramaFeed');
                    await ReviewShareImageHelper.captureAndShare(
                      context,
                      ReviewShareCardData(
                        dramaTitle: displayTitle,
                        rating: my.rating,
                        reviewPreview: my.comment,
                        userNickname: nick,
                        posterUrl: posterUrl,
                        posterAsset: posterAsset,
                      ),
                    );
                  } else {
                    await ShareSheet.show(context, title: detail.item.title, type: 'drama');
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 줄거리: 위에 장르 태그 pill (가로 스크롤) + 본문. 가입 국가별 언어로 표시.
class _SynopsisSection extends StatefulWidget {
  const _SynopsisSection({required this.detail, required this.strings});

  final DramaDetail detail;
  final dynamic strings;

  @override
  State<_SynopsisSection> createState() => _SynopsisSectionState();
}

class _SynopsisSectionState extends State<_SynopsisSection> {
  bool _synopsisExpanded = false;

  @override
  void didUpdateWidget(covariant _SynopsisSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.item.id != widget.detail.item.id) {
      _synopsisExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strings = widget.strings;
    final detail = widget.detail;
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
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                setState(() => _synopsisExpanded = !_synopsisExpanded);
              },
              child: Text(
                displaySynopsis,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.6,
                ),
                maxLines: _synopsisExpanded ? null : 3,
                overflow: _synopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
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
  static const double _headerChevronSize = 14;

  int _rangeIndex = 0;
  int? _selectedEpisodeNumber;
  int? _pendingEpisodeNumber;
  /// 에피소드 구간 탭·가로 카드 목록 접기 (기본 펼침)
  bool _episodesExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EpisodeRatingService.instance.getMyRatingsForDrama(widget.dramaId);
      EpisodeRatingService.instance.loadEpisodeAverageRatings(widget.dramaId);
    });
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Tooltip(
                message:
                    _episodesExpanded ? strings.get('collapse') : strings.get('expand'),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _episodesExpanded = !_episodesExpanded;
                        if (!_episodesExpanded) {
                          _selectedEpisodeNumber = null;
                          _pendingEpisodeNumber = null;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    splashColor: cs.primary.withValues(alpha: 0.14),
                    highlightColor: cs.primary.withValues(alpha: 0.07),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              strings.get('episodes'),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _episodesExpanded
                                ? LucideIcons.chevron_up
                                : LucideIcons.chevron_down,
                            size: _headerChevronSize,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    _showEpisodesBottomSheet(context, episodes, strings),
                borderRadius: BorderRadius.circular(8),
                splashColor: cs.primary.withValues(alpha: 0.14),
                highlightColor: cs.primary.withValues(alpha: 0.07),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings
                            .get('totalEpisodes')
                            .replaceAll('%d', '${episodes.length}'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        LucideIcons.chevron_right,
                        size: _headerChevronSize,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _episodesExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                        final averageRatings =
                            EpisodeRatingService.instance.getAverageNotifierForDrama(widget.dramaId).value;
                        final countMap =
                            EpisodeRatingService.instance.getCountNotifierForDrama(widget.dramaId).value;
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
                              final myRating =
                                  EpisodeRatingService.instance.getMyRating(widget.dramaId, ep.number);
                              return GestureDetector(
                                onTap: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
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
                                              color: hasRating ? Colors.amber : episodeNoRatingColor(context),
                                            ),
                                          ),
                                          SizedBox(width: 12 * 0.25),
                                          Text(
                                            hasRating ? avg.toStringAsFixed(1) : '0',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: hasRating
                                                  ? (Theme.of(context).brightness == Brightness.dark
                                                      ? Colors.white
                                                      : cs.onSurface)
                                                  : episodeNoRatingColor(context),
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
                                EpisodeReviewPanel(
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
        onEpisodeSelected: (episodeNum) {
          Navigator.pop(ctx);
          EpisodeReviewService.instance.loadReviews(widget.dramaId, episodeNum);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DramaEpisodeReviewsScreen(
                  dramaId: widget.dramaId,
                  episodeNumber: episodeNum,
                ),
              ),
            );
          });
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
                                      color: hasRating ? Colors.amber : episodeNoRatingColor(context),
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
                                          : episodeNoRatingColor(context),
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
    required this.onReviewsListTap,
    this.onReviewsChanged,
  });

  final String dramaId;
  final String dramaTitle;
  final double averageRating;
  final int ratingCount;
  final List<DramaReview> reviews;
  final dynamic strings;
  final VoidCallback onWriteReviewTap;
  /// 종합 평점 카드 탭 → 전체 리뷰 화면.
  final VoidCallback onReviewsListTap;
  /// 삭제·수정 후 부모가 서버 리뷰 목록·평점을 다시 불러오도록 할 때 사용.
  final VoidCallback? onReviewsChanged;

  @override
  State<_RatingsAndReviewsSection> createState() => _RatingsAndReviewsSectionState();
}

class _RatingsAndReviewsSectionState extends State<_RatingsAndReviewsSection> {
  bool _sortByLikes = true;
  bool _showAllReviewCards = false;
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    ReviewService.instance.loadIfNeeded();
  }

  Future<void> _shareReviewAsImage(BuildContext context, DramaReview r) async {
    final country = CountryScope.maybeOf(context)?.country
        ?? UserProfileService.instance.signupCountryNotifier.value;
    final locTitle = DramaListService.instance.getDisplayTitle(widget.dramaId, country).trim();
    final displayTitle = locTitle.isNotEmpty ? locTitle : widget.dramaTitle;
    final displayImageUrl = DramaListService.instance.getDisplayImageUrl(widget.dramaId, country);
    String? posterUrl;
    String? posterAsset;
    if (displayImageUrl != null && displayImageUrl.isNotEmpty) {
      if (displayImageUrl.startsWith('http')) {
        posterUrl = displayImageUrl;
      } else {
        posterAsset = displayImageUrl;
      }
    }
    await ReviewShareImageHelper.captureAndShare(
      context,
      ReviewShareCardData(
        dramaTitle: displayTitle,
        rating: r.rating,
        reviewPreview: r.comment,
        userNickname: r.userName,
        posterUrl: posterUrl,
        posterAsset: posterAsset,
      ),
    );
  }

  int _displayLikeCount(DramaReview r) {
    final base = r.likeCount ?? 0;
    final id = r.id ?? '${r.userName}_${r.timeAgo}';
    return base + (_likedIds.contains(id) ? 1 : 0);
  }

  Widget _buildRatingSpotlightColumn(ColorScheme cs, dynamic s) {
    final r = _spotlightReview;
    if (r == null) {
      return Center(
        child: Text(
          s.get('dramaSpotlightNoReviews'),
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      );
    }
    final likes = _displayLikeCount(r);
    final body = r.comment.trim();
    // 평균 점수 블록 오른쪽: 본문만 (닉네임 없음). 좋아요는 본문 아래 보조로만.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            body.isNotEmpty ? body : '—',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: body.isNotEmpty ? FontWeight.w400 : FontWeight.w500,
              color: body.isNotEmpty
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withValues(alpha: 0.45),
              height: 1.45,
            ),
          ),
          if (likes > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.heart, size: 13, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  formatCompactCount(likes),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: false);

  DateTime _reviewTimestamp(DramaReview r) => r.writtenAt ?? _epoch;

  /// 평점 카드 오른쪽 스포트라이트: 좋아요 최다 → 동률·전부 0이면 최신.
  DramaReview? get _spotlightReview {
    final reviews = _displayReviews;
    if (reviews.isEmpty) return null;
    var maxLikes = 0;
    for (final r in reviews) {
      final n = _displayLikeCount(r);
      if (n > maxLikes) maxLikes = n;
    }
    if (maxLikes > 0) {
      final best = reviews.where((r) => _displayLikeCount(r) == maxLikes).toList()
        ..sort((a, b) => _reviewTimestamp(b).compareTo(_reviewTimestamp(a)));
      return best.first;
    }
    final sorted = List<DramaReview>.from(reviews)
      ..sort((a, b) => _reviewTimestamp(b).compareTo(_reviewTimestamp(a)));
    return sorted.first;
  }

  Set<String> get _myReviewIdsForDrama => ReviewService.instance.list
      .where((e) => e.dramaId == widget.dramaId)
      .map((e) => e.id)
      .toSet();

  DramaReview _localMyReviewToCard(MyReviewItem my) {
    final timeAgo = my.modifiedAt != null
        ? '${formatTimeAgo(my.modifiedAt!)} (${widget.strings.get('edited')})'
        : formatTimeAgo(my.writtenAt);
    final myPhotoUrl = UserProfileService.instance.profileImageUrlNotifier.value;
    return DramaReview(
      id: my.id,
      userName: my.authorName ?? '나',
      rating: my.rating,
      comment: my.comment,
      timeAgo: timeAgo,
      likeCount: 0,
      replies: const [],
      authorPhotoUrl: myPhotoUrl,
      writtenAt: my.modifiedAt ?? my.writtenAt,
    );
  }

  List<DramaReview> get _displayReviews {
    final myIds = _myReviewIdsForDrama;
    final list = List<DramaReview>.from(widget.reviews);
    list.removeWhere((r) {
      final id = r.id;
      return id != null && id.isNotEmpty && myIds.contains(id);
    });
    final mine = ReviewService.instance.list
        .where((e) => e.dramaId == widget.dramaId)
        .toList()
      ..sort((a, b) {
        final tb = b.modifiedAt ?? b.writtenAt;
        final ta = a.modifiedAt ?? a.writtenAt;
        return tb.compareTo(ta);
      });
    final head = mine.map(_localMyReviewToCard).toList();
    return [...head, ...list];
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
    final id = r.id;
    if (id == null || id.isEmpty) return false;
    return _myReviewIdsForDrama.contains(id);
  }

  /// Firestore 집계에 내 여러 건이 이미 포함되므로 그대로 사용.
  double get _computedAverageRating => widget.averageRating;

  int get _computedRatingCount => widget.ratingCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.get('ratingsAndComments'),
          style: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        // 평균·스포트라이트 + 정렬 + 리뷰 목록을 한 카드로 통합
        ValueListenableBuilder<List<MyReviewItem>>(
          valueListenable: ReviewService.instance.listNotifier,
          builder: (context, _, __) {
            final list = _sortedReviews;
            final hasReviews = list.isNotEmpty;
            final preview = hasReviews
                ? (_showAllReviewCards ? list : list.take(3).toList())
                : const <DramaReview>[];

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
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: widget.onReviewsListTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(width: 6),
                            Icon(Icons.star_rounded, size: 60, color: Colors.amber),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
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
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildRatingSpotlightColumn(cs, s)),
                          ],
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: cs.outline.withValues(alpha: 0.12),
                    ),
                    if (!hasReviews)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ReviewsEmptyState(
                          onTap: widget.onWriteReviewTap,
                          strings: widget.strings,
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: _SortTabsPill(
                          sortByLikes: _sortByLikes,
                          onSortChanged: (v) => setState(() {
                            _sortByLikes = v;
                            _showAllReviewCards = false;
                          }),
                          strings: s,
                        ),
                      ),
                      ...preview.asMap().entries.expand((e) {
                        final i = e.key;
                        final r = e.value;
                        final isMine = _isMyReview(r);
                        final card = _ReviewCard(
                          review: r,
                          likeCount: _displayLikeCount(r),
                          isLiked: _likedIds.contains(
                            r.id ?? '${r.userName}_${r.timeAgo}',
                          ),
                          onLikeTap: () => _toggleLike(r),
                          strings: s,
                          isMine: isMine,
                          embeddedInMergedSection: true,
                          onShareReview: () => _shareReviewAsImage(context, r),
                          onEdit: isMine && (r.id != null && r.id!.isNotEmpty)
                              ? () async {
                                  final my = ReviewService.instance.getById(r.id!);
                                  if (my != null) {
                                    await WriteReviewSheet.show(
                                      context,
                                      dramaId: widget.dramaId,
                                      dramaTitle: widget.dramaTitle,
                                      editingReviewId: my.id,
                                      initialRating: my.rating,
                                      initialComment: my.comment,
                                    );
                                    if (context.mounted) {
                                      widget.onReviewsChanged?.call();
                                      setState(() {
                                        _showAllReviewCards = false;
                                      });
                                    }
                                  }
                                }
                              : null,
                          onDelete: isMine && (r.id != null && r.id!.isNotEmpty)
                              ? () async {
                                  final dlg = CountryScope.of(context).strings;
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(
                                        dlg.get('delete'),
                                        style: GoogleFonts.notoSansKr(),
                                      ),
                                      content: Text(
                                        dlg.get('deleteReviewConfirm'),
                                        style: GoogleFonts.notoSansKr(),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: Text(
                                            dlg.get('cancel'),
                                            style: GoogleFonts.notoSansKr(),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: Text(
                                            dlg.get('ok'),
                                            style: GoogleFonts.notoSansKr(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await ReviewService.instance.deleteById(r.id!);
                                    widget.onReviewsChanged?.call();
                                    if (context.mounted) {
                                      setState(() {
                                        _showAllReviewCards = false;
                                      });
                                    }
                                  }
                                }
                              : null,
                        );
                        if (i == 0) return [card];
                        return [
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: 16,
                            endIndent: 16,
                            color: cs.outline.withValues(alpha: 0.08),
                          ),
                          card,
                        ];
                      }),
                      if (list.length > 3 && !_showAllReviewCards)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                          child: Center(
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _showAllReviewCards = true),
                              child: Text(
                                s.get('dramaAllReviewsCta'),
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.pen_line,
                size: 26,
                color: cs.onSurface.withValues(alpha: 0.88),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              strings.get('firstReview'),
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                strings.get('leaveReview'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 정렬 탭: 어두운 트랙 + 선택 시 블루그레이 블록 (텍스트만, 50/50)
class _SortTabsPill extends StatelessWidget {
  const _SortTabsPill({
    required this.sortByLikes,
    required this.onSortChanged,
    required this.strings,
  });

  static const _selectedBg = Color(0xFF5D6D7E);
  static const _inactiveTextDark = Color(0xFF999999);
  static const _trackDark = Color(0xFF1A1A1A);
  static const _trackBorderDark = Color(0xFF333333);

  final bool sortByLikes;
  final ValueChanged<bool> onSortChanged;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outerBg = isDark ? _trackDark : cs.surfaceContainerHighest;
    final outerBorder = isDark ? _trackBorderDark : cs.outline.withValues(alpha: 0.35);
    final inactiveText =
        isDark ? _inactiveTextDark : cs.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: outerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outerBorder, width: 1),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onSortChanged(true),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sortByLikes ? _selectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s.get('sortByLikes'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: sortByLikes ? FontWeight.w700 : FontWeight.w400,
                    color: sortByLikes ? Colors.white : inactiveText,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onSortChanged(false),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !sortByLikes ? _selectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s.get('sortByLatest'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: !sortByLikes ? FontWeight.w700 : FontWeight.w400,
                    color: !sortByLikes ? Colors.white : inactiveText,
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
    this.onShareReview,
    /// true: 평점 요약과 같은 큰 카드 안 — 개별 그림자·배경 카드 제거.
    this.embeddedInMergedSection = false,
  });

  final DramaReview review;
  final int likeCount;
  final bool isLiked;
  final VoidCallback onLikeTap;
  final dynamic strings;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShareReview;
  final bool embeddedInMergedSection;

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
        margin: widget.embeddedInMergedSection
            ? EdgeInsets.zero
            : const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: widget.embeddedInMergedSection
            ? null
            : BoxDecoration(
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
                if (widget.onShareReview != null) ...[
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onShareReview?.call();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Icon(LucideIcons.share_2, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
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

class _SimilarSection extends StatefulWidget {
  const _SimilarSection({
    required this.dramaId,
    required this.genreDisplay,
    required this.country,
    this.preloadedSimilar = const [],
    required this.strings,
  });

  final String dramaId;
  final String genreDisplay;
  /// 부모 build()에서 확정된 국가 코드 — CountryService 폴백 포함.
  final String? country;
  final List<DramaItem> preloadedSimilar;
  final dynamic strings;

  @override
  State<_SimilarSection> createState() => _SimilarSectionState();
}

class _SimilarSectionState extends State<_SimilarSection> {
  List<DramaItem> _similar = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedSimilar.isNotEmpty) {
      _similar = widget.preloadedSimilar;
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 한 프레임 그린 뒤 + microtask로 무거운 장르 스캔을 조금 미뤄 전환 애니메이션이 끊기지 않게 함
        Future<void>.microtask(() {
          if (!mounted) return;
          // country는 부모에서 확정된 값(CountryService 폴백 포함)을 그대로 사용
          final country = widget.country
              ?? CountryService.instance.countryNotifier.value;
          final list = DramaListService.instance.getSimilarByGenre(
            widget.dramaId,
            widget.genreDisplay,
            country,
            limit: 8,
            maxScan: 700,
          );
          if (!mounted) return;
          setState(() {
            _similar = list;
            _loading = false;
          });
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = widget.country
        ?? CountryScope.maybeOf(context)?.country
        ?? CountryService.instance.countryNotifier.value;
    final colorScheme = Theme.of(context).colorScheme;
    final strings = widget.strings;
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
          child: _loading && _similar.isEmpty
              ? Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colorScheme.primary,
                    ),
                  ),
                )
              : ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _similar.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = _similar[i];
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
