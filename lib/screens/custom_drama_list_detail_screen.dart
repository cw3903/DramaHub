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
import '../widgets/lists_style_subpage_app_bar.dart';
import 'drama_detail_page.dart';
import 'lists_screen.dart';

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
  final img = list.coverImageUrl?.trim();
  if (img != null &&
      img.isNotEmpty &&
      (img.startsWith('http://') || img.startsWith('https://'))) {
    return true;
  }
  final c = list.coverDramaId?.trim();
  return c != null && c.isNotEmpty && list.dramaIds.contains(c);
}

String? _coverImageUrl(CustomDramaList list, String? country) {
  final img = list.coverImageUrl?.trim();
  if (img != null &&
      img.isNotEmpty &&
      (img.startsWith('http://') || img.startsWith('https://'))) {
    return img;
  }
  final c = list.coverDramaId?.trim();
  if (c == null || c.isEmpty || !list.dramaIds.contains(c)) return null;
  final u = DramaListService.instance.getDisplayImageUrl(c, country);
  if (u != null && u.isNotEmpty) return u;
  return null;
}

Future<void> _openListEditor(BuildContext context, CustomDramaList list) async {
  final ok = await Navigator.push<bool>(
    context,
    CupertinoPageRoute<bool>(
      builder: (_) => DramaListEditorScreen(existingList: list),
    ),
  );
  if (ok == true && context.mounted) {
    await CustomDramaListService.instance.loadIfNeeded(force: true);
  }
}

