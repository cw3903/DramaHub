import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter/cupertino.dart';

import '../models/drama.dart';
import '../services/post_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';
import '../widgets/country_scope.dart';
import '../constants/app_profile_avatar_size.dart';
import '../widgets/drama_row_profile_avatar.dart';
import '../widgets/drama_watch_activity_sheet.dart';
import '../widgets/feed_review_star_row.dart'
    show FeedReviewRatingStars, kFeedReviewRatingThumbWidth;
import '../widgets/review_body_lines_indicator.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/user_profile_nav.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart'
    show RecentActivityWatchOnlyPage, RecentActivityReviewGate;

/// 드라마 상세 스탯 바「Watch」— 피드 기반 시청 활동(닉네임 · 선택 별점 · 선택 리뷰 아이콘).
class DramaWatchersScreen extends StatefulWidget {
  const DramaWatchersScreen({
    super.key,
    required this.dramaId,
    required this.dramaTitle,
    required this.dramaItem,
    this.initialReviews = const [],
  });

  final String dramaId;
  final String dramaTitle;
  final DramaItem dramaItem;
  final List<DramaReview> initialReviews;

  @override
  State<DramaWatchersScreen> createState() => _DramaWatchersScreenState();
}

class _WatcherRowVm {
  const _WatcherRowVm({
    required this.userName,
    required this.rating,
    required this.review,
    this.photoUrl,
    this.hasReview = false,
    this.authorUid,
  });

  final String userName;
  final double rating;
  /// 원본 DramaReview — 탭 시 리뷰/워치로그 상세 전환에 사용.
  final DramaReview review;
  final String? photoUrl;
  final bool hasReview;
  final String? authorUid;
}

class _DramaWatchersScreenState extends State<DramaWatchersScreen> {
  List<DramaReview> _reviews = [];
  bool _loading = true;
  /// feedPostId → (likeCount, commentCount) 배치 조회 결과
  Map<String, ({int likeCount, int commentCount, bool isLiked})> _postMeta = {};

  @override
  void initState() {
    super.initState();
    _reviews = List<DramaReview>.from(widget.initialReviews);
    WatchHistoryService.instance.loadIfNeeded();
    if (_reviews.isNotEmpty) _fetchPostMetaBatch(_reviews);
    _refresh();
  }

