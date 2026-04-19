import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/episode_rating_service.dart';
import '../services/episode_review_service.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../widgets/episode_review_panel.dart'
    show EpisodeReviewListStyle, EpisodeReviewPanel, episodeNoRatingColor;
import '../widgets/lists_style_subpage_app_bar.dart'
    show
        ListsStyleSubpageHeaderBar,
        ListsStyleSubpageHorizontalSwipeBack,
        kListsStyleSubpageLeadingEdgeInset,
        listsStyleSubpageBarForeground,
        listsStyleSubpageHeaderBackground,
        listsStyleSubpageSystemOverlay,
        popListsStyleSubpage;

/// 전체 회차 목록(바텀시트)에서 회차 탭 시 — 해당 화 리뷰 전체 화면.
class DramaEpisodeReviewsScreen extends StatefulWidget {
  const DramaEpisodeReviewsScreen({
    super.key,
    required this.dramaId,
    required this.episodeNumber,
  });

  final String dramaId;
  final int episodeNumber;

  @override
  State<DramaEpisodeReviewsScreen> createState() => _DramaEpisodeReviewsScreenState();
}

class _EpisodeReviewsBarTitle extends StatelessWidget {
  const _EpisodeReviewsBarTitle({
    required this.dramaId,
    required this.episodeNumber,
    required this.strings,
  });

  final String dramaId;
  final int episodeNumber;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final barFg = listsStyleSubpageBarForeground(theme, cs);
    return ListenableBuilder(
      listenable: Listenable.merge([
        EpisodeRatingService.instance.getAverageNotifierForDrama(dramaId),
        EpisodeRatingService.instance.getCountNotifierForDrama(dramaId),
      ]),
      builder: (context, _) {
        final averageRatings =
            EpisodeRatingService.instance.getAverageNotifierForDrama(dramaId).value;
        final countMap =
            EpisodeRatingService.instance.getCountNotifierForDrama(dramaId).value;
        final count = countMap[episodeNumber] ?? 0;
        final avg = averageRatings[episodeNumber] ?? 0.0;
        final hasRating = avg > 0;
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.get('episodeLabel').replaceAll('%d', '$episodeNumber'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  color: barFg,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.star_rounded,
                size: 16,
                color: hasRating ? AppColors.ratingStar : episodeNoRatingColor(context),
              ),
              const SizedBox(width: 4),
              Text(
                hasRating ? avg.toStringAsFixed(1) : '0',
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                  color: hasRating
                      ? (theme.brightness == Brightness.dark ? Colors.white : cs.onSurface)
                      : episodeNoRatingColor(context),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                strings.get('episodeReviewRaterCount').replaceAll('%d', '$count'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  height: 1.05,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DramaEpisodeReviewsScreenState extends State<DramaEpisodeReviewsScreen> {
  @override
  void initState() {
    super.initState();
    EpisodeReviewService.instance.loadReviews(widget.dramaId, widget.episodeNumber);
    EpisodeRatingService.instance.getMyRatingsForDrama(widget.dramaId);
    EpisodeRatingService.instance.loadEpisodeAverageRatings(widget.dramaId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = CountryScope.of(context).strings;
    final headerBg = listsStyleSubpageHeaderBackground(theme);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: listsStyleSubpageSystemOverlay(theme, headerBg),
      child: ListsStyleSubpageHorizontalSwipeBack(
        onSwipePop: () => popListsStyleSubpage(context),
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListsStyleSubpageHeaderBar(
                title: s.get('episodeLabel').replaceAll('%d', '${widget.episodeNumber}'),
                centerTitle: _EpisodeReviewsBarTitle(
                  dramaId: widget.dramaId,
                  episodeNumber: widget.episodeNumber,
                  strings: s,
                ),
                onBack: () => popListsStyleSubpage(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kListsStyleSubpageLeadingEdgeInset,
                  ),
                  child: EpisodeReviewPanel(
                    dramaId: widget.dramaId,
                    episodeNumber: widget.episodeNumber,
                    onClose: () => popListsStyleSubpage(context),
                    strings: s,
                    showCloseButton: false,
                    listStyle: EpisodeReviewListStyle.divider,
                    hideSummaryHeader: true,
                    hideReviewCardTimestamp: true,
                    pinComposerToBottom: true,
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
