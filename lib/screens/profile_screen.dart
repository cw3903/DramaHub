import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../services/auth_service.dart';
import '../services/level_service.dart';
import '../models/message.dart';
import '../services/message_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/saved_service.dart';
import '../services/watch_history_service.dart';
import '../services/review_service.dart';
import '../services/share_service.dart';
import '../services/user_level_service.dart';
import '../services/user_profile_service.dart';
import '../services/theme_service.dart';
import '../services/post_service.dart';
import 'level_info_page.dart';
import 'messages_screen.dart';
import 'profile_photo_preview_page.dart';
import 'saved_screen.dart';
import 'share_settings_page.dart';
import 'language_select_screen.dart';
import 'user_posts_screen.dart';
import 'user_comments_screen.dart';
import 'my_reviews_screen.dart';
import '../models/drama.dart';
import 'drama_detail_page.dart';
import 'watched_dramas_screen.dart';
import '../utils/format_utils.dart';
import '../widgets/optimized_network_image.dart';
import '../services/country_service.dart';
import '../services/drama_list_service.dart';

final ValueNotifier<int> _profileStatsRefreshNotifier = ValueNotifier(0);

/// 가입 시 선택한 언어 코드 → 표시 이름 (프로필용)
String _signupCountryDisplayName(String? code) {
  switch (code?.toLowerCase()) {
    case 'us': return 'EN';
    case 'kr': return '한국어';
    case 'cn': return '中文';
    case 'jp': return '日本語';
    default: return code ?? '';
  }
}

