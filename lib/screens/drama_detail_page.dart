import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
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
import '../services/post_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/custom_drama_list_service.dart';
import '../services/watch_history_service.dart';
import '../services/watchlist_service.dart';
import '../services/locale_service.dart';
import '../constants/app_profile_avatar_size.dart';
import '../models/drama.dart';
import 'login_page.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/drama_reviews_list_feed_row.dart';
import '../widgets/feed_inline_action_colors.dart';
import '../widgets/green_rating_stars.dart';
import '../widgets/episode_review_panel.dart';
import '../widgets/app_delete_confirm_dialog.dart';
import '../widgets/user_profile_nav.dart';
import 'drama_episode_reviews_screen.dart';
import 'tag_drama_list_screen.dart';
import 'drama_watchers_screen.dart';
import 'drama_reviews_list_screen.dart';
import 'drama_lists_screen.dart';

TextStyle _detailSectionCapsLabel(ColorScheme cs) => GoogleFonts.notoSansKr(
  fontSize: 16,
  fontWeight: FontWeight.w800,
  letterSpacing: 2.0,
  height: 1.0,
  color: cs.onSurface.withValues(alpha: 0.90),
);

/// 섹션 캡션 가로 확장(1.1)은 **영어(us)** UI에서만 적용.
double _detailCapsScaleX() =>
    LocaleService.instance.locale == 'us' ? 1.1 : 1.0;

Widget _detailCapsTitleText(
  String text,
  ColorScheme cs, {
  int? maxLines,
  TextOverflow? overflow,
}) {
  final scaleX = _detailCapsScaleX();
  final child = Text(
    text,
    style: _detailSectionCapsLabel(cs),
    maxLines: maxLines,
    overflow: overflow,
  );
  if (scaleX == 1.0) return child;
  return Transform.scale(
    scaleX: scaleX,
    alignment: Alignment.centerLeft,
    child: child,
  );
}

Widget _sectionLabel(String text, ColorScheme cs) =>
    _detailCapsTitleText(text, cs);

/// 스탯 타일 텍스트: CTA 1줄 ↔ 라벨+숫자 2줄 전환 시에도 동일 높이·세로 중앙 유지.
const double _kStatsBarTextLine1BoxHeight = 15;
const double _kStatsBarTextLine2Gap = 2;
const double _kStatsBarTextLine2BoxHeight = 12;

class _StatsBarWatchlistButton extends StatelessWidget {
  const _StatsBarWatchlistButton({
    required this.dramaId,
    required this.userCount,
    required this.strings,
    required this.onTap,
  });

  final String dramaId;

  /// 이 드라마를 워치리스트에 둔 전체 유저 수.
  final int userCount;
  final dynamic strings;
  final VoidCallback onTap;

  /// surfaceContainerHighest 대비 구분되는 선명한 인디고 슬레이트.
  static const Color _kBackground = Color(0xFF404B63);

  /// 워치리스트 미담김: 배지 채움 + 플러스 (파란 배경 + 밝은 글리프).
  static const Color _kWatchlistBadgePlusFill = Color(0xFF1E88E5);
  static const Color _kWatchlistBadgePlusGlyph = Color(0xFFFFFFFF);

  /// 워치리스트 담김: 빨간 배지 + 마이너스.
  static const Color _kWatchlistBadgeMinusFill = Color(0xFFE53935);
  static const Color _kWatchlistBadgeMinusGlyph = Color(0xFFFFFFFF);

  static const double _clockSize = 22;
  static const double _badgeSize = 12;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([
        AuthService.instance.isLoggedIn,
        WatchlistService.instance.itemsNotifier,
      ]),
      builder: (context, _) {
        final iconColor = cs.onSurface;
        final did = dramaId.trim();
        final inList =
            AuthService.instance.isLoggedIn.value &&
            did.isNotEmpty &&
            WatchlistService.instance.isInWatchlist(did);
        final labelColor = cs.onSurface;
        return Material(
          color: _kBackground,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            splashColor: cs.primary.withValues(alpha: 0.12),
            highlightColor: cs.primary.withValues(alpha: 0.06),
            onTap: onTap,
            child: SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: _clockSize + 2,
                              height: _clockSize,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.clock,
                                    size: _clockSize,
                                    color: iconColor,
                                  ),
                                  Positioned(
                                    right: -1,
                                    bottom: 0,
                                    child: inList
                                        ? Container(
                                            width: _badgeSize,
                                            height: _badgeSize,
                                            alignment: Alignment.center,
                                            decoration: const BoxDecoration(
                                              color: _kWatchlistBadgeMinusFill,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              LucideIcons.minus,
                                              size: 8,
                                              color: _kWatchlistBadgeMinusGlyph,
                                            ),
                                          )
                                        : Container(
                                            width: _badgeSize,
                                            height: _badgeSize,
                                            alignment: Alignment.center,
                                            decoration: const BoxDecoration(
                                              color: _kWatchlistBadgePlusFill,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              LucideIcons.plus,
                                              size: 8,
                                              color: _kWatchlistBadgePlusGlyph,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: _kStatsBarTextLine1BoxHeight,
                                  width: double.infinity,
                                  child: Center(
                                    child: Text(
                                      strings.get('dramaBottomActionWatchlist'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: labelColor,
                                        height: 1.1,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: _kStatsBarTextLine2Gap),
                                SizedBox(
                                  height: _kStatsBarTextLine2BoxHeight,
                                  width: double.infinity,
                                  child: Center(
                                    child: Text(
                                      formatCompactCount(userCount),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: labelColor.withValues(alpha: 0.88),
                                        height: 1.05,
                                        letterSpacing: -0.15,
                                      ),
                                    ),
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
    required this.strings,
    required this.onTap,
    /// 집계 전에도 보조 아이콘(예: 리뷰 문서)을 쓸지 — [peek] 등으로 별점 건수가 있을 때.
    this.useSecondaryIcon = false,
  });

  final IconData icon;
  final IconData? iconWhenHasCount;
  final Color backgroundColor;
  final int count;
  final String labelKey;
  final dynamic strings;
  final VoidCallback onTap;
  final bool useSecondaryIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelColor = cs.onSurface;
    final resolvedIcon =
        (count > 0 || useSecondaryIcon) && iconWhenHasCount != null
            ? iconWhenHasCount!
            : icon;

    final line1Style = GoogleFonts.notoSansKr(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: labelColor,
      height: 1.1,
      letterSpacing: -0.2,
    );

    final line2Style = GoogleFonts.notoSansKr(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: labelColor.withValues(alpha: 0.88),
      height: 1.05,
      letterSpacing: -0.15,
    );

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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(resolvedIcon, size: 22, color: labelColor),
                        const SizedBox(height: 4),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: _kStatsBarTextLine1BoxHeight,
                              width: double.infinity,
                              child: Center(
                                child: Text(
                                  strings.get(labelKey),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: line1Style,
                                ),
                              ),
                            ),
                            SizedBox(height: _kStatsBarTextLine2Gap),
                            SizedBox(
                              height: _kStatsBarTextLine2BoxHeight,
                              width: double.infinity,
                              child: Center(
                                child: Text(
                                  formatCompactCount(count),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: line2Style,
                                ),
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
    required this.onWatchlistTap,
    required this.reviewCount,
    required this.watcherCount,
    required this.watchlistUserCount,
    /// 리스트가 비어 있어도 캐시된 별점 건수가 있으면 문서 아이콘(첫 프레임부터).
    this.reviewUseFileIcon = false,
  });

  final DramaDetail detail;
  final dynamic strings;
  final VoidCallback onReviewsTap;
  final VoidCallback onWatchedTap;
  final VoidCallback onListsTap;
  final VoidCallback onWatchlistTap;
  final int reviewCount;
  final int watcherCount;
  final int watchlistUserCount;
  final bool reviewUseFileIcon;

  /// Letterboxd-style stat 타일 — 선명한 채도, 리뷰만 웜 코랄로 슬레이트(워치리스트)와 구분.
  static const Color _kWatchersGreen = Color(0xFF1FA65A);
  static const Color _kReviewsCoral = Color(0xFFFF5C45);
  static const Color _kListsBlue = Color(0xFF2D8CED);

  /// 네 칸 동일 너비·타일 높이 (내부는 세로 패딩 3+콘텐츠로 62 안에 맞춤).
  static const double _rowHeight = 62;

  @override
  Widget build(BuildContext context) {
    final dramaId = detail.item.id;
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
              strings: strings,
              onTap: onReviewsTap,
              useSecondaryIcon: reviewUseFileIcon,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: CustomDramaListService.instance.listsNotifier,
              builder: (context, lists, _) {
                final listCount = lists
                    .where((l) => l.dramaIds.contains(dramaId))
                    .length;
                return _StatsBarSlot(
                  icon: LucideIcons.square_stack,
                  backgroundColor: _kListsBlue,
                  count: listCount,
                  labelKey: 'statsBarListsLabel',
                  strings: strings,
                  onTap: onListsTap,
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatsBarWatchlistButton(
              dramaId: detail.item.id,
              userCount: watchlistUserCount,
              strings: strings,
              onTap: onWatchlistTap,
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
    /// [openFromItem] 등에서 워치리스트 집계를 미리 받아 첫 프레임부터 반영.
    this.prefetchedWatchlistUserCount,
  });

  final DramaDetail detail;
  final bool scrollToRatings;

  /// 서버 집계를 넘기면 상세 내부에서 다시 기다리지 않아도 됨.
  final int? prefetchedWatchlistUserCount;

  /// 카탈로그에서 진입: 동기 [buildDetailForItem]만으로 바로 푸시(목록에서 멈춤 없음).
  /// 집계는 상세 [initState]의 [_loadRatingStats]에서 로드.
  static Future<void> openFromItem(
    BuildContext context,
    DramaItem item, {
    String? country,
    bool scrollToRatings = false,
  }) async {
    final detail =
        DramaListService.instance.buildDetailForItem(item, country);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: const Duration(milliseconds: 100),
        opaque: true,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            ),
            child: DramaDetailPage(
              key: ValueKey<String>(detail.item.id),
              detail: detail,
              scrollToRatings: scrollToRatings,
            ),
          );
        },
      ),
    );
  }

  @override
  State<DramaDetailPage> createState() => _DramaDetailPageState();
}

class _DramaDetailPageState extends State<DramaDetailPage> {
  final _ratingsKey = GlobalKey();
  double? _liveAverage;
  int? _liveCount;
  List<DramaReview>? _liveReviews;
  int? _liveViews;
  int _watchlistUserCount = 0;

