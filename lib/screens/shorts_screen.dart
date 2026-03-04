import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../utils/format_utils.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:video_player/video_player.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/drama.dart';
import '../services/saved_service.dart';
import '../services/watch_history_service.dart';
import 'drama_detail_page.dart';
import 'shorts_search_screen.dart';
import 'tag_drama_list_screen.dart';
import '../widgets/share_sheet.dart';
import '../widgets/country_scope.dart';
class _ShortData {
  const _ShortData({
    required this.title,
    required this.tags,
    required this.description,
    required this.episode,
    required this.totalEpisodes,
    required this.views,
    required this.color,
    this.commentCount = 0,
    this.videoPath,
    this.imageUrl,
  });
  final String title;
  final List<String> tags;
  final String description;
  final int episode;
  final int totalEpisodes;
  final String views;
  final Color color;
  final int commentCount;
  final String? videoPath;
  /// 드라마 썸네일 URL (내가 본 드라마 카드 표시용)
  final String? imageUrl;
}

const _shortsData = <_ShortData>[];

_ShortData _shortFromDramaDetail(DramaDetail detail) {
  final tags = detail.genre.split(' · ');
  final desc = detail.synopsis.length > 80
      ? '${detail.synopsis.substring(0, 80)}... 더 보기'
      : detail.synopsis;
  return _ShortData(
    title: detail.item.title,
    tags: tags,
    description: desc,
    episode: 1,
    totalEpisodes: detail.episodes.length,
    views: detail.item.views,
    color: const Color(0xFF2D5A3D),
    commentCount: 24,
    videoPath: 'assets/videos/asuna.mp4',
    imageUrl: detail.item.imageUrl,
  );
}

/// 숏폼 탭 - 전체 화면 세로 영상
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({
    super.key,
    this.initialDetail,
    this.onInitialDetailConsumed,
    this.isActive = true,
  });

  final DramaDetail? initialDetail;
  final VoidCallback? onInitialDetailConsumed;
  final bool isActive;

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final PageController _pageController = PageController();
  List<_ShortData> _items = _shortsData;

  @override
  void initState() {
    super.initState();
    if (widget.initialDetail != null) {
      _items = [_shortFromDramaDetail(widget.initialDetail!), ..._shortsData];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onInitialDetailConsumed?.call();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ShortsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDetail != null &&
        widget.initialDetail != oldWidget.initialDetail) {
      final short = _shortFromDramaDetail(widget.initialDetail!);
      setState(() {
        _items = [short, ..._shortsData];
      });
      widget.onInitialDetailConsumed?.call();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          if (_items.isEmpty)
            Center(
              child: Text(
                CountryScope.of(context).strings.get('notReadyYet'),
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _items.length,
              itemBuilder: (context, index) {
                return _FullScreenShort(item: _items[index], isActive: widget.isActive);
              },
            ),
          // 상단 검색 아이콘
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: IconButton(
                  icon: Icon(LucideIcons.search, color: Colors.white.withOpacity(0.9), size: 24),
                  onPressed: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const ShortsSearchScreen()),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

DramaDetail _buildDramaDetailFromShort(_ShortData item) {
  final similarList = [
    DramaItem(id: 's1', title: '사랑은 시간 뒤에 서다', subtitle: '비밀신분', views: '9.1M', rating: 4.5, isPopular: true),
    DramaItem(id: 's2', title: '폭풍같은 결혼생활', subtitle: '대여주', views: '45.3M', rating: 4.3, isNew: true),
    DramaItem(id: 's3', title: '동생이 훔친 사랑', subtitle: '로맨스', views: '2.1M', rating: 4.6, isPopular: true),
    DramaItem(id: 's4', title: '후회·집착남', subtitle: '독립적인 여성', views: '567K', rating: 3.5, isPopular: true),
  ];
  final dramaItem = DramaItem(
    id: 'short-${item.title}',
    title: item.title,
    subtitle: item.tags.isNotEmpty ? item.tags.first : '',
    views: item.views,
    rating: 4.7,
    isPopular: item.tags.contains('인기'),
  );
  final fullSynopsis = '태성바이오 창립자 박창욱은 신분을 숨긴 채 청소부로 살아가고, 아들 정훈은 만삭의 아내 미연과 장차 이어질 가족의 행복을 꿈꾼다. 그러나 한 순간의 실수로 모든 것이 바뀌고, 박창욱은 숨겨왔던 진실을 마주하게 된다. 비밀과 진실, 사랑과 복수가 교차하는 드라마틱한 스토리.';
  const reviews = <DramaReview>[];
  final episodes = List.generate(item.totalEpisodes, (i) => DramaEpisode(number: i + 1, title: '${i + 1}화', duration: '45분'));
  return DramaDetail(
    item: dramaItem,
    synopsis: fullSynopsis,
    year: '2024',
    genre: item.tags.join(' · '),
    averageRating: 4.7,
    ratingCount: 8500,
    episodes: episodes,
    reviews: reviews,
    similar: similarList,
  );
}

void _showCommentSheet(BuildContext context, _ShortData item) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ShortsCommentSheet(item: item),
  );
}

class _FullScreenShort extends StatefulWidget {
  const _FullScreenShort({required this.item, this.isActive = true});

  final _ShortData item;
  final bool isActive;

  @override
  State<_FullScreenShort> createState() => _FullScreenShortState();
}

int _parseViews(String s) {
  s = s.replaceAll(',', '').toUpperCase();
  if (s.endsWith('M')) return ((double.tryParse(s.substring(0, s.length - 1)) ?? 0) * 1000000).round();
  if (s.endsWith('K')) return ((double.tryParse(s.substring(0, s.length - 1)) ?? 0) * 1000).round();
  return int.tryParse(s) ?? 0;
}

String _formatLikeCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.toString();
}

