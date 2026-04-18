import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/level_service.dart';
import '../services/post_service.dart';
import '../services/review_service.dart';
import '../services/user_profile_service.dart';
import '../services/locale_service.dart';
import '../utils/format_utils.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import '../widgets/share_sheet.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/browser_nav_bar.dart';
import '../services/notification_service.dart';
import 'login_page.dart';
import 'notification_screen.dart';
import 'post_detail_page.dart';
import 'write_post_page.dart';
import 'video_select_page.dart';
import 'community_search_page.dart';
import '../widgets/blind_refresh_indicator.dart';
import '../widgets/community_board_tabs.dart';
import '../utils/post_board_utils.dart';
import '../services/home_tab_visibility.dart';
import '../theme/app_theme.dart';

/// 홈 탭 - 인기글 / 자유게시판 (모던 스타일)
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    this.onProfileTap,
    this.writeNotifier,
    this.writeOpenAsReview,
  });

  final VoidCallback? onProfileTap;

  /// main_screen에서 만들기 버튼 누를 때 notify → _openWritePost 호출
  final ValueNotifier<int>? writeNotifier;

  /// 홈 외 탭에서 [+] 시 true → 글쓰기는 리뷰 탭 기준으로 열고 소비 시 false로 되돌림
  final ValueNotifier<bool>? writeOpenAsReview;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Post> _freeBoardPosts = [];
  String? _postsError;
  String? _currentUserAuthor;

  /// 글 상세 네비용 (로드된 글 합집합)
  List<Post> _cachedFiltered = [];

  /// 홈 DramaFeed: 리뷰·자유만 (질문 게시판은 노출하지 않음)
  static const List<String> _feedBoards = ['review', 'talk'];
  static final int _feedTabCount = _feedBoards.length;
  final List<List<Post>> _tabFeedPosts =
      List.generate(_feedTabCount, (_) => []);
  final List<DocumentSnapshot<Map<String, dynamic>>?> _tabLastDoc =
      List.generate(_feedTabCount, (_) => null);
  final List<bool> _tabHasMore = List.generate(_feedTabCount, (_) => true);
  final List<bool> _tabLoadingMore =
      List.generate(_feedTabCount, (_) => false);
  final List<bool> _tabInitialLoading = [true, false];
  late final List<ScrollController> _feedScrollControllers;
  int _feedPrevTabIndex = 0;
  bool _feedTabListenerArmed = false;

  /// 톡·에스크 피드: false=구분선 목록(기본), true=카드.
  bool _talkAskUseCardFeedLayout = false;

  // 브라우저 히스토리 (community 레벨)
  List<(Post, int)> _navBackStack = [];
  List<(Post, int)> _navForwardStack = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _feedTabCount, vsync: this);
    _feedScrollControllers = List.generate(_feedTabCount, (i) {
      final c = ScrollController();
      c.addListener(() => _onFeedScrollNearEnd(i));
      return c;
    });
    _tabController.addListener(_onFeedTabControllerTick);
    _rebuildPostCache();
    _loadCurrentUserAuthor();
    AuthService.instance.isLoggedIn.addListener(_onAuthChanged);
    widget.writeNotifier?.addListener(_onExternalWriteTap);
    BlockService.instance.ensureLoaded().then((_) {
      if (mounted) _applyBlockFilterToFeeds();
    });
    BlockService.instance.addListener(_onBlockListChanged);
    LocaleService.instance.localeNotifier.addListener(_onLocaleForFeedReload);
    ReviewService.instance.reviewFeedPostsDeletedTick.addListener(
      _onReviewFeedPostsDeletedTick,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _feedTabListenerArmed = true;
      // 프로필 Firestore가 지연·멈추면 여기서 await 하면 피드가 영원히 시작되지 않음(무한 로딩).
      _loadFeedTabPage(0, reset: true);
      if (AuthService.instance.isLoggedIn.value) {
        unawaited(
          UserProfileService.instance.loadUserProfile().catchError((e, st) {
            if (kDebugMode) {
              debugPrint('CommunityScreen loadUserProfile: $e\n$st');
            }
          }),
        );
      }
    });
  }

  void _onFeedTabControllerTick() {
    if (!_feedTabListenerArmed) return;
    final idx = _tabController.index;
    // 애니메이션 중에도 목적 탭이 비어 있으면 곧바로 로딩 표시(빈 화면 문구 깜빡임 방지)
    if (_tabController.indexIsChanging) {
      if (_tabFeedPosts[idx].isEmpty &&
          !_tabLoadingMore[idx] &&
          !_tabInitialLoading[idx]) {
        setState(() => _tabInitialLoading[idx] = true);
      }
      return;
    }
    if (idx != _feedPrevTabIndex) {
      // 이전 탭 목록은 유지 → 다시 들어올 때 네트워크 없이 즉시 표시(스크롤 위치도 유지)
      setState(() => _postsError = null);
      _feedPrevTabIndex = idx;
    }
    _ensureFeedTabBootstrapped(idx);
  }

  /// 언어·전체 새로고침 등: 해당 탭 캐시 비우고 맨 위로
  void _purgeFeedTab(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _feedTabCount) return;
    final c = _feedScrollControllers[tabIndex];
    if (c.hasClients) {
      try {
        c.jumpTo(0);
      } catch (_) {}
    }
    setState(() {
      _tabFeedPosts[tabIndex].clear();
      _tabLastDoc[tabIndex] = null;
      _tabHasMore[tabIndex] = true;
      _tabLoadingMore[tabIndex] = false;
      _tabInitialLoading[tabIndex] = true;
      _postsError = null;
    });
  }

  void _ensureFeedTabBootstrapped(int tabIndex) {
    if (_tabFeedPosts[tabIndex].isEmpty && !_tabLoadingMore[tabIndex]) {
      _loadFeedTabPage(tabIndex, reset: false);
    }
  }

  void _onFeedScrollNearEnd(int tabIndex) {
    if (_tabController.index != tabIndex) return;
    final c = _feedScrollControllers[tabIndex];
    if (!c.hasClients) return;
    if (_tabLoadingMore[tabIndex] || !_tabHasMore[tabIndex]) return;
    // 첫 페이지는 init/bootstrap이 담당. 목록이 비어 있을 때는 extentAfter가 작아져
    // 페이징만 반복 호출되는 경우가 있어 여기서는 추가 로드를 하지 않음.
    if (_tabFeedPosts[tabIndex].isEmpty) return;
    if (c.position.extentAfter > 200) return;
    _loadFeedTabPage(tabIndex, reset: false);
  }

  /// DramaFeed 상대 시간·기타 표시용: **앱 표시 언어**를 피드 국가 키로 정규화한다.
  /// (피드 문서 로드 시 국가 필터는 쓰지 않고, Firestore `country`와 불일치해도 글이 보이게 한다.)
  String _viewerLanguageForFeed() {
    final raw = LocaleService.instance.locale;
    final t = raw.trim();
    return Post.normalizeFeedCountry(t.isEmpty ? null : t);
  }

  void _mergeIntoMasterFeeds(List<Post> incoming) {
    final ids = _freeBoardPosts.map((e) => e.id).toSet();
    for (final p in incoming) {
      if (ids.add(p.id)) {
        _freeBoardPosts.add(p);
      }
    }
    _rebuildPostCache();
  }

  Future<void> _loadFeedTabPage(int tabIndex, {required bool reset}) async {
    if (tabIndex < 0 || tabIndex >= _feedTabCount) return;
    // pull-to-refresh 등 reset이면 진행 중인 요청과 겹쳐도 새로고침은 허용
    if (_tabLoadingMore[tabIndex] && !reset) return;
    if (!reset && !_tabHasMore[tabIndex]) return;

    setState(() {
      if (reset) {
        _tabFeedPosts[tabIndex].clear();
        _tabLastDoc[tabIndex] = null;
        _tabHasMore[tabIndex] = true;
        _postsError = null;
      }
      if (_tabFeedPosts[tabIndex].isEmpty) {
        _tabInitialLoading[tabIndex] = true;
      }
      _tabLoadingMore[tabIndex] = true;
    });

    try {
      final viewerLanguage = _viewerLanguageForFeed();
      final accumulated = <Post>[];
      DocumentSnapshot<Map<String, dynamic>>? cursor = _tabLastDoc[tabIndex];
      var pageHasMore = _tabHasMore[tabIndex];

      // 클라이언트 필터로 비는 페이지가 많을 수 있어 여러 번 시도하되, 상한으로 지연 방지.
      // DramaFeed 홈은 [getPosts]의 국가 필터를 쓰지 않음(Firestore country·앱 언어 불일치로 목록이 통째로 비는 경우 방지).
      // 톡은 최근 N개가 리뷰 위주일 때 스킵이 많이 필요함.
      final maxFilterSkips = _feedBoards[tabIndex] == 'review' ? 48 : 64;
      for (var attempt = 0; attempt < maxFilterSkips; attempt++) {
        final page = await PostService.instance.getPosts(
          country: null,
          timeAgoLocale: viewerLanguage,
          type: _feedBoards[tabIndex],
          lastDocument: cursor,
          limit: 24,
        );
        pageHasMore = page.hasMore;
        cursor = page.lastDocument;
        for (final p in page.posts) {
          if (!BlockService.instance.isBlocked(p.author) &&
              !BlockService.instance.isPostBlocked(p.id)) {
            accumulated.add(p);
          }
        }
        if (accumulated.isNotEmpty ||
            !pageHasMore ||
            page.lastDocument == null) {
          break;
        }
      }
      // Firestore `hasMore`는 필터 전 문서 개수 기준이라, 필터 후 목록이 비면 hasMore가 true로 남을 수 있음.
      // 빈 리스트에서 스크롤이 끝으로 잡혀 페이징만 반복되며 로딩 스피너가 무한 표시되는 것을 막음.
      if (accumulated.isEmpty) {
        pageHasMore = false;
      }

      if (!mounted) return;
      setState(() {
        final ids = _tabFeedPosts[tabIndex].map((e) => e.id).toSet();
        for (final p in accumulated) {
          if (ids.add(p.id)) {
            _tabFeedPosts[tabIndex].add(p);
          }
        }
        _tabLastDoc[tabIndex] = cursor;
        _tabHasMore[tabIndex] = pageHasMore;
        _mergeIntoMasterFeeds(accumulated);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _postsError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _tabLoadingMore[tabIndex] = false;
          _tabInitialLoading[tabIndex] = false;
        });
      }
    }
  }

  Future<void> _refreshActiveFeedTab() async {
    final i = _tabController.index;
    await _loadFeedTabPage(i, reset: true);
  }

  void _onLocaleForFeedReload() {
    if (!mounted) return;
    _loadCurrentUserAuthor();
    for (var i = 0; i < _feedTabCount; i++) {
      _purgeFeedTab(i);
    }
    _feedPrevTabIndex = _tabController.index;
    _loadFeedTabPage(_tabController.index, reset: true);
  }

  /// _freeBoardPosts 또는 블록 목록 변경 시 글 상세용 목록 갱신
  void _rebuildPostCache() {
    _cachedFiltered = _freeBoardPosts
        .where(
          (p) =>
              !BlockService.instance.isBlocked(p.author) &&
              !BlockService.instance.isPostBlocked(p.id),
        )
        .toList();
  }

  void _applyBlockFilterToFeeds() {
    setState(() {
      for (final list in _tabFeedPosts) {
        list.removeWhere(
          (p) =>
              BlockService.instance.isBlocked(p.author) ||
              BlockService.instance.isPostBlocked(p.id),
        );
      }
      _freeBoardPosts.removeWhere(
        (p) =>
            BlockService.instance.isBlocked(p.author) ||
            BlockService.instance.isPostBlocked(p.id),
      );
      _rebuildPostCache();
    });
  }

  void _onBlockListChanged() => _applyBlockFilterToFeeds();

  void _syncPostInFeeds(Post updated) {
    setState(() {
      final i = _freeBoardPosts.indexWhere((p) => p.id == updated.id);
      if (i >= 0) {
        _freeBoardPosts[i] = updated;
      } else {
        _freeBoardPosts.insert(0, updated);
      }
      for (var t = 0; t < _feedTabCount; t++) {
        if (!postMatchesFeedFilter(updated, _feedBoards[t])) {
          _tabFeedPosts[t].removeWhere((p) => p.id == updated.id);
          continue;
        }
        final j = _tabFeedPosts[t].indexWhere((p) => p.id == updated.id);
        if (j >= 0) {
          _tabFeedPosts[t][j] = updated;
        } else {
          _tabFeedPosts[t].insert(0, updated);
        }
      }
      _rebuildPostCache();
    });
  }

  void _removePostFromAllFeeds(String id) {
    setState(() {
      _freeBoardPosts.removeWhere((p) => p.id == id);
      for (final list in _tabFeedPosts) {
        list.removeWhere((p) => p.id == id);
      }
      _rebuildPostCache();
    });
  }

  /// 드라마 상세 리뷰 탭에서 내 리뷰 삭제 시, 연동된 DramaFeed 글이 지워지면 목록에서 즉시 제거.
  void _onReviewFeedPostsDeletedTick() {
    final ids = ReviewService.instance.consumeLastDeletedFeedPostIds();
    if (!mounted || ids.isEmpty) return;
    setState(() {
      for (final id in ids) {
        _freeBoardPosts.removeWhere((p) => p.id == id);
        for (final list in _tabFeedPosts) {
          list.removeWhere((p) => p.id == id);
        }
      }
      _rebuildPostCache();
    });
  }

  void _onExternalWriteTap() => _openWritePost();

  void _onAuthChanged() {
    if (AuthService.instance.isLoggedIn.value) {
      _loadCurrentUserAuthor();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshActiveFeedTab();
        unawaited(
          UserProfileService.instance.loadUserProfile().catchError((e, st) {
            if (kDebugMode) {
              debugPrint('CommunityScreen auth loadUserProfile: $e\n$st');
            }
          }),
        );
      });
    } else if (mounted) {
      setState(() => _currentUserAuthor = null);
    }
  }

  Future<void> _loadCurrentUserAuthor() async {
    if (!AuthService.instance.isLoggedIn.value) return;
    final author = await UserProfileService.instance.getAuthorForPost();
    if (mounted) setState(() => _currentUserAuthor = author);
  }

  @override
  void dispose() {
    AuthService.instance.isLoggedIn.removeListener(_onAuthChanged);
    widget.writeNotifier?.removeListener(_onExternalWriteTap);
    BlockService.instance.removeListener(_onBlockListChanged);
    LocaleService.instance.localeNotifier.removeListener(
      _onLocaleForFeedReload,
    );
    ReviewService.instance.reviewFeedPostsDeletedTick.removeListener(
      _onReviewFeedPostsDeletedTick,
    );
    for (final c in _feedScrollControllers) {
      c.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openPost(
    Post post, {
    String? tabName,
    List<(Post, int)>? backStack,
    List<(Post, int)>? forwardStack,
    int? tabIndex,
  }) async {
    final result = await Navigator.push<PostDetailResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailPage(
          post: post,
          tabName: tabName,
          initialBackStack: backStack ?? [],
          initialForwardStack: forwardStack ?? [],
          initialTabIndex: tabIndex,
          initialBoardPosts: _cachedFiltered,
          dramaFeedTalkAskUseCardFeedLayout: _talkAskUseCardFeedLayout,
          onPostDeleted: (deleted) {
            _removePostFromAllFeeds(deleted.id);
          },
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _navBackStack = result.backStack;
        _navForwardStack = result.forwardStack;
      });
      if (result.updatedPost != null) {
        _syncPostInFeeds(result.updatedPost!);
      }
    }
  }

  Future<void> _navBack() async {
    if (_navBackStack.isEmpty) return;
    final (post, tabIndex) = _navBackStack.last;
    final newBack = List<(Post, int)>.of(_navBackStack)..removeLast();
    await _openPost(
      post,
      tabIndex: tabIndex,
      backStack: newBack,
      forwardStack: _navForwardStack,
    );
  }

  Future<void> _navForward() async {
    if (_navForwardStack.isEmpty) return;
    final (post, tabIndex) = _navForwardStack.last;
    final newForward = List<(Post, int)>.of(_navForwardStack)..removeLast();
    await _openPost(
      post,
      tabIndex: tabIndex,
      backStack: _navBackStack,
      forwardStack: newForward,
    );
  }

  Future<void> _openWritePost() async {
    if (!AuthService.instance.isLoggedIn.value) {
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (!mounted || loggedIn != true) return;
    }
    final forceReview = widget.writeOpenAsReview?.value == true;
    if (forceReview && widget.writeOpenAsReview != null) {
      widget.writeOpenAsReview!.value = false;
    }
    final initialBoard = forceReview
        ? 'review'
        : switch (_tabController.index) {
            0 => 'review',
            _ => 'talk',
          };
    final Post? post = await Navigator.push<Post>(
      context,
      MaterialPageRoute(
        builder: (_) => WritePostPage(initialBoard: initialBoard),
      ),
    );
    if (post != null && mounted) {
      final s = CountryScope.of(context).strings;
      // 즉시 목록에 노출 (낙관적 업데이트)
      _syncPostInFeeds(post);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.get('postSubmitted'),
            style: GoogleFonts.notoSansKr(),
          ),
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
        _freeBoardPosts.removeWhere((p) => p.id == post.id);
        for (final list in _tabFeedPosts) {
          list.removeWhere((p) => p.id == post.id);
        }
        _syncPostInFeeds(saved);
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
    final isDark = theme.brightness == Brightness.dark;
    final homeHeaderBarBg = AppColors.homeHeaderBarBackground(theme);
    final homeStatusOverlay = SystemUiOverlayStyle(
      statusBarColor: homeHeaderBarBg,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemStatusBarContrastEnforced: false,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: homeStatusOverlay,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: homeHeaderBarBg,
          systemOverlayStyle: homeStatusOverlay,
          elevation: 6,
          scrolledUnderElevation: 6,
          shadowColor: cs.shadow.withOpacity(0.18),
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          centerTitle: false,
          toolbarHeight: 52 * r,
          leadingWidth: 0,
          titleSpacing: 0,
          title: Transform.translate(
            offset: Offset(0, -3 * r),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 14 * r),
                child: Text(
                  'DramaFeed',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 22 * r,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: 6 * r),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CommunitySearchPage(),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(left: 4 * r, right: 6 * r),
                      child: Icon(
                        LucideIcons.search,
                        size: 20 * r,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: NotificationService.instance.unreadCount,
                    builder: (context, unread, _) {
                      return GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationScreen(),
                            ),
                          );
                          NotificationService.instance.markAllRead();
                        },
                        child: Padding(
                          padding: EdgeInsets.only(left: 6 * r, right: 6 * r),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                unread > 0
                                    ? LucideIcons.bell_dot
                                    : LucideIcons.bell,
                                size: 20 * r,
                                color: unread > 0 ? cs.primary : cs.onSurface,
                              ),
                              if (unread > 0)
                                Positioned(
                                  top: -3 * r,
                                  right: -3 * r,
                                  child: Container(
                                    padding: EdgeInsets.all(2.5 * r),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: BoxConstraints(
                                      minWidth: 14 * r,
                                      minHeight: 14 * r,
                                    ),
                                    child: Text(
                                      unread > 99 ? '99+' : '$unread',
                                      style: TextStyle(
                                        color: cs.onPrimary,
                                        fontSize: 8 * r,
                                        fontWeight: FontWeight.w700,
                                      ),
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
            preferredSize: Size.fromHeight(38 * r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _tabController.animation!,
                      builder: (context, _) {
                        final tabW = 60.0 * r;
                        final tabH = 26.0 * r;
                        final tabGap = 5.0 * r;
                        final leftPad = 14.0 * r;
                        // TabController는 드래그 중 index만으로는 리스너가 안 도므로
                        // animation을 구독해 스와이프 끝나자마자 칩·글자색이 맞게 갱신.
                        final animRaw = _tabController.animation!.value;
                        final maxSlide = (_feedTabCount - 1).toDouble();
                        final animValue =
                            animRaw.clamp(0.0, maxSlide).toDouble();
                        final idx =
                            animRaw.round().clamp(0, _feedTabCount - 1);

                        return Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: leftPad +
                                (tabW + tabGap) * (_feedTabCount - 1) +
                                tabW,
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
                                      borderRadius: BorderRadius.circular(
                                        6 * r,
                                      ),
                                    ),
                                  ),
                                ),
                                for (var i = 0; i < _feedTabCount; i++)
                                  Positioned(
                                    left: leftPad + (tabW + tabGap) * i,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap: () {
                                        if (_tabFeedPosts[i].isEmpty &&
                                            !_tabLoadingMore[i] &&
                                            !_tabInitialLoading[i]) {
                                          setState(
                                            () => _tabInitialLoading[i] = true,
                                          );
                                        }
                                        _tabController.animateTo(
                                          i,
                                          duration: Duration.zero,
                                        );
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: SizedBox(
                                        width: tabW,
                                        height: tabH,
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: cs.outline,
                                              width: 1.25 * r,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6 * r,
                                            ),
                                          ),
                                          child: Text(
                                            [
                                              s.get('tabReviews'),
                                              s.get('tabGeneral'),
                                            ][i],
                                            textHeightBehavior:
                                                const TextHeightBehavior(
                                                  applyHeightToFirstAscent:
                                                      false,
                                                  applyHeightToLastDescent:
                                                      false,
                                                ),
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 10 * r,
                                              height: 1.0,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.2,
                                              foreground: Paint()
                                                ..style = PaintingStyle.fill
                                                ..strokeWidth = 0.4
                                                ..color = (idx == i
                                                    ? cs.onInverseSurface
                                                    : cs.onSurfaceVariant),
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
                    AnimatedBuilder(
                      animation: _tabController.animation!,
                      builder: (context, _) {
                        final idx = _tabController.animation!.value
                            .round()
                            .clamp(0, _feedTabCount - 1);
                        final showLayoutToggle = idx == 1;
                        if (!showLayoutToggle) {
                          return SizedBox(width: 14 * r);
                        }
                        final tip = _talkAskUseCardFeedLayout
                            ? s.get('talkAskFeedLayoutSwitchToList')
                            : s.get('talkAskFeedLayoutSwitchToCards');
                        return Padding(
                          padding: EdgeInsets.only(right: 6 * r),
                          child: Tooltip(
                            message: tip,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => setState(
                                  () => _talkAskUseCardFeedLayout =
                                      !_talkAskUseCardFeedLayout,
                                ),
                                borderRadius: BorderRadius.circular(8 * r),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6 * r,
                                    vertical: 2 * r,
                                  ),
                                  child: Icon(
                                    _talkAskUseCardFeedLayout
                                        ? LucideIcons.menu
                                        : LucideIcons.layout_grid,
                                    size: 14 * r,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: 10 * r),
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
                    posts: _tabFeedPosts[0],
                    isLoading:
                        _tabFeedPosts[0].isEmpty &&
                        (_tabInitialLoading[0] || _tabLoadingMore[0]),
                    error: _postsError,
                    currentUserAuthor: _currentUserAuthor,
                    onRefresh: _refreshActiveFeedTab,
                    useReviewLayout: true,
                    useLetterboxdReviewLayout: true,
                    useSimpleFeedLayout: true,
                    reviewLetterboxdInlineFeed: true,
                    feedScrollController: _feedScrollControllers[0],
                    feedLoadingMore: _tabLoadingMore[0],
                    feedHasMore: _tabHasMore[0],
                    onPostUpdated: _syncPostInFeeds,
                    onPostDeleted: (Post deleted) =>
                        _removePostFromAllFeeds(deleted.id),
                    onUserBlocked: _applyBlockFilterToFeeds,
                  ),
                  FreeBoardTab(
                    posts: _tabFeedPosts[1],
                    isLoading:
                        _tabFeedPosts[1].isEmpty &&
                        (_tabInitialLoading[1] || _tabLoadingMore[1]),
                    error: _postsError,
                    currentUserAuthor: _currentUserAuthor,
                    onRefresh: _refreshActiveFeedTab,
                    useSimpleFeedLayout: true,
                    useCardFeedLayout: _talkAskUseCardFeedLayout,
                    feedScrollController: _feedScrollControllers[1],
                    feedLoadingMore: _tabLoadingMore[1],
                    feedHasMore: _tabHasMore[1],
                    onPostUpdated: _syncPostInFeeds,
                    onPostDeleted: (Post deleted) =>
                        _removePostFromAllFeeds(deleted.id),
                    onPostTap: (post) => _openPost(
                      post,
                      tabName: s.get('tabGeneral'),
                      tabIndex: 1,
                      backStack: _navBackStack,
                      forwardStack: [],
                    ),
                    onUserBlocked: _applyBlockFilterToFeeds,
                  ),
                ],
              ),
              // 하단 메인에서 '홈'일 때 < · 새로고침 · > 는 보이지 않게(트리·상태는 유지)
              ValueListenableBuilder<bool>(
                valueListenable: HomeTabVisibility.isHomeMainTabSelected,
                builder: (context, isHomeMainTab, _) {
                  return AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      final showBar = !isHomeMainTab;
                      return Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Visibility(
                          visible: showBar,
                          maintainState: true,
                          maintainAnimation: true,
                          maintainSize: false,
                          child: IgnorePointer(
                            ignoring: !showBar,
                            child: BrowserNavBar(
                              canGoBack: _navBackStack.isNotEmpty,
                              canGoForward: _navForwardStack.isNotEmpty,
                              isRefreshing:
                                  _tabLoadingMore[_tabController.index],
                              onRefresh: _refreshActiveFeedTab,
                              onBack: _navBack,
                              onForward: _navForward,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
