import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/watch_history_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/green_rating_stars.dart';
import '../widgets/optimized_network_image.dart';

/// Letterboxd 스타일 — 이 드라마에 별점/리뷰를 남긴 사용자 목록(시청 활동).
/// 상단 탭(Everyone / …)은 구현하지 않음.
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

const Color _kStarGreen = Color(0xFF00C46C);

class _WatcherRowVm {
  const _WatcherRowVm({
    required this.userName,
    required this.rating,
    this.photoUrl,
    this.hasReview = false,
  });

  final String userName;
  final double rating;
  final String? photoUrl;
  final bool hasReview;
}

class _DramaWatchersScreenState extends State<DramaWatchersScreen> {
  List<DramaReview> _reviews = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reviews = List<DramaReview>.from(widget.initialReviews);
    WatchHistoryService.instance.loadIfNeeded();
    _refresh();
  }

  Future<void> _toggleWatchHistory(BuildContext context) async {
    final s = CountryScope.of(context).strings;
    final dramaId = widget.dramaItem.id;
    final watched = WatchHistoryService.instance.isWatched(dramaId);
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final locTitle =
        DramaListService.instance.getDisplayTitle(dramaId, country);
    final title =
        locTitle.trim().isNotEmpty ? locTitle : widget.dramaItem.title;
    final imgUrl = DramaListService.instance.getDisplayImageUrl(
          dramaId,
          country,
        ) ??
        widget.dramaItem.imageUrl;
    if (watched) {
      await WatchHistoryService.instance.remove(dramaId);
    } else {
      await WatchHistoryService.instance.add(
        id: dramaId,
        title: title,
        subtitle: widget.dramaItem.subtitle,
        views: widget.dramaItem.views,
        imageUrl: imgUrl,
      );
    }
    if (!context.mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          watched
              ? s.get('watchHistoryToastRemoved')
              : s.get('watchHistoryToastAdded'),
          style: GoogleFonts.notoSansKr(),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _refresh() async {
    if (_reviews.isEmpty) {
      if (mounted) setState(() => _loading = true);
    }
    try {
      final list = await ReviewService.instance.getDramaReviews(widget.dramaId);
      if (!mounted) return;
      setState(() {
        _reviews = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_WatcherRowVm> _buildRows() {
    final seen = <String>{};
    final out = <_WatcherRowVm>[];
    for (final r in _reviews) {
      final name = r.userName.trim();
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      out.add(
        _WatcherRowVm(
          userName: name,
          rating: r.rating.clamp(0.0, 5.0),
          photoUrl: r.authorPhotoUrl,
          hasReview: r.comment.trim().isNotEmpty,
        ),
      );
    }
    out.sort((a, b) => b.rating.compareTo(a.rating));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    final rows = _buildRows();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
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
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: WatchHistoryService.instance.isWatched(widget.dramaId)
                ? s.get('dramaWatchHistoryTooltipRemove')
                : s.get('dramaWatchHistoryTooltipAdd'),
            icon: Icon(
              LucideIcons.eye,
              size: 22,
              color: WatchHistoryService.instance.isWatched(widget.dramaId)
                  ? _kStarGreen
                  : cs.onSurfaceVariant,
            ),
            onPressed: () => _toggleWatchHistory(context),
          ),
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
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: rows.length,
                separatorBuilder: (context, _) => Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outline.withValues(alpha: 0.12),
                ),
                itemBuilder: (context, index) {
                  return _WatcherListTile(row: rows[index], cs: cs);
                },
              ),
            ),
    );
  }
}

class _WatcherListTile extends StatelessWidget {
  const _WatcherListTile({required this.row, required this.cs});

  final _WatcherRowVm row;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final initial = row.userName.isNotEmpty
        ? row.userName.substring(0, 1).toUpperCase()
        : '?';

    return Material(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(url: row.photoUrl, label: initial, cs: cs),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                row.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            GreenRatingStars(rating: row.rating, size: 16, color: _kStarGreen),
            if (row.hasReview) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.list, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.65)),
            ],
          ],
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
