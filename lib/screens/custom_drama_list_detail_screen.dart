import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_strings.dart';
import '../models/custom_drama_list.dart';
import '../models/drama.dart';
import '../services/auth_service.dart';
import '../services/custom_drama_list_service.dart';
import '../services/drama_list_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'drama_detail_page.dart';

String _ownerName() {
  final n = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (n != null && n.isNotEmpty) return n;
  final d = AuthService.instance.currentUser.value?.displayName?.trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('@')) return d.split('@').first;
    return d;
  }
  final e = AuthService.instance.currentUser.value?.email?.trim();
  if (e != null && e.isNotEmpty) return e.split('@').first;
  return '';
}

bool _hasListCover(CustomDramaList list) {
  final c = list.coverDramaId?.trim();
  return c != null && c.isNotEmpty && list.dramaIds.contains(c);
}

String? _coverImageUrl(CustomDramaList list, String? country) {
  if (!_hasListCover(list)) return null;
  final id = list.coverDramaId!.trim();
  final u = DramaListService.instance.getDisplayImageUrl(id, country);
  if (u != null && u.isNotEmpty) return u;
  return null;
}

DramaItem _listDramaItemForId(String dramaId, String? country) {
  for (final it in DramaListService.instance.listNotifier.value) {
    if (it.id == dramaId) return it;
  }
  final title = DramaListService.instance.getDisplayTitle(dramaId, country);
  final url = DramaListService.instance.getDisplayImageUrl(dramaId, country);
  return DramaItem(
    id: dramaId,
    title: title.isNotEmpty ? title : dramaId,
    subtitle: '',
    views: '0',
    imageUrl: url,
  );
}

/// Lists(목록) ≠ List(단일 리스트). 앱바는 불투명, 표지는 앱바 **아래**에만 표시.
class CustomDramaListDetailScreen extends StatelessWidget {
  const CustomDramaListDetailScreen({super.key, required this.list});
  final CustomDramaList list;

  static const double _heroHeight = 268;
  static const double _cellGap = 4;
  static const double _cellRadius = 4.5;
  /// width/height — 값을 키우면 셀 높이가 줄어들어 썸네일이 조금 작아짐.
  static const double _gridRatio = 0.69;
  /// 스캐폴드 배경 → 썸네일 띠: 검은색 쪽으로 아주 약하게만 보간 (라이트/다크 동일 비율).
  static const double _gridStripDarkenBlend = 0.14;
  static const double _listAppBarToolbarHeight = 46;
  /// `centerTitle`이 화면 정중앙이 되도록 leading과 같은 폭을 오른쪽에 둠.
  static const double _listAppBarLeadingWidth = 108;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = theme.scaffoldBackgroundColor;
    final gridStripBgBase = Color.lerp(
          pageBg,
          Colors.black,
          CustomDramaListDetailScreen._gridStripDarkenBlend,
        ) ??
        pageBg;
    /// 상단 앱바만 순수 검정 (메타 영역은 [pageBg] = 스캐폴드).
    final headerBarBg = isDark ? Colors.black : pageBg;
    final country = CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final barFg = isDark ? Colors.white : cs.onSurface;
    /// « Lists » — 가운데 제목보다 한 톤 옅게.
    final leadingMuted = isDark
        ? Colors.white.withValues(alpha: 0.52)
        : cs.onSurface.withValues(alpha: 0.55);

