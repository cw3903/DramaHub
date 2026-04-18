import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/country_scope.dart';
import '../services/auth_service.dart';
import '../services/level_service.dart';
import '../services/message_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/saved_service.dart';
import '../services/watchlist_service.dart';
import '../services/watch_history_service.dart';
import '../services/review_service.dart';
import '../services/custom_drama_list_service.dart';
import '../services/share_service.dart';
import '../services/user_profile_service.dart';
import '../services/theme_service.dart';
import '../services/post_service.dart';
import '../services/follow_service.dart';
import '../theme/app_theme.dart';
import 'follow_screen.dart';
import 'profile_photo_preview_page.dart';
import 'lists_screen.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/app_delete_confirm_dialog.dart';
import '../widgets/review_body_lines_indicator.dart';
import 'watchlist_screen.dart';
import 'language_select_screen.dart';
import 'user_posts_screen.dart';
import 'user_public_reviews_screen.dart';
import 'my_reviews_screen.dart';
import '../models/drama.dart';
import '../models/post.dart';
import '../models/profile_stat_row_data.dart';
import '../models/profile_favorite.dart';
import '../models/profile_rating_histogram.dart';
import 'drama_detail_page.dart';
import 'post_detail_page.dart';
import 'drama_search_screen.dart';
import 'diary_screen.dart';
import 'favorite_title_activity_screen.dart';
import 'likes_screen.dart';
import 'user_public_diary_screen.dart';
import 'user_public_lists_screen.dart';
import 'user_public_watchlist_screen.dart';
import 'user_public_likes_screen.dart';
import '../widgets/optimized_network_image.dart';
import '../services/country_service.dart';
import '../services/drama_list_service.dart';
import '../services/locale_service.dart';

final ValueNotifier<int> _profileStatsRefreshNotifier = ValueNotifier(0);

/// RATINGS 히스토그램 — 별 슬롯 순차 등장(슬롯당 구간).
Widget _profileRatingsRevealSlot({
  required Animation<double> animation,
  required int slotIndex,
  required int slotCount,
  required Widget child,
}) {
  if (slotCount <= 0) return child;
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final w = 1.0 / slotCount;
      final start = slotIndex * w;
      final raw = (animation.value - start) / w;
      final t = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(-7 * (1 - t), 0),
          child: child,
        ),
      );
    },
  );
}

/// `halfAsTextLabel` 별줄의 슬롯 수(꽉 찬 별 개수 + ½ 한 칸이면 +1).
int _starHalfLabelSlotCount(double rating) {
  final c = rating.clamp(0.0, 5.0);
  final r = (c * 2).round() / 2.0;
  final full = r.floor();
  final hasHalf = (r - full) >= 0.5;
  return full + (hasHalf ? 1 : 0);
}

/// RATINGS 제목·FAVORITES 등 섹션 캡션·메뉴(다이어리~언어) 라벨·숫자 공통 크기.
const double _kProfileRatingsAndMenuFontSize = 12;

/// RATINGS 히스토그램 축·막대 위 별 아이콘 크기 — Recent Activity 별줄과 동일.
const double _kProfileRatingsAxisStarSize = 11.0;

/// RECENT ACTIVITY 포스터 슬롯 가로:세로 비(기준). FAVORITES 썸네일도 동일 비율.
const double _kProfileRecentActivityPosterAspect = 2 / 3;

/// 프로필 화면 전역 — FAVORITES 라벨과 동일 [Noto Sans KR], 영문 UI에서도 통일된 자간.
TextStyle _profileText(
  ColorScheme cs, {
  required double size,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double letterSpacing = 0.22,
  double? height,
}) => GoogleFonts.notoSansKr(
  fontSize: size,
  fontWeight: weight,
  color: color ?? cs.onSurface,
  letterSpacing: letterSpacing,
  height: height,
);

/// FAVORITES / RATINGS / RECENT ACTIVITY 등 섹션 캡션.
TextStyle _profileCapsLabel(ColorScheme cs) => _profileText(
  cs,
  size: _kProfileRatingsAndMenuFontSize,
  weight: FontWeight.w800,
  letterSpacing: 1.6,
  color: cs.onSurface.withValues(alpha: 0.90),
);

/// 빈 즐겨찾기·최근활동 슬롯 점선 — 라이트에서 `outline`만 쓰면 배경에 묻힘.
Color _profileEmptySlotDashColor(ColorScheme cs, Brightness brightness) {
  if (brightness == Brightness.dark) {
    return cs.outline.withValues(alpha: 0.62);
  }
  return cs.onSurface.withValues(alpha: 0.32);
}

double _profileEmptySlotDashStrokeWidth(Brightness brightness) =>
    brightness == Brightness.light ? 1.45 : 1.2;

/// Ratings 아래 메뉴 라벨·트레일 숫자 — 다이어리~언어 등 캡션과 동일하게 진한 톤.
TextStyle _profileMenuRowLabel(ColorScheme cs) => _profileText(
  cs,
  size: _kProfileRatingsAndMenuFontSize,
  weight: FontWeight.w800,
  letterSpacing: 0.42,
  color: cs.onSurface.withValues(alpha: 0.90),
);

/// 섹션 구분선 — 눈에 덜 띄게(대비 낮춤).
Color _profileSectionDividerColor(ColorScheme cs) =>
    cs.onSurfaceVariant.withValues(alpha: 0.12);

Widget _profileFullBleedDivider(ColorScheme cs) =>
    Divider(height: 1, thickness: 1, color: _profileSectionDividerColor(cs));

Widget _profileMenuRowDivider(ColorScheme cs) => Divider(
  height: 1,
  thickness: 1,
  color: cs.onSurfaceVariant.withValues(alpha: 0.055),
);

/// 풀블리드 구분선 직전·직후 섹션 여백 통일 (썸네일 ↔ 선 간격 포함).
const double _kProfileSectionBleedPadV = 16.0;
const double _kProfileSectionBleedPadH = 16.0;

/// 프로필 메뉴(다이어리~언어) 리딩·트레일 아이콘 크기.
const double _kProfileMenuLeadingIconSize = 11.0;
const double _kProfileMenuTrailingIconSize = 10.0;

/// Ratings 아래 메뉴 — 다이어리·좋아요 건수 포함(좋아요는 Firestore 비동기 로드).
class _ProfileLinksMenu extends StatefulWidget {
  const _ProfileLinksMenu({
    required this.cs,
    required this.strings,
    this.showAppSettings = true,
    this.menuDiaryCount,
    this.menuListsCount,
    this.menuWatchlistCount,
    this.menuLikesCount,
    this.viewedUid,
    this.ownerDisplayName,
  });

  final ColorScheme cs;
  final dynamic strings;

  /// false: Theme·Language 행 숨김 (타 유저 프로필).
  final bool showAppSettings;

  final int? menuDiaryCount;
  final int? menuListsCount;
  final int? menuWatchlistCount;
  final int? menuLikesCount;

  /// 타인 프로필일 때 설정. null이면 본인 화면으로 이동.
  final String? viewedUid;
  final String? ownerDisplayName;

  @override
  State<_ProfileLinksMenu> createState() => _ProfileLinksMenuState();
}

class _ProfileLinksMenuState extends State<_ProfileLinksMenu> {
  int _likesCount = 0;

  @override
  void initState() {
    super.initState();
    _profileStatsRefreshNotifier.addListener(_onLikesRefreshSignal);
    AuthService.instance.currentUser.addListener(_onLikesRefreshSignal);
    LocaleService.instance.localeNotifier.addListener(_onAppLocaleChanged);
    // 다른 유저 프로필에서는 현재 사용자 서비스 로드 불필요
    if (widget.viewedUid == null) {
      WatchHistoryService.instance.loadIfNeeded();
      CustomDramaListService.instance.loadIfNeeded();
      WatchlistService.instance.loadIfNeeded();
    }
    if (widget.menuLikesCount != null) {
      _likesCount = widget.menuLikesCount!;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reloadLikesTotal());
    }
  }

  @override
  void dispose() {
    LocaleService.instance.localeNotifier.removeListener(_onAppLocaleChanged);
    _profileStatsRefreshNotifier.removeListener(_onLikesRefreshSignal);
    AuthService.instance.currentUser.removeListener(_onLikesRefreshSignal);
    super.dispose();
  }

  /// [CountryScope.maybeOf]는 구독을 걸지 않아 `didChangeDependencies`가
  /// 언어 변경 때마다 오지 않을 수 있음 — [LocaleService.localeNotifier]로 직접 갱신.
  void _onAppLocaleChanged() {
    if (widget.menuLikesCount != null) return;
    _reloadLikesTotal();
  }

  void _onLikesRefreshSignal() {
    if (widget.menuLikesCount != null) return;
    CustomDramaListService.instance.loadIfNeeded(force: true);
    _reloadLikesTotal();
  }

  Future<void> _reloadLikesTotal() async {
    if (widget.menuLikesCount != null) return;
    final uid = AuthService.instance.currentUser.value?.uid;
    if (!mounted) return;
    if (uid == null || uid.isEmpty) {
      setState(() => _likesCount = 0);
      return;
    }
    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    try {
      final list = await PostService.instance.getPostsLikedByUid(
        uid,
        countryForTimeAgo: country,
      );
      if (!mounted) return;
      PostService.instance.cacheLikedPostsForLikesScreen(uid, list);
      setState(() => _likesCount = list.length);
    } catch (_) {
      if (mounted) setState(() => _likesCount = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final s = widget.strings;
    final w = widget;

    return AnimatedBuilder(
      animation: Listenable.merge([
        WatchlistService.instance.itemsNotifier,
        WatchHistoryService.instance.listNotifier,
        CustomDramaListService.instance.listsNotifier,
      ]),
      builder: (context, _) {
        final watchlistCount =
            w.menuWatchlistCount ??
            WatchlistService.instance.itemsNotifier.value.length;
        final diaryCount =
            w.menuDiaryCount ?? WatchHistoryService.instance.list.length;
        final listsCount =
            w.menuListsCount ??
            CustomDramaListService.instance.listsNotifier.value.length;

        final viewedUid = w.viewedUid;
        final ownerName = w.ownerDisplayName;
        final isOtherUser =
            viewedUid != null && viewedUid.trim().isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profileFullBleedDivider(cs),
            _ProfileTile(
              icon: LucideIcons.notebook,
              label: s.get('diary'),
              trailingCount: diaryCount,
              onTap: () {
                if (isOtherUser) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => UserPublicDiaryScreen(
                        uid: viewedUid,
                        ownerDisplayName: ownerName,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const DiaryScreen()),
                  );
                }
              },
              color: cs,
            ),
            _profileMenuRowDivider(cs),
            _ProfileTile(
              icon: LucideIcons.library,
              label: s.get('tabLists'),
              trailingCount: listsCount,
              onTap: () {
                if (isOtherUser) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => UserPublicListsScreen(
                        uid: viewedUid,
                        ownerDisplayName: ownerName,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const ListsScreen()),
                  );
                }
              },
              color: cs,
            ),
            _profileMenuRowDivider(cs),
            _ProfileTile(
              icon: LucideIcons.clock,
              label: s.get('tabWatchlist'),
              trailingCount: watchlistCount,
              onTap: () {
                if (isOtherUser) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => UserPublicWatchlistScreen(
                        uid: viewedUid,
                        ownerDisplayName: ownerName,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const WatchlistScreen()),
                  );
                }
              },
              color: cs,
            ),
            _profileMenuRowDivider(cs),
            _ProfileTile(
              icon: LucideIcons.heart,
              label: s.get('likes'),
              trailingCount: w.menuLikesCount ?? _likesCount,
              onTap: () {
                if (isOtherUser) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => UserPublicLikesScreen(
                        uid: viewedUid,
                        ownerDisplayName: ownerName,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const LikesScreen()),
                  );
                }
              },
              color: cs,
            ),
            if (w.showAppSettings) ...[
              _profileMenuRowDivider(cs),
              ListenableBuilder(
                listenable: ThemeService.instance.themeModeNotifier,
                builder: (context, _) {
                  final themeIcon =
                      Theme.of(context).brightness == Brightness.dark
                      ? LucideIcons.moon
                      : LucideIcons.sun;
                  return _ProfileTile(
                    icon: themeIcon,
                    label: s.get('theme'),
                    onTap: () => _showThemeSheet(context, s),
                    color: cs,
                  );
                },
              ),
              _profileMenuRowDivider(cs),
              _ProfileTile(
                icon: LucideIcons.languages,
                label: s.get('language'),
                onTap: () async {
                  await Navigator.push<bool>(
                    context,
                    MaterialPageRoute<bool>(
                      builder: (_) => LanguageSelectScreen(
                        title: s.get('language'),
                        showCloseButton: true,
                      ),
                    ),
                  );
                },
                color: cs,
              ),
            ],
          ],
        );
      },
    );
  }
}