  Future<void> _openWatchActivitySheet() async {
    final ok = await DramaWatchActivitySheet.show(
      context,
      dramaId: widget.dramaId,
      dramaTitle: widget.dramaTitle,
      dramaItem: widget.dramaItem,
    );
    if (!mounted) return;
    if (ok == true) {
      final s = CountryScope.of(context).strings;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.get('dramaWatchActivityPosted'),
            style: GoogleFonts.notoSansKr(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_reviews.isEmpty) {
      if (mounted) setState(() => _loading = true);
    }
    try {
      final country =
          CountryScope.maybeOf(context)?.country ??
          UserProfileService.instance.signupCountryNotifier.value;
      final list = await ReviewService.instance.getDramaReviews(
        widget.dramaId,
        country: country,
      );
      if (!mounted) return;
      setState(() {
        _reviews = list;
        _loading = false;
      });
      // 리뷰 목록 표시 즉시 → 하트·댓글 수 배치 조회 (병목 없이 백그라운드)
      _fetchPostMetaBatch(list);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPostMetaBatch(List<DramaReview> reviews) async {
    final ids = reviews
        .map((r) {
          final fp = r.feedPostId?.trim();
          if (fp != null && fp.isNotEmpty) return fp;
          return r.id?.trim() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    try {
      final meta = await PostService.instance.batchGetPostMeta(ids);
      if (!mounted || meta.isEmpty) return;
      setState(() => _postMeta = meta);
    } catch (_) {}
  }

  List<_WatcherRowVm> _buildRows() {
    final out = <_WatcherRowVm>[];
    for (final r in _reviews) {
      final name = r.userName.trim();
      if (name.isEmpty) continue;
      final rt = r.rating.clamp(0.0, 5.0);
      final hasText = r.comment.trim().isNotEmpty;
      out.add(
        _WatcherRowVm(
          userName: name,
          rating: rt,
          review: r,
          photoUrl: r.authorPhotoUrl,
          hasReview: rt > 0 && hasText,
          authorUid: r.authorUid?.trim(),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final rows = _buildRows();
    final headerBarBg = listsStyleSubpageHeaderBackground(theme);
    final overlay = listsStyleSubpageSystemOverlay(theme, headerBarBg);

    return ListsStyleSwipeBack(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: widget.dramaTitle,
            onBack: () => popListsStyleSubpage(context),
            trailing: ListsStyleSubpageHeaderAddButton(
              onTap: _openWatchActivitySheet,
            ),
          ),
        ),
        body: _loading && _reviews.isEmpty
            ? Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(28),
                        children: [
                          Center(
                            child: Text(
                              s.get('dramaSpotlightNoReviews'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(
                          bottom: listsStyleSubpageMainTabBottomInset(context),
                        ),
                        itemCount: rows.length,
                        separatorBuilder: (context, _) => Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.outline.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, index) {
                          return _WatcherListTile(
                            row: rows[index],
                            cs: cs,
                            dramaId: widget.dramaId,
                            dramaTitle: widget.dramaTitle,
                          );
                        },
                      ),
              ),
      ),
    ),
    );
  }
}

class _WatcherListTile extends StatelessWidget {
  const _WatcherListTile({
    required this.row,
    required this.cs,
    required this.dramaId,
    required this.dramaTitle,
  });

  final _WatcherRowVm row;
  final ColorScheme cs;
  final String dramaId;
  final String dramaTitle;

  /// 오른쪽 고정 열 폭. 줄 아이콘은 5별 폭 기준 오프셋에 고정(별 개수와 무관).
  static const double _kRatingTrailWidth = 118;

  void _onRowTap(BuildContext context) {
    final uid = row.authorUid?.trim() ?? '';
    final r = row.review;
    final hasRating = r.rating > 0;
    final hasText = r.comment.trim().isNotEmpty;
    final locale = CountryScope.maybeOf(context)?.country;
    final country =
        locale ??
        UserProfileService.instance.signupCountryNotifier.value ??
        'us';

    // 별점 또는 리뷰 텍스트가 있으면 ActivityReviewDetail 페이지로 이동.
    if (hasRating || hasText) {
      final review = MyReviewItem(
        id: r.id ?? '',
        dramaId: dramaId,
        dramaTitle: dramaTitle,
        rating: r.rating,
        comment: r.comment,
        writtenAt: r.writtenAt ?? DateTime.now(),
        authorName: r.userName,
        feedPostId: r.feedPostId,
      );
      Navigator.push<void>(
        context,
        CupertinoPageRoute<void>(
          builder: (_) => RecentActivityReviewGate(
            authorUid: uid,
            dramaId: dramaId,
            locale: locale,
            review: review,
            country: country,
            authorPhotoUrl: row.photoUrl,
          ),
        ),
      );
      return;
    }

    // 워치로그만 있는 경우 — 다이어리 워치로그 탭 동작과 동일.
    if (uid.isNotEmpty) {
      final review = MyReviewItem(
        id: r.id ?? '',
        dramaId: dramaId,
        dramaTitle: dramaTitle,
        rating: 0,
        comment: '',
        writtenAt: r.writtenAt ?? DateTime.now(),
        authorName: r.userName,
        feedPostId: r.feedPostId,
      );
      Navigator.push<void>(
        context,
        CupertinoPageRoute<void>(
          builder: (_) => RecentActivityWatchOnlyPage(
            authorUid: uid,
            review: review,
            country: country,
            locale: locale,
            authorNameOverride: r.userName,
            authorPhotoUrl: row.photoUrl,
          ),
        ),
      );
      return;
    }

    // uid 없을 때 최후 fallback — 기존 프로필 이동.
    openUserProfileFromAuthorUid(context, uid);
  }

  /// [kFeedReviewRatingThumbWidth] 끝에서 줄 아이콘까지 간격.
  static const double _kLinesAfterFiveStars = 6;

  @override
  Widget build(BuildContext context) {
    final showStars = row.rating > 0;
    final showTrail = showStars || row.hasReview;
    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: () => _onRowTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      DramaRowProfileAvatar(
                        imageUrl: row.photoUrl,
                        authorUid: row.authorUid,
                        colorScheme: cs,
                        size: kAppUnifiedProfileAvatarSize,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appUnifiedNicknameStyle(cs),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showTrail) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: _kRatingTrailWidth,
                  height: 36,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      if (showStars)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FeedReviewRatingStars(
                            rating: row.rating,
                            layoutThumbWidth: kFeedReviewRatingThumbWidth,
                          ),
                        ),
                      if (row.hasReview)
                        Positioned(
                          left: kFeedReviewRatingThumbWidth + _kLinesAfterFiveStars,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: ReviewBodyLinesIndicator(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.44),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
