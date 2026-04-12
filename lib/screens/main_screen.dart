import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../services/auth_service.dart';
import '../services/home_tab_visibility.dart';
import '../models/drama.dart';
import '../services/play_to_shorts_service.dart';
import 'community_screen.dart';
import 'drama_screen.dart';
import 'shorts_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

/// 메인 화면 - 하단 4탭 (홈 / 리뷰 / 숏폼 / 프로필) + 가운데 만들기 버튼. 숏폼 숨김 시 3탭.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  /// 숏폼 탭 노출 여부. false면 하단에서만 숨김(코드는 유지). true로 바꾸면 다시 표시됨.
  static const bool showShortsTab = false;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  DramaDetail? _pendingPlayToShorts;

  // 0=홈, 1=리뷰, 2=숏폼(또는 숨김 시 없음), 3=프로필. 숨김 시 0,1,2 = 홈,리뷰,프로필
  final _navKey0 = GlobalKey<NavigatorState>();
  final _navKey1 = GlobalKey<NavigatorState>();
  final _navKey2 = GlobalKey<NavigatorState>();
  final _navKey3 = GlobalKey<NavigatorState>();

  final _shortsIsActive = ValueNotifier<bool>(false);
  final _writeNotifier = ValueNotifier<int>(0);

  GlobalKey<NavigatorState> _keyForIndex(int i) {
    if (!MainScreen.showShortsTab) {
      if (i == 0) return _navKey0;
      if (i == 1) return _navKey1;
      if (i == 2) return _navKey3; // 프로필
      return _navKey0;
    }
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
    setState(() => _selectedIndex = MainScreen.showShortsTab ? 3 : 2);
    HomeTabVisibility.isHomeMainTabSelected.value = false;
  }

  void _onTabTap(int index) {
    if (index == -1) {
      // 만들기 버튼: 홈 탭으로 이동 후 CommunityScreen의 _openWritePost 호출
      _shortsIsActive.value = false;
      setState(() => _selectedIndex = 0);
      HomeTabVisibility.isHomeMainTabSelected.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
      _shortsIsActive.value = MainScreen.showShortsTab && index == 2;
      setState(() => _selectedIndex = index);
      HomeTabVisibility.isHomeMainTabSelected.value = index == 0;
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
    if (!MainScreen.showShortsTab) return;
    final detail = PlayToShortsService.instance.takeRequest();
    if (detail != null && mounted) {
      setState(() {
        _selectedIndex = 2;
        _shortsIsActive.value = true;
        _pendingPlayToShorts = detail;
      });
      HomeTabVisibility.isHomeMainTabSelected.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navBg = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.white;

    final showShorts = MainScreen.showShortsTab;
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
          if (showShorts)
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
                            if (!mounted) return;
                            setState(() => _selectedIndex = 0);
                            HomeTabVisibility.isHomeMainTabSelected.value = true;
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
            showShortsTab: showShorts,
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

/// 하단 네비: 홈 / 리뷰 / (숏폼) / 프로필 / [만들기+]. showShortsTab false면 숏폼 없이 3탭.
class _BottomNavContent extends StatelessWidget {
  const _BottomNavContent({
    required this.currentIndex,
    required this.onTap,
    required this.theme,
    this.showShortsTab = true,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final ThemeData theme;
  final bool showShortsTab;

  static const List<IconData> _icons = [
    LucideIcons.house,
    Icons.format_list_bulleted,
    LucideIcons.circle_play,
    LucideIcons.user,
  ];

  static const String _homeOutlineAsset = 'assets/icons/nav_home_outline.png';
  static const String _homeFilledAsset = 'assets/icons/nav_home_filled.png';
  static const String _shortsOutlineAsset = 'assets/icons/nav_shorts_outline.png';
  static const String _shortsFilledAsset = 'assets/icons/nav_shorts_filled.png';

  static const double _homeIconSize = 22;
  static const double _navIconSize = 26;

  /// iconIndex: 하단 순서와 다르게 쓸 아이콘(예: 숏폼 숨김 시 2번 슬롯에 프로필 아이콘)
  Widget _buildNavIcon(int iconIndex, bool selected, Color color) {
    if (iconIndex == 1) {
      return Icon(
        selected ? Icons.format_list_bulleted_rounded : Icons.format_list_bulleted_outlined,
        size: _navIconSize,
        color: color,
      );
    }
    String? asset;
    if (iconIndex == 0) asset = selected ? _homeFilledAsset : _homeOutlineAsset;
    if (iconIndex == 2) asset = selected ? _shortsFilledAsset : _shortsOutlineAsset;
    if (asset != null) {
      final size = iconIndex == 0 ? _homeIconSize : _navIconSize;
      return Image.asset(
        asset,
        width: size,
        height: size,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (_, __, ___) => Icon(_icons[iconIndex], size: size, color: color),
      );
    }
    if (iconIndex == 3) {
      return Icon(
        selected ? Icons.person_rounded : Icons.person_outline_rounded,
        size: _navIconSize,
        color: color,
      );
    }
    return Icon(_icons[iconIndex], size: _navIconSize, color: color);
  }

  Widget _buildTabItem(BuildContext context, int index, {int? iconIndex}) {
    final cs = theme.colorScheme;
    final selected = index == currentIndex;
    final color = selected ? cs.onSurface : cs.onSurfaceVariant;
    final icon = iconIndex ?? index;
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
            child: _buildNavIcon(icon, selected, color),
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
        if (showShortsTab) _buildTabItem(context, 2),
        _buildTabItem(context, showShortsTab ? 3 : 2, iconIndex: 3),
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