Future<void> _confirmDeleteList(BuildContext context, CustomDramaList list) async {
  final s = CountryScope.of(context).strings;
  final cs = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        s.get('listDeleteConfirmTitle'),
        style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
      ),
      content: Text(
        s.get('listDeleteConfirmMessage'),
        style: GoogleFonts.notoSansKr(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.get('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            s.get('delete'),
            style: TextStyle(color: cs.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final deleted = await CustomDramaListService.instance.deleteList(list.id);
  if (!context.mounted) return;
  if (deleted) {
    Navigator.pop(context);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.get('listDetailDeleteFailed'))),
    );
  }
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

/// **Lists**(탭 목록) ≠ **List**(단일 커스텀 리스트 상세). 앱바는 불투명, 표지는 앱바 **아래**에만 표시.
/// 표지 박스: 가로는 화면 전체, 세로는 가로 대비 3:2 — 이미지는 [BoxFit.cover]로 잘라 맞춤.
/// 그리드 썸네일 셀 비율은 이 화면 전용 상수로만 조정.
class CustomDramaListDetailScreen extends StatelessWidget {
  const CustomDramaListDetailScreen({super.key, required this.list});
  final CustomDramaList list;

  /// List 상세 표지 가로:세로 = 3:2 ([ListsScreen] 리스트 작성 크롭과 동일).
  static const double _coverAspectW = 3;
  static const double _coverAspectH = 2;

  /// List 상세 그리드 셀 사이 간격(가로·세로 동일). Lists 탭과 무관.
  static const double _cellGap = 7;
  static const double _cellRadius = 4.5;
  /// List 상세 그리드만의 좌우 패딩. 늘리면 4열 셀 너비가 줄어 썸네일이 작아짐(Lists 탭과 무관).
  static const double _gridHorizontalPadding = 15;
  /// List 상세 그리드 `childAspectRatio`(가로/세로). 값을 키우면 세로가 짧아져 썸네일이 작아짐.
  static const double _gridRatio = 0.74;
  /// 스캐폴드 배경 → 썸네일 띠: 검은색 쪽으로 아주 약하게만 보간 (라이트/다크 동일 비율).
  static const double _gridStripDarkenBlend = 0.14;
  /// [kListsStyleSubpageToolbarHeight] / [kListsStyleSubpageSideSlotWidth]와 동일

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
        CustomDramaListService.instance.listsNotifier,
      ]),
      builder: (context, _) {
        CustomDramaList? synced;
        for (final e in CustomDramaListService.instance.listsNotifier.value) {
          if (e.id == this.list.id) {
            synced = e;
            break;
          }
        }
        final list = synced ?? this.list;
        final uid = AuthService.instance.currentUser.value?.uid;
        final mine = CustomDramaListService.instance.listsNotifier.value
            .map((e) => e.id)
            .toSet();
        final canManageList = uid != null && mine.contains(list.id);
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
                toolbarHeight: kListsStyleSubpageToolbarHeight,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: headerBarBg,
                surfaceTintColor: Colors.transparent,
                systemOverlayStyle: statusOverlay,
                foregroundColor: barFg,
                iconTheme: IconThemeData(color: leadingMuted, size: 14),
                leadingWidth: kListsStyleSubpageSideSlotWidth,
                actionsPadding: EdgeInsets.zero,
                actions: [
                  if (canManageList)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _openListEditor(context, list),
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              s.get('edit'),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: leadingMuted,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _confirmDeleteList(context, list),
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              s.get('delete'),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: cs.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(width: kListsStyleSubpageSideSlotWidth),
                ],
                leading: SizedBox(
                  width: kListsStyleSubpageSideSlotWidth,
                  height: kListsStyleSubpageToolbarHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: kListsStyleSubpageLeadingEdgeInset,
                      right: 4,
                    ),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      behavior: HitTestBehavior.opaque,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 14,
                          color: leadingMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                title: SizedBox(
                  height:
                      kListsStyleSubpageToolbarHeight,
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

              // 표지: 앱바 아래, 가로=화면 전체·비율 3:2
              if (hasCover && coverUrl != null) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: AspectRatio(
                      aspectRatio: CustomDramaListDetailScreen._coverAspectW /
                          CustomDramaListDetailScreen._coverAspectH,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0xFF1E252E)),
                          if (coverUrl.startsWith('http'))
                            Positioned.fill(
                              child: OptimizedNetworkImage(
                                imageUrl: coverUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 1200,
                                memCacheHeight: 800,
                              ),
                            )
                          else
                            Positioned.fill(
                              child: Image.asset(
                                coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, st) =>
                                    const SizedBox.shrink(),
                              ),
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
                                  CustomDramaListDetailScreen
                                      ._gridHorizontalPadding,
                                  14,
                                  CustomDramaListDetailScreen
                                      ._gridHorizontalPadding,
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
                                  CustomDramaListDetailScreen
                                      ._gridHorizontalPadding,
                                  14,
                                  CustomDramaListDetailScreen
                                      ._gridHorizontalPadding,
                                  MediaQuery.of(context).padding.bottom + 24,
                                ),
                                child: GridView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
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
                          CustomDramaListDetailScreen._gridHorizontalPadding,
                          14,
                          CustomDramaListDetailScreen._gridHorizontalPadding,
                          MediaQuery.of(context).padding.bottom + 24,
                        ),
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
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
    const likeTextHeight = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    final textStyle = GoogleFonts.notoSansKr(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      height: 1.0,
      letterSpacing: 0.35,
      color: likeRowColor,
    );
    // 숫자 라벨: 굵기·행고를 LIKE?와 동일하게 해 세로 정렬 맞춤
    final countStyle = GoogleFonts.notoSansKr(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      height: 1.0,
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
        // 좋아요 시 하트만 채움·빨강 — 라벨·숫자는 설명 톤 유지
        final heartColor = liked ? Colors.redAccent : likeRowColor;

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
                    color: heartColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.get('listDetailLikePrompt'),
                    style: textStyle,
                    textHeightBehavior: likeTextHeight,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _listDetailLikesCountLabel(s, count),
                    style: countStyle,
                    textHeightBehavior: likeTextHeight,
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
                memCacheWidth: 184,
                memCacheHeight: 276,
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
