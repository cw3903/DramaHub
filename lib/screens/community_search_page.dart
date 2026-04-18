import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post.dart';
import '../services/drama_list_service.dart';
import '../services/locale_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../services/watchlist_service.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/lists_style_subpage_app_bar.dart';
import '../widgets/optimized_network_image.dart';
import '../theme/app_theme.dart';
import '../widgets/review_arrow_tag_chip.dart';
import 'drama_detail_page.dart';
import 'post_detail_page.dart';

/// 통합 검색 페이지 - 제목 / 내용 / 댓글 / 닉네임 검색
class CommunitySearchPage extends StatefulWidget {
  const CommunitySearchPage({
    super.key,
    this.initialQuery,
    this.reviewDramaId,
    this.reviewDramaPosterUrl,
  });

  /// 검색창에 미리 넣을 문자열(태그 탭 등).
  final String? initialQuery;

  /// 리뷰 글 태그 탭 시: 해당 리뷰의 드라마 ID(포스터 그리드만 표시).
  final String? reviewDramaId;

  /// [reviewDramaId] 썸네일 폴백(Firestore 스냅샷).
  final String? reviewDramaPosterUrl;

  @override
  State<CommunitySearchPage> createState() => _CommunitySearchPageState();
}

enum _SearchFilter { all, title, body, comment, nickname }

