import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/saved_service.dart';
import 'post_detail_page.dart';

/// 저장한 콘텐츠 목록 (콘텐츠 탭 + 글 탭)
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '저장',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: GoogleFonts.notoSansKr(fontSize: 14),
          tabs: const [
            Tab(text: '콘텐츠'),
            Tab(text: '글'),
          ],
        ),
      ),
      body: ValueListenableBuilder<List<SavedItem>>(
        valueListenable: SavedService.instance.savedList,
        builder: (context, list, _) {
          final contentItems = SavedService.instance.savedContent;
          final postItems = SavedService.instance.savedPosts;
          return TabBarView(
            controller: _tabController,
            children: [
              _ContentTab(contentItems: contentItems),
              _PostsTab(postItems: postItems),
            ],
          );
        },
      ),
    );
  }
}

/// 콘텐츠 탭: 숏폼/리뷰 저장 목록 → 드라마 카드 스타일
class _ContentTab extends StatelessWidget {
  const _ContentTab({required this.contentItems});

  final List<SavedItem> contentItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (contentItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.tv,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '저장한 콘텐츠가 없습니다',
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '숏폼·드라마에서 저장 버튼을 눌러 추가해보세요',
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: cs.onSurfaceVariant.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: contentItems.length,
      itemBuilder: (context, index) {
        final item = contentItems[index];
        return _SavedContentCard(item: item);
      },
    );
  }
}

/// 저장한 콘텐츠 1개 - 드라마 카드 스타일
class _SavedContentCard extends StatelessWidget {
  const _SavedContentCard({required this.item});

  final SavedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.grey.shade700,
                          Colors.grey.shade800,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        LucideIcons.tv,
                        size: 32,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                      child: IconButton(
                        icon: Icon(Icons.bookmark, size: 20, color: cs.primary),
                        onPressed: () => SavedService.instance.remove(item.id),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.play, size: 12, color: Colors.white.withOpacity(0.9)),
                        const SizedBox(width: 4),
                        Text(
                          item.views,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              child: Text(
                item.title,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 글 탭: 게시판 저장 목록
class _PostsTab extends StatelessWidget {
  const _PostsTab({required this.postItems});

  final List<SavedItem> postItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (postItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.message_square,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '저장한 글이 없습니다',
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '게시판에서 글의 저장 버튼을 눌러 추가해보세요',
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: cs.onSurfaceVariant.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: postItems.length,
      itemBuilder: (context, index) {
        final item = postItems[index];
        final post = item.post!;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailPage(post: post),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.title,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${post.author.startsWith("u/") ? post.author.substring(2) : post.author} · ${post.timeAgo}',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.bookmark, color: cs.primary, size: 22),
                      onPressed: () => SavedService.instance.remove(item.id),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
