import 'package:flutter/material.dart';
import '../widgets/blind_refresh_indicator.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/talk_ask_feed_list_row.dart';
import '../widgets/country_scope.dart';
import '../widgets/community_board_tabs.dart' show PostSearchScope, postSearchScopeLabel, postSearchScopeOrder;

const int _postsPerPage = 20;

double _listBottomPad(BuildContext context) =>
    48 + MediaQuery.of(context).padding.bottom;

class QuestionBoardTab extends StatefulWidget {
  const QuestionBoardTab({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.onRefresh,
    this.error,
    this.currentUserAuthor,
    this.onPostUpdated,
    this.onPostDeleted,
    this.onPostTap,
    this.onUserBlocked,
    this.enablePullToRefresh = true,
    this.shrinkWrap = false,
    this.useSimpleFeedLayout = false,
    this.feedScrollController,
    this.feedLoadingMore = false,
    this.feedHasMore = true,
    this.feedAuthorAvatarSize,
    this.useCardFeedLayout = false,
  });

  final List<Post> posts;
  final bool isLoading;
  final String? error;
  final String? currentUserAuthor;
  final Future<void> Function() onRefresh;
  final bool enablePullToRefresh;
  final bool shrinkWrap;
  final void Function(Post)? onPostUpdated;
  final void Function(Post)? onPostDeleted;
  final void Function(Post)? onPostTap;
  final VoidCallback? onUserBlocked;
  final bool useSimpleFeedLayout;
  final ScrollController? feedScrollController;
  final bool feedLoadingMore;
  final bool feedHasMore;
  final double? feedAuthorAvatarSize;
  final bool useCardFeedLayout;

  @override
  State<QuestionBoardTab> createState() => _QuestionBoardTabState();
}