  /// [itemsNotifier]와 전역 집계가 어긋나지 않게: 초기 [loadIfNeeded] 이후에만 델타 반영.
  bool _watchlistListenerPrimed = false;

  /// 이 드라마가 내 워치리스트에 있는지(다른 화면에서 삭제·추가 시 델타용).
  bool _wlHadCurrentDrama = false;

  /// feedPostId → (likeCount, commentCount) from posts collection.
  /// Overrides the potentially-stale likeCount stored in drama_reviews docs.
  Map<String, ({int likeCount, int commentCount, bool isLiked})>
  _reviewPostMeta = {};

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

  /// 시스템 뒤로 등: Navigator 잠금과 겹치지 않게 [pop] 연기.
  Future<void> _popDetailRouteWithResult(Map<String, int>? resultToPass) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (!nav.canPop()) return;
    nav.pop(resultToPass);
  }

  Future<void> _loadRatingStats({bool ignoreDetailCache = false}) async {
    final dramaId = widget.detail.item.id;
    final country = mounted
        ? (CountryScope.maybeOf(context)?.country ??
              UserProfileService.instance.signupCountryNotifier.value)
        : UserProfileService.instance.signupCountryNotifier.value;
    try {
      final preloaded =
          widget.detail.reviews.isNotEmpty && !ignoreDetailCache;

      if (preloaded) {
        // [DramaDetail]에 리뷰가 이미 채워져 있음 → drama_reviews 재조회 생략.
        int wlCount = _watchlistUserCount;
        if (widget.prefetchedWatchlistUserCount == null) {
          final results = await Future.wait<Object?>([
            WatchlistService.instance
                .countUsersIncludingDrama(dramaId)
                .timeout(const Duration(seconds: 10), onTimeout: () => null),
          ]);
          if (!mounted) return;
          final watchN = results[0] as int?;
          final userHasIt = WatchlistService.instance.isInWatchlist(dramaId);
          if (watchN != null) {
            wlCount = (userHasIt && watchN < 1) ? 1 : watchN;
          }
        }
        if (!mounted) return;
        setState(() {
          _liveAverage = widget.detail.averageRating;
          _liveCount = widget.detail.ratingCount;
          _liveReviews = widget.detail.reviews;
          _watchlistUserCount = wlCount;
          if (_watchlistListenerPrimed) {
            _wlHadCurrentDrama =
                WatchlistService.instance.isInWatchlist(dramaId);
          }
        });
        final ids = _reviewPostIds(widget.detail.reviews);
        if (ids.isNotEmpty) {
          unawaited(_kickBatchReviewPostMeta(ids));
        }
        return;
      }

      // drama_reviews + 워치리스트 집계 → 한 setState에 반영.
      final results = await Future.wait<Object?>([
        ReviewService.instance
            .getDramaReviewDetailBundle(dramaId, country: country)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () =>
                  (average: 0.0, count: 0, reviews: <DramaReview>[]),
            ),
        WatchlistService.instance
            .countUsersIncludingDrama(dramaId)
            .timeout(const Duration(seconds: 10), onTimeout: () => null),
      ]);
      if (!mounted) return;
      final bundle = results[0]
          as ({double average, int count, List<DramaReview> reviews});
      final watchN = results[1] as int?;
      final userHasIt = WatchlistService.instance.isInWatchlist(dramaId);
      int wlCount = _watchlistUserCount;
      if (watchN != null) {
        wlCount = (userHasIt && watchN < 1) ? 1 : watchN;
      }
      setState(() {
        _liveAverage = bundle.average;
        _liveCount = bundle.count;
        _liveReviews = bundle.reviews;
        _watchlistUserCount = wlCount;
        if (_watchlistListenerPrimed) {
          _wlHadCurrentDrama =
              WatchlistService.instance.isInWatchlist(dramaId);
        }
      });
      final ids = _reviewPostIds(bundle.reviews);
      if (ids.isNotEmpty) {
        unawaited(_kickBatchReviewPostMeta(ids));
      }
    } catch (_) {}
  }

  /// 스탯 바·리뷰 행은 이미 반영된 뒤 호출 — posts 메타만 보강(추가 setState, 스탯 레이아웃 불변).
  Future<void> _kickBatchReviewPostMeta(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final meta = await PostService.instance
          .batchGetPostMeta(ids)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () =>
                <String, ({int likeCount, int commentCount, bool isLiked})>{},
          );
      if (!mounted || meta.isEmpty) return;
      setState(() => _reviewPostMeta = {..._reviewPostMeta, ...meta});
      final uncovered = ids.where((id) => !meta.containsKey(id)).toList();
      if (uncovered.isNotEmpty) unawaited(_fetchReviewPostMeta(uncovered));
    } catch (_) {}
  }

  /// Extracts unique feedPostId / id strings for a list of reviews.
  List<String> _reviewPostIds(List<DramaReview> reviews) {
    return reviews
        .map((r) {
          final fp = r.feedPostId?.trim();
          if (fp != null && fp.isNotEmpty) return fp;
          return r.id?.trim() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _fetchReviewPostMeta(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final meta = await PostService.instance.batchGetPostMeta(ids);
      if (!mounted || meta.isEmpty) return;
      setState(() => _reviewPostMeta = {..._reviewPostMeta, ...meta});
    } catch (_) {}
  }

  Future<void> _loadWatchlistUserCount() async {
    final dramaId = widget.detail.item.id;
    try {
      final n = await WatchlistService.instance
          .countUsersIncludingDrama(dramaId)
          .timeout(const Duration(seconds: 10));
      if (!mounted || n == null) return;
      // Firestore count aggregation can lag behind a very recent write.
      // If the current user has this drama in their watchlist but the server
      // count seems too low, bump by 1 so the UI is never stale after adding.
      final userHasIt = WatchlistService.instance.isInWatchlist(dramaId);
      final corrected = (userHasIt && n < 1) ? 1 : n;
      setState(() => _watchlistUserCount = corrected);
    } catch (_) {
      // 타임아웃·네트워크 오류: 낙관적/이전 숫자 유지 (0으로 덮지 않음)
    }
  }

  @override
  void initState() {
    super.initState();
    final dramaId = widget.detail.item.id;
    final d = widget.detail;

    if (widget.prefetchedWatchlistUserCount != null) {
      _watchlistUserCount = widget.prefetchedWatchlistUserCount!;
    } else if (WatchlistService.instance.isInWatchlist(dramaId)) {
      _watchlistUserCount = 1;
    }

    if (d.reviews.isNotEmpty) {
      _liveReviews = d.reviews;
      _liveAverage = d.averageRating;
      _liveCount = d.ratingCount;
    } else if (d.ratingCount > 0) {
      _liveAverage = d.averageRating;
      _liveCount = d.ratingCount;
    } else if (dramaId.isNotEmpty) {
      final peek = ReviewService.instance.peekDramaAggregateStats(dramaId);
      if (peek != null) {
        _liveAverage = peek.average;
        _liveCount = peek.count;
      }
    }

    LocaleService.instance.localeNotifier.addListener(
      _reloadEpisodeRatingsForLocaleChange,
    );
    ReviewService.instance.listNotifier.addListener(_onMyReviewsListChanged);
    WatchlistService.instance.itemsNotifier.addListener(
      _onWatchlistItemsChanged,
    );
    // 리뷰·워치리스트 집계는 즉시 시작. posts 메타는 [_kickBatchReviewPostMeta]에서 비동기만.
    unawaited(_loadRatingStats().catchError((_) {}));
    // 첫 프레임·전환 애니메이션 후에 나머지 네트워크·서비스 로드 → 탭 직후 멈춤 체감 완화
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final id = widget.detail.item.id;
      if (id.isNotEmpty) {
        unawaited(EpisodeRatingService.instance.getMyRatingsForDrama(id));
        unawaited(EpisodeRatingService.instance.loadEpisodeAverageRatings(id));
      }
      unawaited(_updateViewCount().catchError((_) {}));
      unawaited(WatchHistoryService.instance.loadIfNeeded());
      unawaited(CustomDramaListService.instance.loadIfNeeded());
      await WatchlistService.instance.loadIfNeeded();
      if (!mounted) return;
      final did = id.trim();
      _wlHadCurrentDrama = did.isNotEmpty &&
          AuthService.instance.isLoggedIn.value &&
          WatchlistService.instance.isInWatchlist(did);
      _watchlistListenerPrimed = true;
      if (widget.scrollToRatings) {
        WidgetsBinding.instance.addPostFrameCallback((__) {
          if (!mounted) return;
          Scrollable.ensureVisible(
            _ratingsKey.currentContext!,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        });
      }
    });
  }

  void _onWatchlistItemsChanged() {
    if (!mounted || !_watchlistListenerPrimed) return;
    final did = widget.detail.item.id.trim();
    if (did.isEmpty || !AuthService.instance.isLoggedIn.value) return;
    final has = WatchlistService.instance.isInWatchlist(did);
    if (has == _wlHadCurrentDrama) return;
    final was = _wlHadCurrentDrama;
    _wlHadCurrentDrama = has;
    setState(() {
      if (was && !has) {
        _watchlistUserCount =
            _watchlistUserCount > 0 ? _watchlistUserCount - 1 : 0;
      } else if (!was && has) {
        _watchlistUserCount += 1;
      }
    });
    unawaited(_loadWatchlistUserCount());
  }

  void _reloadEpisodeRatingsForLocaleChange() {
    final id = widget.detail.item.id.trim();
    if (id.isEmpty) return;
    EpisodeRatingService.instance.invalidateEpisodeDataForDrama(id);
    EpisodeReviewService.instance.clearNotifiersForDrama(id);
    unawaited(EpisodeRatingService.instance.getMyRatingsForDrama(id));
    unawaited(EpisodeRatingService.instance.loadEpisodeAverageRatings(id));
  }

  void _onMyReviewsListChanged() {
    if (!mounted) return;
    unawaited(_loadRatingStats(ignoreDetailCache: true).catchError((_) {}));
  }

  @override
  void dispose() {
    WatchlistService.instance.itemsNotifier.removeListener(
      _onWatchlistItemsChanged,
    );
    ReviewService.instance.listNotifier.removeListener(
      _onMyReviewsListChanged,
    );
    LocaleService.instance.localeNotifier.removeListener(
      _reloadEpisodeRatingsForLocaleChange,
    );
    super.dispose();
  }

  void _openDramaLists(BuildContext context, DramaDetail detail) {
    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final locTitle = DramaListService.instance.getDisplayTitle(
      detail.item.id,
      country,
    );
    final title = locTitle.trim().isNotEmpty ? locTitle : detail.item.title;
    final poster =
        DramaListService.instance.getDisplayImageUrl(detail.item.id, country) ??
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
    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final locTitle = DramaListService.instance.getDisplayTitle(
      detail.item.id,
      country,
    );
    final title = locTitle.trim().isNotEmpty ? locTitle : detail.item.title;
    final reviews = _visibleRatingsAndReviews(_liveReviews ?? detail.reviews);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DramaReviewsListScreen(
          dramaId: detail.item.id,
          dramaTitle: title,
          initialReviews: reviews,
          initialPostMeta: _reviewPostMeta,
        ),
      ),
    );
  }

  void _openDramaWatchers(BuildContext context, DramaDetail detail) {
    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final locTitle = DramaListService.instance.getDisplayTitle(
      detail.item.id,
      country,
    );
    final title = locTitle.trim().isNotEmpty ? locTitle : detail.item.title;
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

  List<DramaReview> _visibleRatingsAndReviews(List<DramaReview> reviews) {
    return reviews
        .where((r) => r.rating > 0 || r.comment.trim().isNotEmpty)
        .toList();
  }

  Future<void> _toggleWatchlistFromDetail(
    BuildContext context,
    DramaDetail detail,
  ) async {
    if (!AuthService.instance.isLoggedIn.value) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
      );
      if (!context.mounted) return;
      if (ok != true || !AuthService.instance.isLoggedIn.value) return;
    }

    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final id = detail.item.id;
    final currentlyInList = WatchlistService.instance.isInWatchlist(id);

    // [remove]/[add]가 동기로 notifier를 갱신하기 전에 맞춰 두어 [_onWatchlistItemsChanged]가 이중 반영하지 않게 함.
    _wlHadCurrentDrama = !currentlyInList;

    // Optimistic UI: 즉시 카운트 반영 (Firestore 응답 기다리지 않음)
    setState(() {
      _watchlistUserCount = currentlyInList
          ? (_watchlistUserCount > 0 ? _watchlistUserCount - 1 : 0)
          : _watchlistUserCount + 1;
    });

    // Firestore 쓰기는 백그라운드 (서비스 내부도 optimistic)
    if (currentlyInList) {
      unawaited(WatchlistService.instance.remove(id));
    } else {
      unawaited(WatchlistService.instance.add(id, country));
    }

    // 0.8초 뒤 서버 실제 집계로 카운트 보정
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) unawaited(_loadWatchlistUserCount());
    });
  }

  Future<void> _handleWriteReviewTap(BuildContext context, dynamic s) async {
    final dramaId = widget.detail.item.id;
    final dramaTitle = widget.detail.item.title;
    if (AuthService.instance.isLoggedIn.value) {
      await WriteReviewSheet.show(
        context,
        dramaId: dramaId,
        dramaTitle: dramaTitle,
      );
      if (mounted) _loadRatingStats();
    } else {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        await WriteReviewSheet.show(
          context,
          dramaId: dramaId,
          dramaTitle: dramaTitle,
        );
        if (mounted) _loadRatingStats();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final detail = widget.detail;
    final visibleReviews = _visibleRatingsAndReviews(
      _liveReviews ?? detail.reviews,
    );
    final rawReviews = _liveReviews ?? detail.reviews;
    final ratingCountHint = _liveCount ?? detail.ratingCount;
    final watcherForStats =
        rawReviews.isNotEmpty ? rawReviews.length : ratingCountHint;
    final reviewUseFileIcon =
        visibleReviews.isNotEmpty || ratingCountHint > 0;
    final reviewForStats =
        visibleReviews.isNotEmpty ? visibleReviews.length : ratingCountHint;
    final theme = Theme.of(context);
    final headerBg = listsStyleSubpageHeaderBackground(theme);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          final resultToPass = _buildViewCountResult();
          unawaited(_popDetailRouteWithResult(resultToPass));
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: listsStyleSubpageSystemOverlay(theme, headerBg),
        child: ListsStyleSubpageHorizontalSwipeBack(
          onSwipePop: () =>
              popListsStyleSubpage(context, _buildViewCountResult()),
          child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: RefreshIndicator(
            onRefresh: () => _loadRatingStats(ignoreDetailCache: true),
            child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 상단: 포스터 + 제목 (조회수는 목록 갱신용으로만 서버 반영, UI 비표시)
              SliverToBoxAdapter(
                child: _HeaderSection(
                  detail: widget.detail,
                  onBack: () {
                    popListsStyleSubpage(context, _buildViewCountResult());
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatsBar(
                        detail: detail,
                        strings: s,
                        onReviewsTap: () =>
                            _openDramaReviewsList(context, detail),
                        onWatchedTap: () =>
                            _openDramaWatchers(context, detail),
                        onListsTap: () => _openDramaLists(context, detail),
                        onWatchlistTap: () => unawaited(
                          _toggleWatchlistFromDetail(context, detail),
                        ),
                        reviewCount: reviewForStats,
                        watcherCount: watcherForStats,
                        watchlistUserCount: _watchlistUserCount,
                        reviewUseFileIcon: reviewUseFileIcon,
                      ),
                      const SizedBox(height: 32),
                      // 줄거리 (가입 국가별 언어, 위에 장르 태그 pill)
                      _SynopsisSection(detail: detail, strings: s),
                      const SizedBox(height: 32),
                      // 회차 (구간 탭 + 에피소드 버튼)
                      _EpisodesSection(
                        dramaId: detail.item.id,
                        episodes: detail.episodes,
                        strings: s,
                      ),
                      const SizedBox(height: 32),
                      if (detail.cast.any((n) => n.trim().isNotEmpty)) ...[
                        _CastSection(
                          castNames: detail.cast
                              .map((n) => n.trim())
                              .where((n) => n.isNotEmpty)
                              .toList(),
                          strings: s,
                        ),
                        const SizedBox(height: 32),
                      ],
                      // 평점 & 리뷰
                      KeyedSubtree(
                        key: _ratingsKey,
                        child: _RatingsAndReviewsSection(
                          dramaId: detail.item.id,
                          dramaTitle: detail.item.title,
                          averageRating: _liveAverage ?? detail.averageRating,
                          ratingCount: _liveCount ?? detail.ratingCount,
                          reviews: visibleReviews,
                          postMeta: _reviewPostMeta,
                          strings: s,
                          onWriteReviewTap: () =>
                              _handleWriteReviewTap(context, s),
                          onReviewsListTap: () =>
                              _openDramaReviewsList(context, detail),
                          onReviewsChanged: () {
                            if (mounted) {
                              unawaited(
                                _loadRatingStats(ignoreDetailCache: true)
                                    .catchError((_) {}),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                      // 비슷한 작품
                      _SimilarSection(
                        dramaId: detail.item.id,
                        genreDisplay: detail.genre,
                        country:
                            CountryScope.maybeOf(context)?.country ??
                            CountryService.instance.countryNotifier.value,
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
          ),
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
                        errorBuilder: (_, __, ___) => Icon(
                          LucideIcons.tv,
                          size: 80,
                          color: cs.onSurfaceVariant,
                        ),
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
                style: IconButton.styleFrom(backgroundColor: Colors.black26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 상단: 포스터 + 제목 (화이트 테마)
class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.detail, this.onBack});

  final DramaDetail detail;

  /// null이면 기본 Navigator.pop(context). 있으면 호출 (pop 시 조회수 결과 전달용).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceColor = cs.surface;
    // 설정 언어(앱 locale) 기준으로 제목·이미지 표시
    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final displayTitle = () {
      final t = DramaListService.instance.getDisplayTitle(
        detail.item.id,
        country,
      );
      return t.isNotEmpty ? t : detail.item.title;
    }();
    final displayImageUrl =
        DramaListService.instance.getDisplayImageUrl(detail.item.id, country) ??
        detail.item.imageUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListsStyleSubpageHeaderBar(
          title: displayTitle,
          onBack: () {
            if (onBack != null) {
              onBack!();
            } else {
              popListsStyleSubpage(context);
            }
          },
        ),
        Stack(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(color: surfaceColor),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 포스터 (탭 시 크게 보기)
                  GestureDetector(
                    onTap: () {
                      if (displayImageUrl != null &&
                          displayImageUrl.isNotEmpty) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (ctx) => _FullScreenPosterPage(
                              imageUrl: displayImageUrl,
                            ),
                          ),
                        );
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 80,
                        height: 80 * 1.3,
                        child:
                            displayImageUrl != null &&
                                displayImageUrl.isNotEmpty
                            ? (displayImageUrl.startsWith('http')
                                  ? OptimizedNetworkImage(
                                      imageUrl: displayImageUrl,
                                      fit: BoxFit.cover,
                                      width: 80,
                                      height: 80 * 1.3,
                                      memCacheWidth: 168,
                                      memCacheHeight: 220,
                                    )
                                  : Image.asset(
                                      displayImageUrl,
                                      fit: BoxFit.cover,
                                      width: 80,
                                      height: 80 * 1.3,
                                      errorBuilder: (_, __, ___) =>
                                          _posterPlaceholder(context),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  /// 접힌 상태에서 레이아웃 부담 완화(긴 JSON 줄거리 등).
  static const int _kSynopsisLayoutCap = 2800;

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
        final genre = DramaListService.instance.getDisplaySubtitle(
          detail.item.id,
          country,
        );
        final displayGenre = genre.isNotEmpty ? genre : detail.genre;
        var genreTags = displayGenre
            .split(RegExp(r'[·,]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (genreTags.isEmpty) genreTags = [displayGenre];

        final synopsis = DramaListService.instance.getDisplaySynopsis(
          detail.item.id,
          country,
        );
        final rawSynopsis =
            synopsis.isNotEmpty ? synopsis : detail.synopsis;
        final displaySynopsis = (!_synopsisExpanded &&
                rawSynopsis.length > _kSynopsisLayoutCap)
            ? '${rawSynopsis.substring(0, _kSynopsisLayoutCap)}…'
            : rawSynopsis;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(strings.get('synopsis').toUpperCase(), cs),
            const SizedBox(height: 14),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
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
                                child: Icon(
                                  LucideIcons.chevron_right,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
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
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.6,
                ),
                maxLines: _synopsisExpanded ? null : 3,
                overflow: _synopsisExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
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
                    color: filled ? AppColors.ratingStar : cs.onSurfaceVariant,
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final episodes = widget.episodes;
    final strings = widget.strings;
    if (episodes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(strings.get('episodes').toUpperCase(), cs),
          const SizedBox(height: 12),
          Text(
            '회차 정보가 없습니다.',
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
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

    final selectedRange = _rangeIndex < ranges.length
        ? ranges[_rangeIndex]
        : ranges.first;
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
                message: _episodesExpanded
                    ? strings.get('collapse')
                    : strings.get('expand'),
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _detailCapsTitleText(
                            strings.get('episodes').toUpperCase(),
                            cs,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 12),
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
                child: Builder(
                  builder: (context) {
                    final totalEpsColor = cs.onSurfaceVariant.withValues(
                      alpha: 0.72,
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings
                                .get('totalEpisodes')
                                .replaceAll('%d', '${episodes.length}'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: totalEpsColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            LucideIcons.chevron_right,
                            size: _headerChevronSize,
                            color: totalEpsColor,
                          ),
                        ],
                      ),
                    );
                  },
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
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    if (ranges.length > 1) const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        LocaleService.instance.localeNotifier,
                        EpisodeRatingService.instance.getNotifierForDrama(
                          widget.dramaId,
                        ),
                        EpisodeRatingService.instance
                            .getAverageNotifierForDrama(widget.dramaId),
                        EpisodeRatingService.instance.getCountNotifierForDrama(
                          widget.dramaId,
                        ),
                      ]),
                      builder: (context, _) {
                        final averageRatings = EpisodeRatingService.instance
                            .getAverageNotifierForDrama(widget.dramaId)
                            .value;
                        final countMap = EpisodeRatingService.instance
                            .getCountNotifierForDrama(widget.dramaId)
                            .value;
                        return SizedBox(
                          height: 56,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: rangeEpisodes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 4),
                            itemBuilder: (context, i) {
                              final ep = rangeEpisodes[i];
                              final avg = averageRatings[ep.number] ?? 0.0;
                              final count = countMap[ep.number] ?? 0;
                              final hasRating = avg > 0;
                              final myRating = EpisodeRatingService.instance
                                  .getMyRating(widget.dramaId, ep.number);
                              return GestureDetector(
                                onTap: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  if (_selectedEpisodeNumber == ep.number) {
                                    setState(
                                      () => _selectedEpisodeNumber = null,
                                    );
                                  } else if (_selectedEpisodeNumber != null) {
                                    setState(() {
                                      _selectedEpisodeNumber = null;
                                      _pendingEpisodeNumber = ep.number;
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          final num = _pendingEpisodeNumber;
                                          setState(() {
                                            _selectedEpisodeNumber = num;
                                            _pendingEpisodeNumber = null;
                                          });
                                          if (num != null) {
                                            EpisodeReviewService.instance
                                                .loadReviews(
                                                  widget.dramaId,
                                                  num,
                                                );
                                          }
                                        });
                                  } else {
                                    setState(
                                      () => _selectedEpisodeNumber = ep.number,
                                    );
                                    EpisodeReviewService.instance.loadReviews(
                                      widget.dramaId,
                                      ep.number,
                                    );
                                  }
                                },
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: cs.outline.withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        strings
                                            .get('episodeLabel')
                                            .replaceAll('%d', '${ep.number}'),
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Transform.translate(
                                            offset: const Offset(0, 1.5),
                                            child: Icon(
                                              Icons.star_rounded,
                                              size: 12,
                                              color: hasRating
                                                  ? AppColors.ratingStar
                                                  : episodeNoRatingColor(
                                                      context,
                                                    ),
                                            ),
                                          ),
                                          SizedBox(width: 12 * 0.25),
                                          Text(
                                            hasRating
                                                ? avg.toStringAsFixed(1)
                                                : '0',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: hasRating
                                                  ? (Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.white
                                                        : cs.onSurface)
                                                  : episodeNoRatingColor(
                                                      context,
                                                    ),
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
                    if (_selectedEpisodeNumber != null) ...[
                      const SizedBox(height: 16),
                      EpisodeReviewPanel(
                        dramaId: widget.dramaId,
                        episodeNumber: _selectedEpisodeNumber!,
                        onClose: () =>
                            setState(() => _selectedEpisodeNumber = null),
                        strings: widget.strings,
                        showCloseButton: false,
                        hideReviewCardTimestamp: true,
                        maxVisibleReviews: 3,
                        onViewAll: () {
                          final n = _selectedEpisodeNumber;
                          if (n == null || !context.mounted) return;
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => DramaEpisodeReviewsScreen(
                                dramaId: widget.dramaId,
                                episodeNumber: n,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _showEpisodesBottomSheet(
    BuildContext context,
    List<DramaEpisode> episodes,
    dynamic strings,
  ) {
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

  void _reloadEpisodeRatingsForLocaleChange() {
    final id = widget.dramaId.trim();
    if (id.isEmpty) return;
    EpisodeRatingService.instance.invalidateEpisodeDataForDrama(id);
    EpisodeReviewService.instance.clearNotifiersForDrama(id);
    unawaited(EpisodeRatingService.instance.getMyRatingsForDrama(id));
    unawaited(EpisodeRatingService.instance.loadEpisodeAverageRatings(id));
  }

  @override
  void initState() {
    super.initState();
    unawaited(EpisodeRatingService.instance.getMyRatingsForDrama(widget.dramaId));
    unawaited(
      EpisodeRatingService.instance.loadEpisodeAverageRatings(widget.dramaId),
    );
    LocaleService.instance.localeNotifier.addListener(
      _reloadEpisodeRatingsForLocaleChange,
    );
  }

  @override
  void dispose() {
    LocaleService.instance.localeNotifier.removeListener(
      _reloadEpisodeRatingsForLocaleChange,
    );
    super.dispose();
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
    final selectedRange = _rangeIndex < ranges.length
        ? ranges[_rangeIndex]
        : ranges.first;
    final rangeEpisodes = episodes.sublist(
      selectedRange.start - 1,
      selectedRange.end.clamp(0, episodes.length),
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
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
                  icon: Icon(
                    LucideIcons.x,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${r.start}-${r.end}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
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
                  LocaleService.instance.localeNotifier,
                  EpisodeRatingService.instance.getNotifierForDrama(
                    widget.dramaId,
                  ),
                  EpisodeRatingService.instance.getAverageNotifierForDrama(
                    widget.dramaId,
                  ),
                  EpisodeRatingService.instance.getCountNotifierForDrama(
                    widget.dramaId,
                  ),
                ]),
                builder: (context, _) {
                  final averageRatings = EpisodeRatingService.instance
                      .getAverageNotifierForDrama(widget.dramaId)
                      .value;
                  final countMap = EpisodeRatingService.instance
                      .getCountNotifierForDrama(widget.dramaId)
                      .value;
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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
                      final myRating = EpisodeRatingService.instance
                          .getMyRating(widget.dramaId, ep.number);
                      return GestureDetector(
                        onTap: () {
                          if (widget.onEpisodeSelected != null) {
                            widget.onEpisodeSelected!(ep.number);
                          } else {
                            _showEpisodeRatingPicker(
                              context,
                              widget.dramaId,
                              ep.number,
                              myRating ?? 0.0,
                            );
                          }
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: cs.outline.withOpacity(0.4),
                              width: 1,
                            ),
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
                                      color: hasRating
                                          ? AppColors.ratingStar
                                          : episodeNoRatingColor(context),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    hasRating ? avg.toStringAsFixed(1) : '0',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: hasRating
                                          ? (Theme.of(context).brightness ==
                                                    Brightness.dark
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
          ListView.separated(
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
                    child: Icon(
                      LucideIcons.user,
                      size: 22,
                      color: cs.onSurfaceVariant,
                    ),
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
                  Icon(
                    LucideIcons.chevron_right,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              );
            },
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
    this.postMeta = const {},
  });

  final String dramaId;
  final String dramaTitle;
  final double averageRating;
  final int ratingCount;
  final List<DramaReview> reviews;
  final dynamic strings;
  final VoidCallback onWriteReviewTap;

  /// feedPostId → real (likeCount, commentCount, isLiked) from the posts collection.
  final Map<String, ({int likeCount, int commentCount, bool isLiked})> postMeta;

  /// 종합 평점 카드 탭 → 전체 리뷰 화면.
  final VoidCallback onReviewsListTap;

  /// 삭제·수정 후 부모가 서버 리뷰 목록·평점을 다시 불러오도록 할 때 사용.
  final VoidCallback? onReviewsChanged;

  @override
  State<_RatingsAndReviewsSection> createState() =>
      _RatingsAndReviewsSectionState();
}

class _RatingsAndReviewsSectionState extends State<_RatingsAndReviewsSection> {
  /// 상세 카드에 표시하는 리뷰 최대 개수 — 좋아요 많은 순 상위 [개] (나머지는 "전체 리뷰").
  static const int _kDetailReviewPreviewMax = 5;
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ReviewService.instance.loadIfNeeded());
    });
    _syncLikedIdsFromMeta(widget.postMeta);
  }

  @override
  void didUpdateWidget(covariant _RatingsAndReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postMeta != widget.postMeta) {
      _syncLikedIdsFromMeta(widget.postMeta);
    }
  }

  void _syncLikedIdsFromMeta(
    Map<String, ({int likeCount, int commentCount, bool isLiked})> meta,
  ) {
    final liked = <String>{};
    for (final r in widget.reviews) {
      final m = _postMetaForWith(r, meta);
      if (m != null && m.isLiked) {
        liked.add(_reviewKey(r));
      }
    }
    if (liked.isNotEmpty || _likedIds.isNotEmpty) {
      // Only update if there's a real change to avoid unnecessary rebuilds
      if (!setEquals(liked, _likedIds)) {
        setState(
          () => _likedIds
            ..clear()
            ..addAll(liked),
        );
      }
    }
  }

  ({int likeCount, int commentCount, bool isLiked})? _postMetaForWith(
    DramaReview r,
    Map<String, ({int likeCount, int commentCount, bool isLiked})> meta,
  ) {
    final fp = r.feedPostId?.trim();
    if (fp != null && fp.isNotEmpty) {
      final m = meta[fp];
      if (m != null) return m;
    }
    final id = r.id?.trim();
    if (id != null && id.isNotEmpty) return meta[id];
    return null;
  }

  /// Returns the postMeta entry for this review (keyed by feedPostId then id).
  ({int likeCount, int commentCount, bool isLiked})? _postMetaFor(
    DramaReview r,
  ) {
    final fp = r.feedPostId?.trim();
    if (fp != null && fp.isNotEmpty) {
      final m = widget.postMeta[fp];
      if (m != null) return m;
    }
    final id = r.id?.trim();
    if (id != null && id.isNotEmpty) return widget.postMeta[id];
    return null;
  }

  String _reviewKey(DramaReview r) => r.id ?? '${r.userName}_${r.timeAgo}';

  int _displayLikeCount(DramaReview r) {
    final meta = _postMetaFor(r);
    final base = meta != null ? meta.likeCount : (r.likeCount ?? 0);
    final nowLiked = _likedIds.contains(_reviewKey(r));
    if (meta == null) {
      return base + (nowLiked ? 1 : 0);
    }
    // base already includes server liked-state. Only apply optimistic delta.
    final delta = nowLiked == meta.isLiked ? 0 : (nowLiked ? 1 : -1);
    return (base + delta).clamp(0, 999999);
  }

  int _displayCommentCount(DramaReview r) {
    final meta = _postMetaFor(r);
    if (meta != null) return meta.commentCount;
    return r.replies.length;
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
    final body = r.comment.trim();
    // 평균 점수 블록 오른쪽: 본문만 (닉네임·좋아요 없음).
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
        ],
      ),
    );
  }

  void _toggleLike(DramaReview r) {
    final key = _reviewKey(r);
    final nowLiked = !_likedIds.contains(key);
    setState(() {
      if (nowLiked) {
        _likedIds.add(key);
      } else {
        _likedIds.remove(key);
      }
    });
    final feedPostId = (r.feedPostId?.trim().isNotEmpty == true)
        ? r.feedPostId!.trim()
        : r.id?.trim();
    if (feedPostId != null && feedPostId.isNotEmpty) {
      unawaited(
        PostService.instance.togglePostLike(
          feedPostId,
          postAuthorUid: r.authorUid,
        ),
      );
    }
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: false,
  );

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
      final best =
          reviews.where((r) => _displayLikeCount(r) == maxLikes).toList()..sort(
            (a, b) => _reviewTimestamp(b).compareTo(_reviewTimestamp(a)),
          );
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
    final scopeRaw = CountryScope.maybeOf(context)?.country;
    final scopeCountry = (scopeRaw?.trim() ?? '');
    final signupRaw = UserProfileService.instance.signupCountryNotifier.value;
    final signupCountry = (signupRaw?.trim() ?? '');
    final loc = scopeCountry.isNotEmpty
        ? scopeCountry.toLowerCase()
        : signupCountry.toLowerCase();
    final safeLoc = loc.isNotEmpty ? loc : 'us';
    final timeAgo = my.modifiedAt != null
        ? '${formatTimeAgo(my.modifiedAt!, safeLoc)} (${widget.strings.get('edited')})'
        : formatTimeAgo(my.writtenAt, safeLoc);
    final myPhotoUrl =
        UserProfileService.instance.profileImageUrlNotifier.value;
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
      authorUid: AuthService.instance.currentUser.value?.uid,
      feedPostId: my.feedPostId,
      appLocale: my.appLocale,
    );
  }

  List<DramaReview> get _displayReviews {
    final myIds = _myReviewIdsForDrama;
    final list = List<DramaReview>.from(widget.reviews);
    list.removeWhere((r) => r.comment.trim().isEmpty);
    list.removeWhere((r) {
      final id = r.id;
      return id != null && id.isNotEmpty && myIds.contains(id);
    });
    final mine =
        ReviewService.instance.list
            .where(
              (e) => e.dramaId == widget.dramaId && e.comment.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final tb = b.modifiedAt ?? b.writtenAt;
            final ta = a.modifiedAt ?? a.writtenAt;
            return tb.compareTo(ta);
          });
    final head = mine.map(_localMyReviewToCard).toList();
    return [...head, ...list];
  }

  List<DramaReview> get _likesSortedReviews {
    final sorted = List<DramaReview>.from(_displayReviews);
    sorted.sort((a, b) {
      final byLikes = _displayLikeCount(b).compareTo(_displayLikeCount(a));
      if (byLikes != 0) return byLikes;
      return _reviewTimestamp(b).compareTo(_reviewTimestamp(a));
    });
    return sorted;
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
        _sectionLabel(s.get('ratingsAndComments').toUpperCase(), cs),
        const SizedBox(height: 16),
        // 평균·스포트라이트 + 좋아요순 상위 리뷰 목록을 한 카드로 통합
        ValueListenableBuilder<List<MyReviewItem>>(
          valueListenable: ReviewService.instance.listNotifier,
          builder: (context, _, __) {
            final list = _likesSortedReviews;
            final hasReviews = list.isNotEmpty;
            final preview = hasReviews
                ? list.take(_kDetailReviewPreviewMax).toList()
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: cs.outline.withOpacity(0.4),
                    width: 1,
                  ),
                ),
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
                      color: cs.outline.withValues(alpha: 0.26),
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
                      ...preview.asMap().entries.expand((e) {
                        final i = e.key;
                        final r = e.value;
                        final card = _ReviewCard(
                          review: r,
                          dramaId: widget.dramaId,
                          dramaTitle: widget.dramaTitle,
                          likeCount: _displayLikeCount(r),
                          commentCountOverride: _displayCommentCount(r),
                          isLiked: _likedIds.contains(_reviewKey(r)),
                          onLikeTap: () => _toggleLike(r),
                          strings: s,
                          embeddedInMergedSection: true,
                          onReviewsChanged: widget.onReviewsChanged,
                        );
                        if (i == 0) return [card];
                        return [
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: 16,
                            endIndent: 16,
                            color: cs.outline.withValues(alpha: 0.22),
                          ),
                          card,
                        ];
                      }),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                        child: Center(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: cs.onSurfaceVariant.withValues(
                                alpha: 0.55,
                              ),
                            ),
                            onPressed: widget.onReviewsListTap,
                            child: Text(
                              s.get('dramaAllReviewsCta'),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
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
  const _ReplyInput({required this.strings, required this.onSubmitted});

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
                color: hasText
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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

  static const double _size = kAppUnifiedProfileAvatarSize;

  final DramaReviewReply reply;

  static Widget _greyIconAvatar(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: CircleAvatar(
        radius: _size / 2,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, size: 15, color: Colors.white),
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
        child: Icon(Icons.person, size: 15, color: iconColor),
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
            memCacheWidth: 52,
            memCacheHeight: 52,
            errorWidget: ValueListenableBuilder<int?>(
              valueListenable: UserProfileService.instance.avatarColorNotifier,
              builder: (_, colorIdx, __) {
                final isMine =
                    reply.author ==
                    (UserProfileService.instance.nicknameNotifier.value ?? '나');
                if (isMine && colorIdx != null)
                  return _coloredMemberIcon(colorIdx);
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
        final isMine =
            reply.author ==
            (UserProfileService.instance.nicknameNotifier.value ?? '나');
        if (isMine && colorIdx != null) return _coloredMemberIcon(colorIdx);
        return _greyIconAvatar(context);
      },
    );
  }
}

/// 리뷰 아바타: 프로필 사진 등록되어 있으면 프로필 사진, 없으면 회원 색깔 아이콘 (크기 동일)
class _ReviewAvatar extends StatelessWidget {
  const _ReviewAvatar({required this.review, required this.isMine});

  static const double _size = kAppUnifiedProfileAvatarSize;

  final DramaReview review;
  final bool isMine;

  static Widget _greyMemberIcon(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: CircleAvatar(
        radius: _size / 2,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, size: 16, color: Colors.white),
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
        child: Icon(Icons.person, size: 16, color: iconColor),
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
            memCacheWidth: 52,
            memCacheHeight: 52,
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
    required this.dramaId,
    required this.dramaTitle,
    required this.likeCount,
    required this.isLiked,
    required this.onLikeTap,
    required this.strings,
    this.isMine = false,
    this.onEdit,
    this.onDelete,
    this.onShareReview,
    this.commentCountOverride,

    /// true: 평점 요약과 같은 큰 카드 안 — 개별 그림자·배경 카드 제거.
    this.embeddedInMergedSection = false,
    this.onReviewsChanged,
  });

  final DramaReview review;
  final String dramaId;
  final String dramaTitle;
  final int likeCount;
  final bool isLiked;
  final VoidCallback onLikeTap;
  final dynamic strings;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShareReview;

  /// When non-null, overrides the replies.length used as comment count display.
  final int? commentCountOverride;
  final bool embeddedInMergedSection;

  /// 수정·삭제 후 상세 평점·리뷰 블록 갱신.
  final VoidCallback? onReviewsChanged;

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
      _localReplies.add(
        DramaReviewReply(
          author: author,
          text: text,
          timeAgo: widget.strings.get('timeAgoJustNow'),
          likeCount: 0,
          authorPhotoUrl: photoUrl,
        ),
      );
    });
  }

  List<Widget> _embeddedMineActions(BuildContext context) {
    if (!widget.isMine || (widget.onEdit == null && widget.onDelete == null)) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
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
                    fontWeight: FontWeight.w700,
                    color: kAppDeleteActionColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _embeddedActionRow(
    BuildContext context,
    List<DramaReviewReply> replies,
    bool hasReplies, {
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 2, 14, 2),
  }) {
    final cs = Theme.of(context).colorScheme;
    const iconSize = 13.0;
    final actionFg = feedInlineActionMutedForeground(cs);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onLikeTap();
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.isLiked
                      ? Icon(
                          Icons.favorite,
                          size: iconSize,
                          color: Colors.redAccent,
                        )
                      : Icon(
                          Icons.favorite_border,
                          size: iconSize,
                          color: actionFg,
                        ),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(widget.likeCount),
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.message_circle,
                    size: iconSize,
                    color: actionFg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(
                      widget.commentCountOverride ?? replies.length,
                    ),
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
                child: Icon(
                  LucideIcons.share_2,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _replyExpansionWidgets(
    BuildContext context,
    List<DramaReviewReply> replies,
    bool hasReplies,
  ) {
    if (!_showReplies) return const [];
    return [
      if (hasReplies) ...[
        const SizedBox(height: 10),
        Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
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
                                style: appUnifiedNicknameStyle(
                                  Theme.of(context).colorScheme,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                r.timeAgo,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.text,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            isLiked
                                ? const _LikedHeartIcon(size: 14)
                                : Icon(
                                    Icons.favorite_border,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            const SizedBox(width: 2),
                            Text(
                              displayCount > 0
                                  ? formatCompactCount(displayCount)
                                  : '0',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                color: isLiked
                                    ? const Color(0xFFd95d75)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final replies = [...review.replies, ..._localReplies];
    final hasReplies = replies.isNotEmpty;

    if (widget.embeddedInMergedSection) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._embeddedMineActions(context),
          DramaReviewsListFeedRow(
            key: ValueKey<String>(
              review.id ?? '${review.userName}_${review.timeAgo}',
            ),
            review: review,
            dramaId: widget.dramaId,
            dramaTitle: widget.dramaTitle,
            onReviewMutated: widget.onReviewsChanged,
            displayLikeCountOverride: widget.likeCount,
            displayCommentCountOverride: widget.commentCountOverride,
            initialIsLiked: widget.isLiked,
            rowMaterialColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
        ],
      );
    }

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
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withOpacity(0.08),
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
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final u = review.authorUid?.trim();
                      if (u != null && u.isNotEmpty) {
                        openUserProfileFromAuthorUid(context, u);
                      }
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ReviewAvatar(review: review, isMine: widget.isMine),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                review.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: appUnifiedNicknameStyle(
                                  Theme.of(context).colorScheme,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  GreenRatingStars(
                                    rating: review.rating,
                                    size: 14,
                                    color: AppColors.ratingStar,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      review.timeAgo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.isMine &&
                    (widget.onEdit != null || widget.onDelete != null))
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
                              fontWeight: FontWeight.w700,
                              color: kAppDeleteActionColor,
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
            _embeddedActionRow(
              context,
              replies,
              hasReplies,
              padding: EdgeInsets.zero,
            ),
            ..._replyExpansionWidgets(context, replies, hasReplies),
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
          final country =
              widget.country ?? CountryService.instance.countryNotifier.value;
          final list = DramaListService.instance.getSimilarByGenre(
            widget.dramaId,
            widget.genreDisplay,
            country,
            limit: 8,
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
    final country =
        widget.country ??
        CountryScope.maybeOf(context)?.country ??
        CountryService.instance.countryNotifier.value;
    final colorScheme = Theme.of(context).colorScheme;
    final strings = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(strings.get('similarDramas').toUpperCase(), colorScheme),
        const SizedBox(height: 14),
        SizedBox(
          height: 165,
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
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final item = _similar[i];
                    final imageUrl = DramaListService.instance
                        .getDisplayImageUrl(item.id, country);
                    final genre = DramaListService.instance.getDisplaySubtitle(
                      item.id,
                      country,
                    );
                    final rating = ReviewService.instance.ratingForListCard(
                      item.id,
                      catalogRating: item.rating,
                    );
                    final displayTitle = () {
                      final t = DramaListService.instance.getDisplayTitle(
                        item.id,
                        country,
                      );
                      return t.isNotEmpty ? t : item.title;
                    }();
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    final titleColor = colorScheme.onSurface;
                    final greyColor = isDark
                        ? colorScheme.onSurfaceVariant
                        : Colors.grey.shade500;
                    const posterW = 80.0;
                    const posterH = 104.0;
                    const posterRadius = 8.0;
                    const metaFont = 9.0;
                    const starSize = 11.0;
                    final ratingTextColor = rating > 0
                        ? (isDark ? colorScheme.onSurface : Colors.black)
                        : greyColor;
                    return GestureDetector(
                      onTap: () async {
                        await DramaDetailPage.openFromItem(
                          context,
                          item,
                          country: country,
                        );
                      },
                      child: SizedBox(
                        width: posterW,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(posterRadius),
                              child: SizedBox(
                                width: posterW,
                                height: posterH,
                                child: imageUrl != null && imageUrl.isNotEmpty
                                    ? (imageUrl.startsWith('http')
                                          ? OptimizedNetworkImage(
                                              imageUrl: imageUrl,
                                              fit: BoxFit.cover,
                                              width: posterW,
                                              height: posterH,
                                            )
                                          : Image.asset(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                              width: posterW,
                                              height: posterH,
                                              errorBuilder: (_, __, ___) =>
                                                  _posterPlaceholder(context),
                                            ))
                                    : _posterPlaceholder(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              displayTitle,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: starSize,
                                  color: rating > 0
                                      ? AppColors.ratingStar
                                      : greyColor,
                                ),
                                Text(
                                  rating > 0 ? rating.toStringAsFixed(1) : '0',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: metaFont,
                                    fontWeight: FontWeight.w500,
                                    color: ratingTextColor,
                                  ),
                                ),
                                if (genre.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      genre,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: metaFont,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
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
