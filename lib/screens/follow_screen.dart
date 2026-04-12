import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'user_posts_screen.dart';

/// Letterboxd 스타일 Network — `{닉네임}'s Network` + 팔로잉/팔로워 탭.
class FollowScreen extends StatefulWidget {
  const FollowScreen({
    super.key,
    /// null이면 현재 로그인 사용자.
    this.networkOwnerUid,
    /// 타이틀용 표시 이름 (null이면 닉네임/디스플레이명 조회).
    this.ownerDisplayName,
  });

  final String? networkOwnerUid;
  final String? ownerDisplayName;

  @override
  State<FollowScreen> createState() => _FollowScreenState();
}

class _FollowScreenState extends State<FollowScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const Color _lbGreen = Color(0xFF00C030);

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

  String _effectiveOwnerUid() => widget.networkOwnerUid ?? AuthService.instance.currentUser.value?.uid ?? '';

  String _titleName(String fallback) {
    final w = widget.ownerDisplayName?.trim();
    if (w != null && w.isNotEmpty) return w;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ownerUid = _effectiveOwnerUid();

    if (ownerUid.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(s.get('followScreenTitle'), style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600)),
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              s.get('loginRequiredForFollow'),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _resolveOwnerTitle(ownerUid),
      builder: (context, titleSnap) {
        final displayName = _titleName(titleSnap.data ?? 'Member');
        final title = s.get('networkPageTitle').replaceAll('{name}', displayName);

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              title,
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            centerTitle: false,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 20, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: cs.onSurface,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: _lbGreen,
                  indicatorWeight: 3,
                  dividerColor: cs.outline.withValues(alpha: 0.15),
                  labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800, fontSize: 14),
                  unselectedLabelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w500, fontSize: 14),
                  tabs: [
                    Tab(text: s.get('tabFollowing')),
                    Tab(text: s.get('tabFollowers')),
                  ],
                ),
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _NetworkList(
                ownerUid: ownerUid,
                isFollowingTab: true,
                cs: cs,
                s: s,
                lbGreen: _lbGreen,
              ),
              _NetworkList(
                ownerUid: ownerUid,
                isFollowingTab: false,
                cs: cs,
                s: s,
                lbGreen: _lbGreen,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _resolveOwnerTitle(String ownerUid) async {
    if (widget.ownerDisplayName != null && widget.ownerDisplayName!.trim().isNotEmpty) {
      return widget.ownerDisplayName!.trim();
    }
    final pub = await FollowService.instance.getUserPublic(ownerUid);
    if (pub != null && pub.nickname.isNotEmpty && pub.nickname != ownerUid) return pub.nickname;
    return AuthService.instance.currentUser.value?.displayName?.trim() ?? 'Member';
  }
}

class _NetworkList extends StatelessWidget {
  const _NetworkList({
    required this.ownerUid,
    required this.isFollowingTab,
    required this.cs,
    required this.s,
    required this.lbGreen,
  });

  final String ownerUid;
  final bool isFollowingTab;
  final ColorScheme cs;
  final dynamic s;
  final Color lbGreen;

  @override
  Widget build(BuildContext context) {
    final col = isFollowingTab ? 'following' : 'followers';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(ownerUid).collection(col).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '${snap.error}',
                style: GoogleFonts.notoSansKr(color: cs.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                isFollowingTab ? s.get('followEmptyFollowing') : s.get('followEmptyFollowers'),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  height: 1.45,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          itemCount: docs.length,
          separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: cs.outline.withValues(alpha: 0.08)),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final rowUid = doc.id;
            final data = doc.data();
            final nick = (data['nickname'] as String?)?.trim();
            final photo = data['photoUrl'] as String?;
            final displayNick = (nick != null && nick.isNotEmpty) ? nick : rowUid;

            return _NetworkMemberRow(
              rowUid: rowUid,
              displayNickname: displayNick,
              photoUrl: photo,
              ownerUid: ownerUid,
              isFollowingTab: isFollowingTab,
              cs: cs,
              s: s,
              lbGreen: lbGreen,
            );
          },
        );
      },
    );
  }
}