class _FullScreenShortState extends State<_FullScreenShort> {
  VideoPlayerController? _videoController;
  bool _initFailed = false;
  bool _isLiked = false;
  bool _hasOpenedEpisodes = false;
  bool _hasShared = false;
  bool _commentSheetOpen = false;
  bool _showPlayPauseOverlay = false;
  bool _overlayVisible = true;
  void _videoPositionListener() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized || !mounted) return;
    if (c.value.position.inSeconds >= 15 && _overlayVisible) {
      setState(() => _overlayVisible = false);
      c.removeListener(_videoPositionListener);
    }
  }

  void _resetOverlayAndSchedule() {
    setState(() => _overlayVisible = true);
    _videoController?.removeListener(_videoPositionListener);
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.addListener(_videoPositionListener);
    } else {
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _overlayVisible) setState(() => _overlayVisible = false);
      });
    }
  }

  void _onVideoTap() {
    if (_commentSheetOpen) {
      setState(() => _commentSheetOpen = false);
      return;
    }
    if (_videoController != null &&
        _videoController!.value.isInitialized) {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
      setState(() => _showPlayPauseOverlay = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showPlayPauseOverlay = false);
      });
    }
    // 숨겨진 상태에서 탭 시 오버레이 다시 표시 + 15초 타이머 재시작
    if (!_overlayVisible) {
      _resetOverlayAndSchedule();
    }
  }

  @override
  void initState() {
    super.initState();
    // 숏폼 노출 시 즉시 시청 기록 저장 (비디오 로드 여부와 무관, 썸네일 URL 포함)
    WatchHistoryService.instance.add(
      id: 'short-${widget.item.title}',
      title: widget.item.title,
      subtitle: widget.item.tags.isNotEmpty ? widget.item.tags.first : '',
      views: widget.item.views,
      imageUrl: widget.item.imageUrl,
    );
    final path = widget.item.videoPath;
    if (path != null && path.isNotEmpty) {
      _videoController = VideoPlayerController.asset(path);
      _videoController!.initialize().then((_) {
        if (mounted && !_initFailed) {
          _videoController!.setLooping(true);
          if (widget.isActive) _videoController!.play();
          _videoController!.addListener(_videoPositionListener);
          setState(() {});
        }
      }).catchError((Object e, StackTrace st) {
        debugPrint('비디오 로드 실패: $e');
        if (mounted) {
          _initFailed = true;
          _videoController?.dispose();
          _videoController = null;
          setState(() {});
        }
      });
    }
    _resetOverlayAndSchedule();
  }

  @override
  void didUpdateWidget(covariant _FullScreenShort oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      final c = _videoController;
      if (c != null && c.value.isInitialized) {
        if (widget.isActive) {
          c.play();
        } else {
          c.pause();
        }
      }
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_videoPositionListener);
    _videoController?.dispose();
    super.dispose();
  }

  int get _displayLikeCount {
    final base = _parseViews(widget.item.views);
    return base + (_isLiked ? 1 : 0);
  }

  SavedItem get _savedItem => SavedItem(
    id: 'short-${widget.item.title}',
    title: widget.item.title,
    views: widget.item.views,
    type: SavedItemType.content,
  );

  /// 가로 1 기준 세로 최대 1.4. 1:1이면 1:1, 1:1.5처럼 더 길면 1:1.4로 표시(세로 캡).
  static const double _maxHeightPerWidth = 1.4;

  Widget _buildVideoContent(double width, double height) {
    final item = widget.item;
    final ctrl = _videoController;
    final initialized = ctrl != null && ctrl.value.isInitialized;
    // 표시 비율: 동영상 비율이 1:1.4보다 세로로 길면 1:1.4로 캡, 아니면 원본 비율
    double? videoW, videoH, contentW, contentH;
    if (initialized) {
      videoW = ctrl!.value.size.width;
      videoH = ctrl.value.size.height;
      final aspect = videoW! / videoH!;
      final cappedAspect = aspect < (1 / _maxHeightPerWidth) ? (1 / _maxHeightPerWidth) : aspect;
      if (width / cappedAspect <= height) {
        contentW = width;
        contentH = width / cappedAspect;
      } else {
        contentH = height;
        contentW = height * cappedAspect;
      }
    }
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        onTap: _onVideoTap,
        child: Stack(
        fit: StackFit.expand,
        children: [
            // 비디오 또는 그라데이션 배경
            Positioned.fill(
            child: initialized && contentW != null && contentH != null
                ? Center(
                    child: SizedBox(
                      width: contentW,
                      height: contentH,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: videoW,
                          height: videoH,
                          child: VideoPlayer(ctrl!),
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF3D6B4F),
                          const Color(0xFF2D5A3D),
                          const Color(0xFF5C4033),
                          const Color(0xFF4A3528),
                        ],
                        stops: const [0.0, 0.4, 0.7, 1.0],
                      ),
                    ),
                    child: Center(
                      child: widget.item.videoPath != null && !_initFailed
                          ? const SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(color: Colors.white),
                            )
                          : Icon(
                              LucideIcons.play,
                              size: 72,
                              color: Colors.white.withOpacity(0.85),
                            ),
                    ),
                  ),
          ),
          // 하단 오버레이 + 좌측 정보 + 우측 액션 (댓글창 열려 있으면 숨김, 15초 후에도 숨김)
          if (_overlayVisible && !_commentSheetOpen) ...[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: height * 0.45,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 70,
            bottom: MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    final detail = _buildDramaDetailFromShort(widget.item);
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => DramaDetailPage(detail: detail),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Text(
                        widget.item.title,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.chevron_right, size: 20, color: Colors.white70),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: widget.item.tags.map((t) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => TagDramaListScreen(tag: t),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          t,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: widget.item.description.replaceFirst(' 더 보기', ''),
                      ),
                      TextSpan(
                        text: ' 더 보기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            final detail = _buildDramaDetailFromShort(widget.item);
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) => DramaDetailPage(detail: detail),
                              ),
                            );
                          },
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Text(
                  '${widget.item.episode}화 / ${widget.item.totalEpisodes}화',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // 우측 액션 버튼들
          Positioned(
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIcon(
                  icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                  label: _formatLikeCount(_displayLikeCount),
                  onTap: () => setState(() => _isLiked = !_isLiked),
                ),
                const SizedBox(height: 16),
                _ActionIcon(
                  icon: Icons.chat_bubble_outline,
                  label: formatCompactCount(widget.item.commentCount),
                  onTap: () => setState(() => _commentSheetOpen = true),
                ),
                const SizedBox(height: 16),
                _ActionIcon(
                  icon: _hasOpenedEpisodes ? Icons.playlist_play : Icons.playlist_play_outlined,
                  label: '회차',
                  onTap: () => setState(() => _hasOpenedEpisodes = !_hasOpenedEpisodes),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<List<SavedItem>>(
                  valueListenable: SavedService.instance.savedList,
                  builder: (_, list, __) {
                    final isSaved = SavedService.instance.isSaved(_savedItem.id);
                    return _ActionIcon(
                      icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                      label: '저장',
                      onTap: () => SavedService.instance.toggle(_savedItem),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _ActionIcon(
                  icon: _hasShared ? Icons.share : Icons.share_outlined,
                  label: '공유',
                  onTap: () {
                    setState(() => _hasShared = true);
                    ShareSheet.show(context, title: widget.item.title, type: 'short');
                  },
                ),
              ],
            ),
          ),
          ],
          // 탭 시 재생/일시정지 아이콘 오버레이 (댓글창 열려 있으면 숨김)
          if (_showPlayPauseOverlay &&
              !_commentSheetOpen &&
              _videoController != null &&
              _videoController!.value.isInitialized)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Icon(
                    _videoController!.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _buildVideoContent(
                constraints.maxWidth,
                constraints.maxHeight,
              );
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _commentSheetOpen
              ? SizedBox(
                  height: size.height * 0.6,
                  child: _ShortsCommentInline(
                    item: widget.item,
                    onClose: () => setState(() => _commentSheetOpen = false),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ShortsCommentInline extends StatelessWidget {
  const _ShortsCommentInline({
    required this.item,
    required this.onClose,
  });

  final _ShortData item;
  final VoidCallback onClose;

  static const _comments = [
    _CommentData(author: 'vibesongplay', timeAgo: '5일', content: '듣기만 해도 기분 좋은 플레이리스트, 매일 피드에서 만나보세요! 🙌', likes: 2286, isAuthor: true, replyCount: 1),
    _CommentData(author: 'snxin_.47', timeAgo: '5일', content: '풍성수', likes: 7195, replyCount: 7),
    _CommentData(author: 'weddingday_everything', timeAgo: '5일', content: '불꽃', likes: 209, isAuthorFavorite: true),
    _CommentData(author: '6_eun.14', timeAgo: '5일', content: '불꽃 불꽃 불꽃 불꽃', likes: 20),
  ];

  static const _emojis = ['❤️', '🙌', '🔥', '👏', '😢', '🥰', '😮', '😄'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 드래그 핸들 + 닫기
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: subColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: textColor, size: 24),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '댓글',
                style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final c = _comments[index];
                return _CommentTile(
                  author: c.author,
                  timeAgo: c.timeAgo,
                  content: c.content,
                  likes: c.likes,
                  isAuthor: c.isAuthor,
                  isAuthorFavorite: c.isAuthorFavorite,
                  replyCount: c.replyCount,
                  textColor: textColor,
                  subColor: subColor,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _emojis.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(e, style: const TextStyle(fontSize: 24)),
                )).toList(),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(top: BorderSide(color: subColor.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: subColor.withOpacity(0.3),
                  child: Icon(Icons.person, size: 20, color: subColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: subColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      '${item.title}에 댓글 추가',
                      style: GoogleFonts.notoSansKr(fontSize: 15, color: subColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {},
                  child: Text('GIF', style: GoogleFonts.notoSansKr(fontSize: 14, color: subColor)),
                ),
                IconButton(
                  icon: Icon(Icons.card_giftcard, color: subColor, size: 24),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortsCommentSheet extends StatelessWidget {
  const _ShortsCommentSheet({required this.item});

  final _ShortData item;

  static const _comments = [
    _CommentData(author: 'vibesongplay', timeAgo: '5일', content: '듣기만 해도 기분 좋은 플레이리스트, 매일 피드에서 만나보세요! 🙌', likes: 2286, isAuthor: true, replyCount: 1),
    _CommentData(author: 'snxin_.47', timeAgo: '5일', content: '풍성수', likes: 7195, replyCount: 7),
    _CommentData(author: 'weddingday_everything', timeAgo: '5일', content: '불꽃', likes: 209, isAuthorFavorite: true),
    _CommentData(author: '6_eun.14', timeAgo: '5일', content: '불꽃 불꽃 불꽃 불꽃', likes: 20),
  ];

  static const _emojis = ['❤️', '🙌', '🔥', '👏', '😢', '🥰', '😮', '😄'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: subColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '댓글',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              // 댓글 목록
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _comments.length,
                  itemBuilder: (context, index) {
                    final c = _comments[index];
                    return _CommentTile(
                      author: c.author,
                      timeAgo: c.timeAgo,
                      content: c.content,
                      likes: c.likes,
                      isAuthor: c.isAuthor,
                      isAuthorFavorite: c.isAuthorFavorite,
                      replyCount: c.replyCount,
                      textColor: textColor,
                      subColor: subColor,
                    );
                  },
                ),
              ),
              // 이모지 반응 바
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _emojis.map((e) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    )).toList(),
                  ),
                ),
              ),
              // 댓글 입력
              Container(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border(top: BorderSide(color: subColor.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: subColor.withOpacity(0.3),
                      child: Icon(Icons.person, size: 20, color: subColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: subColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          '${item.title}에 댓글 추가',
                          style: GoogleFonts.notoSansKr(fontSize: 15, color: subColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {},
                      child: Text('GIF', style: GoogleFonts.notoSansKr(fontSize: 14, color: subColor)),
                    ),
                    IconButton(
                      icon: Icon(Icons.card_giftcard, color: subColor, size: 24),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CommentData {
  const _CommentData({
    required this.author,
    required this.timeAgo,
    required this.content,
    required this.likes,
    this.isAuthor = false,
    this.isAuthorFavorite = false,
    this.replyCount = 0,
  });
  final String author;
  final String timeAgo;
  final String content;
  final int likes;
  final bool isAuthor;
  final bool isAuthorFavorite;
  final int replyCount;
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.author,
    required this.timeAgo,
    required this.content,
    required this.likes,
    required this.textColor,
    required this.subColor,
    this.isAuthor = false,
    this.isAuthorFavorite = false,
    this.replyCount = 0,
  });
  final String author;
  final String timeAgo;
  final String content;
  final int likes;
  final Color textColor;
  final Color subColor;
  final bool isAuthor;
  final bool isAuthorFavorite;
  final int replyCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: subColor.withOpacity(0.3),
            child: Text(
              author.isNotEmpty ? author[0].toUpperCase() : '?',
              style: GoogleFonts.notoSansKr(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      author,
                      style: GoogleFonts.notoSansKr(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeAgo,
                      style: GoogleFonts.notoSansKr(fontSize: 12, color: subColor),
                    ),
                    if (isAuthor) ...[
                      const SizedBox(width: 6),
                      Text('작성자', style: GoogleFonts.notoSansKr(fontSize: 11, color: subColor)),
                    ],
                    if (isAuthorFavorite) ...[
                      const SizedBox(width: 6),
                      Text('작성자가 좋아하는 댓글', style: GoogleFonts.notoSansKr(fontSize: 11, color: subColor)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: GoogleFonts.notoSansKr(fontSize: 14, color: textColor, height: 1.4),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.favorite_border, size: 18, color: subColor),
                    const SizedBox(width: 4),
                    Text(
                      formatCompactCount(likes),
                      style: GoogleFonts.notoSansKr(fontSize: 12, color: subColor),
                    ),
                    const SizedBox(width: 16),
                    Text('답글 달기', style: GoogleFonts.notoSansKr(fontSize: 12, color: subColor)),
                    if (replyCount > 0) ...[
                      const SizedBox(width: 12),
                      Text('답글 $replyCount개 더 보기', style: GoogleFonts.notoSansKr(fontSize: 12, color: subColor)),
                    ],
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

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: Colors.white),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.notoSansKr(fontSize: 11, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

