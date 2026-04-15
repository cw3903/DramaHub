import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
import '../widgets/app_delete_confirm_dialog.dart';
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
    unawaited(
      CustomDramaListService.instance.loadIfNeeded(force: true).catchError(
        (Object e, StackTrace st) {
          debugPrint('_openListEditor refresh: $e\n$st');
        },
      ),
    );
  }
}

Future<void> _confirmDeleteList(
  BuildContext context,
  CustomDramaList list,
) async {
  final s = CountryScope.of(context).strings;
  final msg =
      '${s.get('listDeleteConfirmTitle')}\n\n${s.get('listDeleteConfirmMessage')}';
  final confirmed = await showAppDeleteConfirmDialog(
    context,
    message: msg,
    cancelText: s.get('cancel'),
    confirmText: s.get('delete'),
  );
  if (confirmed != true || !context.mounted) return;
  final deleted = await CustomDramaListService.instance.deleteList(list.id);
  if (!context.mounted) return;
  if (deleted) {
    Navigator.pop(context);
  } else {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.get('listDetailDeleteFailed'))));
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

/// **Lists**(? ??) ? **List**(?? ??? ??? ??). ??? ???, ??? ?? **??**?? ??.
/// ?? ??: ??? ?? ??, ??? ?? ?? 3:2 ? ???? [BoxFit.cover]? ?? ??.
/// ??? ??? ? ??? ? ?? ?? ???? ??.
class CustomDramaListDetailScreen extends StatelessWidget {
  const CustomDramaListDetailScreen({super.key, required this.list});
  final CustomDramaList list;

  /// List ?? ?? ??:?? = 3:2 ([ListsScreen] ??? ?? ??? ??).
  static const double _coverAspectW = 3;
  static const double _coverAspectH = 2;

  /// List ?? ??? ? ?? ??(????? ??). Lists ?? ??.
  static const double _cellGap = 7;
  static const double _cellRadius = 4.5;

  /// List ?? ????? ?? ??. ??? 4? ? ??? ?? ???? ???(Lists ?? ??).
  static const double _gridHorizontalPadding = 15;

  /// List ?? ??? `childAspectRatio`(??/??). ?? ??? ??? ??? ???? ???.
  static const double _gridRatio = 0.74;

  /// ???? ?? ? ??? ?: ??? ??? ?? ???? ?? (???/?? ?? ??).
  static const double _gridStripDarkenBlend = 0.14;

  /// [kListsStyleSubpageToolbarHeight] / [kListsStyleSubpageSideSlotWidth]? ??

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = theme.scaffoldBackgroundColor;
    final gridStripBgBase =
        Color.lerp(
          pageBg,
          Colors.black,
          CustomDramaListDetailScreen._gridStripDarkenBlend,
        ) ??
        pageBg;

    /// ?? ??? ?? ?? (?? ??? [pageBg] = ????).
    final headerBarBg = isDark ? Colors.black : pageBg;
    final country =
        CountryScope.maybeOf(context)?.country ??
        UserProfileService.instance.signupCountryNotifier.value;
    final barFg = isDark ? Colors.white : cs.onSurface;

    /// ? Lists ? ? ??? ???? ? ? ??.
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
        final gridStripBg = isDark ? pageBg : gridStripBgBase;
        const likeToDividerGap = 14.0;
        const dividerToThumbGap = 14.0;