    return AnimatedBuilder(
      animation: Listenable.merge([
        DramaListService.instance.listNotifier,
        UserProfileService.instance.nicknameNotifier,
        AuthService.instance.currentUser,
      ]),
      builder: (context, _) {
        final list = this.list;
        final hasCover = _hasListCover(list);
        final coverUrl = _coverImageUrl(list, country);
        final owner = _ownerName();
        final gridStripBg = gridStripBgBase;

        final titleColor = hasCover
            ? Colors.white
            : (isDark ? Colors.white : cs.onSurface);
        final descColor = hasCover
            ? Colors.white.withValues(alpha: 0.58)
            : (isDark
                ? Colors.white.withValues(alpha: 0.55)
                : cs.onSurfaceVariant);
        final userMuted = hasCover
            ? Colors.white.withValues(alpha: 0.88)
            : (isDark
                ? Colors.white.withValues(alpha: 0.88)
                : cs.onSurfaceVariant);

        Widget metaBlock({
          required EdgeInsets padding,
          double gapBelowLike = 14,
        }) {
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasCover
                            ? Colors.black.withValues(alpha: 0.35)
                            : (isDark
                                ? const Color(0xFF2C3440)
                                : cs.surfaceContainerHighest),
                        border: Border.all(
                          color: hasCover
                              ? Colors.white.withValues(alpha: 0.2)
                              : cs.outline.withValues(alpha: 0.28),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        size: 17,
                        color: hasCover
                            ? Colors.white70
                            : (isDark
                                ? Colors.white54
                                : cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        owner.isNotEmpty
                            ? owner
                            : s.get('diaryTitleWhenAnonymous'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: userMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  list.title,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                    letterSpacing: -0.3,
                    color: titleColor,
                  ),
                ),
                if (list.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    list.description.trim(),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      height: 1.5,
                      color: descColor,
                    ),
                  ),
                ],
                SizedBox(
                  height: list.description.trim().isNotEmpty ? 30 : 26,
                ),
                _ListDetailLikeRow(
                  list: list,
                  likeRowColor: descColor,
                ),
                if (gapBelowLike > 0) SizedBox(height: gapBelowLike),
              ],
            ),
          );
        }

        final statusOverlay = SystemUiOverlayStyle(
          statusBarColor: headerBarBg,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemStatusBarContrastEnforced: false,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: statusOverlay,
          child: Scaffold(
          /// 본문이 화면보다 짧을 때 아래가 비치는 색. 메타/표지는 각각 `pageBg`로 덮음.
          backgroundColor: gridStripBg,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight:
                    CustomDramaListDetailScreen._listAppBarToolbarHeight,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: headerBarBg,
                surfaceTintColor: Colors.transparent,
                systemOverlayStyle: statusOverlay,
                foregroundColor: barFg,
                iconTheme: IconThemeData(color: leadingMuted, size: 14),
                leadingWidth: CustomDramaListDetailScreen._listAppBarLeadingWidth,
                actionsPadding: EdgeInsets.zero,
                actions: const [
                  SizedBox(
                    width: CustomDramaListDetailScreen._listAppBarLeadingWidth,
                  ),
                ],
                leading: SizedBox(
                  height:
                      CustomDramaListDetailScreen._listAppBarToolbarHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 14,
                              color: leadingMuted,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                s.get('tabLists'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  height: 1.1,
                                  fontWeight: FontWeight.w500,
                                  color: leadingMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                title: SizedBox(
                  height:
                      CustomDramaListDetailScreen._listAppBarToolbarHeight,
                  child: Center(
                    child: Text(
                      s.get('listDetailScreenTitle'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: barFg,
                      ),
                    ),
                  ),
                ),
                centerTitle: true,
              ),

              // 표지: 앱바 아래에만 (설정한 경우에만)
              if (hasCover && coverUrl != null) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SizedBox(
                      height: CustomDramaListDetailScreen._heroHeight,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: const Color(0xFF1E252E)),
                          if (coverUrl.startsWith('http'))
                            OptimizedNetworkImage(
                              imageUrl: coverUrl,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              memCacheWidth: 900,
                              memCacheHeight: 540,
                            )
                          else
                            Image.asset(
                              coverUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (c, e, st) =>
                                  const SizedBox.shrink(),
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  gridStripBg.withValues(alpha: 0.22),
                                  gridStripBg.withValues(alpha: 0.88),
                                  gridStripBg,
                                ],
                                stops: const [0.35, 0.62, 0.88, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: metaBlock(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 12, 14),
                              gapBelowLike: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: gridStripBg,
                    child: SizedBox(
                      height: 14,
                      width: double.infinity,
                    ),
                  ),
                ),
              ] else
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ColoredBox(
                        color: pageBg,
                        child: metaBlock(
                          padding:
                              const EdgeInsets.fromLTRB(16, 18, 12, 0),
                        ),
                      ),
                      ColoredBox(
                        color: gridStripBg,
                        child: list.dramaIds.isEmpty
                            ? Padding(
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  14,
                                  12,
                                  MediaQuery.of(context).padding.bottom + 48,
                                ),
                                child: SizedBox(
                                  height: 220,
                                  child: Center(
                                    child: Text(
                                      s.get('listDetailEmptyGrid'),
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 15,
                                        color: isDark
                                            ? Colors.white38
                                            : cs.outline,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Padding(
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  14,
                                  12,
                                  MediaQuery.of(context).padding.bottom + 24,
                                ),
                                child: GridView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    crossAxisSpacing:
                                        CustomDramaListDetailScreen._cellGap,
                                    mainAxisSpacing:
                                        CustomDramaListDetailScreen._cellGap,
                                    childAspectRatio:
                                        CustomDramaListDetailScreen._gridRatio,
                                  ),
                                  itemCount: list.dramaIds.length,
                                  itemBuilder: (context, index) {
                                    final id = list.dramaIds[index];
                                    final item = _listDramaItemForId(
                                      id,
                                      country,
                                    );
                                    final imageUrl = DramaListService.instance
                                            .getDisplayImageUrl(
                                              id,
                                              country,
                                            ) ??
                                        item.imageUrl;
                                    return _PosterCell(
                                      imageUrl: imageUrl,
                                      radius: CustomDramaListDetailScreen
                                          ._cellRadius,
                                      onTap: () {
                                        final detail = DramaListService
                                            .instance
                                            .buildDetailForItem(
                                              item,
                                              country,
                                            );
                                        Navigator.push<void>(
                                          context,
                                          CupertinoPageRoute<void>(
                                            builder: (_) => DramaDetailPage(
                                              detail: detail,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

              if (hasCover && coverUrl != null)
                if (list.dramaIds.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ColoredBox(
                      color: gridStripBg,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 14, 32, 32),
                          child: Text(
                            s.get('listDetailEmptyGrid'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              color: isDark ? Colors.white38 : cs.outline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: gridStripBg,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          14,
                          12,
                          MediaQuery.of(context).padding.bottom + 24,
                        ),
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing:
                                CustomDramaListDetailScreen._cellGap,
                            mainAxisSpacing:
                                CustomDramaListDetailScreen._cellGap,
                            childAspectRatio:
                                CustomDramaListDetailScreen._gridRatio,
                          ),
                          itemCount: list.dramaIds.length,
                          itemBuilder: (context, index) {
                            final id = list.dramaIds[index];
                            final item = _listDramaItemForId(id, country);
                            final imageUrl =
                                DramaListService.instance.getDisplayImageUrl(
                                      id,
                                      country,
                                    ) ??
                                    item.imageUrl;
                            return _PosterCell(
                              imageUrl: imageUrl,
                              radius:
                                  CustomDramaListDetailScreen._cellRadius,
                              onTap: () {
                                final detail = DramaListService.instance
                                    .buildDetailForItem(item, country);
                                Navigator.push<void>(
                                  context,
                                  CupertinoPageRoute<void>(
                                    builder: (_) =>
                                        DramaDetailPage(detail: detail),
                                  ),
                                );
                              },
                            );
                          },
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

String _listDetailLikesCountLabel(AppStrings s, int n) {
  if (n == 1) {
    return s.get('listDetailLikesSingular').replaceAll('{n}', '1');
  }
  return s.get('listDetailLikesPlural').replaceAll('{n}', '$n');
}

class _ListDetailLikeRow extends StatelessWidget {
  const _ListDetailLikeRow({
    required this.list,
    required this.likeRowColor,
  });

  final CustomDramaList list;
  /// 설명과 같은 톤의 회색(레터박스 스타일).
  final Color likeRowColor;

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return const SizedBox.shrink();

    final s = CountryScope.of(context).strings;
    final textStyle = GoogleFonts.notoSansKr(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      height: 1.15,
      letterSpacing: 0.35,
      color: likeRowColor,
    );
    final countStyle = GoogleFonts.notoSansKr(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: 1.15,
      letterSpacing: 0.1,
      color: likeRowColor,
    );

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('custom_lists')
          .doc(list.id)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final List<String> likedBy;
        int count;
        if (data != null) {
          likedBy = List<String>.from(
            (data['likedBy'] as List<dynamic>?)?.map((e) => e.toString()) ?? [],
          );
          count = (data['likeCount'] as num?)?.toInt() ?? 0;
          if (count < likedBy.length) count = likedBy.length;
        } else {
          likedBy = list.likedBy;
          count = list.likeCount;
        }
        final liked = likedBy.contains(uid);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () =>
                CustomDramaListService.instance.toggleListLike(list.id),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 16,
                    color: likeRowColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.get('listDetailLikePrompt'),
                    style: textStyle,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _listDetailLikesCountLabel(s, count),
                    style: countStyle,
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

class _PosterCell extends StatelessWidget {
  const _PosterCell({
    required this.imageUrl,
    required this.onTap,
    this.radius = 3.0,
  });

  final String? imageUrl;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? const Color(0xFF4A5568)
        : theme.colorScheme.outline.withValues(alpha: 0.38);
    final url = imageUrl;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: 0.6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF1E252E)),
            if (url != null && url.startsWith('http'))
              OptimizedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 200,
                memCacheHeight: 300,
              )
            else if (url != null && url.isNotEmpty)
              Image.asset(
                url,
                fit: BoxFit.cover,
                errorBuilder: (c, e, st) => const SizedBox.shrink(),
              )
            else
              Center(
                child: Icon(
                  LucideIcons.tv,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