void _showThemeSheet(BuildContext context, dynamic s) {
  final current = ThemeService.instance.themeModeNotifier.value;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.get('theme'),
              style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(LucideIcons.sun, color: Theme.of(ctx).colorScheme.primary),
              title: Text(s.get('themeLight'), style: GoogleFonts.notoSansKr()),
              trailing: current == ThemeMode.light ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
              onTap: () {
                ThemeService.instance.setThemeMode(ThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.moon, color: Theme.of(ctx).colorScheme.primary),
              title: Text(s.get('themeDark'), style: GoogleFonts.notoSansKr()),
              trailing: current == ThemeMode.dark ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
              onTap: () {
                ThemeService.instance.setThemeMode(ThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// 프로필 탭 - 로그인 후 표시 (UX 중심)
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ValueListenableBuilder<int>(
      valueListenable: LevelService.instance.totalPointsNotifier,
      builder: (context, totalPoints, _) {
        final level = LevelService.instance.getLevel(totalPoints);
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                _profileStatsRefreshNotifier.value++;
                await UserProfileService.instance.loadIfNeeded();
                await SavedService.instance.loadIfNeeded();
                await WatchHistoryService.instance.loadIfNeeded();
                await ReviewService.instance.loadIfNeeded();
                await Future.delayed(const Duration(milliseconds: 300));
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                // ─── 프로필 헤더 (카드 밖) ───
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Column(
                      children: [
                        // 프로필 사진 + 카메라 아이콘
                        Builder(
                          builder: (outerCtx) => ValueListenableBuilder<String?>(
                            valueListenable: UserProfileService.instance.profileImageUrlNotifier,
                            builder: (_, profileUrl, __) {
                              final hasPhoto = profileUrl != null && profileUrl.isNotEmpty;
                              return ValueListenableBuilder<int?>(
                                valueListenable: UserProfileService.instance.avatarColorNotifier,
                                builder: (_, colorIdx, __) {
                                  final bgColor = colorIdx != null
                                      ? UserProfileService.bgColorFromIndex(colorIdx)
                                      : cs.surfaceContainerHighest;
                                  final iconColor = colorIdx != null
                                      ? UserProfileService.iconColorFromIndex(colorIdx)
                                      : cs.onSurfaceVariant.withOpacity(0.6);
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: hasPhoto ? cs.surfaceContainerHighest : bgColor,
                                          border: Border.all(color: cs.outline.withOpacity(0.4), width: 2),
                                          image: hasPhoto
                                              ? DecorationImage(
                                                  image: CachedNetworkImageProvider(profileUrl!),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: hasPhoto
                                            ? null
                                            : Icon(
                                                Icons.person,
                                                size: 44,
                                                color: iconColor,
                                              ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: GestureDetector(
                                          onTap: () => _showProfilePhotoOptions(outerCtx, s, cs),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      border: Border.all(color: cs.outline.withOpacity(0.4)),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: cs.shadow.withOpacity(0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      LucideIcons.camera,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 닉네임 · 가입 국가 (미저장 시 현재 앱 국가 표시)
                        ListenableBuilder(
                          listenable: Listenable.merge([
                            UserProfileService.instance.nicknameNotifier,
                            UserProfileService.instance.signupCountryNotifier,
                          ]),
                          builder: (context, _) {
                            final nickname = UserProfileService.instance.nicknameNotifier.value?.trim() ??
                                AuthService.instance.currentUser.value?.displayName?.trim() ??
                                '';
                            final name = nickname.isEmpty ? 'DramaHub' : nickname;
                            final countryCode = UserProfileService.instance.signupCountryNotifier.value?.isNotEmpty == true
                                ? UserProfileService.instance.signupCountryNotifier.value
                                : CountryScope.maybeOf(context)?.country;
                            final countryName = (countryCode != null && countryCode.isNotEmpty)
                                ? _signupCountryDisplayName(countryCode)
                                : null;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                      letterSpacing: -0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (countryName != null && countryName.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    countryName,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        // 레벨 · 활동지수
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${s.get('level')} $level  ·  ',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ).createShader(bounds),
                              child: Icon(Icons.local_fire_department_rounded, size: 16, color: Colors.white),
                            ),
                            Text(
                              ' ${s.get('activityScore')} $totalPoints',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 커뮤니티 랭킹 (아래 줄)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.trophy, size: 14, color: const Color(0xFFFFB366)),
                            const SizedBox(width: 4),
                            Text(
                              '${s.get('communityRanking')} #${(1000 - totalPoints).clamp(1, 999)}',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // ─── 통계 카드 (내가 쓴 글, 댓글, 쪽지) ───
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color ?? cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outline.withOpacity(0.4)),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListenableBuilder(
                            listenable: Listenable.merge([
                              MessageService.instance.conversations,
                              _profileStatsRefreshNotifier,
                            ]),
                            builder: (context, child) {
                              final convList = MessageService.instance.conversations.value;
                              final messageCount = convList.length;
                              return FutureBuilder<({String postAuthor, String commentAuthor, int postCount, int commentCount})>(
                                future: () async {
                                  final base = await UserProfileService.instance.getAuthorBaseName();
                                  final postAuthor = await UserProfileService.instance.getAuthorForPost();
                                  final posts = await PostService.instance.getPostsByAuthor(postAuthor);
                                  final comments = await PostService.instance.getCommentsByAuthor(base);
                                  return (postAuthor: postAuthor, commentAuthor: base, postCount: posts.length, commentCount: comments.length);
                                }(),
                                builder: (context, snap) {
                                  final postCount = snap.data?.postCount ?? 0;
                                  final commentCount = snap.data?.commentCount ?? 0;
                                  final postAuthor = snap.data?.postAuthor ?? 'u/익명';
                                  final commentAuthor = snap.data?.commentAuthor ?? '익명';
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _StatCard(
                                          icon: LucideIcons.file_text,
                                          label: s.get('myPosts'),
                                          count: postCount,
                                          loading: snap.connectionState == ConnectionState.waiting,
                                          onTap: () => Navigator.push(
                                            context,
                                            CupertinoPageRoute(builder: (_) => UserPostsScreen(authorName: postAuthor)),
                                          ),
                                          isLight: true,
                                        ),
                                      ),
                                      Container(width: 1, height: 28, color: cs.outline.withOpacity(0.4)),
                                      Expanded(
                                        child: _StatCard(
                                          icon: LucideIcons.message_circle,
                                          label: s.get('comments'),
                                          count: commentCount,
                                          loading: snap.connectionState == ConnectionState.waiting,
                                          onTap: () => Navigator.push(
                                            context,
                                            CupertinoPageRoute(builder: (_) => UserCommentsScreen(authorName: commentAuthor)),
                                          ),
                                          isLight: true,
                                        ),
                                      ),
                                      Container(width: 1, height: 28, color: cs.outline.withOpacity(0.4)),
                                      Expanded(
                                        child: _StatCard(
                                          icon: LucideIcons.mail,
                                          label: s.get('messages'),
                                          count: messageCount,
                                          onTap: () => Navigator.push(
                                            context,
                                            CupertinoPageRoute(builder: (_) => const MessagesScreen()),
                                          ),
                                          isLight: true,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                // ─── 콘텐츠 카드: 내가 본 드라마, 내가 쓴 리뷰 ───
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WatchedDramaContentCard(
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (_) => const WatchedDramasScreen()),
                          ),
                          child: _WatchHistoryScope(
                            child: ValueListenableBuilder<List<WatchedDramaItem>>(
                              valueListenable: WatchHistoryService.instance.listNotifier,
                              builder: (context, list, _) {
                                if (list.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Container(
                                      height: 100,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(LucideIcons.film, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                            const SizedBox(height: 6),
                                            Text(
                                              CountryScope.of(context).strings.get('noWatchedDramas'),
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 12,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return ValueListenableBuilder<List<DramaItem>>(
                                  valueListenable: DramaListService.instance.listNotifier,
                                  builder: (context, _, __) {
                                    return SizedBox(
                                      height: 72,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: list.length > 4 ? 4 : list.length,
                                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                                        itemBuilder: (context, i) {
                                          final item = list[i];
                                          return _WatchedDramaThumbnail(item: item);
                                        },
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _MyReviewsContentCard(
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (_) => const MyReviewsScreen()),
                          ),
                          child: _ReviewScope(
                            child: ValueListenableBuilder<List<MyReviewItem>>(
                              valueListenable: ReviewService.instance.listNotifier,
                              builder: (context, list, _) {
                                return _MyReviewsPreview(list: list);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                // ─── 무료 시청 횟수 카드 ───
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ValueListenableBuilder<int>(
                      valueListenable: UserLevelService.instance.freeViewCredits,
                      builder: (context, credits, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFE7635C), Color(0xFFF37A48)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(LucideIcons.ticket, size: 28, color: Colors.white),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.get('freeViewCountLabel'),
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$credits',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(s.get('notReadyYet'), style: GoogleFonts.notoSansKr()),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.12),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              ShaderMask(
                                                blendMode: BlendMode.srcIn,
                                                shaderCallback: (bounds) => const LinearGradient(
                                                  colors: [Color(0xFFED6805), Color(0xFFE76A08)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ).createShader(bounds),
                                                child: const Icon(Icons.star_rounded, size: 22, color: Colors.white),
                                              ),
                                              Positioned(
                                                top: -1,
                                                right: -1,
                                                child: ShaderMask(
                                                  blendMode: BlendMode.srcIn,
                                                  shaderCallback: (bounds) => const LinearGradient(
                                                    colors: [Color(0xFFED6805), Color(0xFFE76A08)],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ).createShader(bounds),
                                                  child: SizedBox(
                                                    width: 9,
                                                    height: 9,
                                                    child: Stack(
                                                      alignment: Alignment.center,
                                                      children: [
                                                        Container(
                                                          width: 7,
                                                          height: 2,
                                                          decoration: BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius: BorderRadius.circular(1),
                                                          ),
                                                        ),
                                                        Container(
                                                          width: 2,
                                                          height: 7,
                                                          decoration: BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius: BorderRadius.circular(1),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          s.get('watchAdPlusOne'),
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFE76A08),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          LucideIcons.chevron_right,
                                          size: 16,
                                          color: const Color(0xFFE76A08),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // 메뉴 카드
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color ?? cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outline.withOpacity(0.4)),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _ProfileTile(
                        icon: LucideIcons.bookmark,
                        label: s.get('saved'),
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (_) => const SavedScreen()),
                          );
                        },
                        color: cs,
                      ),
                      _divider(cs),
                      _ProfileTile(
                        icon: LucideIcons.message_circle,
                        label: s.get('messages'),
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (_) => const MessagesScreen()),
                          );
                        },
                        color: cs,
                      ),
                      _divider(cs),
                      _ProfileTile(
                        icon: LucideIcons.award,
                        label: s.get('memberLevel'),
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (_) => const LevelInfoPage()),
                          );
                        },
                        color: cs,
                      ),
                      _divider(cs),
                      _ProfileTile(
                        icon: LucideIcons.share_2,
                        label: s.get('shareSettings'),
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (_) => const ShareSettingsPage()),
                          );
                        },
                        color: cs,
                      ),
                      _divider(cs),
                      _ProfileTile(
                        icon: LucideIcons.palette,
                        label: s.get('theme'),
                        onTap: () => _showThemeSheet(context, s),
                        color: cs,
                      ),
                      _divider(cs),
                      _ProfileTile(
                        icon: LucideIcons.languages,
                        label: s.get('language'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LanguageSelectScreen(
                                title: s.get('language'),
                                showCloseButton: true,
                              ),
                            ),
                          );
                        },
                        color: cs,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            // 로그아웃
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final s = CountryScope.of(context).strings;
                          await AuthService.instance.signOut();
                          SavedService.instance.clearForLogout();
                          MessageService.instance.clearForLogout();
                          await LevelService.instance.resetForLogout();
                          UserProfileService.instance.clearForLogout();
                          await ShareService.instance.clearForLogout();
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('last_free_board_post_time_ms');
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(s.get('logoutSuccess'), style: GoogleFonts.notoSansKr()),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: cs.inverseSurface,
                            ),
                          );
                        },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.log_out, size: 20, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            s.get('logout'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _divider(ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(left: 48),
        child: Divider(height: 1, color: cs.outline.withOpacity(0.12)),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    this.loading = false,
    this.isLight = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  final bool loading;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isLight ? cs.onSurfaceVariant : Colors.white.withOpacity(0.85);
    final labelColor = isLight ? cs.onSurfaceVariant : Colors.white.withOpacity(0.75);
    final valueColor = isLight ? cs.onSurface : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 10,
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isLight ? cs.onSurfaceVariant : Colors.white.withOpacity(0.7),
                      ),
                    )
                  : Text(
                      '$count',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 프로필 진입 시 리뷰 기록 로드
class _ReviewScope extends StatefulWidget {
  const _ReviewScope({required this.child});
  final Widget child;

  @override
  State<_ReviewScope> createState() => _ReviewScopeState();
}

class _ReviewScopeState extends State<_ReviewScope> {
  @override
  void initState() {
    super.initState();
    ReviewService.instance.loadIfNeeded();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 내가 쓴 리뷰 전용 카드 ([별] 내가 쓴 리뷰  더보기, 최대 2개 리뷰 표시)
class _MyReviewsContentCard extends StatelessWidget {
  const _MyReviewsContentCard({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.star_rounded, size: 20, color: Colors.amber),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        s.get('myReviews'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${s.get('seeMore')} ',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Icon(LucideIcons.chevron_right, size: 14, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 리뷰 미리보기 (최대 2개, 드라마명 + 별점 + 리뷰 일부)
class _MyReviewsPreview extends StatelessWidget {
  const _MyReviewsPreview({required this.list});

  final List<MyReviewItem> list;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '아직 작성한 리뷰가 없어요',
          style: GoogleFonts.notoSansKr(
        fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final displayList = list.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: displayList.map((item) => _ReviewPreviewTile(item: item)).toList(),
    );
  }
}

class _ReviewPreviewTile extends StatelessWidget {
  const _ReviewPreviewTile({required this.item});

  final MyReviewItem item;

  String _displayTitle(BuildContext context) {
    final locale = CountryScope.maybeOf(context)?.country;
    if (item.dramaId.isNotEmpty) {
      final t = DramaListService.instance.getDisplayTitle(item.dramaId, locale);
      if (t.isNotEmpty) return t;
    }
    return DramaListService.instance.getDisplayTitleByTitle(item.dramaTitle, locale);
  }

  @override
  Widget build(BuildContext context) {
    final snippet = item.comment.length > 12 ? '${item.comment.substring(0, 12)}...' : item.comment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayTitle(context),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StarRow(rating: item.rating, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        snippet,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 리뷰 탭과 동일: 황금색 둥근 별 1개 + 평점 숫자
class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating, this.size = 16});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size, color: Colors.amber),
        SizedBox(width: size * 0.25),
        Text(
          rating.toStringAsFixed(1),
          style: GoogleFonts.notoSansKr(
            fontSize: size * 0.875,
            fontWeight: FontWeight.w600,
            color: Colors.amber,
          ),
        ),
      ],
    );
  }
}

/// 프로필 진입 시 숏폼 시청 기록 로드
/// 내가 본 드라마 전용 카드 (핀 아이콘 + 행 크기, 주황색 없음)
class _WatchedDramaContentCard extends StatelessWidget {
  const _WatchedDramaContentCard({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      theme.brightness == Brightness.dark
                          ? 'assets/icons/pin_icon_dark.png'
                          : 'assets/icons/pin_icon.png',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        CountryScope.of(context).strings.get('watchedDramas'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${CountryScope.of(context).strings.get('seeMore')} ',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Icon(LucideIcons.chevron_right, size: 14, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 리뷰한 드라마 썸네일 (내가 본 드라마 = 리뷰한 드라마 카드용). 탭 시 해당 드라마 상세로 이동.
class _ReviewedDramaThumbnail extends StatelessWidget {
  const _ReviewedDramaThumbnail({required this.item});

  final MyReviewItem item;

  static const _gradients = [
    [Color(0xFF2D5A3D), Color(0xFF1E3D2C)],
    [Color(0xFF4A3F6B), Color(0xFF2E2744)],
    [Color(0xFF5C4033), Color(0xFF3D2A20)],
    [Color(0xFF2C4A6B), Color(0xFF1E3548)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[item.dramaTitle.hashCode.abs() % _gradients.length];
    const width = 88.0;
    const height = 72.0;
    final detail = _detailFromReviewItem(context, item);
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => DramaDetailPage(detail: detail, scrollToRatings: true),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

DramaDetail _detailFromReviewItem(BuildContext context, MyReviewItem item) {
  const similarList = [
    DramaItem(id: 's1', title: '사랑은 시간 뒤에 서다', subtitle: '비밀신분', views: '9.1M', rating: 4.5, isPopular: true),
    DramaItem(id: 's2', title: '폭풍같은 결혼생활', subtitle: '대여주', views: '45.3M', rating: 4.3, isNew: true),
    DramaItem(id: 's3', title: '동생이 훔친 사랑', subtitle: '로맨스', views: '2.1M', rating: 4.6, isPopular: true),
    DramaItem(id: 's4', title: '후회·집착남', subtitle: '독립적인 여성', views: '567K', rating: 3.5, isPopular: true),
  ];
  final locale = CountryScope.maybeOf(context)?.country;
  final displayTitle = item.dramaId.isNotEmpty
      ? (DramaListService.instance.getDisplayTitle(item.dramaId, locale).isNotEmpty
          ? DramaListService.instance.getDisplayTitle(item.dramaId, locale)
          : item.dramaTitle)
      : DramaListService.instance.getDisplayTitleByTitle(item.dramaTitle, locale);
  final dramaItem = DramaItem(
    id: item.dramaId,
    title: displayTitle,
    subtitle: '',
    views: '0',
    rating: item.rating,
    isPopular: false,
  );
  const fullSynopsis = '태성바이오 창립자 박창욱은 신분을 숨긴 채 청소부로 살아가고, 아들 정훈은 만삭의 아내 미연과 장차 이어질 가족의 행복을 꿈꾼다.';
  final userName = AuthService.instance.currentUser.value?.displayName?.split('@').first ?? '나';
  final myReview = DramaReview(
    id: item.id,
    userName: userName,
    rating: item.rating,
    comment: item.comment,
    timeAgo: formatTimeAgo(item.writtenAt, locale),
    likeCount: 0,
    replies: const [],
  );
  final reviews = [myReview];
  final episodes = [const DramaEpisode(number: 1, title: '1화', duration: '45분')];
  return DramaDetail(
    item: dramaItem,
    synopsis: fullSynopsis,
    year: '2024',
    genre: '',
    averageRating: item.rating,
    ratingCount: 1,
    episodes: episodes,
    reviews: reviews,
    similar: similarList,
  );
}

/// 드라마 포스터형 썸네일 (내가 본 드라마 카드용) — 저장된 URL 또는 드라마 목록에서 제목/id로 조회
class _WatchedDramaThumbnail extends StatelessWidget {
  const _WatchedDramaThumbnail({required this.item});

  final WatchedDramaItem item;

  static const _gradients = [
    [Color(0xFF2D5A3D), Color(0xFF1E3D2C)],
    [Color(0xFF4A3F6B), Color(0xFF2E2744)],
    [Color(0xFF5C4033), Color(0xFF3D2A20)],
    [Color(0xFF2C4A6B), Color(0xFF1E3548)],
  ];

  String? _resolveImageUrl(BuildContext context) {
    final country = CountryScope.maybeOf(context)?.country ?? CountryService.instance.countryNotifier.value;
    if (!item.id.startsWith('short-')) {
      final byId = DramaListService.instance.getDisplayImageUrl(item.id, country);
      if (byId != null && byId.isNotEmpty) return byId;
    }
    final byTitle = DramaListService.instance.getDisplayImageUrlByTitle(item.title, country);
    if (byTitle != null && byTitle.isNotEmpty) return byTitle;
    final url = item.imageUrl?.trim();
    if (url != null && url.isNotEmpty) return url;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[item.title.hashCode.abs() % _gradients.length];
    const width = 88.0;
    const height = 72.0;
    final imageUrl = _resolveImageUrl(context);
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    Widget child;
    if (hasImage && imageUrl!.startsWith('http')) {
      child = OptimizedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(12),
        memCacheWidth: null,
        memCacheHeight: null,
        errorWidget: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      );
    } else if (hasImage && imageUrl!.startsWith('assets/')) {
      child = Image.asset(
        imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      );
    } else {
      child = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}

class _WatchHistoryScope extends StatefulWidget {
  const _WatchHistoryScope({required this.child});
  final Widget child;

  @override
  State<_WatchHistoryScope> createState() => _WatchHistoryScopeState();
}

class _WatchHistoryScopeState extends State<_WatchHistoryScope> {
  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.loadIfNeeded();
    DramaListService.instance.loadFromAsset();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      child,
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeeMoreChip extends StatelessWidget {
  const _SeeMoreChip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = CountryScope.of(context).strings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${s.get('seeMore')} ',
          style: GoogleFonts.notoSansKr(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: cs.onSurfaceVariant,
          ),
        ),
        Icon(LucideIcons.chevron_right, size: 14, color: cs.onSurfaceVariant),
      ],
    );
  }
}

void _showProfilePhotoOptions(BuildContext context, dynamic s, ColorScheme cs) {
  final hasPhoto = UserProfileService.instance.profileImageUrlNotifier.value != null &&
      UserProfileService.instance.profileImageUrlNotifier.value!.isNotEmpty;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                s.get('changeProfilePhoto'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            ListTile(
              leading: Icon(LucideIcons.image, color: cs.primary),
              title: Text(s.get('pickFromGallery'), style: GoogleFonts.notoSansKr()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadProfileImage(context, s, cs);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(LucideIcons.trash_2, color: cs.error),
                title: Text(s.get('removePhoto'), style: GoogleFonts.notoSansKr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeProfileImage(context, s, cs);
                },
              ),
            ListTile(
              leading: Icon(LucideIcons.x, color: cs.onSurfaceVariant),
              title: Text(s.get('cancel'), style: GoogleFonts.notoSansKr()),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pickAndUploadProfileImage(BuildContext context, dynamic s, ColorScheme cs) async {
  final picker = ImagePicker();
  final xFile = await picker.pickImage(source: ImageSource.gallery);
  if (xFile == null || !context.mounted) return;
  final originalPath = xFile.path;

  while (context.mounted) {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: originalPath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: s.get('edit'),
          toolbarColor: Theme.of(context).colorScheme.surface,
          toolbarWidgetColor: Theme.of(context).colorScheme.onSurface,
        ),
        IOSUiSettings(
          title: s.get('edit'),
        ),
      ],
    );
    if (croppedFile == null || !context.mounted) return;

    final needEdit = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (ctx) => ProfilePhotoPreviewPage(
          croppedImagePath: croppedFile.path,
          originalImagePath: originalPath,
          onSave: (bytes) async {
            // ProfilePhotoPreviewPage 안에서 로딩 표시 후 업로드
            // 이 콜백이 끝나면 ProfilePhotoPreviewPage가 자동으로 pop됨
            final err = await UserProfileService.instance.uploadProfileImage(bytes);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(err ?? s.get('profilePhotoUpdated'), style: GoogleFonts.notoSansKr()),
                behavior: SnackBarBehavior.floating,
                backgroundColor: err != null ? cs.error : null,
              ),
            );
          },
          onEdit: () => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    if (needEdit != true || !context.mounted) return;
  }
}

Future<void> _removeProfileImage(BuildContext context, dynamic s, ColorScheme cs) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final err = await UserProfileService.instance.removeProfileImage();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(err ?? s.get('profilePhotoUpdated'), style: GoogleFonts.notoSansKr()),
      behavior: SnackBarBehavior.floating,
      backgroundColor: err != null ? cs.error : null,
    ),
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color.onSurface,
                ),
              ),
            ),
            Icon(LucideIcons.chevron_right, size: 18, color: color.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
