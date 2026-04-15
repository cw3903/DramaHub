import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/green_rating_stars.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/user_profile_nav.dart';
import '../widgets/write_review_sheet.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

/// 드라마 상세 스탯 바「리뷰」→ 전체 리뷰 목록 (Popular / 전체).
class DramaReviewsListScreen extends StatefulWidget {
  const DramaReviewsListScreen({
    super.key,
    required this.dramaId,
    required this.dramaTitle,
    this.initialReviews = const [],
  });

  final String dramaId;
  final String dramaTitle;
  final List<DramaReview> initialReviews;

  @override
  State<DramaReviewsListScreen> createState() => _DramaReviewsListScreenState();
}

const Color _kReviewStarGreen = Color(0xFFFFB020);
const Color _kUserNameTint = Color(0xFF9BB0CC);

class _DramaReviewsListScreenState extends State<DramaReviewsListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DramaReview> _reviews = [];
  List<DramaReview> _popularSorted = [];
  List<DramaReview> _allSorted = [];
  bool _loading = true;

  void _recomputeSortedLists() {
    _popularSorted = _sortedPopular(_reviews);
    _allSorted = _sortedAll(_reviews);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reviews = List<DramaReview>.from(widget.initialReviews);
    _recomputeSortedLists();
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      setState(() {
        _reviews = list;
        _recomputeSortedLists();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _likeScore(DramaReview r) => r.likeCount ?? 0;

  DateTime _writtenAt(DramaReview r) => r.writtenAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  List<DramaReview> _sortedPopular(List<DramaReview> list) {
    final copy = List<DramaReview>.from(list);
    copy.sort((a, b) {
      final lc = _likeScore(b).compareTo(_likeScore(a));
      if (lc != 0) return lc;
      return _writtenAt(b).compareTo(_writtenAt(a));
    });
    return copy;
  }

  List<DramaReview> _sortedAll(List<DramaReview> list) {
    final copy = List<DramaReview>.from(list);
    copy.sort((a, b) => _writtenAt(b).compareTo(_writtenAt(a)));
    return copy;
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
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.dramaTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.get('statsBarComingSoon'),
            icon: Icon(LucideIcons.list_filter, size: 22, color: cs.onSurfaceVariant),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.get('statsBarComingSoon'), style: GoogleFonts.notoSansKr()),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kReviewStarGreen,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: _kReviewStarGreen,
          indicatorWeight: 2.5,
          labelStyle: GoogleFonts.notoSansKr(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.notoSansKr(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(text: s.get('dramaReviewsTabPopular')),
            Tab(text: s.get('dramaReviewsTabAll')),
          ],
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
          : TabBarView(
              controller: _tabController,
              children: [
                _ReviewListBody(
                  reviews: _popularSorted,
                  onRefresh: _refresh,
                  emptyMessage: s.get('dramaSpotlightNoReviews'),
                ),
                _ReviewListBody(
                  reviews: _allSorted,
                  onRefresh: _refresh,
                  emptyMessage: s.get('dramaSpotlightNoReviews'),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openWriteReview(context),
        backgroundColor: _kReviewStarGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}

class _ReviewListBody extends StatelessWidget {
  const _ReviewListBody({
    required this.reviews,
    required this.onRefresh,
    required this.emptyMessage,
  });

  final List<DramaReview> reviews;
  final Future<void> Function() onRefresh;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (reviews.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            Center(
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: reviews.length,
        separatorBuilder: (context, _) => Divider(
          height: 1,
          thickness: 1,
          color: cs.outline.withValues(alpha: 0.12),
        ),
        itemBuilder: (context, i) => _ReviewListTile(review: reviews[i]),
      ),
    );
  }
}

class _ReviewListTile extends StatelessWidget {
  const _ReviewListTile({required this.review});

  final DramaReview review;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = review.userName.trim().isEmpty ? '—' : review.userName;
    final initial =
        name.isNotEmpty && name != '—' ? name.substring(0, 1).toUpperCase() : '?';
    final body = review.comment.trim();
    final liked = (review.likeCount ?? 0) > 0;

    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: () {
          final u = review.authorUid?.trim();
          if (u != null && u.isNotEmpty) {
            openUserProfileFromAuthorUid(context, u);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(url: review.authorPhotoUrl, label: initial, cs: cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kUserNameTint,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GreenRatingStars(rating: review.rating, size: 15, color: _kReviewStarGreen),
                      if (liked) ...[
                        const SizedBox(width: 6),
                        Icon(
                          LucideIcons.heart,
                          size: 16,
                          color: const Color(0xFFFF8A34),
                        ),
                      ],
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        height: 1.45,
                        color: cs.onSurface.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.label, required this.cs});

  final String? url;
  final String label;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();
    if (u != null && u.startsWith('http')) {
      return ClipOval(
        child: OptimizedNetworkImage.avatar(
          imageUrl: u,
          size: 40,
          errorWidget: _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return CircleAvatar(
      radius: 20,
      backgroundColor: cs.surfaceContainerHighest,
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
