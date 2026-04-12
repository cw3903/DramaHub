import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_compress/video_compress.dart';
import '../services/mux_service.dart';
import '../widgets/country_scope.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/user_profile_service.dart';
import '../services/locale_service.dart';
import '../services/level_service.dart';
import '../utils/post_board_utils.dart';
import '../models/drama.dart';
import '../services/drama_list_service.dart';
import 'video_select_page.dart';
import '../widgets/optimized_network_image.dart';

const int _maxTitleLength = 80;
const int _maxPhotos = 4;

class _PickFromFiles {
  const _PickFromFiles();
}

/// 자유게시판 글쓰기 (UX: 제목/내용/사진 또는 영상, 검증, 등록). initialPost 있으면 수정 모드.
class WritePostPage extends StatefulWidget {
  const WritePostPage({
    super.key,
    this.initialPost,
    this.initialCategory = 'free',
    this.initialBoard,
    this.initialVideoPath,
    this.isGif = false,
  });

  final Post? initialPost;
  /// 글쓰기 시작 시 선택된 게시판: 'free' 또는 'question'
  final String initialCategory;
  /// DramaFeed 탭 기준: 'review' | 'talk' | 'ask' ([initialPost]가 있으면 무시)
  final String? initialBoard;
  /// 영상 업로드 플로우에서 넘긴 파일 경로 (있으면 영상/GIF 업로드 모드)
  final String? initialVideoPath;
  /// true면 GIF로 업로드 (uploadPostGif)
  final bool isGif;

  @override
  State<WritePostPage> createState() => _WritePostPageState();
}