class _CommunitySearchPageState extends State<CommunitySearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';
  _SearchFilter _filter = _SearchFilter.all;
  List<Post> _allPosts = [];
  bool _loading = false;
  bool _hasFetched = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialQuery?.trim() ?? '';
    if (_reviewTagDramaMode) {
      if (seed.isNotEmpty) {
        _controller.text = seed;
        _query = seed;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _focusNode.unfocus();
        await DramaListService.instance.loadFromAsset();
      });
    } else if (seed.isNotEmpty) {
      _controller.text = seed;
      _query = seed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.unfocus();
        _fetchIfNeeded();
      });
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchIfNeeded() async {
    if (_hasFetched) return;
    setState(() => _loading = true);
    final posts = await PostService.instance.getPostsAllPages();
    if (mounted) {
      setState(() {
        _allPosts = posts;
        _loading = false;
        _hasFetched = true;
      });
    }
  }

  void _onQueryChanged(String q) {
    setState(() => _query = q.trim());
    if (!_hasFetched && q.trim().isNotEmpty) _fetchIfNeeded();
  }

  bool _matchPost(Post post, String q) {
    final lower = q.toLowerCase();
    switch (_filter) {
      case _SearchFilter.all:
        if (post.title.toLowerCase().contains(lower)) return true;
        if ((post.body ?? '').toLowerCase().contains(lower)) return true;
        if (post.author.toLowerCase().contains(lower)) return true;
        if (_anyCommentContains(post.commentsList, lower)) return true;
        for (final t in post.tags) {
          if (t.toLowerCase().contains(lower)) return true;
        }
        return false;
      case _SearchFilter.title:
        return post.title.toLowerCase().contains(lower);
      case _SearchFilter.body:
        return (post.body ?? '').toLowerCase().contains(lower);
      case _SearchFilter.nickname:
        return post.author.toLowerCase().contains(lower);
      case _SearchFilter.comment:
        return _anyCommentContains(post.commentsList, lower);
    }
  }

  bool _anyCommentContains(List<PostComment> comments, String q) {
    for (final c in comments) {
      if (c.text.toLowerCase().contains(q)) return true;
      if (_anyCommentContains(c.replies, q)) return true;
    }
    return false;
  }

  /// 리뷰에서 태그 탭: 태그 문자열 + 연결 드라마가 있을 때(포스터만).
  bool get _reviewTagDramaMode {
    final q = widget.initialQuery?.trim() ?? '';
    final id = widget.reviewDramaId?.trim() ?? '';
    return q.isNotEmpty && id.isNotEmpty;
  }

  String get _seedTag => (widget.initialQuery ?? '').trim();

  Widget _buildSearchField(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onQueryChanged,
        style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: CountryScope.of(context).strings.get('searchCommunityHint'),
          hintStyle: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurfaceVariant),
          prefixIcon: Icon(LucideIcons.search, size: 18, color: cs.onSurfaceVariant),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant),
                  onPressed: () {
                    _controller.clear();
                    _onQueryChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  List<Post> get _results {
    if (_query.isEmpty) return [];
    return _allPosts.where((p) => _matchPost(p, _query)).toList();
  }

  // 매칭된 텍스트에 하이라이트
  TextSpan _highlight(String text, String query, {TextStyle? base}) {
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    if (lowerQ.isEmpty || !lower.contains(lowerQ)) {
      return TextSpan(text: text, style: base);
    }
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lower.indexOf(lowerQ, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: base));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: base));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + lowerQ.length),
        style: (base ?? const TextStyle()).copyWith(
          color: const Color(0xFFFF4500),
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + lowerQ.length;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bodyBg = theme.scaffoldBackgroundColor;

    if (_reviewTagDramaMode) {
      final headerBarBg = listsStyleSubpageHeaderBackground(theme);
      final listAppBarOverlay = listsStyleSubpageSystemOverlay(theme, headerBarBg);
      final tagChipMaxW =
          (MediaQuery.sizeOf(context).width - 220).clamp(100.0, 280.0);

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: listAppBarOverlay,
        child: Scaffold(
          backgroundColor: bodyBg,
          appBar: PreferredSize(
            preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
            child: ListsStyleSubpageHeaderBar(
              title: _seedTag,
              onBack: () => popListsStyleSubpage(context),
              centerTitle: ReviewArrowTagChip(
                label: _seedTag,
                height: 24,
                maxLabelWidth: tagChipMaxW,
              ),
            ),
          ),
          body: _buildReviewTagDramaGrid(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bodyBg,
      appBar: AppBar(
        backgroundColor: theme.cardTheme.color ?? cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(LucideIcons.arrow_left, size: 22, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: SizedBox(
                height: 40,
                child: _buildSearchField(cs),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _FilterChips(
            selected: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),
        ),
      ),
      body: _buildBody(results),
    );
  }

  Widget _buildBody(List<Post> results) {
    final cs = Theme.of(context).colorScheme;
    if (_query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.search, size: 48, color: cs.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              CountryScope.of(context).strings.get('searchEnterQuery'),
              style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.file_search, size: 48, color: cs.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              CountryScope.of(context).strings.get('searchNoResults').replaceAll('%s', _query),
              style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: cs.outline.withOpacity(0.2)),
      itemBuilder: (context, i) {
        final post = results[i];
        return _SearchResultTile(
          post: post,
          query: _query,
          filter: _filter,
          highlight: _highlight,
          onTap: () async {
            final result = await Navigator.push<PostDetailResult>(
              context,
              MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
            );
            final updated = result?.updatedPost;
            if (updated != null) {
              final idx = _allPosts.indexWhere((p) => p.id == updated.id);
              if (idx != -1 && mounted) {
                setState(() => _allPosts[idx] = updated);
              }
            }
          },
        );
      },
    );
  }

  bool _isFavoriteDrama(String dramaId) {
    if (dramaId.trim().isEmpty) return false;
    return UserProfileService.instance
        .favoritesVisibleForCurrentLocale()
        .any((e) => e.dramaId == dramaId);
  }

  Future<void> _openReviewTagDramaDetail(String dramaId, String? country) async {
    await DramaListService.instance.loadFromAsset();
    if (!mounted) return;
    final item = WatchlistService.instance.resolveDramaItem(dramaId);
    if (!mounted) return;
    await DramaDetailPage.openFromItem(context, item, country: country);
  }

  /// [WatchlistScreen] 그리드와 동일 비율·간격, 셀은 포스터만.
  Widget _buildReviewTagDramaGrid() {
    final theme = Theme.of(context);
    final bodyBg = theme.scaffoldBackgroundColor;
    final id = widget.reviewDramaId!.trim();
    const padH = 15.0;
    const gap = 7.0;
    const aspect = 0.74;

    return AnimatedBuilder(
      animation: Listenable.merge([
        LocaleService.instance.localeNotifier,
        DramaListService.instance.listNotifier,
        UserProfileService.instance.favoritesNotifier,
      ]),
      builder: (context, _) {
        final country = CountryScope.maybeOf(context)?.country ??
            UserProfileService.instance.signupCountryNotifier.value;
        final fromCatalog =
            DramaListService.instance.getDisplayImageUrl(id, country);
        final poster = (fromCatalog != null && fromCatalog.isNotEmpty)
            ? fromCatalog
            : (widget.reviewDramaPosterUrl?.trim().isNotEmpty == true
                ? widget.reviewDramaPosterUrl!.trim()
                : null);

        return ColoredBox(
          color: bodyBg,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(padH, 10, padH, 28),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: aspect,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
            ),
            itemCount: 1,
            itemBuilder: (context, index) {
              return _ReviewTagPosterCell(
                key: ValueKey(id),
                imageUrl: poster,
                showFavoriteStar: _isFavoriteDrama(id),
                onOpen: () => _openReviewTagDramaDetail(id, country),
              );
            },
          ),
        );
      },
    );
  }
}