        final titleColor = isDark ? Colors.white : cs.onSurface;
        final descColor = isDark
            ? Colors.white.withValues(alpha: 0.55)
            : cs.onSurfaceVariant;
        final userMuted = hasCover
            ? Colors.white.withValues(alpha: 0.74)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.76)
                  : cs.onSurfaceVariant.withValues(alpha: 0.78));
        final thumbDividerColor = isDark
            ? Colors.white.withValues(alpha: 0.10)
            : cs.outlineVariant.withValues(alpha: 0.55);

        Widget ownerRowBlock({required EdgeInsets padding}) {
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
                            ? const Color(0xFF2C2C2C)
                            : (isDark
                                  ? const Color(0xFF2C3440)
                                  : cs.surfaceContainerHighest),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        size: 17,
                        color: hasCover
                            ? Colors.white
                            : (isDark ? Colors.white54 : cs.onSurfaceVariant),
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
              ],
            ),
          );
        }

        Widget detailsBlock({
          required EdgeInsets padding,
          double gapBelowLike = likeToDividerGap,
        }) {
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  const SizedBox(height: 16),
                  Text(
                    list.description.trim(),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      height: 1.5,
                      color: descColor,
                    ),
                  ),
                ],
                SizedBox(height: list.description.trim().isNotEmpty ? 26 : 24),
                _ListDetailLikeRow(list: list, likeRowColor: descColor),
                if (gapBelowLike > 0) SizedBox(height: gapBelowLike),
              ],
            ),
          );
        }

        final statusOverlay = SystemUiOverlayStyle(
          statusBarColor: headerBarBg,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemStatusBarContrastEnforced: false,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: statusOverlay,
          child: Scaffold(
            /// Keep the page baseline aligned with the title/details section.
            backgroundColor: pageBg,
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
                    SizedBox(
                      width: kListsStyleSubpageSideSlotWidth,
                      child: canManageList
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          _openListEditor(context, list),
                                      style: TextButton.styleFrom(
                                        minimumSize: Size.zero,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        s.get('edit'),
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: leadingMuted,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          _confirmDeleteList(context, list),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.redAccent,
                                        minimumSize: Size.zero,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        s.get('delete'),
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : null,
                    ),
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
                    height: kListsStyleSubpageToolbarHeight,
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

                // ??: ?? ??, ??=?? ????? 3:2
                if (hasCover && coverUrl != null) ...[
                  SliverToBoxAdapter(
                    child: AspectRatio(
                      aspectRatio:
                          CustomDramaListDetailScreen._coverAspectW /
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
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      pageBg.withValues(alpha: 0.0),
                                      pageBg.withValues(alpha: 0.01),
                                      pageBg.withValues(alpha: 0.03),
                                      pageBg.withValues(alpha: 0.06),
                                      pageBg.withValues(alpha: 0.12),
                                      pageBg.withValues(alpha: 0.22),
                                      pageBg.withValues(alpha: 0.38),
                                      pageBg.withValues(alpha: 0.62),
                                      pageBg.withValues(alpha: 0.82),
                                      pageBg.withValues(alpha: 0.94),
                                      pageBg,
                                    ],
                                    stops: const [
                                      0.0,
                                      0.20,
                                      0.32,
                                      0.44,
                                      0.56,
                                      0.66,
                                      0.74,
                                      0.80,
                                      0.86,
                                      0.93,
                                      1.0,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ownerRowBlock(
                              padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: pageBg,
                      child: detailsBlock(
                        padding: const EdgeInsets.fromLTRB(16, 16, 12, 0),
                        gapBelowLike: likeToDividerGap,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: pageBg,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          height: 1,
                          child: ColoredBox(color: thumbDividerColor),
                        ),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ownerRowBlock(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  18,
                                  12,
                                  0,
                                ),
                              ),
                              const SizedBox(height: 12),
                              detailsBlock(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  12,
                                  0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ColoredBox(
                          color: pageBg,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              height: 1,
                              child: ColoredBox(color: thumbDividerColor),
                            ),
                          ),
                        ),
                        ColoredBox(
                          color: gridStripBg,
                          child: list.dramaIds.isEmpty
                              ? Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    CustomDramaListDetailScreen
                                        ._gridHorizontalPadding,
                                    dividerToThumbGap,
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
                                    dividerToThumbGap,
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
                                              CustomDramaListDetailScreen
                                                  ._cellGap,
                                          mainAxisSpacing:
                                              CustomDramaListDetailScreen
                                                  ._cellGap,
                                          childAspectRatio:
                                              CustomDramaListDetailScreen
                                                  ._gridRatio,
                                        ),
                                    itemCount: list.dramaIds.length,
                                    itemBuilder: (context, index) {
                                      final id = list.dramaIds[index];
                                      final item = _listDramaItemForId(
                                        id,
                                        country,
                                      );
                                      final imageUrl =
                                          DramaListService.instance
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
                            dividerToThumbGap,
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
                                radius: CustomDramaListDetailScreen._cellRadius,
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
  const _ListDetailLikeRow({required this.list, required this.likeRowColor});

  final CustomDramaList list;

  /// ??? ?? ?? ??(???? ???).
  final Color likeRowColor;

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser.value?.uid;
    if (uid == null) return const SizedBox.shrink();

    final s = CountryScope.of(context).strings;
    final textStyle = GoogleFonts.notoSansKr(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.35,
      color: likeRowColor,
    );
    final countStyle = GoogleFonts.notoSansKr(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      height: 1.2,
      letterSpacing: 0.1,
      color: likeRowColor.withValues(alpha: 0.54),
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
        // ??? ? ??? ????? ? ?????? ?? ? ??
        final heartColor = liked ? Colors.redAccent : likeRowColor;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () =>
                CustomDramaListService.instance.toggleListLike(list.id),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    liked ? LucideIcons.heart : LucideIcons.heart,
                    size: 15,
                    color: liked ? Colors.redAccent : likeRowColor,
                    fill: liked ? 1.0 : 0.0,
                  ),
                  const SizedBox(width: 7),
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
