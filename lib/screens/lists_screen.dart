import 'dart:async' show unawaited;
import 'dart:io' show Directory, File;
import 'dart:math' show min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/custom_drama_list.dart';
import '../models/drama.dart';
import '../models/watchlist_item.dart';
import '../services/auth_service.dart';
import '../services/custom_drama_list_service.dart';
import '../services/drama_list_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/country_scope.dart';
import '../widgets/optimized_network_image.dart';
import 'custom_list_navigation.dart';
import 'drama_search_screen.dart';
import '../widgets/lists_style_subpage_app_bar.dart';

Future<File> _listCoverWriteTempFile(Uint8List bytes) async {
  final name = 'list_cover_${DateTime.now().microsecondsSinceEpoch}.jpg';
  final f = File('${Directory.systemTemp.path}/$name');
  await f.writeAsBytes(bytes);
  return f;
}

/// 리스트 표지 — 가로:세로 = 3:2 (상세 페이지·갤러리 크롭과 동일).
class _ListCoverCropAspectPreset implements CropAspectRatioPresetData {
  const _ListCoverCropAspectPreset();
  @override
  (int, int)? get data => (3, 2);
  @override
  String get name => 'list_cover_3x2';
}

/// 작성 화면 표지 슬롯 크기(가로형 3:2).
abstract final class _ListCoverSlot {
  static const double shortSide = 56;
  static double get longSide => shortSide * 3 / 2;
  static double get aspectRatio => 3 / 2;
}

/// Letterboxd 스타일 Lists — 상단 Lists + 필터, 카드마다 제목·편수·포스터(무간격)·설명
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
      CupertinoPageRoute<bool>(builder: (_) => const DramaListEditorScreen()),
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
    final headerBarBg = listsStyleSubpageHeaderBackground(theme);
    final listAppBarOverlay = listsStyleSubpageSystemOverlay(
      theme,
      headerBarBg,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: listAppBarOverlay,
      child: Scaffold(
        backgroundColor: bodyBg,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: s.get('tabLists'),
            onBack: () => popListsStyleSubpage(context),
            trailing: ListsStyleSubpageHeaderAddButton(
              onTap: () => _openCreateList(context, s),
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
          color: colorScheme.outline.withValues(alpha: isDark ? 0.30 : 0.22),
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
          shape: RoundedRectangleBorder(borderRadius: r, side: stripSide),
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
          Positioned.fill(child: ClipRect(child: image)),
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

  /// 마지막 콘텐츠(설명 또는 포스터+보정)와 구분선 사이.
  static const double _gapLastContentToDivider = 10;

  /// 설명 없음: 포스터만 있을 때 시각 간격이 설명 있을 때(글 줄상자 하단~구분선)에 가깝도록.
  static const double _gapBelowPosterWhenNoDescription = 7;

  static const TextHeightBehavior _listDescriptionTextHeightBehavior =
      TextHeightBehavior(applyHeightToLastDescent: false);

  final CustomDramaList data;
  final dynamic strings;
  final bool isDark;
  final ColorScheme colorScheme;
  final String? country;

  @override
  Widget build(BuildContext context) {
    final trimmedDesc = data.description.trim();
    final hasDesc = trimmedDesc.isNotEmpty;
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
        onTap: () => openCustomDramaListDetail(context, data),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FlushPosterStrip(
                    items: items,
                    country: country,
                    isDark: isDark,
                    colorScheme: cs,
                  ),
                  if (!hasDesc)
                    const SizedBox(height: _gapBelowPosterWhenNoDescription),
                  if (hasDesc) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        trimmedDesc,
                        textAlign: TextAlign.start,
                        textHeightBehavior: _listDescriptionTextHeightBehavior,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          height: 1.45,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: _gapLastContentToDivider),
          ],
        ),
      ),
    );
  }
}

/// 리스트 생성·수정 공통 화면. [existingList]가 있으면 수정 모드.
class DramaListEditorScreen extends StatefulWidget {
  const DramaListEditorScreen({super.key, this.existingList});
  final CustomDramaList? existingList;
  bool get isEditMode => existingList != null;

  @override
  State<DramaListEditorScreen> createState() => _DramaListEditorScreenState();
}

class _DramaListEditorScreenState extends State<DramaListEditorScreen> {
  static const int _kMaxDramas = 20;
  static const int _kMaxTitleLen = 100;
  static const int _kMaxDescriptionLen = 1000;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<DramaItem> _selected = [];

  /// 서버에서 온 드라마 포스터 표지(수정 모드 로드용). UI에서는 더 이상 드라마로 표지를 고르지 않음.
  String? _coverDramaId;
  /// 갤러리에서 고른 커스텀 표지(업로드 전 미리보기). 있으면 [_coverDramaId]보다 우선.
  Uint8List? _customCoverBytes;
  /// 서버에 이미 있는 커스텀 표지 URL(수정 모드 미리보기).
  String? _existingCoverImageUrl;
  final ImagePicker _coverImagePicker = ImagePicker();
  bool _saving = false;

