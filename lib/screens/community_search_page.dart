import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import 'post_detail_page.dart';

/// 통합 검색 페이지 - 제목 / 내용 / 댓글 / 닉네임 검색
class CommunitySearchPage extends StatefulWidget {
  const CommunitySearchPage({super.key});

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
    _focusNode.requestFocus();
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
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
            final updated = await Navigator.push<Post>(
              context,
              MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
            );
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
                  highlight(author, query, base: baseSmall),
                  TextSpan(text: ' · ${post.timeAgo}', style: baseSmall),
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