class _WritePostPageState extends State<WritePostPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _linkController = TextEditingController();
  final _reviewBodyController = TextEditingController();
  final _tagsController = TextEditingController();
  final _dramaSearchController = TextEditingController();
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _dramaSearchFocus = FocusNode();
  bool _isSubmitting = false;
  final List<XFile> _pickedImages = [];
  final ImagePicker _picker = ImagePicker();

  bool get _isEditMode => widget.initialPost != null;
  /// 영상 모드: 클립 조정에서 넘긴 영상/GIF 경로 (null이면 이미지 모드)
  String? _videoPathForUpload;
  /// 영상 미리보기용 로컬 썸네일 경로
  String? _videoThumbPath;
  /// 영상으로 등록 시 GIF 여부 (영상 선택 플로우에서 설정)
  bool _postAsGif = false;

  bool get _isVideoMode => _videoPathForUpload != null && _videoPathForUpload!.isNotEmpty;
  late String _selectedCategory;
  /// review | talk | ask
  late String _boardKind;
  String? _pickDramaId;
  String? _pickDramaTitle;
  String? _pickDramaThumb;
  double? _reviewRating;
  /// 리뷰: No spoilers ON → hasSpoiler false
  bool _noSpoilers = true;
  bool _reviewDramaLiked = false;
  bool _isFirstWatch = true;
  bool _allowReply = true;
  bool _dramaSearchExpanded = false;

  bool get _isReviewLayout => _boardKind == 'review' && !_isVideoMode;

  @override
  void initState() {
    super.initState();
    DramaListService.instance.loadFromAsset();
    _videoPathForUpload = widget.initialVideoPath;
    if (widget.initialVideoPath != null) {
      _postAsGif = widget.isGif;
      _generateLocalThumb(widget.initialVideoPath!);
    }
    final p = widget.initialPost;
    if (p != null) {
      _titleController.text = p.title;
      _bodyController.text = p.body ?? '';
      _linkController.text = p.linkUrl ?? '';
      _selectedCategory = p.category;
      final dt = postDisplayType(p);
      _boardKind = dt == 'review' ? 'review' : (dt == 'ask' ? 'ask' : 'talk');
      if (_boardKind == 'review') {
        _pickDramaId = p.dramaId;
        _pickDramaTitle = p.dramaTitle;
        _pickDramaThumb = p.dramaThumbnail;
        _reviewRating = p.rating;
        _noSpoilers = !p.hasSpoiler;
        _reviewDramaLiked = p.isLiked;
        _isFirstWatch = p.isFirstWatch;
        _allowReply = p.allowReply;
        _reviewBodyController.text = p.body ?? '';
        _tagsController.text = p.tags.join(', ');
      }
    } else {
      _boardKind = widget.initialBoard ??
          (widget.initialCategory == 'question' ? 'ask' : 'review');
      _selectedCategory = _boardKind == 'ask' ? 'question' : 'free';
    }
    _reviewBodyController.addListener(_onReviewFieldChanged);
    _tagsController.addListener(_onReviewFieldChanged);
    _dramaSearchController.addListener(_onReviewFieldChanged);
  }

  void _onReviewFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _generateLocalThumb(String videoPath) async {
    try {
      final path = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 640,
        quality: 80,
      );
      if (mounted && path != null) setState(() => _videoThumbPath = path);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_videoThumbPath != null) {
      try { File(_videoThumbPath!).deleteSync(); } catch (_) {}
    }
    _reviewBodyController.removeListener(_onReviewFieldChanged);
    _tagsController.removeListener(_onReviewFieldChanged);
    _dramaSearchController.removeListener(_onReviewFieldChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _linkController.dispose();
    _reviewBodyController.dispose();
    _tagsController.dispose();
    _dramaSearchController.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _dramaSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _showImageSourceChoice() async {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_pickedImages.length >= _maxPhotos) return;
    const _pickFromFilesSentinel = _PickFromFiles();
    final source = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Icon(LucideIcons.image, color: cs.primary),
                title: Text(
                  s.get('pickFromGallery'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(LucideIcons.folder_open, color: cs.primary),
                title: Text(
                  s.get('pickFromFiles'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, _pickFromFilesSentinel),
              ),
              ListTile(
                leading: Icon(LucideIcons.camera, color: cs.primary),
                title: Text(
                  s.get('takePhoto'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final remaining = _maxPhotos - _pickedImages.length;
      if (remaining <= 0) return;
      if (source == _pickFromFilesSentinel) {
        await _pickFromFiles();
        return;
      }
      if (source == ImageSource.gallery) {
        final files = await _picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 1200,
          limit: remaining.clamp(1, _maxPhotos),
        );
        if (files.isNotEmpty && mounted) {
          setState(() {
            for (final f in files) {
              if (_pickedImages.length >= _maxPhotos) break;
              _pickedImages.add(f);
            }
          });
        }
      } else {
        final file = await _picker.pickImage(
          source: source as ImageSource,
          imageQuality: 85,
          maxWidth: 1200,
        );
        if (file != null && mounted && _pickedImages.length < _maxPhotos) {
          setState(() => _pickedImages.add(file));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${s.get('addPhoto')}: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 파일 앱(다운로드 등)에서 이미지 선택. 에뮬레이터에 끌어넣은 사진은 여기서 선택 가능.
  Future<void> _pickFromFiles() async {
    final s = CountryScope.of(context).strings;
    final remaining = _maxPhotos - _pickedImages.length;
    if (remaining <= 0 || !mounted) return;
    try {
      // FileType.image는 기기에서 갤러리(Select photos)를 띄워 비어 보일 수 있음 → custom으로 파일 브라우저(다운로드 등) 노출
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final toAdd = <XFile>[];
      for (final pf in result.files) {
        if (toAdd.length >= remaining) break;
        toAdd.add(pf.xFile);
      }
      if (toAdd.isNotEmpty && mounted) {
        setState(() {
          for (final x in toAdd) {
            if (_pickedImages.length >= _maxPhotos) break;
            _pickedImages.add(x);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${s.get('addPhoto')}: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _pickedImages.removeAt(index));
  }

  String _typeForStorage() {
    if (_boardKind == 'review') return 'review';
    if (_boardKind == 'ask') return 'ask';
    return 'talk';
  }

  List<String> _parseTagsInput() {
    final raw = _tagsController.text.trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[,#\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<DramaItem> _dramasForSearchGrid(String? country) {
    final all = DramaListService.instance.getListForCountry(country);
    final popular = all.where((e) => e.isPopular).toList();
    final base = popular.length >= 6 ? popular : all;
    final q = _dramaSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return base.take(30).toList();
    return base
        .where((item) {
          final t = DramaListService.instance.getDisplayTitle(item.id, country).toLowerCase();
          final sub = DramaListService.instance.getDisplaySubtitle(item.id, country).toLowerCase();
          return t.contains(q) || sub.contains(q);
        })
        .take(30)
        .toList();
  }

  void _selectDramaForReview(DramaItem item, String? country) {
    final title = DramaListService.instance.getDisplayTitle(item.id, country);
    final thumb = DramaListService.instance.getDisplayImageUrl(item.id, country) ?? item.imageUrl;
    setState(() {
      _pickDramaId = item.id;
      _pickDramaTitle = title;
      _pickDramaThumb = thumb;
      _dramaSearchExpanded = false;
      _dramaSearchController.clear();
      _dramaSearchFocus.unfocus();
    });
  }

  Future<void> _onVideoTap() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => const VideoSelectPage()),
    );
    if (!mounted || result == null) return;
    // 클립 조정에서 path·isGif만 돌려받음 → 같은 글쓰기 화면에 영상만 반영 (제목/내용 유지)
    if (result is Map) {
      final path = result['path'] as String?;
      if (path != null && path.isNotEmpty) {
        setState(() {
          _videoPathForUpload = path;
          _postAsGif = result['isGif'] == true;
        });
        _generateLocalThumb(path);
      }
      return;
    }
    // 예전 플로우: Post가 반환된 경우(등록 완료) → 상위로 전달
    if (result is Post) {
      Navigator.pop(context, result);
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    _titleFocus.unfocus();
    _bodyFocus.unfocus();
    if (!_isReviewLayout) {
      if (!_formKey.currentState!.validate()) return;
    }

    final s = CountryScope.of(context).strings;
    if (_isReviewLayout) {
      if (_pickDramaId == null || _pickDramaId!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('reviewNeedDrama'), style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if ((_reviewRating ?? 0) <= 0) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.get('ratingLabel'), style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700)),
            content: Text(s.get('reviewPleaseSelectRating'), style: GoogleFonts.notoSansKr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.get('ok'), style: GoogleFonts.notoSansKr()),
              ),
            ],
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    await Future.delayed(const Duration(milliseconds: 400));

    try {
    // 영상/GIF 업로드 모드 (클립 조정에서 진입)
    if (_isVideoMode && _videoPathForUpload != null) {
      String uploadPath = _videoPathForUpload!;
      String? compressedPath;
      String? contentUriTempPath;

      void showStatus(String msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.notoSansKr()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 120),
        ));
      }

      // ── Android content:// URI → 임시 파일로 복사 (File(path)로는 읽을 수 없음) ──
      if (uploadPath.startsWith('content://') || uploadPath.startsWith('content:')) {
        showStatus('영상 준비 중…');
        try {
          final xfile = XFile(uploadPath);
          final bytes = await xfile.readAsBytes();
          if (bytes.isEmpty) throw Exception('영상 파일을 읽을 수 없습니다.');
          final ext = xfile.name.contains('.') ? xfile.name.split('.').last.toLowerCase() : 'mp4';
          final temp = File('${Directory.systemTemp.path}/drama_hub_video_${DateTime.now().millisecondsSinceEpoch}.$ext');
          await temp.writeAsBytes(bytes);
          contentUriTempPath = temp.path;
          uploadPath = contentUriTempPath;
        } catch (e) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('영상 준비 실패'),
                content: SingleChildScrollView(child: Text(e.toString())),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
              ),
            );
          }
          return;
        }
        if (!mounted) { setState(() => _isSubmitting = false); return; }
      }

      // ── 1. 압축 (Mux 쓸 때는 생략 → Mux가 서버에서 변환하므로 훨씬 빠름) ──
      final useMux = !_postAsGif && MuxService.isConfigured;
      if (!_postAsGif && !useMux) {
        showStatus('영상 압축 중…');
        try {
          final info = await VideoCompress.compressVideo(
            uploadPath,
            quality: VideoQuality.LowQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          final compressed = info?.path;
          if (compressed != null) {
            compressedPath = compressed;
            uploadPath = compressedPath;
          }
        } catch (_) {}
      }

      if (!mounted) { setState(() => _isSubmitting = false); return; }

      String videoUrl;
      String? thumbnailUrl;

      // ── 2a. Mux 업로드 (원본 그대로 업로드 → 변환은 Mux 서버에서) ──
      if (useMux) {
        try {
          showStatus('영상 업로드 중…');
          final playbackId = await MuxService.instance.uploadAndGetPlaybackId(
            uploadPath,
          );
          if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
          videoUrl = MuxService.hlsUrl(playbackId);
          thumbnailUrl = MuxService.thumbnailUrl(playbackId);
        } catch (e) {
          if (compressedPath != null) { try { await File(compressedPath).delete(); } catch (_) {} }
          if (contentUriTempPath != null) { try { await File(contentUriTempPath).delete(); } catch (_) {} }
          if (mounted) {
            setState(() => _isSubmitting = false);
            final message = e is MuxAssetLimitException
                ? e.toString()
                : '영상 업로드 실패: $e';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(message, style: GoogleFonts.notoSansKr()),
              behavior: SnackBarBehavior.floating,
              duration: e is MuxAssetLimitException ? const Duration(seconds: 6) : const Duration(seconds: 4),
            ));
          }
          return;
        }
      }
      // ── 2b. Firebase 업로드 (GIF 또는 Mux 미설정 시 폴백) ──
      else {
        showStatus('영상 업로드 중…');
        String videoUrlFromUpload;
        try {
          videoUrlFromUpload = _postAsGif
              ? await PostService.instance.uploadPostGif(uploadPath)
              : await PostService.instance.uploadPostVideo(uploadPath);
        } catch (e) {
          if (compressedPath != null) { try { await File(compressedPath).delete(); } catch (_) {} }
          if (contentUriTempPath != null) { try { await File(contentUriTempPath).delete(); } catch (_) {} }
          if (mounted) {
            setState(() => _isSubmitting = false);
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('영상 업로드 실패'),
                content: SingleChildScrollView(child: Text(e.toString())),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
              ),
            );
          }
          return;
        }
        if (!mounted) { setState(() => _isSubmitting = false); return; }
        videoUrl = videoUrlFromUpload;
        // 썸네일 생성 & 업로드
        try {
          final thumbPath = await VideoThumbnail.thumbnailFile(
            video: uploadPath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 640,
            quality: 75,
          );
          if (thumbPath != null && mounted) {
            thumbnailUrl = await PostService.instance.uploadPostVideoThumbnail(thumbPath);
            try { await File(thumbPath).delete(); } catch (_) {}
          }
        } catch (_) {}
      }

      if (compressedPath != null) { try { await File(compressedPath).delete(); } catch (_) {} }
      if (contentUriTempPath != null) { try { await File(contentUriTempPath).delete(); } catch (_) {} }
      if (!mounted) { setState(() => _isSubmitting = false); return; }

      await UserProfileService.instance.loadIfNeeded();
      final nickname = UserProfileService.instance.nicknameNotifier.value;
      final displayName = AuthService.instance.currentUser.value?.displayName;
      final email = AuthService.instance.currentUser.value?.email;
      String authorName = nickname?.trim().isNotEmpty == true
          ? nickname!.trim()
          : (displayName?.trim().isNotEmpty == true ? displayName!.trim() : (email != null ? email.split('@').first : ''));
      if (authorName.isEmpty) authorName = '익명';
      final linkTrimmed = _linkController.text.trim();
      final post = Post(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        subreddit: s.get('freeBoardPlaceholder'),
        author: 'u/$authorName',
        timeAgo: s.get('soon'),
        votes: 0,
        comments: 0,
        hasImage: false,
        imageUrls: const [],
        hasVideo: true,
        videoUrl: videoUrl,
        videoThumbnailUrl: thumbnailUrl,
        isGif: _postAsGif,
        body: _bodyController.text.trim(),
        linkUrl: linkTrimmed.isEmpty ? null : linkTrimmed,
        authorLevel: LevelService.instance.currentLevel.clamp(1, 30),
        category: _selectedCategory,
        type: 'talk',
        isLiked: false,
        isFirstWatch: true,
        tags: const [],
        allowReply: true,
        authorPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
        authorAvatarColorIndex: UserProfileService.instance.avatarColorNotifier.value,
        country: UserProfileService.instance.signupCountryNotifier.value ?? LocaleService.instance.locale,
      );
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      Navigator.pop(context, post);
      return;
    }

    // 이미지 업로드 (Firebase Storage) + 크기 저장 (레딧처럼 가로 꽉, 세로는 비율에 따라)
    List<String> imageUrls = [];
    List<List<int>>? imageDimensions;
    if (_pickedImages.isNotEmpty) {
      try {
        final result = await PostService.instance.uploadPostImages(_pickedImages);
        imageUrls = result.urls;
        imageDimensions = result.dimensions.every((d) => d.length >= 2 && d[0] > 0 && d[1] > 0)
            ? result.dimensions
            : null;
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('사진 업로드 실패'),
              content: SingleChildScrollView(child: Text(e.toString())),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
            ),
          );
        }
        return;
      }
    }

    await UserProfileService.instance.loadIfNeeded();
    final nickname = UserProfileService.instance.nicknameNotifier.value;
    final displayName = AuthService.instance.currentUser.value?.displayName;
    final email = AuthService.instance.currentUser.value?.email;
    String authorName = nickname?.trim().isNotEmpty == true
        ? nickname!.trim()
        : (displayName?.trim().isNotEmpty == true ? displayName!.trim() : (email != null ? email.split('@').first : ''));
    if (authorName.isEmpty) authorName = '익명';

    final linkTrimmed = _linkController.text.trim();
    if (_isEditMode && widget.initialPost != null) {
      final base = widget.initialPost!;
      final updated = base.copyWith(
        title: _isReviewLayout && (_pickDramaTitle?.isNotEmpty ?? false)
            ? _pickDramaTitle!.trim()
            : _titleController.text.trim(),
        hasImage: imageUrls.isNotEmpty || base.imageUrls.isNotEmpty,
        imageUrls: imageUrls.isNotEmpty ? imageUrls : base.imageUrls,
        imageDimensions: imageDimensions ?? base.imageDimensions,
        body: _isReviewLayout ? _reviewBodyController.text.trim() : _bodyController.text.trim(),
        linkUrl: linkTrimmed.isEmpty ? null : linkTrimmed,
        category: _selectedCategory,
        type: _typeForStorage(),
        dramaId: _boardKind == 'review' ? _pickDramaId : null,
        dramaTitle: _boardKind == 'review' ? _pickDramaTitle : null,
        dramaThumbnail: _boardKind == 'review' ? _pickDramaThumb : null,
        rating: _boardKind == 'review' ? _reviewRating : null,
        hasSpoiler: _boardKind == 'review' ? !_noSpoilers : false,
        isLiked: _boardKind == 'review' ? _reviewDramaLiked : base.isLiked,
        isFirstWatch: _boardKind == 'review' ? _isFirstWatch : base.isFirstWatch,
        tags: _boardKind == 'review' ? _parseTagsInput() : base.tags,
        allowReply: _boardKind == 'review' ? _allowReply : base.allowReply,
      );
      final result = await PostService.instance.updatePost(updated);
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('postEditSuccess'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
        );
        Navigator.pop(context, result);
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('postEditFailed'), style: GoogleFonts.notoSansKr()), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    final reviewTitle = (_pickDramaTitle?.trim().isNotEmpty ?? false) ? _pickDramaTitle!.trim() : '';
    final post = Post(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _isReviewLayout ? reviewTitle : _titleController.text.trim(),
      subreddit: _boardKind == 'review' ? s.get('tabReviews') : s.get('freeBoardPlaceholder'),
      author: 'u/$authorName',
      timeAgo: s.get('soon'),
      votes: 0,
      comments: 0,
      hasImage: imageUrls.isNotEmpty,
      imageUrls: imageUrls,
      imageDimensions: imageDimensions,
      body: _isReviewLayout ? _reviewBodyController.text.trim() : _bodyController.text.trim(),
      linkUrl: linkTrimmed.isEmpty ? null : linkTrimmed,
      authorLevel: LevelService.instance.currentLevel.clamp(1, 30),
      category: _selectedCategory,
      type: _typeForStorage(),
      dramaId: _boardKind == 'review' ? _pickDramaId : null,
      dramaTitle: _boardKind == 'review' ? _pickDramaTitle : null,
      dramaThumbnail: _boardKind == 'review' ? _pickDramaThumb : null,
      rating: _boardKind == 'review' ? _reviewRating : null,
      hasSpoiler: _boardKind == 'review' ? !_noSpoilers : false,
      isLiked: _boardKind == 'review' ? _reviewDramaLiked : false,
      isFirstWatch: _boardKind == 'review' ? _isFirstWatch : true,
      tags: _boardKind == 'review' ? _parseTagsInput() : const [],
      allowReply: _boardKind == 'review' ? _allowReply : true,
      authorPhotoUrl: UserProfileService.instance.profileImageUrlNotifier.value,
      authorAvatarColorIndex: UserProfileService.instance.avatarColorNotifier.value,
      country: UserProfileService.instance.signupCountryNotifier.value ?? LocaleService.instance.locale,
    );

    if (!mounted) return;
    Navigator.pop(context, post);
    } catch (e, st) {
      debugPrint('_submit 예외: $e\n$st');
      if (mounted) {
        setState(() => _isSubmitting = false);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('글 등록 실패'),
            content: SingleChildScrollView(child: Text(e.toString())),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(LucideIcons.x, size: 24, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditMode ? s.get('editPost') : s.get('writePost'),
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSubmitting
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: Text(
                      _isEditMode ? s.get('edit') : s.get('postSubmit'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
            // 게시판 선택 (리뷰 / 톡 / 질문)
            if (!_isEditMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _CategoryPill(
                          label: s.get('tabReviews'),
                          icon: LucideIcons.star,
                          selected: _boardKind == 'review',
                          onTap: () => setState(() {
                            _boardKind = 'review';
                            _selectedCategory = 'free';
                          }),
                          cs: cs,
                        ),
                        const SizedBox(width: 8),
                        _CategoryPill(
                          label: s.get('tabGeneral'),
                          icon: LucideIcons.message_square,
                          selected: _boardKind == 'talk',
                          onTap: () => setState(() {
                            _boardKind = 'talk';
                            _selectedCategory = 'free';
                            _pickDramaId = null;
                            _pickDramaTitle = null;
                            _pickDramaThumb = null;
                            _reviewRating = null;
                            _noSpoilers = true;
                            _reviewDramaLiked = false;
                            _isFirstWatch = true;
                            _allowReply = true;
                          }),
                          cs: cs,
                        ),
                        const SizedBox(width: 8),
                        _CategoryPill(
                          label: s.get('tabQnA'),
                          icon: LucideIcons.message_circle,
                          selected: _boardKind == 'ask',
                          onTap: () => setState(() {
                            _boardKind = 'ask';
                            _selectedCategory = 'question';
                            _pickDramaId = null;
                            _pickDramaTitle = null;
                            _pickDramaThumb = null;
                            _reviewRating = null;
                            _noSpoilers = true;
                            _reviewDramaLiked = false;
                            _isFirstWatch = true;
                            _allowReply = true;
                          }),
                          cs: cs,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_isReviewLayout) _buildReviewLayout(cs, theme),
            if (!_isReviewLayout) ...[
            // 제목 섹션
            _SectionLabel(label: s.get('postTitle')),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).requestFocus(_titleFocus),
              child: TextFormField(
                controller: _titleController,
                focusNode: _titleFocus,
                decoration: InputDecoration(
                hintText: s.get('postTitleHint'),
                hintStyle: GoogleFonts.notoSansKr(
                  color: cs.onSurfaceVariant.withOpacity(0.6),
                  fontSize: 17,
                ),
                counterText: '${_titleController.text.length}/$_maxTitleLength',
                counterStyle: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: _titleController.text.length > _maxTitleLength
                      ? cs.error
                      : cs.onSurfaceVariant.withOpacity(0.7),
                ),
                border: InputBorder.none,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.outline.withOpacity(0.3)),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.error),
                ),
              ),
              style: GoogleFonts.notoSansKr(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
              maxLines: 2,
              maxLength: _maxTitleLength,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_bodyFocus),
              validator: (v) {
                if (_isReviewLayout) return null;
                if (v == null || v.trim().isEmpty) return s.get('titleRequired');
                if (v.trim().length < 2) return s.get('titleMinLength');
                return null;
              },
              ),
            ),
            const SizedBox(height: 24),
            // 내용 섹션
            _SectionLabel(label: s.get('postContent')),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).requestFocus(_bodyFocus),
              child: TextFormField(
                controller: _bodyController,
                focusNode: _bodyFocus,
                decoration: InputDecoration(
                hintText: s.get('postContentHint'),
                hintStyle: GoogleFonts.notoSansKr(
                  color: cs.onSurfaceVariant.withOpacity(0.6),
                  fontSize: 16,
                ),
                alignLabelWithHint: true,
                border: InputBorder.none,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.outline.withOpacity(0.3)),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.error),
                ),
              ),
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                height: 1.5,
                color: cs.onSurface,
              ),
              maxLines: null,
              minLines: 6,
              validator: (v) {
                if (_isReviewLayout) return null;
                final hasImage = _pickedImages.isNotEmpty;
                final hasVideo = _isVideoMode;
                final text = v?.trim() ?? '';
                if (hasImage || hasVideo) return null; // 사진/영상 있으면 내용 없어도 OK
                if (text.isEmpty) return s.get('contentRequired');
                if (text.length < 5) return '내용을 5자 이상 입력해 주세요.';
                return null;
              },
              ),
            ),
            const SizedBox(height: 16),
            // 사진, 동영상 추가 버튼
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isVideoMode ? null : _showImageSourceChoice,
                  icon: Icon(LucideIcons.image, size: 20, color: cs.primary),
                  label: Text(s.get('addPhoto'), style: GoogleFonts.notoSansKr(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    side: BorderSide(color: cs.outline.withOpacity(0.5)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isVideoMode ? null : _onVideoTap,
                  icon: Icon(LucideIcons.video, size: 20, color: cs.primary),
                  label: Text(s.get('addVideo'), style: GoogleFonts.notoSansKr(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    side: BorderSide(color: cs.outline.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 영상/GIF 미리보기 (클립 조정에서 진입 시) - 썸네일 이미지 표시
            if (_isVideoMode) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _videoThumbPath != null
                        ? Image.file(
                            File(_videoThumbPath!),
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            height: 200,
                            width: double.infinity,
                            color: cs.surfaceContainerHighest.withOpacity(0.5),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                          ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 36, color: Colors.white),
                    ),
                    if (_postAsGif)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('GIF',
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _videoPathForUpload = null;
                          _videoThumbPath = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 사진 미리보기만 (키보드 위 툴바에서 추가)
            if (_pickedImages.isNotEmpty) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisCount = 4;
                  const gap = 8.0;
                  final size = (constraints.maxWidth - (crossAxisCount - 1) * gap) / crossAxisCount;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: List.generate(_pickedImages.length, (i) {
                      return _ImagePreviewTile(
                        file: _pickedImages[i],
                        size: size,
                        onRemove: () => _removeImage(i),
                        removeLabel: s.get('removePhoto'),
                        cs: cs,
                      );
                    }),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            ],
          ],
        ),
            ),
            // 키보드 위 툴바: 링크, 사진, 영상 (영상 모드에서는 사진 추가 숨김)
            if (!_isReviewLayout)
              _KeyboardToolbar(
                onLink: () => _showLinkSheet(context),
                onImage: _isVideoMode ? null : _showImageSourceChoice,
                onVideo: _isVideoMode ? null : _onVideoTap,
                cs: cs,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHalfStarRating(ColorScheme cs) {
    const slotW = 36.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (si) {
        final r = _reviewRating ?? 0;
        final IconData icon;
        if (r >= si + 1) {
          icon = Icons.star_rounded;
        } else if (r >= si + 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final half = details.localPosition.dx < slotW / 2;
            setState(() => _reviewRating = si + (half ? 0.5 : 1.0));
          },
          child: SizedBox(
            width: slotW,
            height: 40,
            child: Icon(icon, size: 32, color: const Color(0xFFFFB020)),
          ),
        );
      }),
    );
  }

  Widget _reviewOptionChip({
    required Widget icon,
    required bool selected,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withOpacity(0.25)),
          ),
          child: IconTheme(
            data: IconThemeData(
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              size: 22,
            ),
            child: icon,
          ),
        ),
      ),
    );
  }

  Widget _buildReviewLayout(ColorScheme cs, ThemeData theme) {
    final country = CountryScope.maybeOf(context)?.country;
    final thumbUrl = _pickDramaThumb?.trim();
    final showHttpThumb = thumbUrl != null && thumbUrl.startsWith('http');

    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurfaceVariant.withOpacity(0.65)),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withOpacity(0.45),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outline.withOpacity(0.25)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outline.withOpacity(0.25)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.primary, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pickDramaTitle != null && _pickDramaTitle!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: showHttpThumb
                        ? OptimizedNetworkImage(
                            imageUrl: thumbUrl,
                            width: 72,
                            height: 96,
                            fit: BoxFit.cover,
                            memCacheWidth: 144,
                            memCacheHeight: 192,
                          )
                        : Container(
                            width: 72,
                            height: 96,
                            color: cs.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant, size: 32),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _pickDramaTitle!.trim(),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: cs.onSurface,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _dramaSearchController,
            focusNode: _dramaSearchFocus,
            onTap: () => setState(() => _dramaSearchExpanded = true),
            decoration: deco('Search for a short drama...').copyWith(
              prefixIcon: Icon(LucideIcons.search, size: 20, color: cs.onSurfaceVariant),
            ),
            style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurface),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _dramaSearchExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ValueListenableBuilder<List<DramaItem>>(
                      valueListenable: DramaListService.instance.listNotifier,
                      builder: (context, _, __) {
                        final grid = _dramasForSearchGrid(country);
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.68,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: grid.length,
                            itemBuilder: (context, i) {
                              final item = grid[i];
                              final url = DramaListService.instance.getDisplayImageUrl(item.id, country) ?? item.imageUrl;
                              final title = DramaListService.instance.getDisplayTitle(item.id, country);
                              final ok = url != null && url.startsWith('http');
                              return Material(
                                color: cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _selectDramaForReview(item, country),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ok
                                            ? OptimizedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                                            : Container(
                                                color: cs.surfaceContainerHighest,
                                                alignment: Alignment.center,
                                                child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
                                              ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                                        child: Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.notoSansKr(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHalfStarRating(cs),
              const Spacer(),
              IconButton(
                tooltip: 'Like',
                onPressed: () => setState(() => _reviewDramaLiked = !_reviewDramaLiked),
                icon: Icon(
                  _reviewDramaLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 30,
                  color: _reviewDramaLiked ? const Color(0xFFE53935) : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reviewBodyController,
            minLines: 5,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: deco('Add review...'),
            style: GoogleFonts.notoSansKr(fontSize: 16, height: 1.45, color: cs.onSurface),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsController,
            decoration: deco('Add tags...'),
            style: GoogleFonts.notoSansKr(fontSize: 15, color: cs.onSurface),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _reviewOptionChip(
                icon: Icon(LucideIcons.eye),
                selected: _isFirstWatch,
                onTap: () => setState(() => _isFirstWatch = !_isFirstWatch),
                cs: cs,
              ),
              _reviewOptionChip(
                icon: const Icon(Icons.masks_rounded),
                selected: _noSpoilers,
                onTap: () => setState(() => _noSpoilers = !_noSpoilers),
                cs: cs,
              ),
              _reviewOptionChip(
                icon: Icon(LucideIcons.message_circle),
                selected: _allowReply,
                onTap: () => setState(() => _allowReply = !_allowReply),
                cs: cs,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLinkSheet(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: _linkController.text);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.get('postLink'),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: s.get('postLinkHint'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  keyboardType: TextInputType.url,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(s.get('cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        _linkController.text = controller.text.trim();
                        Navigator.pop(ctx);
                        setState(() {});
                      },
                      child: Text(s.get('apply')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 키보드 위 툴바: 링크, 사진, 영상 (영상 모드일 때는 onImage/onVideo null)
class _KeyboardToolbar extends StatelessWidget {
  const _KeyboardToolbar({
    required this.onLink,
    this.onImage,
    this.onVideo,
    required this.cs,
  });

  final VoidCallback onLink;
  final VoidCallback? onImage;
  final VoidCallback? onVideo;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onLink,
            icon: Icon(LucideIcons.link, size: 24, color: cs.onSurfaceVariant),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
            ),
          ),
          if (onImage != null)
            IconButton(
              onPressed: onImage,
              icon: Icon(LucideIcons.image, size: 24, color: cs.onSurfaceVariant),
              style: IconButton.styleFrom(backgroundColor: Colors.transparent),
            ),
          if (onVideo != null)
            IconButton(
              onPressed: onVideo,
              icon: Icon(LucideIcons.video, size: 24, color: cs.onSurfaceVariant),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label,
      style: GoogleFonts.notoSansKr(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
    );
  }
}

class _ImagePreviewTile extends StatelessWidget {
  const _ImagePreviewTile({
    required this.file,
    required this.size,
    required this.onRemove,
    required this.removeLabel,
    required this.cs,
  });

  final XFile file;
  final double size;
  final VoidCallback onRemove;
  final String removeLabel;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: Image.file(
              File(file.path),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: cs.error,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(LucideIcons.x, size: 14, color: cs.onError),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.cs,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? cs.onPrimary : cs.onSurface.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? cs.onPrimary : cs.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
