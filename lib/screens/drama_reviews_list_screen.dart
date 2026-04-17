import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/drama_reviews_list_feed_row.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/write_review_sheet.dart';
import 'login_page.dart';

/// 드라마 상세 스탯 바「리뷰」— `drama_reviews` 전체(Watch `+` 피드 동기화 + 상세 Ratings & Reviews).
/// 단일 시간순 목록, 탭 없음.
class DramaReviewsListScreen extends StatefulWidget {
  const DramaReviewsListScreen({
    super.key,
    required this.dramaId,
    required this.dramaTitle,
    this.initialReviews = const [],
    this.initialPostMeta = const {},
  });

  final String dramaId;
  final String dramaTitle;
  final List<DramaReview> initialReviews;
  /// Pre-fetched feedPostId → (likeCount, commentCount) from the parent.
  /// Seeded into _postMeta so counts are visible on the first frame.
  final Map<String, ({int likeCount, int commentCount, bool isLiked})> initialPostMeta;

  @override
  State<DramaReviewsListScreen> createState() => _DramaReviewsListScreenState();
}

class _DramaReviewsListScreenState extends State<DramaReviewsListScreen> {
  List<DramaReview> _reviews = [];
  bool _loading = true;
  Map<String, ({int likeCount, int commentCount, bool isLiked})> _postMeta = {};

  List<DramaReview> _visibleReviews(List<DramaReview> input) {
    return input
        .where((r) => r.rating > 0 || r.comment.trim().isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _reviews = _visibleReviews(widget.initialReviews);
    // Seed with parent-supplied meta so counts render on the very first frame.
    if (widget.initialPostMeta.isNotEmpty) {
      _postMeta = Map.of(widget.initialPostMeta);
    }
    // Start meta fetch in parallel with _refresh() to catch any reviews
    // not covered by initialPostMeta (e.g. reviews added since last load).
    if (_reviews.isNotEmpty) _fetchPostMetaBatch(_reviews);
    _refresh();
  }

  Future<void> _refresh() async {
    if (_reviews.isEmpty) {
      if (mounted) setState(() => _loading = true);
    }
    try {
      final country = CountryScope.maybeOf(context)?.country ??
          UserProfileService.instance.signupCountryNotifier.value;
      final list = await ReviewService.instance.getDramaReviews(
        widget.dramaId,
        country: country,
      );
      if (!mounted) return;
      final visible = _visibleReviews(list);
      setState(() {
        _reviews = visible;
        _loading = false;
      });
      _fetchPostMetaBatch(visible);
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

  Future<void> _openWriteReview(BuildContext context) async {
    if (AuthService.instance.isLoggedIn.value) {
      await WriteReviewSheet.show(
        context,
        dramaId: widget.dramaId,
        dramaTitle: widget.dramaTitle,
      );
      if (mounted) await _refresh();
    } else {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
      );
      if (!mounted) return;
      if (ok == true && AuthService.instance.isLoggedIn.value) {
        await WriteReviewSheet.show(
          context,
          dramaId: widget.dramaId,
          dramaTitle: widget.dramaTitle,
        );
        if (mounted) await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
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
              onTap: () => _openWriteReview(context),
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
                child: _reviews.isEmpty
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
                        itemCount: _reviews.length,
                        separatorBuilder: (context, _) => Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.outline.withValues(alpha: 0.26),
                        ),
                        itemBuilder: (context, i) {
                          final r = _reviews[i];
                          final pid = (r.feedPostId?.trim().isNotEmpty == true)
                              ? r.feedPostId!.trim()
                              : (r.id?.trim() ?? '');
                          final meta = _postMeta[pid];
                          return DramaReviewsListFeedRow(
                            key: ValueKey<String>(r.id ?? 'idx-$i'),
                            review: r,
                            displayLikeCountOverride: meta?.likeCount,
                            displayCommentCountOverride: meta?.commentCount,
                            initialIsLiked: meta?.isLiked,
                          );
                        },
                      ),
              ),
      ),
    ),
    );
  }
}
