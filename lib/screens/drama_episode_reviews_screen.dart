import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/episode_rating_service.dart';
import '../services/episode_review_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/episode_review_panel.dart';

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
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.get('episodeLabel').replaceAll('%d', '${widget.episodeNumber}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: EpisodeReviewPanel(
            dramaId: widget.dramaId,
            episodeNumber: widget.episodeNumber,
            onClose: () => Navigator.pop(context),
            strings: s,
            showCloseButton: false,
          ),
        ),
      ),
    );
  }
}