  /// true면 저장 시 표지 없음(갤러리 미리보기 바이트/URL은 유지될 수 있음).
  bool _publishWithoutCover = true;

  bool get _noCoverSelected => _publishWithoutCover;

  bool get _galleryCoverActiveForPublish =>
      !_publishWithoutCover &&
      (_customCoverBytes != null ||
          (_existingCoverImageUrl != null &&
              _existingCoverImageUrl!.trim().isNotEmpty));

  @override
  void initState() {
    super.initState();
    final ex = widget.existingList;
    if (ex != null) {
      _titleController.text = ex.title;
      _descriptionController.text = ex.description;
      final countryGuess =
          UserProfileService.instance.signupCountryNotifier.value;
      for (final id in ex.dramaIds) {
        _selected.add(_dramaItemFromId(id, countryGuess));
      }
      final cu = ex.coverImageUrl?.trim();
      if (cu != null &&
          cu.isNotEmpty &&
          (cu.startsWith('http://') || cu.startsWith('https://'))) {
        _existingCoverImageUrl = cu;
        _publishWithoutCover = false;
      } else {
        final cdi = ex.coverDramaId?.trim();
        if (cdi != null && cdi.isNotEmpty && ex.dramaIds.contains(cdi)) {
          _coverDramaId = cdi;
          _publishWithoutCover = false;
        }
      }
    }
  }

