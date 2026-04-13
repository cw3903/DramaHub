import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/drama.dart';
import '../services/drama_list_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/drama_grid_card.dart';
import 'drama_detail_page.dart';
import 'shorts_search_screen.dart';

/// 시놉시스 아래 장르·태그 탭 시 — 카탈로그에서 해당 태그가 부제에 포함된 작품만 표시.
class TagDramaListScreen extends StatefulWidget {
  const TagDramaListScreen({
    super.key,
    required this.tag,
  });

  final String tag;

  @override
  State<TagDramaListScreen> createState() => _TagDramaListScreenState();
}

class _TagDramaListScreenState extends State<TagDramaListScreen> {
  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
  }

  Widget _posterPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(LucideIcons.tv, size: 28, color: cs.onSurfaceVariant),
      ),
    );
  }

  void _openDrama(BuildContext context, DramaItem item, String? country) {
    final detail = DramaListService.instance.buildDetailForItem(item, country);
    Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(builder: (_) => DramaDetailPage(detail: detail)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final strings = CountryScope.of(context).strings;
    final r = dramaGridScreenScale(context);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(LucideIcons.arrow_left, color: cs.onSurface, size: 24),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(LucideIcons.search, color: cs.onSurface, size: 24),
                    onPressed: () {
                      Navigator.push<void>(
                        context,
                        CupertinoPageRoute<void>(builder: (_) => const ShortsSearchScreen()),
                      );
                    },
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: cs.outline.withValues(alpha: 0.2)),
            Padding(
              padding: EdgeInsets.fromLTRB(20 * r, 16 * r, 20 * r, 12 * r),
              child: Text(
                widget.tag,
                style: GoogleFonts.notoSansKr(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<DramaItem>>(
                valueListenable: DramaListService.instance.listNotifier,
                builder: (context, value, _) {
                  final dramas =
                      DramaListService.instance.getDramasMatchingGenreTag(widget.tag, country);
                  if (dramas.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          strings.get('tagDramaListEmpty'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            color: cs.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(8 * r, 0, 8 * r, 24 * r),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.53,
                      crossAxisSpacing: 8 * r,
                      mainAxisSpacing: 0,
                    ),
                    itemCount: dramas.length,
                    itemBuilder: (context, index) {
                      final item = dramas[index];
                      final displayTitle =
                          DramaListService.instance.getDisplayTitle(item.id, country);
                      final displaySubtitle =
                          DramaListService.instance.getDisplaySubtitle(item.id, country);
                      final imageUrl = DramaListService.instance.getDisplayImageUrl(
                            item.id,
                            country,
                          ) ??
                          item.imageUrl;
                      final rawRating =
                          ReviewService.instance.getByDramaId(item.id)?.rating ?? item.rating;
                      final rating = rawRating > 0 ? rawRating : 0.0;
                      return DramaGridCard(
                        displayTitle: displayTitle,
                        displaySubtitle: displaySubtitle,
                        imageUrl: imageUrl,
                        rating: rating,
                        onTap: () => _openDrama(context, item, country),
                        posterPlaceholder: _posterPlaceholder(context),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
