import 'dart:math' show min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/custom_drama_list.dart';
import '../models/drama.dart';
import '../models/watchlist_item.dart';
import '../services/auth_service.dart';
import '../services/custom_drama_list_service.dart';
import '../services/drama_list_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'custom_drama_list_detail_screen.dart';
import 'drama_search_screen.dart';

/// [CustomDramaListDetailScreen] 앱바와 동일 슬롯·높이·`<` 스타일.
const double _kListsAppBarToolbarHeight = 46;
const double _kListsAppBarSideSlotWidth = 108;

String _listsOwnerDisplayName() {
  final n = UserProfileService.instance.nicknameNotifier.value?.trim();
  if (n != null && n.isNotEmpty) return n;
  final d = AuthService.instance.currentUser.value?.displayName?.trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('@')) return d.split('@').first;
    return d;
  }
  return '';
}

/// Letterboxd 스타일 Lists — 상단 닉네임 + 가운데 Lists + 필터, 카드마다 제목·편수·포스터(무간격)·설명
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CustomDramaListService.instance.loadIfNeeded(force: true);
    });
  }

  Future<void> _openCreateList(BuildContext context, dynamic s) async {
    final created = await Navigator.push<bool>(
      context,
      CupertinoPageRoute<bool>(builder: (_) => const _CreateDramaListScreen()),
    );
    if (!context.mounted) return;
    if (created == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.get('listCreateSuccess'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final isDark = theme.brightness == Brightness.dark;
    final bodyBg = theme.scaffoldBackgroundColor;
    final pageBg =
        isDark ? const Color(0xFF14181C) : theme.scaffoldBackgroundColor;
    final headerBarBg = isDark ? Colors.black : pageBg;
    final barFg = isDark ? Colors.white : cs.onSurface;
    final leadingMuted = isDark
        ? Colors.white.withValues(alpha: 0.52)
        : cs.onSurface.withValues(alpha: 0.55);
    final name = _listsOwnerDisplayName();
    final topInset = MediaQuery.of(context).padding.top;
    final listAppBarOverlay = SystemUiOverlayStyle(
      statusBarColor: headerBarBg,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemStatusBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: listAppBarOverlay,
      child: Scaffold(
        backgroundColor: bodyBg,
        appBar: PreferredSize(
        preferredSize: Size.fromHeight(topInset + _kListsAppBarToolbarHeight),
        child: Material(
          color: headerBarBg,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _kListsAppBarToolbarHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _kListsAppBarSideSlotWidth,
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
                              if (name.isNotEmpty) ...[
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    name,
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        s.get('tabLists'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          color: barFg,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kListsAppBarSideSlotWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _openCreateList(context, s),
                            child: Ink(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C3440),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: Stack(
                                    children: [
                                      Align(
                                        alignment: Alignment.center,
                                        child: Container(
                                          width: 10,
                                          height: 1.7,
                                          color: Colors.white.withValues(
                                            alpha: 0.95,
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.center,
                                        child: Container(
                                          width: 1.7,
                                          height: 10,
                                          color: Colors.white.withValues(
                                            alpha: 0.95,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
          CustomDramaListService.instance.listsNotifier,
          DramaListService.instance.extraNotifier,
          UserProfileService.instance.nicknameNotifier,
          ]),
          builder: (context, _) {
          final country =
              CountryScope.maybeOf(context)?.country ??
              UserProfileService.instance.signupCountryNotifier.value;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              ..._buildCustomListCards(
                context: context,
                strings: s,
                isDark: isDark,
                colorScheme: cs,
                country: country,
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  List<Widget> _buildCustomListCards({
    required BuildContext context,
    required dynamic strings,
    required bool isDark,
    required ColorScheme colorScheme,
    required String? country,
  }) {
    final customLists = CustomDramaListService.instance.listsNotifier.value;
    if (customLists.isEmpty) return const [];
    final widgets = <Widget>[];
    for (final custom in customLists) {
      widgets.add(
        _CustomDramaListCard(
          data: custom,
          strings: strings,
          isDark: isDark,
          colorScheme: colorScheme,
          country: country,
        ),
      );
      widgets.add(
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outline.withValues(alpha: isDark ? 0.18 : 0.12),
        ),
      );
    }
    return widgets;
  }
}

/// 포스터를 가로로 이어 붙임(간격 0). 많으면 가로 스크롤.
class _FlushPosterStrip extends StatelessWidget {
  const _FlushPosterStrip({
    required this.items,
    required this.country,
    required this.isDark,
    required this.colorScheme,
  });

  final List<WatchlistItem> items;
  final String? country;
  final bool isDark;
  final ColorScheme colorScheme;

  static const double _h = 84;
  static const double _w = _h * 2 / 3;
  static const double _stripCornerRadius = 6;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final placeholder = ColoredBox(
      color: isDark ? const Color(0xFF2C3440) : cs.surfaceContainerHighest,
      child: Icon(
        LucideIcons.clock,
        size: 24,
        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    );

    final stripBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : cs.outline.withValues(alpha: 0.42);
    final stripSide = BorderSide(color: stripBorderColor, width: 1);

    if (items.isEmpty) {
      final r = BorderRadius.circular(_stripCornerRadius);
      return SizedBox(
        width: _w,
        height: _h,
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: r,
            side: stripSide,
          ),
          child: placeholder,
        ),
      );
    }

    final stripShape = items.length == 1
        ? BorderRadius.circular(_stripCornerRadius)
        : BorderRadius.horizontal(
            left: Radius.circular(_stripCornerRadius),
            right: Radius.circular(_stripCornerRadius),
          );

    return SizedBox(
      height: _h,
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Material(
            type: MaterialType.transparency,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: stripShape,
              side: stripSide,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final w in items)
                  SizedBox(
                    width: _w,
                    height: _h,
                    child: _stripCell(w, country, cs, placeholder),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stripCell(
    WatchlistItem w,
    String? country,
    ColorScheme cs,
    Widget placeholder,
  ) {
    final id = w.dramaId;
    final url =
        DramaListService.instance.getDisplayImageUrl(id, country) ??
        w.imageUrlSnapshot;
    if (url != null && url.startsWith('http')) {
      return OptimizedNetworkImage(
        imageUrl: url,
        width: _w,
        height: _h,
        fit: BoxFit.cover,
        memCacheWidth: 180,
        memCacheHeight: 270,
        errorWidget: placeholder,
      );
    }
    if (url != null && url.isNotEmpty) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        width: _w,
        height: _h,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }
    return placeholder;
  }
}

/// 리스트 작성 — 빈 슬롯(썸네일 비율 + 점선 + +). 탭 시 드라마 검색.
class _CreateListAddDramaPlaceholder extends StatelessWidget {
  const _CreateListAddDramaPlaceholder({
    required this.onTap,
    required this.colorScheme,
    required this.isDark,
  });

  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final w = _CreateListDramaThumb.thumbWidth;
    final h = _CreateListDramaThumb.thumbHeight;
    final fill = isDark ? const Color(0xFF2C3440) : cs.surfaceContainerHighest;
    final dashColor = isDark
        ? Colors.white.withValues(alpha: 0.28)
        : cs.outline.withValues(alpha: 0.45);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : cs.onSurfaceVariant.withValues(alpha: 0.55);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              CustomPaint(
                size: Size(w, h),
                painter: _DashedRoundedRectPainter(color: dashColor),
              ),
              Icon(Icons.add, size: 28, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedRectPainter extends CustomPainter {
  _DashedRoundedRectPainter({required this.color});

  final Color color;

  static const double _strokeWidth = 1.25;
  static const double _cornerRadius = 6;
  static const double _dash = 4;
  static const double _gap = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final half = _strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      size.width - _strokeWidth,
      size.height - _strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_cornerRadius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final len = min(d + _dash, metric.length);
        canvas.drawPath(metric.extractPath(d, len), paint);
        d = len + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 리스트 작성 — 선택한 드라마 썸네일 + 제거
class _CreateListDramaThumb extends StatelessWidget {
  const _CreateListDramaThumb({
    required this.item,
    required this.country,
    required this.onRemove,
    required this.isDark,
    required this.colorScheme,
  });

  static const double thumbHeight = 84;
  static double get thumbWidth => thumbHeight * 2 / 3;

  final DramaItem item;
  final String? country;
  final VoidCallback onRemove;
  final bool isDark;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final placeholder = ColoredBox(
      color: isDark ? const Color(0xFF2C3440) : cs.surfaceContainerHighest,
      child: Icon(
        LucideIcons.film,
        size: 24,
        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    );
    final url =
        DramaListService.instance.getDisplayImageUrl(item.id, country) ??
        item.imageUrl;

    final Widget image;
    if (url != null && url.startsWith('http')) {
      image = OptimizedNetworkImage(
        imageUrl: url,
        width: thumbWidth,
        height: thumbHeight,
        fit: BoxFit.cover,
        memCacheWidth: 180,
        memCacheHeight: 270,
        errorWidget: placeholder,
      );
    } else if (url != null && url.isNotEmpty) {
      image = Image.asset(
        url,
        fit: BoxFit.cover,
        width: thumbWidth,
        height: thumbHeight,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    } else {
      image = placeholder;
    }

    return SizedBox(
      width: thumbWidth,
      height: thumbHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRect(child: image),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black.withValues(alpha: 0.52),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomDramaListCard extends StatelessWidget {
  const _CustomDramaListCard({
    required this.data,
    required this.strings,
    required this.isDark,
    required this.colorScheme,
    required this.country,
  });

  final CustomDramaList data;
  final dynamic strings;
  final bool isDark;
  final ColorScheme colorScheme;
  final String? country;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final titleColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : cs.onSurface.withValues(alpha: 0.7);
    final muted = (isDark ? Colors.white : cs.onSurfaceVariant).withValues(
      alpha: isDark ? 0.55 : 0.8,
    );
    final items = data.dramaIds
        .take(20)
        .map(
          (id) => WatchlistItem(
            dramaId: id,
            addedAt: data.updatedAt,
            imageUrlSnapshot: DramaListService.instance.getDisplayImageUrl(
              id,
              country,
            ),
            titleSnapshot: DramaListService.instance.getDisplayTitle(
              id,
              country,
            ),
          ),
        )
        .toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push<void>(
            context,
            CupertinoPageRoute<void>(
              builder: (_) => CustomDramaListDetailScreen(list: data),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      data.title,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                  ),
                  Text(
                    strings
                        .get('listsFilmCount')
                        .replaceAll('{n}', '${data.dramaIds.length}'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _FlushPosterStrip(
                items: items,
                country: country,
                isDark: isDark,
                colorScheme: cs,
              ),
            ),
            if (data.description.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    data.description.trim(),
                    textAlign: TextAlign.start,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      height: 1.45,
                      color: muted,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CreateDramaListScreen extends StatefulWidget {
  const _CreateDramaListScreen();

  @override
  State<_CreateDramaListScreen> createState() => _CreateDramaListScreenState();
}

class _CreateDramaListScreenState extends State<_CreateDramaListScreen> {
  static const int _kMaxDramas = 20;
  static const int _kMaxTitleLen = 100;
  static const int _kMaxDescriptionLen = 1000;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<DramaItem> _selected = [];
  /// 리스트 상단 표지. null = 표지 없음. 반드시 [_selected]에 포함된 id만 허용.
  String? _coverDramaId;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDrama() async {
    if (_selected.length >= _kMaxDramas) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CountryScope.of(context).strings.get('listCreateErrorMaxDrama'),
          ),
        ),
      );
      return;
    }
    final remaining = _kMaxDramas - _selected.length;
    final exclude = _selected.map((e) => e.id).toSet();
    FocusManager.instance.primaryFocus?.unfocus();
    await DramaListService.instance.loadFromAsset();
    if (!mounted) return;
    final pickedList = await Navigator.push<List<DramaItem>>(
      context,
      CupertinoPageRoute<List<DramaItem>>(
        builder: (_) => DramaSearchScreen(
          pickMode: true,
          multiPickMax: remaining,
          pickExcludeDramaIds: exclude,
        ),
      ),
    );
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (pickedList == null) return;
    setState(() {
      for (final item in pickedList) {
        if (_selected.length >= _kMaxDramas) break;
        if (!_selected.any((e) => e.id == item.id)) _selected.add(item);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (AuthService.instance.currentUser.value?.uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CountryScope.of(context).strings.get('listCreateLoginRequired'),
          ),
        ),
      );
      return;
    }
    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CountryScope.of(context).strings.get('listCreateErrorNeedTitle'),
          ),
        ),
      );
      return;
    }
    if (_selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CountryScope.of(context).strings.get('listCreateErrorNeedDrama'),
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await CustomDramaListService.instance.createList(
        title: title,
        description: description,
        dramaIds: _selected.map((e) => e.id).toList(),
        coverDramaId: _coverDramaId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('createList failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CountryScope.of(context).strings.get('listCreateErrorSaveFailed'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final s = CountryScope.of(context).strings;
    final country = CountryScope.maybeOf(context)?.country;
    void unfocusFields() => FocusManager.instance.primaryFocus?.unfocus();

    return Scaffold(
      appBar: AppBar(title: Text(s.get('listCreateTitle'))),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: unfocusFields,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            TextField(
              controller: _titleController,
              maxLength: _kMaxTitleLen,
              onTapOutside: (_) => unfocusFields(),
              decoration: InputDecoration(
                labelText: s.get('listCreateFieldTitle'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 10,
              maxLength: _kMaxDescriptionLen,
              textAlignVertical: TextAlignVertical.top,
              onTapOutside: (_) => unfocusFields(),
              decoration: InputDecoration(
                alignLabelWithHint: true,
                labelText: s.get('listCreateFieldDescription'),
                floatingLabelAlignment: FloatingLabelAlignment.start,
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                s
                    .get('listCreateDramaCount')
                    .replaceAll('{count}', '${_selected.length}')
                    .replaceAll('{max}', '$_kMaxDramas'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _pickDrama,
                icon: const Icon(Icons.add),
                label: Text(s.get('listCreateAddDrama')),
              ),
            ],
          ),
          if (_selected.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CreateListAddDramaPlaceholder(
                  onTap: _pickDrama,
                  colorScheme: cs,
                  isDark: isDark,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: SizedBox(
                height: _CreateListDramaThumb.thumbHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selected.length,
                  itemBuilder: (context, index) {
                    final item = _selected[index];
                    return _CreateListDramaThumb(
                      item: item,
                      country: country,
                      isDark: isDark,
                      colorScheme: cs,
                      onRemove: () {
                        setState(() {
                          _selected.removeWhere((e) => e.id == item.id);
                          if (_coverDramaId == item.id) {
                            _coverDramaId = null;
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              s.get('listCreateCoverTitle'),
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.get('listCreateCoverHint'),
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 86,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _ListCoverNonePick(
                    selected: _coverDramaId == null,
                    label: s.get('listCreateCoverNone'),
                    colorScheme: cs,
                    isDark: isDark,
                    onTap: () => setState(() => _coverDramaId = null),
                  ),
                  for (final d in _selected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _ListCoverDramaPick(
                        item: d,
                        country: country,
                        selected: _coverDramaId == d.id,
                        colorScheme: cs,
                        isDark: isDark,
                        onTap: () => setState(() => _coverDramaId = d.id),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _create,
            child: Text(
              _saving
                  ? s.get('listCreateSubmitting')
                  : s.get('listCreateSubmit'),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _ListCoverNonePick extends StatelessWidget {
  const _ListCoverNonePick({
    required this.selected,
    required this.label,
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final border = selected
        ? Border.all(color: cs.primary, width: 2)
        : Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : cs.outline.withValues(alpha: 0.35),
            width: 1,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          width: 56,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: border,
            color: isDark ? const Color(0xFF2C3440) : cs.surfaceContainerHighest,
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListCoverDramaPick extends StatelessWidget {
  const _ListCoverDramaPick({
    required this.item,
    required this.country,
    required this.selected,
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
  });

  final DramaItem item;
  final String? country;
  final bool selected;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;

  static const double _h = 80;
  static const double _w = _h * 2 / 3;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final url = DramaListService.instance.getDisplayImageUrl(item.id, country) ??
        item.imageUrl;
    final border = selected
        ? Border.all(color: cs.primary, width: 2)
        : Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : cs.outline.withValues(alpha: 0.35),
            width: 1,
          );
    final placeholder = ColoredBox(
      color: isDark ? const Color(0xFF2C3440) : cs.surfaceContainerHighest,
      child: Icon(
        LucideIcons.film,
        size: 22,
        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          width: _w,
          height: _h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: border,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null && url.startsWith('http'))
                  OptimizedNetworkImage(
                    imageUrl: url,
                    width: _w,
                    height: _h,
                    fit: BoxFit.cover,
                    memCacheWidth: 160,
                    memCacheHeight: 240,
                    errorWidget: placeholder,
                  )
                else if (url != null && url.isNotEmpty)
                  Image.asset(
                    url,
                    fit: BoxFit.cover,
                    width: _w,
                    height: _h,
                    errorBuilder: (c, e, st) => placeholder,
                  )
                else
                  placeholder,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