class _NetworkMemberRow extends StatelessWidget {
  const _NetworkMemberRow({
    required this.rowUid,
    required this.displayNickname,
    required this.photoUrl,
    required this.ownerUid,
    required this.isFollowingTab,
    required this.cs,
    required this.s,
    required this.lbGreen,
  });

  final String rowUid;
  final String displayNickname;
  final String? photoUrl;
  final String ownerUid;
  final bool isFollowingTab;
  final ColorScheme cs;
  final dynamic s;
  final Color lbGreen;

  void _openProfile(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => UserPostsScreen(authorName: displayNickname)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewer = AuthService.instance.currentUser.value?.uid;
    final isOwnNetwork = viewer != null && viewer == ownerUid;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProfile(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _InitialsAvatar(
                nickname: displayNickname,
                photoUrl: photoUrl,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  displayNickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(LucideIcons.ellipsis, size: 20, color: cs.onSurfaceVariant),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onSelected: (value) async {
                  if (value == 'profile') {
                    _openProfile(context);
                  } else if (value == 'unfollow') {
                    await FollowService.instance.unfollowUser(rowUid);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Text(s.get('followViewProfile'), style: GoogleFonts.notoSansKr()),
                  ),
                  if (isFollowingTab && isOwnNetwork && viewer != null)
                    PopupMenuItem(
                      value: 'unfollow',
                      child: Text(
                        s.get('followUnfollow'),
                        style: GoogleFonts.notoSansKr(color: cs.error),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              if (viewer != null && viewer != rowUid)
                _TrailingFollowPlus(
                  rowUid: rowUid,
                  isFollowingTab: isFollowingTab,
                  isOwnNetwork: isOwnNetwork,
                  lbGreen: lbGreen,
                  s: s,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.nickname,
    required this.photoUrl,
  });

  final String nickname;
  final String? photoUrl;

  String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initials(nickname);
    final bg = UserProfileService.bgColorFromIndex(nickname.hashCode.abs() % 10);
    final fg = UserProfileService.iconColorFromIndex(nickname.hashCode.abs() % 10);

    final url = photoUrl?.trim();
    return ClipOval(
      child: url != null && url.isNotEmpty
          ? OptimizedNetworkImage(
              imageUrl: url,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              memCacheHeight: 96,
            )
          : Container(
              width: 48,
              height: 48,
              color: bg,
              alignment: Alignment.center,
              child: Text(
                initial,
                style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
    );
  }
}

class _TrailingFollowPlus extends StatelessWidget {
  const _TrailingFollowPlus({
    required this.rowUid,
    required this.isFollowingTab,
    required this.isOwnNetwork,
    required this.lbGreen,
    required this.s,
  });

  final String rowUid;
  final bool isFollowingTab;
  final bool isOwnNetwork;
  final Color lbGreen;
  final dynamic s;

  @override
  Widget build(BuildContext context) {
    final viewer = AuthService.instance.currentUser.value?.uid;
    if (viewer == null) return const SizedBox(width: 40);

    // 내 네트워크의 팔로잉 탭: 내가 이미 팔로우 중 → + 숨김
    if (isFollowingTab && isOwnNetwork) {
      return const SizedBox(width: 40);
    }

    return StreamBuilder<bool>(
      stream: FollowService.instance.isFollowingStream(viewer, rowUid),
      builder: (context, snap) {
        final following = snap.data ?? false;
        if (following) {
          return SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.check_circle_rounded, size: 26, color: lbGreen.withValues(alpha: 0.45)),
          );
        }
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(Icons.add_circle_outline_rounded, size: 28, color: lbGreen),
          tooltip: s.get('followButtonFollow'),
          onPressed: () => FollowService.instance.followUser(rowUid),
        );
      },
    );
  }
}