void _showThemeSheet(BuildContext context, dynamic s) {
  final current = ThemeService.instance.themeModeNotifier.value;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final sheetCs = Theme.of(ctx).colorScheme;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: sheetCs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.get('theme'),
                style: _profileText(
                  sheetCs,
                  size: 16,
                  weight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(LucideIcons.sun, color: sheetCs.primary),
                title: Text(
                  s.get('themeLight'),
                  style: _profileText(sheetCs, size: 15, letterSpacing: 0.2),
                ),
                trailing: current == ThemeMode.light
                    ? Icon(Icons.check, color: sheetCs.primary)
                    : null,
                onTap: () {
                  ThemeService.instance.setThemeMode(ThemeMode.light);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.moon, color: sheetCs.primary),
                title: Text(
                  s.get('themeDark'),
                  style: _profileText(sheetCs, size: 15, letterSpacing: 0.2),
                ),
                trailing: current == ThemeMode.dark
                    ? Icon(Icons.check, color: sheetCs.primary)
                    : null,
                onTap: () {
                  ThemeService.instance.setThemeMode(ThemeMode.dark);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ─── 내가 쓴 글 / 댓글 / 팔로우 카드 ────────────────────────────────────────
// FutureBuilder 를 StatefulWidget 내부에서 한 번만 생성해 캐시 → 탭 이동 시 재로딩 없음.

class _ProfileStatRow extends StatefulWidget {
  const _ProfileStatRow({
    required this.cs,
    required this.strings,
    this.statsForUid,
    this.statsDisplayNickname,
    this.reviewCountOverride,
  });

  final ColorScheme cs;
  final dynamic strings;

  /// 타 유저 프로필: 게시글/댓글/팔로우 통계용 UID 및 표시 닉네임( `u/` 없음 ).
  final String? statsForUid;
  final String? statsDisplayNickname;

  /// 번들에서 이미 가져온 리뷰 수 — 지정 시 추가 Firestore 호출 생략.
  final int? reviewCountOverride;

  @override
  State<_ProfileStatRow> createState() => _ProfileStatRowState();
}

class _ProfileStatRowState extends State<_ProfileStatRow> {
  late Future<ProfileStatRowData> _statsFuture;
  // extras가 늦게 도착하면 didUpdateWidget에서 반영
  int? _reviewCountFromExtras;

  @override
  void initState() {
    super.initState();
    _reviewCountFromExtras = widget.reviewCountOverride;
    _statsFuture = _load();
    _profileStatsRefreshNotifier.addListener(_onRefresh);
    LocaleService.instance.localeNotifier.addListener(_onLocaleChanged);
  }

  @override
  void didUpdateWidget(_ProfileStatRow old) {
    super.didUpdateWidget(old);
    final newOverride = widget.reviewCountOverride;
    if (newOverride != null && newOverride != _reviewCountFromExtras) {
      _reviewCountFromExtras = newOverride;
      // 리뷰 수만 업데이트 — 재쿼리 없이 setState로 build만 갱신
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _profileStatsRefreshNotifier.removeListener(_onRefresh);
    LocaleService.instance.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (!mounted) return;
    // 루트 locale 반영으로 첫 프레임이 무거움 → 통계 쿼리는 다음 프레임으로 미룸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _statsFuture = _load());
    });
  }

  void _onRefresh() {
    if (mounted) setState(() => _statsFuture = _load());
  }

  Future<ProfileStatRowData> _load() async {
    final w = widget;
    final statsUid = w.statsForUid?.trim();
    if (statsUid != null && statsUid.isNotEmpty) {
      final nick = w.statsDisplayNickname?.trim() ?? '';

      // 포스트 수 + 팔로잉 수를 병렬 로드.
      // 댓글은 UserPostsScreen 진입 시 lazy 로드 (getCommentsByAuthorUid → getPostsAllPages 병목 제거).
      // 리뷰 수는 extras에서 오거나 직접 fetch.
      final postsF = PostService.instance.getPostsByAuthorUid(statsUid);
      final fcF = FollowService.instance.getFollowingCountOnce(statsUid);
      final reviewsF = (_reviewCountFromExtras == null)
          ? ReviewService.instance.fetchReviewsForUserUid(statsUid)
          : Future.value(<MyReviewItem>[]);

      final parallel = await Future.wait([postsF, fcF, reviewsF]);

      final posts = parallel[0] as List<Post>;
      final fc = parallel[1] as int;
      final reviews = parallel[2] as List<MyReviewItem>;

      String postAuthor;
      String commentAuthor;
      if (posts.isNotEmpty) {
        postAuthor = posts.first.author.trim();
        commentAuthor = postAuthor.startsWith('u/')
            ? postAuthor.substring(2)
            : postAuthor;
      } else if (nick.isNotEmpty && nick != 'Member') {
        postAuthor = 'u/$nick';
        commentAuthor = nick;
      } else {
        postAuthor = 'u/user';
        commentAuthor = nick.isNotEmpty ? nick : 'user';
      }

      return ProfileStatRowData(
        postAuthor: postAuthor,
        commentAuthor: commentAuthor,
        postCount: posts.length,
        commentCount: 0, // UserPostsScreen 진입 시 authorUid로 lazy 로드
        reviewCount: _reviewCountFromExtras ?? reviews.length,
        followCountOverride: fc,
        viewAuthorUid: statsUid,
        posts: posts,
        commentItems: null, // lazy
      );
    }
    final base = await UserProfileService.instance.getAuthorBaseName();
    final postAuthor = await UserProfileService.instance.getAuthorForPost();
    final meUid = AuthService.instance.currentUser.value?.uid?.trim();

    final postsF = (meUid != null && meUid.isNotEmpty)
        ? PostService.instance.getPostsByAuthorUid(meUid)
        : PostService.instance.getPostsByAuthor(postAuthor);
    final commentsF = (meUid != null && meUid.isNotEmpty)
        ? PostService.instance.getCommentsByAuthorUid(meUid)
        : PostService.instance.getCommentsByAuthor(base);

    final results = await Future.wait([postsF, commentsF]);
    final posts = results[0] as List<Post>;
    final comments = results[1] as List<({Post post, PostComment comment})>;
    return ProfileStatRowData(
      postAuthor: postAuthor,
      commentAuthor: base,
      postCount: posts.length,
      commentCount: comments.length,
      reviewCount: ReviewService.instance.listNotifier.value.length,
      followCountOverride: null,
      viewAuthorUid: meUid,
      posts: posts,
      commentItems: comments,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final s = widget.strings;
    final w = widget;
    return Row(
      children: [
        // ── Reviews ──
        Expanded(
          child: w.statsForUid != null
              ? FutureBuilder<ProfileStatRowData>(
                  future: _statsFuture,
                  builder: (context, snap) {
                    // extras override가 있으면 우선 사용, 없으면 future 결과
                    final reviewCount =
                        _reviewCountFromExtras ??
                        snap.data?.reviewCount ??
                        0;
                    final uid = w.statsForUid!;
                    final disp = w.statsDisplayNickname?.trim();
                    return _StatCard(
                      icon: LucideIcons.star,
                      label: s.get('tabReviews'),
                      count: reviewCount,
                      onTap: () {
                        Navigator.push<void>(
                          context,
                          CupertinoPageRoute<void>(
                            builder: (_) => UserPublicReviewsScreen(
                              uid: uid,
                              ownerDisplayName: disp,
                            ),
                          ),
                        );
                      },
                      isLight: true,
                    );
                  },
                )
              : ListenableBuilder(
                  listenable: ReviewService.instance.listNotifier,
                  builder: (context, _) {
                    final reviewCount =
                        ReviewService.instance.listNotifier.value.length;
                    return _StatCard(
                      icon: LucideIcons.star,
                      label: s.get('tabReviews'),
                      count: reviewCount,
                      loading: false,
                      onTap: () {
                        Navigator.push<void>(
                          context,
                          CupertinoPageRoute<void>(
                            builder: (_) => const MyReviewsScreen(),
                          ),
                        );
                      },
                      isLight: true,
                    );
                  },
                ),
        ),
        Container(width: 1, height: 28, color: cs.outline.withOpacity(0.4)),
        // ── Posts (글 + 댓글 탭) ──
        Expanded(
          child: FutureBuilder<ProfileStatRowData>(
            future: _statsFuture,
            builder: (context, snap) {
              final postCount = snap.data?.postCount ?? 0;
              final postAuthor = snap.data?.postAuthor ?? 'u/익명';
              final viewUid = snap.data?.viewAuthorUid;
              return _StatCard(
                icon: LucideIcons.file_text,
                label: s.get('userPostsTabPosts'),
                count: postCount,
                onTap: () {
                  final nick = snap.data?.commentAuthor ?? '';
                  final nameForScreen =
                      nick.trim().isNotEmpty ? nick.trim() : postAuthor;
                  final effectiveUid =
                      viewUid ?? AuthService.instance.currentUser.value?.uid;
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => UserPostsScreen(
                        authorName: nameForScreen,
                        authorUid: effectiveUid,
                        initialPosts: snap.data?.posts,
                        initialCommentItems: snap.data?.commentItems,
                      ),
                    ),
                  );
                },
                isLight: true,
              );
            },
          ),
        ),
        Container(width: 1, height: 28, color: cs.outline.withOpacity(0.4)),
        // ── Follow (실시간 notifier) ──
        Expanded(
          child: FutureBuilder<ProfileStatRowData>(
            future: _statsFuture,
            builder: (context, snap) {
              final w = widget;
              if (w.statsForUid != null) {
                final fc = snap.data?.followCountOverride ?? 0;
                final uid = w.statsForUid!;
                final disp = w.statsDisplayNickname?.trim().isNotEmpty == true
                    ? w.statsDisplayNickname!.trim()
                    : 'Member';
                return _StatCard(
                  icon: LucideIcons.user_plus,
                  label: s.get('profileStatFollow'),
                  count: fc,
                  onTap: () {
                    Navigator.push<void>(
                      context,
                      CupertinoPageRoute<void>(
                        builder: (_) => FollowScreen(
                          networkOwnerUid: uid,
                          ownerDisplayName: disp,
                        ),
                      ),
                    );
                  },
                  isLight: true,
                );
              }
              return ValueListenableBuilder<int>(
                valueListenable: FollowService.instance.followingCountNotifier,
                builder: (context, followCount, _) {
                  return _StatCard(
                    icon: LucideIcons.user_plus,
                    label: s.get('profileStatFollow'),
                    count: followCount,
                    onTap: () async {
                      await UserProfileService.instance.loadIfNeeded();
                      if (!context.mounted) return;
                      final uid = AuthService.instance.currentUser.value?.uid;
                      if (uid == null) return;
                      final nick = UserProfileService
                          .instance
                          .nicknameNotifier
                          .value
                          ?.trim();
                      final disp = nick != null && nick.isNotEmpty
                          ? nick
                          : (AuthService.instance.currentUser.value?.displayName
                                    ?.trim() ??
                                'Member');
                      if (!context.mounted) return;
                      Navigator.push<void>(
                        context,
                        CupertinoPageRoute<void>(
                          builder: (_) => FollowScreen(
                            networkOwnerUid: uid,
                            ownerDisplayName: disp,
                          ),
                        ),
                      );
                    },
                    isLight: true,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 메인 탭에서 내 프로필, 또는 [viewedUserUid]로 푸시된 타 유저 프로필.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.favoritesReadOnly = false,
    this.viewedUserUid,
  });

  /// true면 즐겨찾기 슬롯 탭·추가·제거 불가 (다른 유저 프로필용 확장).
  final bool favoritesReadOnly;

  /// 비어 있지 않으면 해당 UID의 공개 프로필(Theme·Language 숨김).
  final String? viewedUserUid;

  @override
  Widget build(BuildContext context) {
    final v = viewedUserUid?.trim();
    if (v != null && v.isNotEmpty) {
      return _OtherUserProfileScreen(uid: v);
    }
    return _MyProfileScreen(favoritesReadOnly: favoritesReadOnly);
  }
}

/// 2단계 로딩용 보조 데이터 (프로필 헤더 표시 후 비동기 로드).
class _OtherProfileExtras {
  const _OtherProfileExtras({
    required this.reviews,
    required this.likesCount,
    required this.listsCount,
    required this.watchlistCount,
    required this.diaryCount,
  });

  final List<MyReviewItem> reviews;
  final int likesCount;
  final int listsCount;
  final int watchlistCount;
  final int diaryCount;
}

/// 푸시된 타 유저 공개 프로필 (Theme·Language·로그아웃 없음).
/// 프로필 헤더(아바타·닉네임·즐겨찾기)는 즉시 표시하고,
/// 통계·리뷰·카운트는 비동기로 로드 → 점진적 렌더링.
class _OtherUserProfileScreen extends StatefulWidget {
  const _OtherUserProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  State<_OtherUserProfileScreen> createState() =>
      _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<_OtherUserProfileScreen> {
  // 1단계: 프로필 문서만 (캐시 있으면 즉시)
  Future<PublicUserProfile?>? _profileFuture;
  // 2단계: 리뷰·좋아요·카운트 (프로필과 동시에 시작)
  Future<_OtherProfileExtras>? _extrasFuture;

  PreferredSizeWidget _listsStyleAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
      child: ListsStyleSubpageHeaderBar(
        title: '',
        onBack: () => popListsStyleSubpage(context),
      ),
    );
  }

  Widget _listsStyleScaffold({
    required BuildContext context,
    required ThemeData theme,
    required PreferredSizeWidget appBar,
    required Widget body,
  }) {
    final headerBg = listsStyleSubpageHeaderBackground(theme);
    return ListsStyleSubpageHorizontalSwipeBack(
      onSwipePop: () => popListsStyleSubpage(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: listsStyleSubpageSystemOverlay(theme, headerBg),
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: appBar,
          body: body,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  void _startLoad({bool forceRefresh = false}) {
    final uid = widget.uid;
    // 프로필과 extras 동시에 시작 — 둘 다 독립적
    _profileFuture = UserProfileService.instance.fetchPublicUserProfile(
      uid,
      forceRefresh: forceRefresh,
    );
    _extrasFuture = _loadExtras(uid);
  }

  Future<_OtherProfileExtras> _loadExtras(String uid) async {
    final results = await Future.wait([
      ReviewService.instance.fetchReviewsForUserUid(uid),
      PostService.instance.getPostsLikedByUid(uid),
      CustomDramaListService.instance.countListsForUid(uid),
      WatchlistService.instance.countWatchlistForUid(uid),
      WatchHistoryService.instance.countWatchHistoryForUid(uid),
    ]);
    return _OtherProfileExtras(
      reviews: results[0] as List<MyReviewItem>,
      likesCount: (results[1] as List<Post>).length,
      listsCount: results[2] as int,
      watchlistCount: results[3] as int,
      diaryCount: results[4] as int,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    if (_profileFuture == null || _extrasFuture == null) {
      _startLoad();
    }

    // 1단계: 프로필만 기다림 (캐시 있으면 즉시 완료)
    return FutureBuilder<PublicUserProfile?>(
      future: _profileFuture,
      builder: (context, profileSnap) {
        if (profileSnap.connectionState == ConnectionState.waiting) {
          return _listsStyleScaffold(
            context: context,
            theme: theme,
            appBar: _listsStyleAppBar(context),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final p = profileSnap.data;
        if (p == null) {
          return _listsStyleScaffold(
            context: context,
            theme: theme,
            appBar: _listsStyleAppBar(context),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.get('profilePublicUserUnavailable'),
                  textAlign: TextAlign.center,
                  style: _profileText(cs, size: 15, letterSpacing: 0.2),
                ),
              ),
            ),
          );
        }
        final hasPhoto =
            p.profileImageUrl != null && p.profileImageUrl!.isNotEmpty;

        // 2단계: extras 비동기 — 아직 로딩 중이어도 헤더는 보여줌
        return _listsStyleScaffold(
          context: context,
          theme: theme,
          appBar: _listsStyleAppBar(context),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => _startLoad(forceRefresh: true));
                await Future.wait([_profileFuture!, _extrasFuture!]);
              },
              child: FutureBuilder<_OtherProfileExtras>(
                future: _extrasFuture,
                builder: (context, extrasSnap) {
                  final extras = extrasSnap.data;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            20,
                            20,
                            20,
                            _kProfileSectionBleedPadV,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: _OtherProfileFollowButton(
                                        targetUid: p.uid,
                                        targetNickname: p.displayNickname,
                                        targetPhotoUrl: p.profileImageUrl,
                                        cs: cs,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasPhoto
                                          ? cs.surfaceContainerHighest
                                          : (p.avatarColorIndex != null
                                                ? UserProfileService.bgColorFromIndex(
                                                    p.avatarColorIndex!,
                                                  )
                                                : cs.surfaceContainerHighest),
                                      border: Border.all(
                                        color: cs.outline.withValues(alpha: 0.4),
                                        width: 2,
                                      ),
                                      image: hasPhoto
                                          ? DecorationImage(
                                              image: CachedNetworkImageProvider(
                                                p.profileImageUrl!,
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: hasPhoto
                                        ? null
                                        : Icon(
                                            Icons.person,
                                            size: 44,
                                            color: p.avatarColorIndex != null
                                                ? UserProfileService.iconColorFromIndex(
                                                    p.avatarColorIndex!,
                                                  )
                                                : cs.onSurfaceVariant.withValues(
                                                    alpha: 0.6,
                                                  ),
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  const Expanded(child: SizedBox()),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                p.displayNickname,
                                textAlign: TextAlign.center,
                                style: _profileText(
                                  cs,
                                  size: 20,
                                  weight: FontWeight.w700,
                                  color: cs.onSurface,
                                  letterSpacing: 0.22,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.cardTheme.color ?? cs.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: cs.outline.withValues(alpha: 0.4),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.shadow.withValues(alpha: 0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: _ProfileStatRow(
                                  cs: cs,
                                  strings: s,
                                  statsForUid: p.uid,
                                  statsDisplayNickname: p.displayNickname,
                                  reviewCountOverride: extras?.reviews.length,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _profileFullBleedDivider(cs)),
                      SliverToBoxAdapter(
                        child: _ProfileFavoritesSection(
                          readOnly: true,
                          favoritesOverride: p.favorites,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _ProfileRecentActivitySection(
                          reviewsOverride: extras?.reviews,
                        ),
                      ),
                      SliverToBoxAdapter(child: _profileFullBleedDivider(cs)),
                      SliverToBoxAdapter(
                        child: _ProfileRatingsSection(ratingsUid: p.uid),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: _kProfileSectionBleedPadV,
                          ),
                          child: _ProfileLinksMenu(
                            cs: cs,
                            strings: s,
                            showAppSettings: false,
                            menuDiaryCount: extras?.diaryCount,
                            menuListsCount: extras?.listsCount,
                            menuWatchlistCount: extras?.watchlistCount,
                            menuLikesCount: extras?.likesCount,
                            viewedUid: p.uid,
                            ownerDisplayName: p.displayNickname,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 프로필 탭 - 로그인 후 표시 (내 계정)
class _MyProfileScreen extends StatelessWidget {
  const _MyProfileScreen({super.key, this.favoritesReadOnly = false});

  /// true면 즐겨찾기 슬롯 탭·추가·제거 불가 (다른 유저 프로필용 확장).
  final bool favoritesReadOnly;

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final logoutTint = cs.onSurfaceVariant.withValues(
      alpha: isLight ? 0.36 : 0.58,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _profileStatsRefreshNotifier.value++;
            await Future.wait([
              UserProfileService.instance.loadIfNeeded(),
              SavedService.instance.loadIfNeeded(),
              WatchlistService.instance.loadIfNeeded(force: true),
              WatchHistoryService.instance.loadIfNeeded(),
              ReviewService.instance.loadIfNeeded(),
            ]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ─── 프로필 헤더 (카드 밖) ───
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    _kProfileSectionBleedPadV,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 프로필 사진 + 카메라 아이콘
                      Align(
                        alignment: Alignment.center,
                        child: Builder(
                          builder: (outerCtx) => ValueListenableBuilder<String?>(
                            valueListenable: UserProfileService
                                .instance
                                .profileImageUrlNotifier,
                            builder: (_, profileUrl, __) {
                              final hasPhoto =
                                  profileUrl != null && profileUrl.isNotEmpty;
                              return ValueListenableBuilder<int?>(
                                valueListenable: UserProfileService
                                    .instance
                                    .avatarColorNotifier,
                                builder: (_, colorIdx, __) {
                                  final bgColor = colorIdx != null
                                      ? UserProfileService.bgColorFromIndex(
                                          colorIdx,
                                        )
                                      : cs.surfaceContainerHighest;
                                  final iconColor = colorIdx != null
                                      ? UserProfileService.iconColorFromIndex(
                                          colorIdx,
                                        )
                                      : cs.onSurfaceVariant.withOpacity(0.6);
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: hasPhoto
                                              ? cs.surfaceContainerHighest
                                              : bgColor,
                                          border: Border.all(
                                            color: cs.outline.withOpacity(0.4),
                                            width: 2,
                                          ),
                                          image: hasPhoto
                                              ? DecorationImage(
                                                  image:
                                                      CachedNetworkImageProvider(
                                                        profileUrl,
                                                      ),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: hasPhoto
                                            ? null
                                            : Icon(
                                                Icons.person,
                                                size: 44,
                                                color: iconColor,
                                              ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: GestureDetector(
                                          onTap: () => _showProfilePhotoOptions(
                                            outerCtx,
                                            s,
                                            cs,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHighest,
                                              border: Border.all(
                                                color: cs.outline.withOpacity(
                                                  0.4,
                                                ),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: cs.shadow.withOpacity(
                                                    0.06,
                                                  ),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              LucideIcons.camera,
                                              size: 16,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<String?>(
                        valueListenable:
                            UserProfileService.instance.nicknameNotifier,
                        builder: (context, nick, _) {
                          final nickname = nick?.trim() ?? '';
                          final displayName = AuthService
                                  .instance
                                  .currentUser
                                  .value
                                  ?.displayName
                                  ?.trim() ??
                              '';
                          final emailPrefix = AuthService
                                  .instance
                                  .currentUser
                                  .value
                                  ?.email
                                  ?.split('@')
                                  .first
                                  .trim() ??
                              '';
                          final name = nickname.isNotEmpty
                              ? nickname
                              : (displayName.isNotEmpty
                                    ? displayName
                                    : (emailPrefix.isNotEmpty
                                          ? emailPrefix
                                          : 'Member'));
                          return Text(
                            name,
                            textAlign: TextAlign.center,
                            style: _profileText(
                              cs,
                              size: 20,
                              weight: FontWeight.w700,
                              color: cs.onSurface,
                              letterSpacing: 0.22,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // Reviews · Posts · Follow (닉네임 바로 아래)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color ?? cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outline.withOpacity(0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _ProfileStatRow(cs: cs, strings: s),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _profileFullBleedDivider(cs)),
              SliverToBoxAdapter(
                child: _ProfileFavoritesSection(readOnly: favoritesReadOnly),
              ),
              const SliverToBoxAdapter(child: _ProfileRecentActivitySection()),
              SliverToBoxAdapter(child: _profileFullBleedDivider(cs)),
              SliverToBoxAdapter(child: _ProfileRatingsSection()),
              // 메뉴: Ratings와 바로 이어지고, 구분선은 Diary 위(_ProfileLinksMenu)에서만
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: _kProfileSectionBleedPadV,
                  ),
                  child: _ProfileLinksMenu(cs: cs, strings: s),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              // 로그아웃
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final s = CountryScope.of(context).strings;
                        await AuthService.instance.signOut();
                        PostService.instance.clearLikedPostsScreenCache();
                        SavedService.instance.clearForLogout();
                        WatchlistService.instance.clearForLogout();
                        MessageService.instance.clearForLogout();
                        await LevelService.instance.resetForLogout();
                        UserProfileService.instance.clearForLogout();
                        await ShareService.instance.clearForLogout();
                        await ReviewService.instance.clearForLogout();
                        await WatchHistoryService.instance.clearForLogout();
                        CustomDramaListService.instance.clearForLogout();
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('last_free_board_post_time_ms');
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              s.get('logoutSuccess'),
                              style: _profileText(
                                cs,
                                size: 14,
                                letterSpacing: 0.18,
                              ),
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: cs.inverseSurface,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.log_out,
                              size: 16,
                              color: logoutTint,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s.get('logout'),
                              style: _profileText(
                                cs,
                                size: 11,
                                weight: FontWeight.w400,
                                color: logoutTint,
                                letterSpacing: 0.14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Letterboxd 프로필 FAVORITES — 가로 4슬롯(2:3), 슬롯 패딩은 RECENT ACTIVITY와 동일.
class _ProfileFavoritesSection extends StatelessWidget {
  const _ProfileFavoritesSection({
    required this.readOnly,
    this.favoritesOverride,
  });

  final bool readOnly;

  /// 타 유저 프로필: Firestore에서 읽은 즐겨찾기(최대 4).
  final List<ProfileFavorite>? favoritesOverride;

  Future<void> _openFavoriteDetail(
    BuildContext context,
    ProfileFavorite f,
  ) async {
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => FavoriteTitleActivityScreen(favorite: f),
      ),
    );
  }

  Future<void> _onEmptySlotTap(BuildContext context) async {
    if (readOnly) return;
    final item = await Navigator.push<DramaItem>(
      context,
      MaterialPageRoute<DramaItem>(
        builder: (_) => const DramaSearchScreen(pickMode: true),
      ),
    );
    if (item == null || !context.mounted) return;
    final country = CountryScope.maybeOf(context)?.country;
    final title = DramaListService.instance.getDisplayTitle(item.id, country);
    final thumb =
        DramaListService.instance.getDisplayImageUrl(item.id, country) ??
        item.imageUrl;
    await UserProfileService.instance.addFavorite(
      ProfileFavorite(
        dramaId: item.id,
        dramaTitle: title,
        dramaThumbnail: thumb,
      ),
    );
  }

  void _onLongPressFavorite(BuildContext context, ProfileFavorite f) {
    if (readOnly) return;
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.delete_outline, color: kAppDeleteActionColor),
              title: Text(
                s.get('profileFavoritesRemove'),
                style: _profileText(cs, size: 15, letterSpacing: 0.2).copyWith(
                  color: kAppDeleteActionColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await UserProfileService.instance.removeFavoriteByDramaId(
                  f.dramaId,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _favoriteSlotContent(
    BuildContext context,
    ColorScheme cs,
    bool readOnly,
    ProfileFavorite? fav,
  ) {
    if (fav == null) {
      return _FavoriteEmptySlot(
        readOnly: readOnly,
        onTap: readOnly ? null : () => _onEmptySlotTap(context),
        color: _profileEmptySlotDashColor(cs, Theme.of(context).brightness),
      );
    }
    // RECENT ACTIVITY와 동일 구조: Material → InkWell → ClipRRect → 이미지
    // memCacheWidth/Height 양쪽 지정 시 ResizeImage가 강제 리사이즈해 비율 왜곡 → null 유지
    final resolved = _profileResolvedFavoriteThumbnail(context, fav);
    final u = resolved?.trim() ?? '';

    Widget imageChild;
    if (u.startsWith('http')) {
      imageChild = OptimizedNetworkImage(
        imageUrl: u,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        memCacheWidth: null,
        memCacheHeight: null,
      );
    } else if (u.startsWith('assets/')) {
      imageChild = Image.asset(
        u,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      imageChild = Center(
        child: Icon(
          LucideIcons.film,
          size: 28,
          color: cs.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Material(
            color: cs.surfaceContainerHighest,
            child: InkWell(
              onTap: () => _openFavoriteDetail(context, fav),
              onLongPress: readOnly
                  ? null
                  : () => _onLongPressFavorite(context, fav),
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageChild,
              ),
            ),
          ),
        ),
        if (!readOnly)
          Positioned(
            top: 3,
            right: 3,
            child: Material(
              color: Colors.black.withValues(alpha: 0.52),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await UserProfileService.instance.removeFavoriteByDramaId(
                    fav.dramaId,
                  );
                },
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    Widget rowFor(List<ProfileFavorite> favs) {
      return ListenableBuilder(
        listenable: Listenable.merge([
          LocaleService.instance.localeNotifier,
          DramaListService.instance.listNotifier,
          DramaListService.instance.extraNotifier,
        ]),
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(4, (i) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AspectRatio(
                    aspectRatio: _kProfileRecentActivityPosterAspect,
                    child: _favoriteSlotContent(
                      context,
                      cs,
                      readOnly,
                      i < favs.length ? favs[i] : null,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kProfileSectionBleedPadH,
        _kProfileSectionBleedPadV,
        _kProfileSectionBleedPadH,
        _kProfileSectionBleedPadV,
      ),
      child: favoritesOverride != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.get('profileFavoritesTitle'),
                  style: _profileCapsLabel(cs),
                ),
                const SizedBox(height: 6),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    LocaleService.instance.localeNotifier,
                    DramaListService.instance.listNotifier,
                    DramaListService.instance.extraNotifier,
                  ]),
                  builder: (context, _) {
                    final favs = UserProfileService.favoritesVisibleInLocale(
                      favoritesOverride!,
                      LocaleService.instance.locale,
                    );
                    return rowFor(favs);
                  },
                ),
              ],
            )
          : ListenableBuilder(
              listenable: Listenable.merge([
                LocaleService.instance.localeNotifier,
                UserProfileService.instance.favoritesNotifier,
              ]),
              builder: (context, _) {
                final favs = UserProfileService.instance
                    .favoritesVisibleForCurrentLocale();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.get('profileFavoritesTitle'),
                      style: _profileCapsLabel(cs),
                    ),
                    const SizedBox(height: 6),
                    rowFor(favs),
                  ],
                );
              },
            ),
    );
  }
}

class _FavoriteEmptySlot extends StatelessWidget {
  const _FavoriteEmptySlot({
    required this.readOnly,
    required this.onTap,
    required this.color,
  });

  final bool readOnly;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final child = CustomPaint(
      painter: _DashedRRectPainter(
        color: color,
        strokeWidth: _profileEmptySlotDashStrokeWidth(brightness),
      ),
      child: Center(
        child: Icon(
          LucideIcons.plus,
          size: 28,
          color: readOnly
              ? cs.onSurfaceVariant.withValues(alpha: 0.25)
              : cs.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );
    if (readOnly || onTap == null) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, this.strokeWidth = 1.2});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      const dash = 5.0;
      const gap = 3.5;
      while (d < metric.length) {
        final len = (dash < metric.length - d) ? dash : (metric.length - d);
        canvas.drawPath(metric.extractPath(d, d + len), paint);
        d += len + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}

/// Letterboxd 스타일 별점 분포 막대 그래프 (탭·드래그로 구간별 별 / 점수 표시).
class _ProfileRatingsSection extends StatefulWidget {
  const _ProfileRatingsSection({this.ratingsUid});

  /// null이면 로그인한 사용자 UID.
  final String? ratingsUid;

  @override
  State<_ProfileRatingsSection> createState() => _ProfileRatingsSectionState();
}

class _ProfileRatingsSectionState extends State<_ProfileRatingsSection> {
  Future<ProfileRatingHistogram>? _histFuture;
  String? _loadedUid;

  String? _resolveUid() {
    final r = widget.ratingsUid?.trim();
    if (r != null && r.isNotEmpty) return r;
    return AuthService.instance.currentUser.value?.uid;
  }

  void _loadHistogram() {
    final uid = _resolveUid();
    if (uid == null || uid.isEmpty) return;
    _loadedUid = uid;
    _histFuture = PostService.instance.aggregateReviewRatingsForUid(uid);
  }

  @override
  void initState() {
    super.initState();
    _loadHistogram();
    _profileStatsRefreshNotifier.addListener(_onHistogramRefresh);
    LocaleService.instance.localeNotifier.addListener(_onLocaleHistogramDeferred);
    // 자신의 프로필일 때만 리뷰 목록 변화 감지
    if (widget.ratingsUid == null) {
      ReviewService.instance.listNotifier.addListener(_onHistogramRefresh);
    }
  }

  @override
  void dispose() {
    _profileStatsRefreshNotifier.removeListener(_onHistogramRefresh);
    LocaleService.instance.localeNotifier.removeListener(
      _onLocaleHistogramDeferred,
    );
    if (widget.ratingsUid == null) {
      ReviewService.instance.listNotifier.removeListener(_onHistogramRefresh);
    }
    super.dispose();
  }

  void _onHistogramRefresh() {
    if (!mounted) return;
    setState(_loadHistogram);
  }

  void _onLocaleHistogramDeferred() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_loadHistogram);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    final uid = _resolveUid();
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();

    // uid가 바뀐 경우(위젯 재사용) 재로드
    if (_loadedUid != uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_loadHistogram);
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kProfileSectionBleedPadH,
        _kProfileSectionBleedPadV,
        _kProfileSectionBleedPadH,
        _kProfileSectionBleedPadV,
      ),
      child: FutureBuilder<ProfileRatingHistogram>(
        future: _histFuture,
        builder: (context, snap) {
          final hist = snap.data ?? ProfileRatingHistogram.empty();
          return _ProfileRatingsInteractiveBody(
            key: ValueKey(hist.countsPerHalfStar.join(',')),
            hist: hist,
            cs: cs,
            strings: s,
            ratingsForSelf: widget.ratingsUid == null,
          );
        },
      ),
    );
  }
}

class _ProfileRatingsInteractiveBody extends StatefulWidget {
  const _ProfileRatingsInteractiveBody({
    super.key,
    required this.hist,
    required this.cs,
    required this.strings,
    required this.ratingsForSelf,
  });

  final ProfileRatingHistogram hist;
  final ColorScheme cs;
  final dynamic strings;
  final bool ratingsForSelf;

  @override
  State<_ProfileRatingsInteractiveBody> createState() =>
      _ProfileRatingsInteractiveBodyState();
}

class _ProfileRatingsInteractiveBodyState
    extends State<_ProfileRatingsInteractiveBody>
    with SingleTickerProviderStateMixin {
  int? _pressedBucket;
  int? _trackingPointer;
  AnimationController? _starsRevealController;

  static const double _chartBarMaxH = 50.0;
  static const double _axisStarSize = _kProfileRatingsAxisStarSize;
  static const Color _axisStarColor = AppColors.ratingStar;
  static const double _leftStarSlotW = _axisStarSize + 2;
  static const double _axisInnerGap = 2.0;
  static const double _rightStarsClusterW = _axisStarSize * 5 + 0.5 * 4;

  double _ratingForBucket(int i) => (i + 1) * 0.5;

  @override
  void initState() {
    super.initState();
    _starsRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _starsRevealController?.dispose();
    super.dispose();
  }

  void _setBucketFromDx(double dx, double width) {
    final n = widget.hist.countsPerHalfStar.length;
    final b = _RatingHistogramPainter.bucketIndexFromDx(dx, width, n);
    if (_pressedBucket != b) {
      setState(() => _pressedBucket = b);
      final c = _starsRevealController;
      if (c != null) {
        c
          ..reset()
          ..forward();
      }
    }
  }

  void _clearBucket() {
    _trackingPointer = null;
    if (_pressedBucket != null) {
      setState(() => _pressedBucket = null);
      _starsRevealController?.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hist = widget.hist;
    final cs = widget.cs;
    final s = widget.strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxC = hist.maxCount;
    final emptyStarTint = cs.onSurfaceVariant.withValues(alpha: 0.38);
    const double rightDetailH = 56.0;

    /// 탭 시 개수 숫자 — 별 줄 위에 붙이기(스택 상단 `top:0`이면 간격이 너무 벌어짐).
    const double rightRatingCountBottom = 15.0;

    final ratingsTitleKey = widget.ratingsForSelf
        ? 'profileRatingsTitle'
        : 'profileRatingsTitleOther';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.get(ratingsTitleKey), style: _profileCapsLabel(cs)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: _leftStarSlotW,
              height: _chartBarMaxH,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _pressedBucket == null ? 1 : 0,
                child: const Align(
                  alignment: Alignment.bottomCenter,
                  child: Icon(
                    Icons.star_rounded,
                    size: _axisStarSize,
                    color: _axisStarColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _axisInnerGap),
            Expanded(
              child: SizedBox(
                height: _chartBarMaxH,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        _trackingPointer = e.pointer;
                        _setBucketFromDx(e.localPosition.dx, w);
                      },
                      onPointerMove: (e) {
                        if (_trackingPointer != e.pointer) return;
                        _setBucketFromDx(e.localPosition.dx, w);
                      },
                      onPointerUp: (e) {
                        if (_trackingPointer != e.pointer) return;
                        _clearBucket();
                      },
                      onPointerCancel: (e) {
                        if (_trackingPointer != e.pointer) return;
                        _clearBucket();
                      },
                      child: CustomPaint(
                        painter: _RatingHistogramPainter(
                          counts: hist.countsPerHalfStar,
                          maxCount: maxC,
                          barMaxHeight: _chartBarMaxH,
                          // 평소: 짙은 회색 / 탭한 막대만 조금 더 옅은 회색.
                          barMuted: cs.onSurface.withValues(
                            alpha: isDark ? 0.28 : 0.44,
                          ),
                          barStrong: cs.onSurface.withValues(
                            alpha: isDark ? 0.48 : 0.62,
                          ),
                          barMutedIdle: cs.onSurface.withValues(
                            alpha: isDark ? 0.28 : 0.44,
                          ),
                          barStrongIdle: cs.onSurface.withValues(
                            alpha: isDark ? 0.48 : 0.62,
                          ),
                          // 빈 슬롯 고스트 — 라이트에서 outline 알파가 너무 낮아 묻힘
                          ghostTint: cs.outline.withValues(
                            alpha: isDark ? 0.22 : 0.48,
                          ),
                          ghostTintIdle: cs.outline.withValues(
                            alpha: isDark ? 0.32 : 0.58,
                          ),
                          selectedIndex: _pressedBucket,
                          selectedLift: cs.surfaceContainerHighest,
                          selectionStroke: cs.onSurface.withValues(
                            alpha: isDark ? 0.22 : 0.34,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: _axisInnerGap),
            // 별 5개 너비 고정 + 탭 시 위쪽에 숫자(중앙) / 아래 별줄
            SizedBox(
              width: _rightStarsClusterW,
              height: rightDetailH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── 하단 고정: 별 5개(평소) or 탭시 별줄 ──
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _pressedBucket == null
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              5,
                              (i) => Padding(
                                padding: EdgeInsets.only(left: i > 0 ? 0.5 : 0),
                                child: const Icon(
                                  Icons.star_rounded,
                                  size: _axisStarSize,
                                  color: _axisStarColor,
                                ),
                              ),
                            ),
                          )
                        : _StarRow(
                            rating: _ratingForBucket(_pressedBucket!),
                            size: _axisStarSize,
                            fillColor: _axisStarColor,
                            emptyColor: emptyStarTint,
                            halfAsTextLabel: true,
                            alignStart: false,
                          ),
                  ),
                  // ── 탭시 개수 숫자 — 별 5개 폭 가로 중앙, 세로는 별 줄 바로 위
                  if (_pressedBucket != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: rightRatingCountBottom,
                      child: Builder(
                        builder: (context) {
                          final ctrl = _starsRevealController;
                          final count = hist.countsPerHalfStar[_pressedBucket!];
                          final child = Text(
                            '$count',
                            textAlign: TextAlign.center,
                            style: _profileText(
                              cs,
                              size: 22,
                              weight: FontWeight.w300,
                              color: cs.onSurface.withValues(alpha: 0.92),
                              letterSpacing: 0.15,
                              height: 1.0,
                            ),
                          );
                          if (ctrl == null) return child;
                          return _profileRatingsRevealSlot(
                            animation: ctrl,
                            slotIndex: 0,
                            slotCount: 1,
                            child: child,
                          );
                        },
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

class _RatingHistogramPainter extends CustomPainter {
  _RatingHistogramPainter({
    required this.counts,
    required this.maxCount,
    required this.barMaxHeight,

    /// 탭(선택)된 막대 — 이전 기본 톤.
    required this.barMuted,
    required this.barStrong,

    /// 평소 막대 — 더 짙은 회색.
    required this.barMutedIdle,
    required this.barStrongIdle,
    required this.ghostTint,
    required this.ghostTintIdle,
    this.selectedIndex,
    required this.selectedLift,
    required this.selectionStroke,
  });

  final List<int> counts;
  final int maxCount;

  /// 막대 최대 픽셀 높이 (count == maxCount일 때 이 값).
  final double barMaxHeight;

  /// 탭 시: 낮은 빈도 / 높은 빈도 (기존 기본과 동일).
  final Color barMuted;
  final Color barStrong;

  /// 평소: 더 짙은 그라데이션 끝점.
  final Color barMutedIdle;
  final Color barStrongIdle;
  final Color ghostTint;
  final Color ghostTintIdle;
  final int? selectedIndex;

  /// 선택된 빈 칸 고스트만 살짝 밝힘.
  final Color selectedLift;
  final Color selectionStroke;

  static const double kBarGap = 3.0;

  static double _barWidth(double width, int n) {
    if (n <= 0 || width <= 0) return 0;
    return (width - kBarGap * (n - 1)) / n;
  }

  /// 차트 너비 [width]·로컬 [dx]에 해당하는 반별 버킷 인덱스 (0..n-1).
  static int bucketIndexFromDx(double dx, double width, int n) {
    dx = dx.clamp(0.0, width);
    if (n <= 0) return 0;
    final bw = _barWidth(width, n);
    if (bw <= 0) return 0;
    for (var i = 0; i < n; i++) {
      final left = i * (bw + kBarGap);
      final barRight = left + bw;
      if (dx <= barRight) return i;
      if (i < n - 1) {
        final nextLeft = (i + 1) * (bw + kBarGap);
        if (dx < nextLeft) {
          final mid = (barRight + nextLeft) / 2;
          return dx < mid ? i : i + 1;
        }
      }
    }
    return n - 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = counts.length;
    if (n == 0) return;
    final bw = _barWidth(size.width, n);
    final maxH = barMaxHeight.clamp(0.0, size.height);
    final mc = maxCount > 0 ? maxCount : 1;
    const ghostH = 2.0;
    final sel = selectedIndex;

    // 각 슬롯별로: 값이 0인 칸만 ghost 선 표시 (값이 있으면 막대만 표시).
    for (var i = 0; i < n; i++) {
      if (counts[i] > 0) continue;
      final left = i * (bw + kBarGap);
      final ghostRect = Rect.fromLTWH(left, maxH - ghostH, bw, ghostH);
      var gh = barMutedIdle;
      if (sel != null && sel == i) {
        gh = barStrong;
      }
      canvas.drawRect(ghostRect, Paint()..color = gh);
    }

    for (var i = 0; i < n; i++) {
      final c = counts[i];
      final h = (c / mc) * maxH;
      if (h <= 0) continue;
      final left = i * (bw + kBarGap);
      final color = sel == i ? barStrong : barMutedIdle;
      final rect = Rect.fromLTWH(left, maxH - h, bw, h);
      canvas.drawRect(rect, Paint()..color = color);
    }

    if (sel != null && sel >= 0 && sel < n) {
      final left = sel * (bw + kBarGap);
      final c = counts[sel];
      final h = (c / mc) * maxH;
      final topY = c > 0 ? maxH - h : maxH - ghostH;
      final strokeH = c > 0 ? h : ghostH;
      final outline = Rect.fromLTWH(left, topY, bw, strokeH);
      canvas.drawRect(
        outline,
        Paint()
          ..color = selectionStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RatingHistogramPainter oldDelegate) =>
      counts != oldDelegate.counts ||
      maxCount != oldDelegate.maxCount ||
      barMaxHeight != oldDelegate.barMaxHeight ||
      barMuted != oldDelegate.barMuted ||
      barStrong != oldDelegate.barStrong ||
      barMutedIdle != oldDelegate.barMutedIdle ||
      barStrongIdle != oldDelegate.barStrongIdle ||
      ghostTint != oldDelegate.ghostTint ||
      ghostTintIdle != oldDelegate.ghostTintIdle ||
      selectedIndex != oldDelegate.selectedIndex ||
      selectedLift != oldDelegate.selectedLift ||
      selectionStroke != oldDelegate.selectionStroke;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    this.loading = false,
    this.isLight = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  final bool loading;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isLight
        ? cs.onSurfaceVariant
        : Colors.white.withOpacity(0.85);
    final labelColor = isLight
        ? cs.onSurfaceVariant
        : Colors.white.withOpacity(0.75);
    final valueColor = isLight ? cs.onSurface : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: _profileText(
                  cs,
                  size: 10,
                  color: labelColor,
                  weight: FontWeight.w700,
                  letterSpacing: 0.15,
                ),
              ),
              const SizedBox(height: 1),
              loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isLight
                            ? cs.onSurfaceVariant
                            : Colors.white.withOpacity(0.7),
                      ),
                    )
                  : Text(
                      '$count',
                      style: _profileText(
                        cs,
                        size: 15,
                        weight: FontWeight.w700,
                        color: valueColor,
                        letterSpacing: 0.2,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recent Activity 반쪽 — RATINGS 히스토그램 탭 시 숫자(`4½`)와 동일 문자·타이포의 `½`만 표시.
Widget _profileRecentHalfGlyphLabel(Color grey, ColorScheme cs) {
  return Text(
    '\u00BD',
    style: _profileText(
      cs,
      size: _kProfileRatingsAndMenuFontSize,
      weight: FontWeight.w800,
      color: grey,
      letterSpacing: 0.2,
      height: 1,
    ),
  );
}

/// 별점 한 줄. [halfAsTextLabel]==true면 Recent Activity: 회색 꽉 별 + RATINGS와 동일 `½`.
class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.rating,
    this.size = 11,
    this.fillColor,
    this.emptyColor,
    this.halfAsTextLabel = false,
    this.alignStart = false,
    this.revealAnimation,
    this.revealFirstSlotIndex = 0,
    this.revealTotalSlots = 0,
  });

  final double rating;
  final double size;
  final Color? fillColor;
  final Color? emptyColor;

  /// true: 4.5 → 회색 별 N개 + RATINGS와 동일 `½`.
  final bool halfAsTextLabel;

  /// true면 `halfAsTextLabel` 줄을 가로 왼쪽 정렬.
  final bool alignStart;
  final Animation<double>? revealAnimation;

  /// [revealAnimation] 사용 시 별·½ 각각의 전역 슬롯 시작 인덱스(위쪽 개수 등이 0번이면 1).
  final int revealFirstSlotIndex;

  /// 전체 슬롯 수(개수+별 등). 0이면 순차 등장 없음.
  final int revealTotalSlots;

  static Widget _halfStar(double iconSize, Color color) {
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 0.5,
        child: Icon(Icons.star_rounded, size: iconSize, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = fillColor ?? AppColors.ratingStar;
    final empty = emptyColor ?? cs.onSurfaceVariant.withValues(alpha: 0.28);
    final c = rating.clamp(0.0, 5.0);
    final r = (c * 2).round() / 2.0;

    if (halfAsTextLabel) {
      final grey = fillColor ?? cs.onSurfaceVariant.withValues(alpha: 0.52);
      final full = r.floor();
      final hasHalf = (r - full) >= 0.5;
      final slotW = size * 0.88;
      final gapBeforeHalf = (size * 0.1).clamp(2.0, 5.0);
      final useReveal = revealAnimation != null && revealTotalSlots > 0;
      Widget wrapReveal(int localSlot, Widget w) {
        if (!useReveal) return w;
        return _profileRatingsRevealSlot(
          animation: revealAnimation!,
          slotIndex: revealFirstSlotIndex + localSlot,
          slotCount: revealTotalSlots,
          child: w,
        );
      }

      final children = <Widget>[];
      var localSlot = 0;
      for (var i = 0; i < full; i++) {
        children.add(
          wrapReveal(
            localSlot,
            SizedBox(
              width: slotW,
              height: size * 1.05,
              child: Center(
                child: Icon(Icons.star_rounded, size: size, color: grey),
              ),
            ),
          ),
        );
        localSlot++;
      }
      if (hasHalf) {
        if (full > 0) children.add(SizedBox(width: gapBeforeHalf));
        children.add(
          wrapReveal(
            localSlot,
            SizedBox(
              height: size * 1.05,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _profileRecentHalfGlyphLabel(grey, cs),
              ),
            ),
          ),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: alignStart
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final starValue = i + 1.0;
        final isFull = r >= starValue;
        final isHalf = r >= starValue - 0.5 && r < starValue;
        final slotW = size * 0.95;
        Widget star;
        if (isFull) {
          star = Icon(Icons.star_rounded, size: size, color: fill);
        } else if (isHalf) {
          star = _halfStar(size, fill);
        } else {
          star = Icon(Icons.star_border_rounded, size: size, color: empty);
        }
        return SizedBox(
          width: slotW,
          height: size * 1.05,
          child: Center(child: star),
        );
      }),
    );
  }
}

DramaItem _dramaItemFromReview(MyReviewItem r, String? country) {
  final title =
      r.dramaId.trim().isNotEmpty &&
          DramaListService.instance
              .getDisplayTitle(r.dramaId, country)
              .trim()
              .isNotEmpty
      ? DramaListService.instance.getDisplayTitle(r.dramaId, country)
      : DramaListService.instance.getDisplayTitleByTitle(r.dramaTitle, country);
  return DramaItem(
    id: r.dramaId,
    title: title,
    subtitle: '',
    views: '0',
    rating: r.rating,
    isPopular: false,
  );
}

/// DramaFeed `posts`에 없을 때 Recent Activity → Letterboxd 리뷰 상세용 합성 글.
Post _syntheticLetterboxdPostFromMyReview({
  required MyReviewItem review,
  required String author,
  required String country,
  String? authorPhotoUrl,
  String? authorUid,
}) {
  final did = review.dramaId.trim();
  final locale = country;
  String displayTitle;
  if (did.isNotEmpty && !did.startsWith('short-')) {
    final t = DramaListService.instance.getDisplayTitle(did, locale).trim();
    displayTitle = t.isNotEmpty ? t : review.dramaTitle.trim();
  } else {
    final t = DramaListService.instance
        .getDisplayTitleByTitle(review.dramaTitle, locale)
        .trim();
    displayTitle = t.isNotEmpty ? t : review.dramaTitle.trim();
  }
  if (displayTitle.isEmpty) displayTitle = review.dramaTitle.trim();

  String? thumb;
  if (did.isNotEmpty && !did.startsWith('short-')) {
    thumb = DramaListService.instance.getDisplayImageUrl(did, locale)?.trim();
  }
  if (thumb == null || thumb.isEmpty) {
    thumb = DramaListService.instance
        .getDisplayImageUrlByTitle(review.dramaTitle, locale)
        ?.trim();
  }
  if (thumb != null && thumb.isEmpty) thumb = null;

  final myUid = AuthService.instance.currentUser.value?.uid;
  final resolvedUid = authorUid ?? myUid;
  // Only fall back to the current user's photo when the post author IS the
  // current user. For other users, prefer null (default avatar) over showing
  // the wrong profile picture before _feedPost loads.
  final isMyPost = resolvedUid != null && resolvedUid == myUid;
  final resolvedPhotoUrl = authorPhotoUrl ??
      (isMyPost
          ? UserProfileService.instance.profileImageUrlNotifier.value
          : null);
  final id =
      'local_profile_review_${review.writtenAt.millisecondsSinceEpoch}_${did.isNotEmpty ? did : displayTitle.hashCode}';

  return Post(
    id: id,
    title: displayTitle,
    subreddit: '',
    author: author,
    timeAgo: '',
    votes: 0,
    comments: 0,
    body: review.comment,
    type: 'review',
    dramaId: did.isNotEmpty ? did : null,
    dramaTitle: displayTitle,
    dramaThumbnail: thumb,
    rating: review.rating,
    authorPhotoUrl: resolvedPhotoUrl,
    authorAvatarColorIndex:
        UserProfileService.instance.avatarColorNotifier.value,
    country: country,
    authorUid: resolvedUid,
    createdAt: review.modifiedAt ?? review.writtenAt,
    commentsList: const [],
  );
}

String _fastSyntheticPostAuthor() {
  final nickname = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (nickname != null && nickname.isNotEmpty) return nickname;
  final displayName = AuthService.instance.currentUser.value?.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  return 'DramaFeed';
}

/// 게시판과 동일: `country`가 있으면 현재 앱 언어와 일치할 때만 표시.
/// `appLocale`이 없으면 [Post.documentVisibleInCountryFeed] 레거시 규칙(모든 언어 표시).
bool _profileRecentActivityMyReviewVisible(MyReviewItem r) {
  final m = <String, dynamic>{};
  if (r.appLocale != null && r.appLocale!.trim().isNotEmpty) {
    m['country'] = r.appLocale!.trim();
  }
  return Post.documentVisibleInCountryFeed(
    m,
    LocaleService.instance.locale,
  );
}

bool _profileRecentActivityWatchVisible(WatchedDramaItem e) {
  final m = <String, dynamic>{};
  if (e.appLocale != null && e.appLocale!.trim().isNotEmpty) {
    m['country'] = e.appLocale!.trim();
  }
  return Post.documentVisibleInCountryFeed(
    m,
    LocaleService.instance.locale,
  );
}

/// 별점을 준 리뷰만, 최신 작성 순 (최대 4개 표시용).
List<MyReviewItem> _ratedReviewsForProfileRecentActivity() {
  return _ratedReviewsForProfileRecentActivityFromList(
    ReviewService.instance.list,
  );
}

List<MyReviewItem> _ratedReviewsForProfileRecentActivityFromList(
  List<MyReviewItem> raw,
) {
  final out = raw
      .where(_profileRecentActivityMyReviewVisible)
      .where((r) => r.rating > 0 && r.dramaId.trim().isNotEmpty)
      .toList();
  out.sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
  return out;
}

/// Recent Activity(내 프로필): 별점 리뷰 + watch-only(eye만 저장) 합산.
/// 별점/리뷰가 이미 있는 드라마의 워치기록은 중복 제외.
List<MyReviewItem> _recentActivitiesForMyProfile() {
  final rated = _ratedReviewsForProfileRecentActivity();
  // 별점/리뷰가 있는 dramaId 셋 — 워치기록 중복 방지
  final ratedDramaIds = rated.map((r) => r.dramaId.trim()).toSet();
  final watchOnly = WatchHistoryService.instance.list
      .where(_profileRecentActivityWatchVisible)
      .where(
        (e) =>
            (e.rating == null || e.rating! <= 0) &&
            (e.comment?.trim().isEmpty ?? true) &&
            e.dramaKey.trim().isNotEmpty &&
            !ratedDramaIds.contains(e.dramaKey.trim()),
      )
      .map(
        (e) => MyReviewItem(
          id: 'watch_${e.id}',
          dramaId: e.dramaKey,
          dramaTitle: e.title,
          rating: 0,
          comment: '',
          writtenAt: e.watchedAt,
          appLocale: e.appLocale,
        ),
      )
      .toList();
  final merged = <MyReviewItem>[...rated, ...watchOnly];
  merged.sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
  return merged;
}

Widget _profileRecentActivityRow(ColorScheme cs, List<MyReviewItem> list) {
  const kSlots = 4;
  if (list.isEmpty) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(kSlots, (i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _RecentActivityEmptySlot(
              cs: cs,
              showBottomPlaceholder: false,
            ),
          ),
        );
      }),
    );
  }
  final shown = list.take(kSlots).toList();
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: List.generate(kSlots, (i) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: i < shown.length
              ? _RecentActivitySlot(
                  key: ValueKey(
                    '${shown[i].id}_${LocaleService.instance.locale}',
                  ),
                  review: shown[i],
                )
              : _RecentActivityEmptySlot(cs: cs, showBottomPlaceholder: true),
        ),
      );
    }),
  );
}

/// [ProfileFavorite.dramaThumbnail]은 저장 시점 URL이라 언어와 어긋날 수 있음 → 현재 표시 국가 기준 카탈로그 URL 우선.
String? _profileResolvedFavoriteThumbnail(
  BuildContext context,
  ProfileFavorite fav,
) {
  final country =
      CountryScope.maybeOf(context)?.country ??
      CountryService.instance.countryNotifier.value;
  final id = fav.dramaId.trim();
  if (id.isNotEmpty && !id.startsWith('short-')) {
    final u = DramaListService.instance.getDisplayImageUrl(id, country);
    if (u != null && u.isNotEmpty) return u;
  }
  final byTitle = DramaListService.instance.getDisplayImageUrlByTitle(
    fav.dramaTitle,
    country,
  );
  if (byTitle != null && byTitle.isNotEmpty) return byTitle;
  final stored = fav.dramaThumbnail?.trim();
  if (stored != null && stored.isNotEmpty) return stored;
  return null;
}

/// Recent Activity — [FAVORITES]와 동일: 카드 없음, 동일 패딩·타이포·슬롯 간격.
class _ProfileRecentActivitySection extends StatelessWidget {
  const _ProfileRecentActivitySection({this.reviewsOverride});

  /// 타 유저 프로필: 서버에서 가져온 리뷰 목록.
  final List<MyReviewItem>? reviewsOverride;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kProfileSectionBleedPadH,
        _kProfileSectionBleedPadV,
        _kProfileSectionBleedPadH,
        _kProfileSectionBleedPadV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.get('recentActivity'), style: _profileCapsLabel(cs)),
          const SizedBox(height: 6),
          _RecentRatedActivityScope(
            child: reviewsOverride != null
                ? ListenableBuilder(
                    listenable: Listenable.merge([
                      LocaleService.instance.localeNotifier,
                      DramaListService.instance.listNotifier,
                      DramaListService.instance.extraNotifier,
                    ]),
                    builder: (context, _) {
                      final list =
                          _ratedReviewsForProfileRecentActivityFromList(
                            reviewsOverride!,
                          );
                      return _profileRecentActivityRow(cs, list);
                    },
                  )
                : AnimatedBuilder(
                    animation: Listenable.merge([
                      LocaleService.instance.localeNotifier,
                      ReviewService.instance.listNotifier,
                      WatchHistoryService.instance.listNotifier,
                      DramaListService.instance.listNotifier,
                      DramaListService.instance.extraNotifier,
                    ]),
                    builder: (context, _) {
                      final list = _recentActivitiesForMyProfile();
                      return _profileRecentActivityRow(cs, list);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityEmptySlot extends StatelessWidget {
  const _RecentActivityEmptySlot({
    required this.cs,
    this.showBottomPlaceholder = true,
  });

  final ColorScheme cs;

  /// `true`: 포스터 아래 `—`로 별점 줄과 높이 맞춤. `false`: FAVORITES 빈 칸처럼 포스터만(점선+플러스).
  final bool showBottomPlaceholder;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dashColor = _profileEmptySlotDashColor(cs, brightness);
    final stroke = _profileEmptySlotDashStrokeWidth(brightness);
    return Column(
      children: [
        AspectRatio(
          aspectRatio: _kProfileRecentActivityPosterAspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              painter: _DashedRRectPainter(
                color: dashColor,
                strokeWidth: stroke,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (showBottomPlaceholder) ...[
          const SizedBox(height: 3),
          Text(
            '—',
            textAlign: TextAlign.center,
            style: _profileText(
              cs,
              size: _kProfileRatingsAndMenuFontSize,
              color: cs.onSurfaceVariant.withValues(
                alpha: brightness == Brightness.light ? 0.52 : 0.45,
              ),
              letterSpacing: 0.12,
            ),
          ),
        ],
      ],
    );
  }
}

class _RecentActivitySlot extends StatelessWidget {
  const _RecentActivitySlot({super.key, required this.review});

  final MyReviewItem review;

  bool get _isWatchOnlyActivity =>
      review.rating <= 0 && review.comment.trim().isEmpty;

  static const List<List<Color>> _gradients = [
    [Color(0xFF2D5A3D), Color(0xFF1E3D2C)],
    [Color(0xFF4A3F6B), Color(0xFF2E2744)],
    [Color(0xFF5C4033), Color(0xFF3D2A20)],
    [Color(0xFF2C4A6B), Color(0xFF1E3548)],
  ];

  String? _resolveImageUrl(BuildContext context) {
    final country = LocaleService.instance.locale;
    final id = review.dramaId.trim();
    if (id.isNotEmpty && !id.startsWith('short-')) {
      final byId = DramaListService.instance.getDisplayImageUrl(id, country);
      if (byId != null && byId.isNotEmpty) return byId;
    }
    final byTitle = DramaListService.instance.getDisplayImageUrlByTitle(
      review.dramaTitle,
      country,
    );
    if (byTitle != null && byTitle.isNotEmpty) return byTitle;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final country = LocaleService.instance.locale;
    final rating = review.rating;
    final colors =
        _gradients[review.dramaTitle.hashCode.abs() % _gradients.length];
    final imageUrl = _resolveImageUrl(context);
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    Widget posterChild;
    if (hasImage && url.startsWith('http')) {
      posterChild = OptimizedNetworkImage(
        key: ValueKey('$country|$url'),
        imageUrl: url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(8),
        memCacheWidth: null,
        memCacheHeight: null,
        errorWidget: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      );
    } else if (hasImage && url.startsWith('assets/')) {
      posterChild = Image.asset(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      );
    } else {
      posterChild = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );
    }

    return Column(
      children: [
        // [_kProfileRecentActivityPosterAspect] 슬롯 + cover
        AspectRatio(
          aspectRatio: _kProfileRecentActivityPosterAspect,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final uid = AuthService.instance.currentUser.value?.uid;
                final dramaId = review.dramaId.trim();
                final locale = CountryScope.maybeOf(context)?.country;
                if (_isWatchOnlyActivity) {
                  Navigator.push<void>(
                    context,
                    CupertinoPageRoute<void>(
                      builder: (_) => RecentActivityWatchOnlyPage(
                        authorUid: uid ?? '',
                        review: review,
                        country: country,
                        locale: locale,
                      ),
                    ),
                  );
                  return;
                }
                if (uid != null) {
                  Navigator.push<void>(
                    context,
                    CupertinoPageRoute<void>(
                      builder: (_) => RecentActivityReviewGate(
                        authorUid: uid,
                        dramaId: dramaId,
                        locale: locale,
                        review: review,
                        country: country,
                      ),
                    ),
                  );
                  return;
                }
                final dramaItem = _dramaItemFromReview(review, country);
                await DramaDetailPage.openFromItem(
                  context,
                  dramaItem,
                  country: country,
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: posterChild,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        if (rating > 0)
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StarRow(
                  rating: rating,
                  size: _kProfileRatingsAxisStarSize,
                  fillColor: cs.onSurfaceVariant.withValues(alpha: 0.52),
                  halfAsTextLabel: true,
                ),
                if (review.comment.trim().isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Transform.scale(
                    scale: 0.82,
                    child: ReviewBodyLinesIndicator(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.44),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          const SizedBox(height: 0),
      ],
    );
  }
}

/// 현재 앱 표시 구역(us/kr/jp/cn)에 맞는 DramaFeed 글만 Watch 화면에 붙임.
bool _feedPostMatchesCurrentViewerLocale(Post? p) {
  if (p == null) return false;
  return Post.documentVisibleInCountryFeed(
    {'country': p.country},
    LocaleService.instance.locale,
  );
}

/// Recent Activity에 넣을 때와 동일: `appLocale` 없으면 레거시로 모든 언어에서 표시.
bool _myReviewLogMatchesCurrentViewerLocale(MyReviewItem r) {
  final al = r.appLocale?.trim();
  if (al == null || al.isEmpty) return true;
  return Post.documentVisibleInCountryFeed(
    {'country': al},
    LocaleService.instance.locale,
  );
}

class RecentActivityWatchOnlyPage extends StatefulWidget {
  const RecentActivityWatchOnlyPage({
    required this.authorUid,
    required this.review,
    required this.country,
    required this.locale,
    /// null이면 로그인 유저 닉네임. 타인 워치로그 보기 시 해당 유저 이름 전달.
    this.authorNameOverride,
    this.authorPhotoUrl,
  });

  final String authorUid;
  final MyReviewItem review;
  final String? country;
  final String? locale;
  final String? authorNameOverride;
  /// 타인 피드 진입 시 해당 유저의 프로필 사진 URL. null이면 현재 로그인 유저 사진.
  final String? authorPhotoUrl;

  @override
  State<RecentActivityWatchOnlyPage> createState() =>
      _RecentActivityWatchOnlyPageState();
}

class _RecentActivityWatchOnlyPageState
    extends State<RecentActivityWatchOnlyPage> {
  late final Post? _syntheticPost;
  Post? _feedPost;
  late final Future<DramaDetail> _dramaDetailBundleFuture;

  @override
  void initState() {
    super.initState();
    final dramaItem = _dramaItemFromReview(widget.review, widget.country);
    _dramaDetailBundleFuture = DramaListService.instance
        .buildDetailWithReviewBundle(dramaItem, widget.country);
    final raw =
        (widget.country ??
                UserProfileService.instance.signupCountryNotifier.value ??
                'us')
            .trim()
            .toLowerCase();
    final c = raw.isNotEmpty ? raw : 'us';
    // Prefer authorNameOverride (set by Drama Watchers screen), then
    // review.authorName, then fall back to the current user's nickname.
    final overrideName = widget.authorNameOverride?.trim() ?? '';
    final reviewAuthorName = widget.review.authorName?.trim() ?? '';
    final watchSyntheticAuthor = overrideName.isNotEmpty
        ? overrideName
        : (reviewAuthorName.isNotEmpty
              ? (reviewAuthorName.startsWith('u/')
                    ? reviewAuthorName
                    : 'u/$reviewAuthorName')
              : _fastSyntheticPostAuthor());
    _syntheticPost = _syntheticLetterboxdPostFromMyReview(
      review: widget.review,
      author: watchSyntheticAuthor,
      country: c,
      authorPhotoUrl: widget.authorPhotoUrl,
      authorUid: widget.authorUid.isNotEmpty ? widget.authorUid : null,
    );
    _loadFeedPost();
  }

  Future<void> _loadFeedPost() async {
    Post? feed;
    try {
      final feedPostId = widget.review.feedPostId?.trim();
      if (feedPostId != null && feedPostId.isNotEmpty) {
        feed = await PostService.instance.getPost(feedPostId, widget.locale);
      }
      if (feed == null) {
        final rid = widget.review.id.trim();
        if (rid.isNotEmpty &&
            !rid.startsWith('watch_') &&
            !rid.startsWith('local_')) {
          feed = await PostService.instance.getPost(rid, widget.locale);
        }
      }
      // Watch-only Recent Activity entries (watch_ prefix) may have no feedPostId
      // stored. Try to find the latest posts document for this author + drama.
      // Recent Activity deduplicates so there's no rated counterpart here.
      if (feed == null &&
          widget.authorUid.isNotEmpty &&
          widget.review.dramaId.trim().isNotEmpty) {
        feed = await PostService.instance.getLatestMyFeedReviewPostForDrama(
          authorUid: widget.authorUid,
          dramaId: widget.review.dramaId,
          locale: widget.locale,
        );
      }
      // If still no posts document (saved before feed-post creation was added
      // for watch-only entries) and this is the current user's own watch log,
      // lazily create a posts document so the page becomes interactive.
      if (feed == null) {
        final myUid = AuthService.instance.currentUser.value?.uid;
        if (myUid != null &&
            myUid.isNotEmpty &&
            myUid == widget.authorUid &&
            widget.review.dramaId.trim().isNotEmpty) {
          try {
            final sync =
                await PostService.instance.addDramaWatchActivityFeedPost(
              dramaId: widget.review.dramaId,
              dramaTitle: widget.review.dramaTitle,
              rating: widget.review.rating,
              comment: '',
              reviewsTabLabel: 'Reviews',
              timeSoonLabel: 'just now',
            );
            if (sync.postId != null && sync.postId!.isNotEmpty) {
              feed = await PostService.instance
                  .getPost(sync.postId!, widget.locale);
            }
          } catch (_) {}
        }
      }
    } catch (_) {
      feed = null;
    }
    if (!mounted) return;
    if (feed != null && !_feedPostMatchesCurrentViewerLocale(feed)) {
      feed = null;
    }
    if (feed == null) return;
    setState(() {
      _feedPost = feed;
    });
  }

  @override
  Widget build(BuildContext context) {
    // If the real community post loaded, show it with the like row visible.
    // Use forceWatchPageTitle to keep "Watch" in the header without hiding the
    // like row (hideLetterboxdRatingAndLike would suppress both).
    if (_feedPost != null) {
      return PostDetailPage(
        post: _feedPost!,
        hideBottomDramaFeed: true,
        forceWatchPageTitle: true,
      );
    }
    if (_syntheticPost != null &&
        _myReviewLogMatchesCurrentViewerLocale(widget.review)) {
      return PostDetailPage(
        post: _syntheticPost!,
        hideBottomDramaFeed: true,
        offlineSyntheticReview: true,
        forceWatchPageTitle: true,
      );
    }
    return FutureBuilder<DramaDetail>(
      future: _dramaDetailBundleFuture,
      builder: (context, snap) {
        if (snap.hasData) {
          return DramaDetailPage(detail: snap.data!);
        }
        final theme = Theme.of(context);
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }
}

/// 타유저 프로필 — FOLLOW / FOLLOWING 버튼 (Optimistic UI + 빠른 배치 쓰기).
class _OtherProfileFollowButton extends StatefulWidget {
  const _OtherProfileFollowButton({
    required this.targetUid,
    required this.targetNickname,
    required this.cs,
    this.targetPhotoUrl,
  });
  final String targetUid;
  final String targetNickname;
  final String? targetPhotoUrl;
  final ColorScheme cs;

  @override
  State<_OtherProfileFollowButton> createState() =>
      _OtherProfileFollowButtonState();
}

class _OtherProfileFollowButtonState
    extends State<_OtherProfileFollowButton> {
  /// null = 스트림 값 사용. true/false = 낙관적(optimistic) 즉시 반영.
  bool? _optimisticFollowing;

  String? get _viewerUid =>
      AuthService.instance.currentUser.value?.uid;

  void _follow() {
    // 즉시 UI 전환
    setState(() => _optimisticFollowing = true);
    unawaited(
      FollowService.instance.followUserFast(
        targetUid: widget.targetUid,
        targetNickname: widget.targetNickname,
        targetPhotoUrl: widget.targetPhotoUrl,
        myNickname:
            UserProfileService.instance.nicknameNotifier.value?.trim() ??
            'Member',
        myPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
      ).catchError((Object e, StackTrace st) {
        debugPrint('followUserFast failed: $e\n$st');
        // 실패 시 낙관적 상태 복구
        if (mounted) setState(() => _optimisticFollowing = null);
      }),
    );
  }

  Future<void> _showUnfollowSheet() async {
    final nick = widget.targetNickname;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(ctx);
                      // 즉시 UI 전환
                      setState(() => _optimisticFollowing = false);
                      unawaited(
                        FollowService.instance
                            .unfollowUserFast(widget.targetUid)
                            .catchError((Object e, StackTrace st) {
                          debugPrint('unfollowUserFast failed: $e\n$st');
                          // 실패 시 낙관적 상태 복구
                          if (mounted) setState(() => _optimisticFollowing = null);
                        }),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Unfollow $nick',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewerUid;
    if (viewer == null || viewer.isEmpty || viewer == widget.targetUid) {
      return const SizedBox.shrink();
    }
    final cs = widget.cs;
    return StreamBuilder<bool>(
      stream: FollowService.instance.isFollowingStream(
        viewer,
        widget.targetUid,
      ),
      builder: (context, snap) {
        // 스트림에서 실제 값이 오면 낙관적 상태 해제
        if (snap.hasData && _optimisticFollowing != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _optimisticFollowing = null);
          });
        }
        final following = _optimisticFollowing ?? (snap.data ?? false);
        const radius = BorderRadius.all(Radius.circular(4));
        const pad = EdgeInsets.symmetric(horizontal: 7, vertical: 3);
        if (following) {
          const green = Color(0xFF00B020);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showUnfollowSheet,
              borderRadius: radius,
              splashColor: green.withValues(alpha: 0.14),
              highlightColor: green.withValues(alpha: 0.08),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: green.withValues(alpha: 0.72),
                    width: 1,
                  ),
                ),
                padding: pad,
                child: Text(
                  'FOLLOWING',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: green.withValues(alpha: 0.9),
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ),
          );
        }
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _follow,
            borderRadius: radius,
            splashColor: cs.primary.withValues(alpha: 0.12),
            highlightColor: cs.onSurface.withValues(alpha: 0.06),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: cs.onSurface.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              padding: pad,
              child: Text(
                'FOLLOW',
                style: GoogleFonts.notoSansKr(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: cs.onSurface.withValues(alpha: 0.48),
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RecentRatedActivityScope extends StatefulWidget {
  const _RecentRatedActivityScope({required this.child});
  final Widget child;

  @override
  State<_RecentRatedActivityScope> createState() =>
      _RecentRatedActivityScopeState();
}

class _RecentRatedActivityScopeState extends State<_RecentRatedActivityScope> {
  @override
  void initState() {
    super.initState();
    ReviewService.instance.loadIfNeeded();
    WatchHistoryService.instance.loadIfNeeded();
    DramaListService.instance.loadFromAsset();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void _showProfilePhotoOptions(BuildContext context, dynamic s, ColorScheme cs) {
  final hasPhoto =
      UserProfileService.instance.profileImageUrlNotifier.value != null &&
      UserProfileService.instance.profileImageUrlNotifier.value!.isNotEmpty;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                s.get('changeProfilePhoto'),
                style: _profileText(
                  cs,
                  size: 16,
                  weight: FontWeight.w600,
                  color: cs.onSurface,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            ListTile(
              leading: Icon(LucideIcons.image, color: cs.primary),
              title: Text(
                s.get('pickFromGallery'),
                style: _profileText(cs, size: 15, letterSpacing: 0.2),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadProfileImage(context, s, cs);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(LucideIcons.trash_2, color: kAppDeleteActionColor),
                title: Text(
                  s.get('removePhoto'),
                  style: _profileText(cs, size: 15, letterSpacing: 0.2).copyWith(
                    color: kAppDeleteActionColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeProfileImage(context, s, cs);
                },
              ),
            ListTile(
              leading: Icon(LucideIcons.x, color: cs.onSurfaceVariant),
              title: Text(
                s.get('cancel'),
                style: _profileText(cs, size: 15, letterSpacing: 0.2),
              ),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pickAndUploadProfileImage(
  BuildContext context,
  dynamic s,
  ColorScheme cs,
) async {
  final picker = ImagePicker();
  final xFile = await picker.pickImage(source: ImageSource.gallery);
  if (xFile == null || !context.mounted) return;
  final originalPath = xFile.path;

  while (context.mounted) {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: originalPath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: s.get('edit'),
          toolbarColor: Theme.of(context).colorScheme.surface,
          toolbarWidgetColor: Theme.of(context).colorScheme.onSurface,
        ),
        IOSUiSettings(title: s.get('edit')),
      ],
    );
    if (croppedFile == null || !context.mounted) return;

    final needEdit = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (ctx) => ProfilePhotoPreviewPage(
          croppedImagePath: croppedFile.path,
          originalImagePath: originalPath,
          onSave: (bytes) async {
            // ProfilePhotoPreviewPage 안에서 로딩 표시 후 업로드
            // 이 콜백이 끝나면 ProfilePhotoPreviewPage가 자동으로 pop됨
            final err = await UserProfileService.instance.uploadProfileImage(
              bytes,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  err ?? s.get('profilePhotoUpdated'),
                  style: _profileText(cs, size: 14, letterSpacing: 0.18),
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: err != null ? cs.error : null,
              ),
            );
          },
          onEdit: () => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    if (needEdit != true || !context.mounted) return;
  }
}

Future<void> _removeProfileImage(
  BuildContext context,
  dynamic s,
  ColorScheme cs,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final err = await UserProfileService.instance.removeProfileImage();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        err ?? s.get('profilePhotoUpdated'),
        style: _profileText(cs, size: 14, letterSpacing: 0.18),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: err != null ? cs.error : null,
    ),
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.trailingCount,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme color;

  /// null이면 숫자 없이 chevron만 (Share / Theme / Language 등).
  final int? trailingCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(
              icon,
              size: _kProfileMenuLeadingIconSize,
              color: color.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: _profileMenuRowLabel(color))),
            if (trailingCount != null) ...[
              Text('$trailingCount', style: _profileMenuRowLabel(color)),
              const SizedBox(width: 6),
            ],
            Icon(
              LucideIcons.chevron_right,
              size: _kProfileMenuTrailingIconSize,
              color: color.onSurfaceVariant.withValues(alpha: 0.65),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recent Activity 썸네일: Firestore 조회를 탭 이후로 미뤄 전환 애니메이션이 바로 시작되게 함.
class RecentActivityReviewGate extends StatefulWidget {
  const RecentActivityReviewGate({
    required this.authorUid,
    required this.dramaId,
    required this.locale,
    required this.review,
    required this.country,
    this.authorPhotoUrl,
  });

  final String authorUid;
  final String dramaId;
  final String? locale;
  final MyReviewItem review;
  final String? country;
  /// 타인 피드 진입 시 해당 유저의 프로필 사진 URL. null이면 현재 로그인 유저 사진.
  final String? authorPhotoUrl;

  @override
  State<RecentActivityReviewGate> createState() =>
      _RecentActivityReviewGateState();
}

class _RecentActivityReviewGateState extends State<RecentActivityReviewGate> {
  Post? _feedPost;
  late final Post? _offlineSyntheticPost;
  late final Future<DramaDetail> _dramaDetailBundleFuture;

  @override
  void initState() {
    super.initState();
    final dramaItem = _dramaItemFromReview(widget.review, widget.country);
    _dramaDetailBundleFuture = DramaListService.instance
        .buildDetailWithReviewBundle(dramaItem, widget.country);
    final raw =
        (widget.country ??
                UserProfileService.instance.signupCountryNotifier.value ??
                'us')
            .trim()
            .toLowerCase();
    final c = raw.isNotEmpty ? raw : 'us';
    // Use the review's actual author name so the synthetic placeholder shows
    // the correct nickname from the start (prevents "my nickname → user nickname"
    // flicker when viewing another user's review in the Watch page).
    final reviewAuthorRaw = widget.review.authorName?.trim() ?? '';
    final syntheticAuthor = reviewAuthorRaw.isNotEmpty
        ? (reviewAuthorRaw.startsWith('u/')
              ? reviewAuthorRaw
              : 'u/$reviewAuthorRaw')
        : _fastSyntheticPostAuthor();
    _offlineSyntheticPost = _syntheticLetterboxdPostFromMyReview(
      review: widget.review,
      author: syntheticAuthor,
      country: c,
      authorPhotoUrl: widget.authorPhotoUrl,
      authorUid: widget.authorUid.isNotEmpty ? widget.authorUid : null,
    );
    _loadFeedPost();
  }

  Future<void> _loadFeedPost() async {
    Post? feed;
    try {
      // Priority 1: feedPostId links directly to the exact community post for
      // this specific log entry (e.g. watch+rating vs watch+rating+review for
      // the same drama are distinct posts with distinct feedPostIds).
      final feedPostId = widget.review.feedPostId?.trim();
      if (feedPostId != null && feedPostId.isNotEmpty) {
        feed = await PostService.instance.getPost(feedPostId, widget.locale);
      }
      // Priority 2: some older reviews have feedPostId == review.id.
      if (feed == null) {
        final rid = widget.review.id.trim();
        if (rid.isNotEmpty &&
            !rid.startsWith('watch_') &&
            !rid.startsWith('local_')) {
          feed = await PostService.instance.getPost(rid, widget.locale);
        }
      }
      // NOTE: We intentionally do NOT fall back to
      // getLatestMyFeedReviewPostForDrama here, because when a user has
      // multiple reviews for the same drama the "latest" query returns the
      // wrong post and causes the wrong content to flash onto the screen.
    } catch (_) {
      feed = null;
    }
    if (!mounted) return;
    if (feed != null && !_feedPostMatchesCurrentViewerLocale(feed)) {
      feed = null;
    }
    if (feed == null) return;
    setState(() {
      _feedPost = feed;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_feedPost != null) {
      return PostDetailPage(
        post: _feedPost!,
        hideBottomDramaFeed: true,
      );
    }
    if (_offlineSyntheticPost != null &&
        _myReviewLogMatchesCurrentViewerLocale(widget.review)) {
      return PostDetailPage(
        post: _offlineSyntheticPost!,
        hideBottomDramaFeed: true,
        offlineSyntheticReview: true,
      );
    }
    return FutureBuilder<DramaDetail>(
      future: _dramaDetailBundleFuture,
      builder: (context, snap) {
        if (snap.hasData) {
          return DramaDetailPage(detail: snap.data!);
        }
        final theme = Theme.of(context);
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }
}
