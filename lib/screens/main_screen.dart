import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../services/auth_service.dart';
import '../models/drama.dart';
import '../services/play_to_shorts_service.dart';
import 'community_screen.dart';
import 'drama_screen.dart';
import 'shorts_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
/// 메인 화면 - 하단 4탭 (홈 / 리뷰 / 숏폼 / 프로필) + 가운데 만들기 버튼
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  DramaDetail? _pendingPlayToShorts;

  // 0=홈, 1=리뷰, 2=숏폼, 3=프로필
  final _navKey0 = GlobalKey<NavigatorState>();
  final _navKey1 = GlobalKey<NavigatorState>();
  final _navKey2 = GlobalKey<NavigatorState>();
  final _navKey3 = GlobalKey<NavigatorState>();

  final _shortsIsActive = ValueNotifier<bool>(false);
  final _writeNotifier = ValueNotifier<int>(0);

  GlobalKey<NavigatorState> _keyForIndex(int i) {
    switch (i) {
      case 0: return _navKey0;
      case 1: return _navKey1;
      case 2: return _navKey2;
      case 3: return _navKey3;
      default: return _navKey0;
    }
  }

  void _goToProfile() {
    if (!mounted) return;
    _shortsIsActive.value = false;
    setState(() => _selectedIndex = 3);
  }

  void _onTabTap(int index) {
    if (index == -1) {
      // 만들기 버튼: 홈 탭으로 이동 후 CommunityScreen의 _openWritePost 호출
      _shortsIsActive.value = false;
      setState(() => _selectedIndex = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // notifier 값을 바꿔서 CommunityScreen에 신호 전달
        _writeNotifier.value = _writeNotifier.value + 1;
      });
      return;
    }
    if (index == _selectedIndex) {
      final nav = _keyForIndex(index).currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((route) => route.isFirst);
      }
    } else {
      _shortsIsActive.value = index == 2;
      setState(() => _selectedIndex = index);
    }
  }

  @override
  void initState() {
    super.initState();
    PlayToShortsService.instance.request.addListener(_onPlayToShortsRequest);
  }

  @override
  void dispose() {
    PlayToShortsService.instance.request.removeListener(_onPlayToShortsRequest);
    _shortsIsActive.dispose();
    _writeNotifier.dispose();
    super.dispose();
  }

  void _onPlayToShortsRequest() {
    final detail = PlayToShortsService.instance.takeRequest();
    if (detail != null && mounted) {
      setState(() {
        _selectedIndex = 2;
        _shortsIsActive.value = true;
        _pendingPlayToShorts = detail;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navBg = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.white;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          RepaintBoundary(
            child: Navigator(
            key: _navKey0,
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => CommunityScreen(
                onProfileTap: _goToProfile,
                writeNotifier: _writeNotifier,
              ),
            ),
          ),
          ),
          RepaintBoundary(
            child: Navigator(
            key: _navKey1,
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => const DramaScreen(),
            ),
          ),
          ),
          // 숏폼: ValueListenableBuilder를 Navigator 바깥에 둔다
          RepaintBoundary(
            child: _ShortsTab(
            navKey: _navKey2,
            isActiveNotifier: _shortsIsActive,
            pendingDetail: _pendingPlayToShorts,
            onDetailConsumed: () {
              if (mounted) setState(() => _pendingPlayToShorts = null);
            },
          ),
          ),
          RepaintBoundary(
            child: Navigator(
            key: _navKey3,
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => ValueListenableBuilder<bool>(
                valueListenable: AuthService.instance.isLoggedIn,
                builder: (_, isLoggedIn, __) => isLoggedIn
                    ? const ProfileScreen()
                    : LoginScreen(
                        onLoginSuccess: () =>
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _selectedIndex = 0);
                        }),
                      ),
              ),
            ),
          ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.5), width: 1),
          ),
        ),
        child: SafeArea(
          bottom: true,
          child: _BottomNavContent(
            currentIndex: _selectedIndex,
            onTap: _onTabTap,
            theme: theme,
          ),
        ),
      ),
    );
  }
}

/// 숏폼 탭: Navigator + ValueListenableBuilder를 분리된 StatefulWidget으로 관리
class _ShortsTab extends StatefulWidget {
  const _ShortsTab({
    required this.navKey,
    required this.isActiveNotifier,
    required this.pendingDetail,
    required this.onDetailConsumed,
  });

  final GlobalKey<NavigatorState> navKey;
  final ValueNotifier<bool> isActiveNotifier;
  final DramaDetail? pendingDetail;
  final VoidCallback onDetailConsumed;

  @override
  State<_ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends State<_ShortsTab> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isActiveNotifier,
      builder: (_, isActive, __) => Navigator(
        key: widget.navKey,
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => ShortsScreen(
            initialDetail: widget.pendingDetail,
            onInitialDetailConsumed: widget.onDetailConsumed,
            isActive: isActive,
          ),
        ),
      ),
    );
  }
}

/// 하단 네비: 홈 / 리뷰 / 숏폼 / 프로필 / [만들기+]
class _BottomNavContent extends StatelessWidget {
  const _BottomNavContent({
    required this.currentIndex,
    required this.onTap,
    required this.theme,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final ThemeData theme;

  static const List<IconData> _icons = [
    LucideIcons.house,
    LucideIcons.message_square,
    LucideIcons.circle_play,
    LucideIcons.user,
  ];

  static const String _homeOutlineAsset = 'assets/icons/nav_home_outline.png';
  static const String _homeFilledAsset = 'assets/icons/nav_home_filled.png';
  static const String _reviewOutlineAsset = 'assets/icons/nav_review_outline.png';
  static const String _reviewFilledAsset = 'assets/icons/nav_review_filled.png';
  static const String _shortsOutlineAsset = 'assets/icons/nav_shorts_outline.png';
  static const String _shortsFilledAsset = 'assets/icons/nav_shorts_filled.png';

  Widget _buildNavIcon(int index, bool selected, Color color) {
    const size = 26.0;
    String? asset;
    if (index == 0) asset = selected ? _homeFilledAsset : _homeOutlineAsset;
    if (index == 1) asset = selected ? _reviewFilledAsset : _reviewOutlineAsset;
    if (index == 2) asset = selected ? _shortsFilledAsset : _shortsOutlineAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (_, __, ___) => Icon(_icons[index], size: size, color: color),
      );
    }
    // 프로필 탭: 선택 시 채워진 아이콘 사용
    if (index == 3) {
      return Icon(
        selected ? Icons.person_rounded : Icons.person_outline_rounded,
        size: size,
        color: color,
      );
    }
    return Icon(_icons[index], size: size, color: color);
  }

  Widget _buildTabItem(BuildContext context, int index) {
    final cs = theme.colorScheme;
    final selected = index == currentIndex;
    final color = selected ? cs.onSurface : cs.onSurfaceVariant;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(index),
          borderRadius: BorderRadius.circular(30),
          splashColor: cs.onSurface.withOpacity(0.06),
          highlightColor: cs.onSurface.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 18),
            child: _buildNavIcon(index, selected, color),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildTabItem(context, 0),
        _buildTabItem(context, 1),
        _buildTabItem(context, 2),
        _buildTabItem(context, 3),
        // 맨 오른쪽 만들기 버튼
        Expanded(
          child: GestureDetector(
            onTap: () => onTap(-1),
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4500),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
