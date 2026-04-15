import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/drama_list_service.dart';
import '../services/review_service.dart' show MyReviewItem, ReviewService;
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import 'my_reviews_screen.dart';

/// 타 유저 UID 기준 공개 리뷰 목록 (프로필 통계 Reviews 탭).
class UserPublicReviewsScreen extends StatefulWidget {
  const UserPublicReviewsScreen({
    super.key,
    required this.uid,
    this.ownerDisplayName,
  });

  final String uid;
  final String? ownerDisplayName;

  @override
  State<UserPublicReviewsScreen> createState() => _UserPublicReviewsScreenState();
}

class _UserPublicReviewsScreenState extends State<UserPublicReviewsScreen> {
  late Future<List<MyReviewItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = ReviewService.instance.fetchReviewsForUserUid(widget.uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DramaListService.instance.loadFromAsset();
    });
  }

  String _headerTitle(dynamic s) {
    final name = widget.ownerDisplayName?.trim() ?? '';
    if (name.isNotEmpty) {
      return (s.get('userPublicReviewsTitleNamed') as String)
          .replaceAll('{name}', name);
    }
    return s.get('tabReviews') as String;
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headerBg = listsStyleSubpageHeaderBackground(theme);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: listsStyleSubpageSystemOverlay(theme, headerBg),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: _headerTitle(s),
            onBack: () => popListsStyleSubpage(context),
          ),
        ),
        body: FutureBuilder<List<MyReviewItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snap.error.toString(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(color: cs.error),
                  ),
                ),
              );
            }
            final raw = snap.data ?? [];
            if (raw.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.star,
                        size: 56,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        s.get('myReviewsEmptyTitle'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final list = List<MyReviewItem>.from(raw)
              ..sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
            return ListView.separated(
              padding: EdgeInsets.only(
                top: 4,
                bottom: listsStyleSubpageMainTabBottomInset(context),
              ),
              itemCount: list.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: cs.outline.withValues(alpha: 0.12),
              ),
              itemBuilder: (context, index) {
                return LetterboxdMyReviewTile(
                  item: list[index],
                  dramaTitleOnSurfaceAlpha: 0.8,
                  reviewBodyFontSize: 12.5,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
