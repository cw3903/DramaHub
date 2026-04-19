import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/episode_review_service.dart';
import '../theme/app_theme.dart';
import 'lists_style_subpage_app_bar.dart' show kListsStyleSubpageLeadingEdgeInset;
import 'review_feed_inline_composer.dart';
import 'user_profile_nav.dart';

/// 에피소드 리뷰 한 건에 대한 댓글·대댓글 (`episode_reviews/{id}/thread`).
class EpisodeReviewThreadSheet {
  static Future<void> show({
    required BuildContext context,
    required String reviewId,
    required String dramaId,
    required int episodeNumber,
    required dynamic strings,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EpisodeReviewThreadSheetBody(
        reviewId: reviewId,
        dramaId: dramaId,
        episodeNumber: episodeNumber,
        strings: strings,
      ),
    );
  }
}

class _EpisodeReviewThreadSheetBody extends StatefulWidget {
  const _EpisodeReviewThreadSheetBody({
    required this.reviewId,
    required this.dramaId,
    required this.episodeNumber,
    required this.strings,
  });

  final String reviewId;
  final String dramaId;
  final int episodeNumber;
  final dynamic strings;

  @override
  State<_EpisodeReviewThreadSheetBody> createState() => _EpisodeReviewThreadSheetBodyState();
}

class _EpisodeReviewThreadSheetBodyState extends State<_EpisodeReviewThreadSheetBody> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  EpisodeReviewThreadItem? _replyingTo;
  bool _sending = false;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final (err, _) = await EpisodeReviewService.instance.addThreadComment(
      reviewId: widget.reviewId,
      dramaId: widget.dramaId,
      episodeNumber: widget.episodeNumber,
      text: text,
      parentCommentId: _replyingTo?.id,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.strings.get(err), style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _textController.clear();
    setState(() => _replyingTo = null);
    _focusNode.unfocus();
  }

  int _depth(EpisodeReviewThreadItem t, Map<String, EpisodeReviewThreadItem> byId) {
    var d = 0;
    String? p = t.parentCommentId;
    final guard = <String>{};
    while (p != null && byId.containsKey(p)) {
      if (!guard.add(p)) break;
      d++;
      p = byId[p]!.parentCommentId;
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final h = (MediaQuery.sizeOf(context).height * 0.72).clamp(320.0, 620.0);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kListsStyleSubpageLeadingEdgeInset,
                10,
                kListsStyleSubpageLeadingEdgeInset,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.strings.get('comments'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.22)),
            Expanded(
              child: StreamBuilder<List<EpisodeReviewThreadItem>>(
                stream: EpisodeReviewService.instance.watchThread(widget.reviewId),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        widget.strings.get('episodeReviewSaveFailed'),
                        style: GoogleFonts.notoSansKr(color: cs.error),
                      ),
                    );
                  }
                  final items = snap.data ?? [];
                  if (items.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final byId = {for (final t in items) t.id: t};
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      kListsStyleSubpageLeadingEdgeInset,
                      8,
                      kListsStyleSubpageLeadingEdgeInset,
                      12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final t = items[i];
                      final depth = _depth(t, byId).clamp(0, 8);
                      final padLeft = 10.0 + depth * 14.0;
                      return Padding(
                        padding: EdgeInsets.only(bottom: 12, left: padLeft),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      final uid = t.uid.trim();
                                      if (uid.isNotEmpty) {
                                        openUserProfileFromAuthorUid(context, uid);
                                      }
                                    },
                                    child: Text(
                                      t.authorName,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  t.timeAgo,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t.comment,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                height: 1.35,
                                color: cs.onSurface,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () {
                                  setState(() => _replyingTo = t);
                                  _focusNode.requestFocus();
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  widget.strings.get('reply'),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.linkBlue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_replyingTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kListsStyleSubpageLeadingEdgeInset,
                  0,
                  kListsStyleSubpageLeadingEdgeInset,
                  4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.strings.get('reply')}: ${_replyingTo!.authorName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _replyingTo = null),
                      child: Text(widget.strings.get('cancel')),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kListsStyleSubpageLeadingEdgeInset - 10,
                4,
                kListsStyleSubpageLeadingEdgeInset - 10,
                12,
              ),
              child: ReviewFeedInlineComposer(
                controller: _textController,
                focusNode: _focusNode,
                isSubmitting: _sending,
                autofocus: false,
                onSend: _send,
                sendSemanticLabel: widget.strings.get('replySubmit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
