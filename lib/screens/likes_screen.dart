import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../utils/post_board_utils.dart';
import '../widgets/app_bar_back_icon_button.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'login_page.dart';
import 'post_detail_page.dart';

/// Letterboxd Likes 스타일 — `posts`에서 `likedBy`에 내 uid가 포함된 글.
class LikesScreen extends StatefulWidget {
  const LikesScreen({super.key});

  @override
  State<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen> with SingleTickerProviderStateMixin {
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
    final s = CountryScope.of(context).strings;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        centerTitle: true,
        title: Text(
          s.get('likes'),
          style: GoogleFonts.notoSansKr(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.12,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: AppBarBackIconButton(
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: GoogleFonts.notoSansKr(fontSize: 14),
          tabs: [
            Tab(text: s.get('tabLikedPosts')),
            Tab(text: s.get('tabLikedReviews')),
          ],
        ),
      ),
      body: ValueListenableBuilder<User?>(
        valueListenable: AuthService.instance.currentUser,
        builder: (context, user, _) {
          if (user == null) {
            return _LoginPrompt(s: s, cs: cs);
          }
          return _LikesTabBody(
            key: ValueKey(user.uid),
            tabController: _tabController,
            s: s,
            cs: cs,
          );
        },
      ),
    );
  }
}

class _LikesTabBody extends StatefulWidget {
  const _LikesTabBody({
    super.key,
    required this.tabController,
    required this.s,
    required this.cs,
  });

  final TabController tabController;
  final dynamic s;
  final ColorScheme cs;

  @override
  State<_LikesTabBody> createState() => _LikesTabBodyState();
}

class _LikesTabBodyState extends State<_LikesTabBody> {
  Future<List<Post>>? _postsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _postsFuture ??= _fetch();
  }

  Future<List<Post>> _fetch() {
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    if (uid.isEmpty) return Future.value([]);
    final country = CountryScope.maybeOf(context)?.country
        ?? UserProfileService.instance.signupCountryNotifier.value;
    return PostService.instance.getPostsLikedByUid(uid, countryForTimeAgo: country);
  }

  Future<void> _onRefresh() async {
    final uid = AuthService.instance.currentUser.value?.uid ?? '';
    if (uid.isEmpty) return;
    final country = CountryScope.maybeOf(context)?.country
        ?? UserProfileService.instance.signupCountryNotifier.value;
    setState(() {
      _postsFuture = PostService.instance.getPostsLikedByUid(uid, countryForTimeAgo: country);
    });
    await _postsFuture;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cs = widget.cs;

    return FutureBuilder<List<Post>>(
      future: _postsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data ?? [];
        final postsOnly = all.where((p) => postDisplayType(p) != 'review').toList();
        final reviewsOnly = all.where((p) => postDisplayType(p) == 'review').toList();

        return TabBarView(
          controller: widget.tabController,
          children: [
            RefreshIndicator(
              onRefresh: _onRefresh,
              child: _LikedPostsList(posts: postsOnly, s: s, cs: cs, emptyKey: 'likesEmptyPosts'),
            ),
            RefreshIndicator(
              onRefresh: _onRefresh,
              child: _LikedReviewsList(posts: reviewsOnly, s: s, cs: cs, emptyKey: 'likesEmptyReviews'),
            ),
          ],
        );
      },
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.s, required this.cs});

  final dynamic s;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.heart, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.45)),
            const SizedBox(height: 16),
            Text(
              s.get('likesLoginRequired'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                );
              },
              child: Text(s.get('login')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikedPostsList extends StatelessWidget {
  const _LikedPostsList({
    required this.posts,
    required this.s,
    required this.cs,
    required this.emptyKey,
  });

  final List<Post> posts;
  final dynamic s;
  final ColorScheme cs;
  final String emptyKey;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: Text(
                s.get(emptyKey),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: posts.length,
      separatorBuilder: (_, __) => Divider(height: 1, thickness: 1, color: cs.outline.withValues(alpha: 0.18)),
      itemBuilder: (context, i) {
        final post = posts[i];
        final author = post.author.startsWith('u/') ? post.author.substring(2) : post.author;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push<void>(
                context,
                CupertinoPageRoute<void>(builder: (_) => PostDetailPage(post: post)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$author · ${post.timeAgo}',
                    style: GoogleFonts.notoSansKr(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LikedReviewsList extends StatelessWidget {
  const _LikedReviewsList({
    required this.posts,
    required this.s,
    required this.cs,
    required this.emptyKey,
  });

  final List<Post> posts;
  final dynamic s;
  final ColorScheme cs;
  final String emptyKey;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  s.get(emptyKey),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: posts.length,
      separatorBuilder: (_, __) => Divider(height: 1, thickness: 1, color: cs.outline.withValues(alpha: 0.18)),
      itemBuilder: (context, i) {
        final post = posts[i];
        final thumb = post.dramaThumbnail?.trim();
        final hasHttp = thumb != null && thumb.startsWith('http');
        final title = post.dramaTitle?.trim().isNotEmpty == true ? post.dramaTitle!.trim() : post.title;
        final rating = post.rating;
        final body = (post.body ?? '').trim();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push<void>(
                context,
                CupertinoPageRoute<void>(builder: (_) => PostDetailPage(post: post)),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 52,
                      height: 74,
                      child: hasHttp
                          ? OptimizedNetworkImage(
                              imageUrl: thumb,
                              width: 52,
                              height: 74,
                              fit: BoxFit.cover,
                              errorWidget: ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(LucideIcons.tv, size: 22, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
                              ),
                            )
                          : ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(LucideIcons.tv, size: 22, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (rating != null && rating > 0)
                          Row(
                            children: [
                              Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade600),
                              const SizedBox(width: 4),
                              Text(
                                rating.toStringAsFixed(1),
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade700,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            '—',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              height: 1.4,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