/// [WatchlistScreen] `_WatchlistPosterCell`과 동일 포스터만(제거 버튼 없음).
class _ReviewTagPosterCell extends StatelessWidget {
  const _ReviewTagPosterCell({
    super.key,
    required this.imageUrl,
    required this.onOpen,
    this.showFavoriteStar = false,
  });

  final String? imageUrl;
  final VoidCallback onOpen;
  final bool showFavoriteStar;

  static const double _radius = 4.5;
  static const double _borderWidth = 0.6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final url = imageUrl;
    final borderColor = isDark
        ? const Color(0xFF4A5568)
        : cs.outline.withValues(alpha: 0.38);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: borderColor, width: _borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF1E252E)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(_radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null &&
                      (url.startsWith('http://') || url.startsWith('https://')))
                    OptimizedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  else if (url != null && url.isNotEmpty)
                    Image.asset(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          LucideIcons.tv,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Icon(
                        LucideIcons.tv,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showFavoriteStar)
            Positioned(
              top: 3,
              left: 3,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 13,
                  color: Color(0xFFFFB020),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});
  final _SearchFilter selected;
  final ValueChanged<_SearchFilter> onSelect;

  static const _filters = [
    (_SearchFilter.all, '전체'),
    (_SearchFilter.title, '제목'),
    (_SearchFilter.body, '내용'),
    (_SearchFilter.comment, '댓글'),
    (_SearchFilter.nickname, '닉네임'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: _filters.map((item) {
          final (filter, label) = item;
          final isSelected = selected == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? cs.inverseSurface : cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? cs.inverseSurface : cs.outline.withOpacity(0.5),
                  ),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected ? cs.onInverseSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.post,
    required this.query,
    required this.filter,
    required this.highlight,
    required this.onTap,
  });

  final Post post;
  final String query;
  final _SearchFilter filter;
  final TextSpan Function(String, String, {TextStyle? base}) highlight;
  final VoidCallback onTap;

  // 댓글 중 매칭된 첫 번째 텍스트 스니펫 반환
  String? _firstMatchingComment(List<PostComment> comments, String q) {
    for (final c in comments) {
      if (c.text.toLowerCase().contains(q.toLowerCase())) return c.text;
      final sub = _firstMatchingComment(c.replies, q);
      if (sub != null) return sub;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final author = post.author.startsWith('u/')
        ? post.author.substring(2)
        : post.author;

    // 댓글 매칭 스니펫
    String? commentSnippet;
    if (filter == _SearchFilter.comment || filter == _SearchFilter.all) {
      commentSnippet = _firstMatchingComment(post.commentsList, query);
    }

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final baseTitle = GoogleFonts.notoSansKr(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    );
    final baseBody = GoogleFonts.notoSansKr(
      fontSize: 13,
      color: cs.onSurfaceVariant,
    );
    final nickBase = appUnifiedNicknameStyle(cs);
    final timeMeta = appUnifiedNicknameMetaTimeStyle(cs);
    final baseSmall = GoogleFonts.notoSansKr(
      fontSize: 11,
      color: cs.onSurfaceVariant,
    );

    return Material(
      color: theme.cardTheme.color ?? cs.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 닉네임 · 시간
              RichText(
                text: TextSpan(children: [
                  highlight(author, query, base: nickBase),
                  TextSpan(text: ' · ${post.timeAgo}', style: timeMeta),
                ]),
              ),
              const SizedBox(height: 4),
              // 제목
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: highlight(post.title, query, base: baseTitle),
              ),
              // 본문 미리보기
              if ((post.body ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: highlight(post.body ?? '', query, base: baseBody),
                ),
              ],
              // 댓글 매칭 스니펫
              if (commentSnippet != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.message_circle, size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: highlight(commentSnippet, query, base: baseBody),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              // 하단: 좋아요·댓글·조회수
              Row(
                children: [
                  Icon(LucideIcons.thumbs_up, size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(formatCompactCount(post.votes), style: baseSmall),
                  const SizedBox(width: 10),
                  Icon(LucideIcons.message_circle, size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(formatCompactCount(post.comments), style: baseSmall),
                  const SizedBox(width: 10),
                  Icon(LucideIcons.eye, size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(formatCompactCount(post.views), style: baseSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