  DramaItem _dramaItemFromId(String dramaId, String? country) {
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
    unawaited(DramaListService.instance.loadFromAsset());
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

  Future<Uint8List?> _cropListCoverFromPath(String sourcePath) async {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    const cropPreset = _ListCoverCropAspectPreset();
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 2),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: s.get('listCreateCoverCropTitle'),
          toolbarColor: theme.colorScheme.surface,
          toolbarWidgetColor: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surface,
          lockAspectRatio: true,
          aspectRatioPresets: const [cropPreset],
          initAspectRatio: cropPreset,
          cropStyle: CropStyle.rectangle,
          showCropGrid: true,
          cropGridRowCount: 2,
          cropGridColumnCount: 2,
          cropFrameColor: Colors.white,
          cropFrameStrokeWidth: 3,
          cropGridColor: Colors.white.withValues(alpha: 0.45),
          cropGridStrokeWidth: 1,
          dimmedLayerColor: Colors.black.withValues(alpha: 0.62),
        ),
        IOSUiSettings(
          title: s.get('listCreateCoverCropTitle'),
          cropStyle: CropStyle.rectangle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          aspectRatioPresets: const [cropPreset],
        ),
      ],
    );
    if (!mounted || cropped == null) return null;
    return File(cropped.path).readAsBytes();
  }

  Future<void> _pickGalleryCover() async {
    final s = CountryScope.of(context).strings;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final x = await _coverImagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (!mounted || x == null) return;

      String? path = x.path;
      if (path.isEmpty) {
        final raw = await x.readAsBytes();
        if (raw.isEmpty) return;
        path = (await _listCoverWriteTempFile(Uint8List.fromList(raw))).path;
      }

      final croppedBytes = await _cropListCoverFromPath(path);
      if (!mounted || croppedBytes == null) return;
      setState(() {
        _customCoverBytes = croppedBytes;
        _coverDramaId = null;
        _existingCoverImageUrl = null;
        _publishWithoutCover = false;
      });
    } catch (e, st) {
      debugPrint('_pickGalleryCover: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.get('listCreateCoverGalleryPickFailed'))),
      );
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final str = CountryScope.of(context).strings;
    if (AuthService.instance.currentUser.value?.uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(str.get('listCreateLoginRequired'))),
      );
      return;
    }
    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(str.get('listCreateErrorNeedTitle'))),
      );
      return;
    }
    if (_selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(str.get('listCreateErrorNeedDrama'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String? uploadedCoverUrl;
      if (_customCoverBytes != null && !_publishWithoutCover) {
        uploadedCoverUrl = await CustomDramaListService.instance
            .uploadListCoverImage(_customCoverBytes!);
        if (!mounted) return;
        if (uploadedCoverUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(str.get('listCreateCoverUploadFailed'))),
          );
          return;
        }
      }

      // updateList / createList now do optimistic local update first and fire
      // Firestore in background — so we can pop immediately without waiting.
      if (widget.isEditMode) {
        final clearAll = _publishWithoutCover;
        String? coverImageUrlArg;
        String? coverDramaIdArg;
        if (!clearAll) {
          if (uploadedCoverUrl != null) {
            coverImageUrlArg = uploadedCoverUrl;
          } else if (_galleryCoverActiveForPublish &&
              _existingCoverImageUrl != null &&
              _existingCoverImageUrl!.trim().isNotEmpty &&
              _coverDramaId == null) {
            coverImageUrlArg = _existingCoverImageUrl!.trim();
          } else if (_coverDramaId != null) {
            coverDramaIdArg = _coverDramaId;
          }
        }
        // Returns true optimistically; Firestore runs in background.
        CustomDramaListService.instance.updateList(
          listId: widget.existingList!.id,
          title: title,
          description: description,
          dramaIds: _selected.map((e) => e.id).toList(),
          coverImageUrl: coverImageUrlArg,
          coverDramaId: coverDramaIdArg,
          clearAllCovers: clearAll,
        ).ignore();
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      // createList also applies optimistic update immediately.
      CustomDramaListService.instance.createList(
        title: title,
        description: description,
        dramaIds: _selected.map((e) => e.id).toList(),
        coverDramaId: uploadedCoverUrl != null || _publishWithoutCover
            ? null
            : _coverDramaId,
        coverImageUrl: uploadedCoverUrl,
      ).ignore();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('save list failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(str.get('listCreateErrorSaveFailed'))),
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

    final headerBg = listsStyleSubpageHeaderBackground(theme);
    final listAppBarOverlay = listsStyleSubpageSystemOverlay(theme, headerBg);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: listAppBarOverlay,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: ListsStyleSubpageHeaderBar.preferredSizeOf(context),
          child: ListsStyleSubpageHeaderBar(
            title: widget.isEditMode
                ? s.get('listEditTitle')
                : s.get('listCreateTitle'),
            onBack: () => popListsStyleSubpage(context),
          ),
        ),
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
                  height: _ListCoverSlot.shortSide + 8,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _ListCoverNonePick(
                        selected: _noCoverSelected,
                        label: s.get('listCreateCoverNone'),
                        colorScheme: cs,
                        isDark: isDark,
                        onTap: () => setState(() {
                          _publishWithoutCover = true;
                          _coverDramaId = null;
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _ListCoverGallerySlot(
                          bytes: _customCoverBytes,
                          networkPreviewUrl: _existingCoverImageUrl,
                          selected: _galleryCoverActiveForPublish,
                          colorScheme: cs,
                          isDark: isDark,
                          onTap: _pickGalleryCover,
                          onClearPreview: () => setState(() {
                            _customCoverBytes = null;
                            _existingCoverImageUrl = null;
                            _publishWithoutCover = true;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        widget.isEditMode
                            ? s.get('listEditSave')
                            : s.get('listCreateSubmit'),
                      ),
              ),
            ],
          ),
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
        child: SizedBox(
          width: _ListCoverSlot.longSide,
          child: AspectRatio(
            aspectRatio: _ListCoverSlot.aspectRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: border,
                color: isDark
                    ? const Color(0xFF2C3440)
                    : cs.surfaceContainerHighest,
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
        ),
      ),
    );
  }
}

/// List 작성 — 표지: None 오른쪽 갤러리 슬롯(회색 + / 선택 시 미리보기, 탭하면 다시 고름).
class _ListCoverGallerySlot extends StatelessWidget {
  const _ListCoverGallerySlot({
    required this.bytes,
    this.networkPreviewUrl,
    required this.selected,
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
    required this.onClearPreview,
  });

  final Uint8List? bytes;
  /// 수정 모드: 서버에 올라간 커스텀 표지 URL 미리보기.
  final String? networkPreviewUrl;
  final bool selected;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onClearPreview;

  static double get _w => _ListCoverSlot.longSide;

  static Widget _networkOrAdd(ColorScheme cs, String? url) {
    final u = url?.trim();
    if (u != null &&
        u.isNotEmpty &&
        (u.startsWith('http://') || u.startsWith('https://'))) {
      return Positioned.fill(
        child: OptimizedNetworkImage(
          imageUrl: u,
          fit: BoxFit.cover,
          memCacheWidth: 252,
          memCacheHeight: 168,
          errorWidget: Center(
            child: Icon(
              Icons.add,
              size: 28,
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: Center(
        child: Icon(
          Icons.add,
          size: 28,
          color: cs.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }

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
    final hasPreview =
        bytes != null ||
        (networkPreviewUrl != null &&
            networkPreviewUrl!.trim().isNotEmpty &&
            (networkPreviewUrl!.startsWith('http://') ||
                networkPreviewUrl!.startsWith('https://')));
    // 가로 ListView 안에서 비율 유지 (표지 3:2).
    final slotAspect = _ListCoverSlot.aspectRatio;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: _w,
          child: AspectRatio(
            aspectRatio: slotAspect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: border,
                color: isDark
                    ? const Color(0xFF2C3440)
                    : cs.surfaceContainerHighest,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (bytes != null)
                      Positioned.fill(
                        child: Image.memory(
                          bytes!,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      )
                    else
                      _networkOrAdd(cs, networkPreviewUrl),
                    if (hasPreview)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onClearPreview,
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
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
      ),
    );
  }
}
