import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/level_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/share_sheet.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/browser_nav_bar.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';
import 'login_page.dart';
import 'notification_screen.dart';
import 'post_detail_page.dart';
import 'write_post_page.dart';
import 'video_select_page.dart';
import 'question_board_tab.dart';
import 'community_search_page.dart';
import '../widgets/blind_refresh_indicator.dart';
import '../widgets/community_board_tabs.dart';

/// 홈 탭 - 인기글 / 자유게시판 (모던 스타일)
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, this.onProfileTap, this.writeNotifier});

  final VoidCallback? onProfileTap;
  /// main_screen에서 만들기 버튼 누를 때 notify → _openWritePost 호출
  final ValueNotifier<int>? writeNotifier;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Post> _freeBoardPosts = [];
  bool _postsLoading = true;
  String? _postsError;
  String? _currentUserAuthor;

  // 탭별 필터 캐시 (build마다 재계산 방지)
  List<Post> _cachedFiltered = [];
  List<Post> _cachedPopular = [];
  List<Post> _cachedFree = [];
  List<Post> _cachedQuestion = [];

  // 브라우저 히스토리 (community 레벨)
  List<(Post, int)> _navBackStack = [];
  List<(Post, int)> _navForwardStack = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _rebuildPostCache();
    _loadPosts();
    _loadCurrentUserAuthor();
    AuthService.instance.isLoggedIn.addListener(_onAuthChanged);
    widget.writeNotifier?.addListener(_onExternalWriteTap);
    BlockService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() => _rebuildPostCache());
    });
    BlockService.instance.addListener(_onBlockListChanged);
  }

  /// _freeBoardPosts 또는 블록 목록 변경 시 탭별 필터를 한 번에 미리 계산
  void _rebuildPostCache() {
    _cachedFiltered = _freeBoardPosts
        .where((p) => !BlockService.instance.isBlocked(p.author) && !BlockService.instance.isPostBlocked(p.id))
        .toList();
    _cachedPopular = _cachedFiltered.where((p) => p.votes >= 10 || p.views >= 100).toList();
    _cachedFree = _cachedFiltered.where((p) => p.category == 'free').toList();
    _cachedQuestion = _cachedFiltered.where((p) => p.category == 'question').toList();
  }

  void _onBlockListChanged() {
    setState(() => _rebuildPostCache());
  }

  void _onExternalWriteTap() => _openWritePost();

  void _onAuthChanged() {
    if (AuthService.instance.isLoggedIn.value) _loadCurrentUserAuthor();
    else if (mounted) setState(() => _currentUserAuthor = null);
  }

  Future<void> _loadCurrentUserAuthor() async {
    if (!AuthService.instance.isLoggedIn.value) return;
    final author = await UserProfileService.instance.getAuthorForPost();
    if (mounted) setState(() => _currentUserAuthor = author);
  }

  Future<void> _loadPosts() async {
    if (mounted) setState(() { _postsLoading = true; _postsError = null; });
    _loadCurrentUserAuthor();
    try {
      // 로그인 사용자: 가입 시 선택한 언어 기준, 비로그인: 현재 앱 언어 기준 → 같은 언어 글만 표시
      final viewerLanguage = AuthService.instance.isLoggedIn.value
          ? (UserProfileService.instance.signupCountryNotifier.value ?? LocaleService.instance.locale)
          : LocaleService.instance.locale;
      // getPosts 내부에서 country 클라이언트 필터 + 0개면 전체 자동 폴백
      final list = await PostService.instance.getPosts(country: viewerLanguage);
      if (mounted) setState(() {
        _freeBoardPosts = list;
        _postsLoading = false;
        _rebuildPostCache();
      });
    } catch (e) {
      if (mounted) setState(() {
        _postsLoading = false;
        _postsError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    AuthService.instance.isLoggedIn.removeListener(_onAuthChanged);
    widget.writeNotifier?.removeListener(_onExternalWriteTap);
    BlockService.instance.removeListener(_onBlockListChanged);
    _tabController.dispose();
    super.dispose();
  }


  Future<void> _openPost(Post post, {String? tabName, List<(Post, int)>? backStack, List<(Post, int)>? forwardStack, int? tabIndex}) async {
    final result = await Navigator.push<PostDetailResult>(
      context,
      MaterialPageRoute(builder: (_) => PostDetailPage(
        post: post,
        tabName: tabName,
        initialBackStack: backStack ?? [],
        initialForwardStack: forwardStack ?? [],
        initialTabIndex: tabIndex,
        initialBoardPosts: _cachedFiltered,
        onPostDeleted: (deleted) {
          setState(() {
            _freeBoardPosts.removeWhere((p) => p.id == deleted.id);
            _rebuildPostCache();
          });
        },
      )),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _navBackStack = result.backStack;
        _navForwardStack = result.forwardStack;
      });
      if (result.updatedPost != null) {
        setState(() {
          final i = _freeBoardPosts.indexWhere((p) => p.id == result.updatedPost!.id);
          if (i >= 0) _freeBoardPosts[i] = result.updatedPost!;
          _rebuildPostCache();
        });
      }
    }
  }

  Future<void> _navBack() async {
    if (_navBackStack.isEmpty) return;
    final (post, tabIndex) = _navBackStack.last;
    final newBack = List<(Post, int)>.of(_navBackStack)..removeLast();
    await _openPost(post, tabIndex: tabIndex, backStack: newBack, forwardStack: _navForwardStack);
  }

  Future<void> _navForward() async {
    if (_navForwardStack.isEmpty) return;
    final (post, tabIndex) = _navForwardStack.last;
    final newForward = List<(Post, int)>.of(_navForwardStack)..removeLast();
    await _openPost(post, tabIndex: tabIndex, backStack: _navBackStack, forwardStack: newForward);
  }

  Future<void> _openWritePost() async {
    if (!AuthService.instance.isLoggedIn.value) {
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (!mounted || loggedIn != true) return;
    }
    final category = _tabController.index == 2 ? 'question' : 'free';
    final Post? post = await Navigator.push<Post>(
      context,
      MaterialPageRoute(builder: (_) => WritePostPage(initialCategory: category)),
    );
    if (post != null && mounted) {
      final s = CountryScope.of(context).strings;
      // 즉시 목록에 노출 (낙관적 업데이트)
      setState(() {
        _freeBoardPosts.insert(0, post);
        _rebuildPostCache();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.get('postSubmitted'), style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      LevelService.instance.addPoints(5);
      // Firestore 저장: 백그라운드에서 재시도(1초→2초→4초→8초) until 성공
      _savePostInBackground(post);
    }
  }

  /// 백그라운드에서 글 저장 재시도. 성공 시 목록을 서버 id로 갱신, 전부 실패 시 실제 오류 메시지 표시.
  void _savePostInBackground(Post post) {
    PostService.instance.addPostWithRetry(post).then((result) {
      final (saved, errorMsg) = result;
      if (!mounted) return;
      if (saved != null) {
        setState(() {
          final idx = _freeBoardPosts.indexOf(post);
          if (idx >= 0) _freeBoardPosts[idx] = saved;
          _rebuildPostCache();
        });
      } else {
        final msg = errorMsg?.trim().isNotEmpty == true
            ? errorMsg!
            : CountryScope.of(context).strings.get('postSyncFailed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shortSide = MediaQuery.sizeOf(context).shortestSide;
    final r = (shortSide / 360).clamp(0.85, 1.25);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 6,
        scrolledUnderElevation: 6,
        shadowColor: cs.shadow.withOpacity(0.18),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20 * r),
            bottomRight: Radius.circular(20 * r),
          ),
        ),
        automaticallyImplyLeading: false,
        centerTitle: false,
        toolbarHeight: 52 * r,
        leadingWidth: 54 * r,
        leading: Builder(
          builder: (context) => GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(left: 10 * r),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(width: 16 * r, height: 1.8 * r, decoration: BoxDecoration(color: cs.onSurface, borderRadius: BorderRadius.circular(2 * r))),
                    SizedBox(height: 4 * r),
                    Container(width: 16 * r, height: 1.8 * r, decoration: BoxDecoration(color: cs.onSurface, borderRadius: BorderRadius.circular(2 * r))),
                    SizedBox(height: 4 * r),
                    Container(width: 16 * r, height: 1.8 * r, decoration: BoxDecoration(color: cs.onSurface, borderRadius: BorderRadius.circular(2 * r))),
                  ],
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 4 * r,
        title: Transform.translate(
          offset: Offset(0, -3 * r),
          child: Text(
            'DramaTALK',
            style: GoogleFonts.notoSansKr(
              fontSize: 22 * r,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 10 * r),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CommunitySearchPage()),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(left: 4 * r, right: 6 * r),
                    child: Icon(LucideIcons.search, size: 26 * r, color: cs.onSurface),
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: NotificationService.instance.unreadCount,
                  builder: (context, unread, _) {
                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationScreen()),
                        );
                        NotificationService.instance.markAllRead();
                      },
                      child: Padding(
                        padding: EdgeInsets.only(left: 6 * r, right: 8 * r),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                      Icon(
                        unread > 0 ? LucideIcons.bell_dot : LucideIcons.bell,
                        size: 26 * r,
                        color: unread > 0 ? cs.primary : cs.onSurface,
                      ),
                      if (unread > 0)
                        Positioned(
                          top: -4 * r,
                          right: -4 * r,
                          child: Container(
                            padding: EdgeInsets.all(3 * r),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            constraints: BoxConstraints(minWidth: 16 * r, minHeight: 16 * r),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: TextStyle(color: cs.onPrimary, fontSize: 9 * r, fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(44 * r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _tabController.animation!,
                    builder: (context, _) {
                      final tabW = 60.0 * r;
                      final tabH = 32.0 * r;
                      final tabGap = 5.0 * r;
                      final leftPad = 14.0 * r;
                      final animValue = _tabController.animation?.value ?? _tabController.index.toDouble();
                      final idx = animValue.round().clamp(0, 2);

                      return Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: leftPad + (tabW + tabGap) * 2 + tabW,
                          height: tabH,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: leftPad + (tabW + tabGap) * animValue,
                                top: 0,
                                child: Container(
                                  width: tabW,
                                  height: tabH,
                                  decoration: BoxDecoration(
                                    color: cs.inverseSurface,
                                    borderRadius: BorderRadius.circular(8 * r),
                                  ),
                                ),
                              ),
                              for (var i = 0; i < 3; i++)
                                Positioned(
                                  left: leftPad + (tabW + tabGap) * i,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () => _tabController.animateTo(i),
                                    behavior: HitTestBehavior.opaque,
                                    child: SizedBox(
                                      width: tabW,
                                      height: tabH,
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: cs.outline, width: 0.7),
                                          borderRadius: BorderRadius.circular(8 * r),
                                        ),
                                        child: Text(
                                          [s.get('tabHot'), s.get('tabGeneral'), s.get('tabQnA')][i],
                                          strutStyle: const StrutStyle(
                                            forceStrutHeight: true,
                                            height: 1.2,
                                            leadingDistribution: TextLeadingDistribution.even,
                                          ),
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 12 * r,
                                            height: 1.2,
                                            fontWeight: FontWeight.w700,
                                            color: idx == i ? cs.onInverseSurface : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  _ThemeSwitchPill(scale: r),
                  SizedBox(width: 14 * r),
                ],
              ),
              SizedBox(height: 20 * r),
            ],
          ),
        ),
      ),
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: Stack(
          children: [
            TabBarView(
            controller: _tabController,
            children: [
              PopularPostsTab(
                posts: _cachedPopular,
                isLoading: _postsLoading,
                error: _postsError,
                currentUserAuthor: _currentUserAuthor,
                onRefresh: _loadPosts,
                onPostUpdated: (Post updated) {
                  setState(() {
                    final i = _freeBoardPosts.indexWhere((p) => p.id == updated.id);
                    if (i >= 0) _freeBoardPosts[i] = updated;
                    _rebuildPostCache();
                  });
                },
                onPostDeleted: (Post deleted) {
                  setState(() {
                    _freeBoardPosts.removeWhere((p) => p.id == deleted.id);
                    _rebuildPostCache();
                  });
                },
                onPostTap: (post) => _openPost(post, tabName: s.get('tabHot'), backStack: _navBackStack, forwardStack: []),
                onUserBlocked: () => setState(() {}),
              ),
              FreeBoardTab(
                posts: _cachedFree,
                isLoading: _postsLoading,
                error: _postsError,
                currentUserAuthor: _currentUserAuthor,
                onRefresh: _loadPosts,
                onPostUpdated: (Post updated) {
                  setState(() {
                    final i = _freeBoardPosts.indexWhere((p) => p.id == updated.id);
                    if (i >= 0) _freeBoardPosts[i] = updated;
                    _rebuildPostCache();
                  });
                },
                onPostDeleted: (Post deleted) {
                  setState(() {
                    _freeBoardPosts.removeWhere((p) => p.id == deleted.id);
                    _rebuildPostCache();
                  });
                },
                onPostTap: (post) => _openPost(post, tabName: s.get('freeBoard'), backStack: _navBackStack, forwardStack: []),
                onUserBlocked: () => setState(() {}),
              ),
              QuestionBoardTab(
                posts: _cachedQuestion,
                isLoading: _postsLoading,
                error: _postsError,
                currentUserAuthor: _currentUserAuthor,
                onRefresh: _loadPosts,
                onPostUpdated: (Post updated) {
                  setState(() {
                    final i = _freeBoardPosts.indexWhere((p) => p.id == updated.id);
                    if (i >= 0) _freeBoardPosts[i] = updated;
                    _rebuildPostCache();
                  });
                },
                onPostDeleted: (Post deleted) {
                  setState(() {
                    _freeBoardPosts.removeWhere((p) => p.id == deleted.id);
                    _rebuildPostCache();
                  });
                },
                onPostTap: (post) => _openPost(post, tabName: s.get('tabQnA'), backStack: _navBackStack, forwardStack: []),
                onUserBlocked: () => setState(() {}),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BrowserNavBar(
              canGoBack: _navBackStack.isNotEmpty,
              canGoForward: _navForwardStack.isNotEmpty,
              isRefreshing: _postsLoading,
              onRefresh: _loadPosts,
              onBack: _navBack,
              onForward: _navForward,
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// 테마 스위치: 애니메이션은 로컬만, 완료 후에 테마 전환해서 앱 전체 렉 방지
class _ThemeSwitchPill extends StatefulWidget {
  const _ThemeSwitchPill({this.scale = 1.0});
  final double scale;

  @override
  State<_ThemeSwitchPill> createState() => _ThemeSwitchPillState();
}

class _ThemeSwitchPillState extends State<_ThemeSwitchPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // controller: 0.0 = Dark(왼쪽), 1.0 = Light(오른쪽)
  @override
  void initState() {
    super.initState();
    final isDark = ThemeService.instance.themeModeNotifier.value == ThemeMode.dark;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
      value: isDark ? 0.0 : 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    final isDark = ThemeService.instance.themeModeNotifier.value == ThemeMode.dark;
    if (isDark) {
      // 스위치 먼저 오른쪽으로 이동 → 완료 후 Light 테마 적용
      _controller.forward().then((_) {
        ThemeService.instance.setThemeMode(ThemeMode.light);
      });
    } else {
      // 스위치 먼저 왼쪽으로 이동 → 완료 후 Dark 테마 적용
      _controller.reverse().then((_) {
        ThemeService.instance.setThemeMode(ThemeMode.dark);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.themeModeNotifier,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        final pillW = 62.0 * scale;
        final pillH = 30.0 * scale;
        final thumbSize = 24.0 * scale;
        final padding = 3.0 * scale;
        final trackInnerW = pillW - padding * 2;

        return GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: pillW,
            height: pillH,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(pillH / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4 * scale,
                  offset: Offset(0, 1 * scale),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Positioned(
                      top: padding,
                      left: padding + _controller.value * (trackInnerW - thumbSize),
                      child: Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white : const Color(0xFF3A3A3C),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 3 * scale,
                              offset: Offset(0, 1 * scale),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  left: isDark ? null : 8 * scale,
                  right: isDark ? 8 * scale : null,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(
                      isDark ? 'DARK' : 'LIGHT',
                      style: GoogleFonts.notoSansKr(
                        fontSize: (isDark ? 9 : 8) * scale,
                        height: isDark ? 11 / 9 : 11 / 8,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF3A3A3C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