class _QuestionBoardTabState extends State<QuestionBoardTab> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageInputController = TextEditingController();
  final GlobalKey _filterKey = GlobalKey();
  int _currentPage = 0;
  String _searchQuery = '';
  bool _showPageInput = false;
  PostSearchScope _searchScope = PostSearchScope.titleAndBody;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageInputController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _currentPage = 0;
    });
  }

  bool _postMatchesQuery(Post p, String q) {
    final title = p.title.toLowerCase();
    final body = (p.body ?? '').toLowerCase();
    final author =
        (p.author.startsWith('u/') ? p.author.substring(2) : p.author)
            .toLowerCase();
    switch (_searchScope) {
      case PostSearchScope.titleAndBody:
        return title.contains(q) || body.contains(q);
      case PostSearchScope.title:
        return title.contains(q);
      case PostSearchScope.body:
        return body.contains(q);
      case PostSearchScope.comment:
        return p.commentsList.any((c) => _commentContainsQuery(c, q));
      case PostSearchScope.nickname:
        return author.contains(q);
    }
  }

  bool _commentContainsQuery(PostComment c, String q) {
    if (c.text.toLowerCase().contains(q)) return true;
    return c.replies.any((r) => _commentContainsQuery(r, q));
  }

  List<Post> get _filteredPosts {
    var list = widget.posts;
    if (_searchQuery.isNotEmpty) {
      list = list.where((p) => _postMatchesQuery(p, _searchQuery)).toList();
    }
    return list;
  }

  List<Post> get _paginatedPosts {
    final f = _filteredPosts;
    final start = _currentPage * _postsPerPage;
    if (start >= f.length) return [];
    return f.sublist(start, (start + _postsPerPage).clamp(0, f.length));
  }

  int get _totalPages {
    final len = _filteredPosts.length;
    if (len == 0) return 0;
    return (len / _postsPerPage).ceil();
  }

  Widget _wrapRefresh(Widget child) {
    if (widget.enablePullToRefresh) {
      return BlindRefreshIndicator(onRefresh: widget.onRefresh, spinnerOffsetDown: 17.0, child: child);
    }
    return child;
  }

  Widget _buildSimpleAskFeed(
    BuildContext context,
    ColorScheme cs,
    List<Post> posts,
    bool isLoading,
    String? error,
    Future<void> Function() onRefresh,
    String? currentUserAuthor,
    void Function(Post)? onPostUpdated,
    void Function(Post)? onPostDeleted,
  ) {
    final tabName = CountryScope.of(context).strings.get('tabQnA');
    if (isLoading && posts.isEmpty) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && posts.isEmpty) {
      final bottom = _listBottomPad(context);
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, bottom),
        children: [
          const SizedBox(height: 8),
          Icon(LucideIcons.cloud_off, size: 56, color: cs.error.withOpacity(0.6)),
          const SizedBox(height: 20),
          Text('글을 불러오지 못했어요', textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(error, textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(fontSize: 12, color: cs.error, height: 1.5)),
          const SizedBox(height: 20),
          TextButton(onPressed: onRefresh, child: Text('다시 시도', style: GoogleFonts.notoSansKr(fontSize: 14, color: cs.primary))),
        ],
      ));
    }
    if (posts.isEmpty) {
      final bottom = _listBottomPad(context);
      return _wrapRefresh(ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, bottom),
        children: [
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          ),
        ],
      ));
    }
    final footerCount = (widget.feedLoadingMore && widget.feedHasMore) ? 1 : 0;
    final bottom = widget.shrinkWrap ? 24.0 : _listBottomPad(context);
    final listView = ListView.builder(
      controller: widget.feedScrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 400,
      itemCount: posts.length + footerCount + 1,
      itemBuilder: (context, index) {
        if (index < posts.length) {
          final post = posts[index];
          if (widget.useCardFeedLayout) {
            return RepaintBoundary(
              child: FeedPostCard(
                key: ValueKey(post.id),
                post: post,
                currentUserAuthor: currentUserAuthor,
                onPostUpdated: onPostUpdated,
                onPostDeleted: onPostDeleted,
                tabName: tabName,
                onTap: widget.onPostTap != null
                    ? () => widget.onPostTap!(post)
                    : null,
                onUserBlocked: widget.onUserBlocked,
                authorAvatarSize: widget.feedAuthorAvatarSize,
              ),
            );
          }
          return RepaintBoundary(
            key: ValueKey('ask_list_${post.id}'),
            child: TalkAskFeedListRow(
              post: post,
              colorScheme: cs,
              showLeadingDivider: index > 0,
              onTap: widget.onPostTap != null
                  ? () => widget.onPostTap!(post)
                  : null,
            ),
          );
        }
        if (footerCount == 1 && index == posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))),
          );
        }
        return SizedBox(height: bottom);
      },
    );
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: _wrapRefresh(listView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final posts = widget.posts;
    final isLoading = widget.isLoading;
    final error = widget.error;
    final onRefresh = widget.onRefresh;
    final currentUserAuthor = widget.currentUserAuthor;
    final onPostUpdated = widget.onPostUpdated;
    final onPostDeleted = widget.onPostDeleted;

    if (widget.useSimpleFeedLayout) {
      return _buildSimpleAskFeed(context, cs, posts, isLoading, error, onRefresh, currentUserAuthor, onPostUpdated, onPostDeleted);
    }

    if (isLoading) {
      if (widget.shrinkWrap) {
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 48),
          children: [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      final bottom = 48 + MediaQuery.of(context).padding.bottom;
      final errorView = ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, bottom),
          children: [
            const SizedBox(height: 8),
            Icon(LucideIcons.cloud_off,
                size: 56, color: cs.error.withOpacity(0.6)),
            const SizedBox(height: 20),
            Text('글을 불러오지 못했어요',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, color: cs.error, height: 1.5)),
            const SizedBox(height: 20),
            TextButton(
                onPressed: onRefresh,
                child: Text('다시 시도',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 14, color: cs.primary))),
          ],
        );
      return widget.enablePullToRefresh
          ? BlindRefreshIndicator(onRefresh: onRefresh, spinnerOffsetDown: 17.0, child: errorView)
          : errorView;
    }
    if (posts.isEmpty) {
      final bottom = 48 + MediaQuery.of(context).padding.bottom;
      final emptyView = ListView(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 48, 24, bottom),
          children: [
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        );
      return widget.enablePullToRefresh
          ? BlindRefreshIndicator(onRefresh: onRefresh, spinnerOffsetDown: 17.0, child: emptyView)
          : emptyView;
    }

    final filtered = _filteredPosts;
    final paginated = _paginatedPosts;
    final totalPages = _totalPages;

    if (_currentPage >= totalPages && totalPages > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(
              () => _currentPage = (totalPages - 1).clamp(0, 999999));
        }
      });
    }

    final bottom = widget.shrinkWrap ? 24.0 : (48 + MediaQuery.of(context).padding.bottom).toDouble();
    final tabName = CountryScope.of(context).strings.get('tabQnA');
    final listView = ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: 400,
      itemCount: paginated.length + 4,
      itemBuilder: (context, index) {
        if (index < paginated.length) {
          final post = paginated[index];
          return RepaintBoundary(
            child: FeedPostCard(
              key: ValueKey(post.id),
              post: post,
            currentUserAuthor: currentUserAuthor,
            onPostUpdated: onPostUpdated,
            onPostDeleted: onPostDeleted,
            tabName: tabName,
            onTap: widget.onPostTap != null ? () => widget.onPostTap!(post) : null,
            onUserBlocked: widget.onUserBlocked,
            authorAvatarSize: widget.feedAuthorAvatarSize,
            ),
          );
        }
        if (index == paginated.length) return const SizedBox(height: 16);
        if (index == paginated.length + 1) return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildSearchBar(cs));
        if (index == paginated.length + 2) return _buildMinimalPagination(cs, totalPages, filtered.length);
        return SizedBox(height: bottom);
      },
    );
    final content = widget.enablePullToRefresh
        ? BlindRefreshIndicator(onRefresh: onRefresh, spinnerOffsetDown: 17.0, child: listView)
        : listView;
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_showPageInput) setState(() => _showPageInput = false);
      },
      behavior: HitTestBehavior.translucent,
      child: content,
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(LucideIcons.search, size: 17, color: cs.onSurfaceVariant.withOpacity(0.8)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              cursorColor: cs.primary,
              decoration: InputDecoration(
                hintText: CountryScope.of(context).strings.get('search'),
                hintStyle: GoogleFonts.notoSansKr(fontSize: 14, color: cs.onSurfaceVariant.withOpacity(0.7), fontWeight: FontWeight.w400),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: GoogleFonts.notoSansKr(fontSize: 14, fontWeight: FontWeight.w400, color: cs.onSurface),
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () { _searchController.clear(); setState(() => _searchQuery = ''); },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant.withOpacity(0.8)),
              ),
            ),
          Container(width: 1, height: 22, color: cs.onSurface.withOpacity(0.08)),
          GestureDetector(
            key: _filterKey,
            onTap: () async {
              final RenderBox btn = _filterKey.currentContext!.findRenderObject() as RenderBox;
              final Offset btnOffset = btn.localToGlobal(Offset.zero);
              final Size screenSize = MediaQuery.of(context).size;
              final selected = await showMenu<PostSearchScope>(
                context: context,
                position: RelativeRect.fromRect(
                  Rect.fromLTWH(btnOffset.dx, btnOffset.dy, btn.size.width, btn.size.height),
                  Offset.zero & screenSize,
                ),
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                items: postSearchScopeOrder.map((scope) {
                  final isSelected = scope == _searchScope;
                  return PopupMenuItem<PostSearchScope>(
                    value: scope,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Row(
                      children: [
                        Text(postSearchScopeLabel(scope, context), style: GoogleFonts.notoSansKr(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? cs.onSurface : cs.onSurfaceVariant)),
                        if (isSelected) ...[const Spacer(), Icon(LucideIcons.check, size: 14, color: cs.onSurface)],
                      ],
                    ),
                  );
                }).toList(),
              );
              if (selected != null && mounted) setState(() => _searchScope = selected);
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(postSearchScopeLabel(_searchScope, context), style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(width: 3),
                  Icon(LucideIcons.chevron_down, size: 13, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalPagination(ColorScheme cs, int totalPages, int totalCount) {
    if (totalCount == 0 || totalPages == 0) return const SizedBox.shrink();
    final c = _currentPage;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: c > 0 ? () => setState(() { _currentPage = c - 1; _showPageInput = false; }) : null,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.chevron_left, size: 22, color: c > 0 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18))),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() { _showPageInput = !_showPageInput; if (_showPageInput) _pageInputController.clear(); }),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showPageInput
                  ? Container(
                      key: const ValueKey('input'),
                      width: 80, height: 34,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark ? cs.outline : const Color(0xFFFF6B35),
                          width: Theme.of(context).brightness == Brightness.dark ? 1 : 1.2,
                        ),
                      ),
                      child: Center(
                        child: TextField(
                          controller: _pageInputController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: '페이지',
                            hintStyle: GoogleFonts.notoSansKr(fontSize: 12, color: cs.onSurfaceVariant),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurface),
                          onSubmitted: (val) {
                            final n = int.tryParse(val);
                            if (n != null && n >= 1 && n <= totalPages) setState(() { _currentPage = n - 1; _showPageInput = false; });
                            else setState(() => _showPageInput = false);
                          },
                        ),
                      ),
                    )
                  : Container(
                      key: const ValueKey('label'),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
                      child: Text('${c + 1} / $totalPages', style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant, letterSpacing: 0.2)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: c < totalPages - 1 ? () => setState(() { _currentPage = c + 1; _showPageInput = false; }) : null,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.chevron_right, size: 22, color: c < totalPages - 1 ? cs.onSurface.withOpacity(0.75) : cs.onSurface.withOpacity(0.18))),
          ),
        ],
      ),
    );
  }

  Widget _arrow(ColorScheme cs, IconData icon, bool enabled,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon,
            size: 22,
            color: enabled
                ? cs.onSurface.withOpacity(0.75)
                : cs.onSurface.withOpacity(0.18)),
      ),
    );
  }
}
