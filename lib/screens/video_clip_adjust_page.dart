import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

const int _kFrameCount = 12;
const double _kTimelineHeight = 60.0;
const double _kHandleWidth = 14.0;

class VideoClipAdjustPage extends StatefulWidget {
  const VideoClipAdjustPage({
    super.key,
    required this.initialVideoPath,
  });

  final String initialVideoPath;

  @override
  State<VideoClipAdjustPage> createState() => _VideoClipAdjustPageState();
}

class _VideoClipAdjustPageState extends State<VideoClipAdjustPage> {
  bool _postAsGif = false;
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  /// 트림 바 핸들/재생헤드 드래그 중일 때 뒤로 스와이프로 인한 pop 방지
  bool _isTrimDragging = false;

  double _startFraction = 0.0;
  double _endFraction = 1.0;

  List<Uint8List?> _frames = [];
  bool _framesLoading = false;
  final GlobalKey _trimTimelineKey = GlobalKey();

  Duration get _totalDuration => _controller?.value.duration ?? Duration.zero;

  Duration get _startTime =>
      Duration(milliseconds: (_totalDuration.inMilliseconds * _startFraction).round());
  Duration get _endTime =>
      Duration(milliseconds: (_totalDuration.inMilliseconds * _endFraction).round());

  @override
  void initState() {
    super.initState();
    final file = File(widget.initialVideoPath);
    if (file.existsSync()) {
      _controller = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _loadFrames();
          }
        })
        ..addListener(_onPlayerUpdate);
    }
  }

  void _onPlayerUpdate() {
    if (!mounted) return;
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _isPlaying) setState(() => _isPlaying = playing);

    final pos = _controller?.value.position ?? Duration.zero;
    final total = _totalDuration;
    if (total.inMilliseconds > 0 && playing) {
      final posFrac = pos.inMilliseconds / total.inMilliseconds;
      if (posFrac >= _endFraction) {
        _controller?.pause();
        _controller?.seekTo(_startTime);
      }
    }
    setState(() {}); // 재생 헤드(흰 바) 위치 갱신
  }

  Future<void> _loadFrames() async {
    if (_framesLoading) return;
    _framesLoading = true;
    final total = _totalDuration.inMilliseconds;
    if (total <= 0) return;
    final results = <Uint8List?>[];
    for (int i = 0; i < _kFrameCount; i++) {
      final ms = (total * i / (_kFrameCount - 1)).round();
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: widget.initialVideoPath,
          timeMs: ms,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 80,
          quality: 50,
        );
        results.add(bytes);
      } catch (_) {
        results.add(null);
      }
    }
    if (mounted) setState(() => _frames = results);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.seekTo(_startTime);
      ctrl.play();
    }
  }

  Future<void> _onNext() async {
    _controller?.pause();
    // 글쓰기 페이지로 새로 가지 않고, 경로·GIF 여부만 돌려줘서 기존 제목/내용 유지
    if (!mounted) return;
    Navigator.pop(context, {'path': widget.initialVideoPath, 'isGif': _postAsGif});
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    if (m > 0) return '${m}:${s.toString().padLeft(2, '0')}';
    return '${s}.${tenths}s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initialized = _controller != null && _controller!.value.isInitialized;
    return PopScope(
      canPop: !_isTrimDragging,
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('클립 조정',
            style: GoogleFonts.notoSansKr(
                fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 영상 미리보기 (비율 유지) ──
            Expanded(
              child: Center(
                child: initialized
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                    : const SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(color: Colors.amber),
                      ),
              ),
            ),

            // ── GIF 토글 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Text('GIF로 게시',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
                  const Spacer(),
                  Switch(
                    value: _postAsGif,
                    onChanged: (v) => setState(() => _postAsGif = v),
                    activeTrackColor: Colors.amber.withOpacity(0.7),
                    activeColor: Colors.amber,
                    inactiveThumbColor: Colors.grey.shade400,
                    inactiveTrackColor: Colors.white.withOpacity(0.3),
                  ),
                ],
              ),
            ),

            // ── 타임라인 (프레임 스트립 + 노란 핸들) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 현재 선택 구간 시간 표시
                  if (initialized)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(_startTime),
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 11, color: Colors.white54)),
                          Text(
                            '선택 구간: ${_fmt(_endTime - _startTime)}',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber),
                          ),
                          Text(_fmt(_endTime),
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 11, color: Colors.white54)),
                        ],
                      ),
                    ),

                  // 프레임 스트립 + 핸들 + 흰색 재생 헤드
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final trackW = constraints.maxWidth;
                      final totalMs = _totalDuration.inMilliseconds;
                      final posMs = _controller?.value.position.inMilliseconds ?? 0;
                      final positionFraction = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;
                      return _TrimTimeline(
                        key: _trimTimelineKey,
                        trackWidth: trackW,
                        frameHeight: _kTimelineHeight,
                        handleWidth: _kHandleWidth,
                        frames: _frames,
                        startFraction: _startFraction,
                        endFraction: _endFraction,
                        positionFraction: positionFraction,
                        onStartDragUpdate: (globalPos) {
                          final box = _trimTimelineKey.currentContext?.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final local = box.globalToLocal(globalPos);
                          final w = box.size.width;
                          if (w <= 0) return;
                          final f = (local.dx / w).clamp(0.0, _endFraction - 0.02);
                          setState(() {
                            _startFraction = f;
                            _controller?.seekTo(_startTime);
                          });
                        },
                        onEndDragUpdate: (globalPos) {
                          final box = _trimTimelineKey.currentContext?.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final local = box.globalToLocal(globalPos);
                          final w = box.size.width;
                          if (w <= 0) return;
                          final f = (local.dx / w).clamp(_startFraction + 0.02, 1.0);
                          setState(() {
                            _endFraction = f;
                            _controller?.seekTo(_endTime);
                          });
                        },
                        onScrubDragUpdate: (globalPos) {
                          final box = _trimTimelineKey.currentContext?.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final local = box.globalToLocal(globalPos);
                          final w = box.size.width;
                          if (w <= 0 || _controller == null) return;
                          final f = (local.dx / w).clamp(_startFraction, _endFraction);
                          final ms = (_totalDuration.inMilliseconds * f).round();
                          _controller!.seekTo(Duration(milliseconds: ms));
                          setState(() {});
                        },
                        onSeekToFraction: (f) {
                          if (_controller == null) return;
                          final ms = (_totalDuration.inMilliseconds * f).round();
                          _controller!.seekTo(Duration(milliseconds: ms));
                          setState(() {});
                        },
                        onTrimDragStart: () => setState(() => _isTrimDragging = true),
                        onTrimDragEnd: () => setState(() => _isTrimDragging = false),
                      );
                    },
                  ),

                  // 전체 길이 레이블
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0.0s',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 10, color: Colors.white38)),
                        Text(initialized ? _fmt(_totalDuration) : '',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 10, color: Colors.white38)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 하단: 뒤로 | ▶ | 다음 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('뒤로',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 15, color: Colors.white70)),
                  ),
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(color: Colors.white54, width: 1.5),
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _onNext,
                    child: Text('다음',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

/// 노란 테두리 트림 타임라인 위젯
const double _kPlayheadWidth = 4.0;

class _TrimTimeline extends StatelessWidget {
  _TrimTimeline({
    super.key,
    required this.trackWidth,
    required this.frameHeight,
    required this.handleWidth,
    required this.frames,
    required this.startFraction,
    required this.endFraction,
    required this.positionFraction,
    required this.onStartDragUpdate,
    required this.onEndDragUpdate,
    required this.onScrubDragUpdate,
    required this.onSeekToFraction,
    required this.onTrimDragStart,
    required this.onTrimDragEnd,
  });

  final double trackWidth;
  final double frameHeight;
  final double handleWidth;
  final List<Uint8List?> frames;
  final double startFraction;
  final double endFraction;
  /// 현재 재생 위치 (0.0~1.0). 흰색 재생 헤드 위치
  final double positionFraction;
  final ValueChanged<Offset> onStartDragUpdate;
  final ValueChanged<Offset> onEndDragUpdate;
  final ValueChanged<Offset> onScrubDragUpdate;
  /// 트림 구간 안 탭 시 해당 위치로 재생 헤드 이동
  final ValueChanged<double> onSeekToFraction;
  final VoidCallback onTrimDragStart;
  final VoidCallback onTrimDragEnd;

  @override
  Widget build(BuildContext context) {
    final startX = startFraction * trackWidth;
    final endX = endFraction * trackWidth;
    final playheadX = (positionFraction * trackWidth).clamp(startX, endX) - _kPlayheadWidth / 2;

    // 터치 다운 즉시 뒤로가기 막기 (드래그 인식 전에 시스템 스와이프가 잡히는 것 방지)
    return Listener(
      onPointerDown: (_) => onTrimDragStart(),
      onPointerUp: (_) => onTrimDragEnd(),
      onPointerCancel: (_) => onTrimDragEnd(),
      child: SizedBox(
      height: frameHeight + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 프레임 스트립 배경
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: trackWidth,
              height: frameHeight,
              child: Row(
                children: List.generate(
                  _kFrameCount,
                  (i) => Expanded(
                    child: frames.length > i && frames[i] != null
                        ? Image.memory(
                            frames[i]!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Container(
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.image_not_supported,
                                size: 12, color: Colors.white12),
                          ),
                  ),
                ),
              ),
            ),
          ),

          // 선택 범위 바깥 어둡게
          Positioned(
            left: 0,
            top: 0,
            width: startX,
            height: frameHeight,
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),
          Positioned(
            left: endX,
            top: 0,
            width: trackWidth - endX,
            height: frameHeight,
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),

          // 노란 테두리 (선택 구간) — 탭하면 재생 헤드가 그 위치로 이동
          Positioned(
            left: startX,
            top: 0,
            width: (endX - startX).clamp(0, trackWidth),
            height: frameHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final w = (endX - startX).clamp(1.0, trackWidth);
                final dx = details.localPosition.dx.clamp(0.0, w);
                final fraction = startFraction + (dx / w) * (endFraction - startFraction);
                onSeekToFraction(fraction.clamp(startFraction, endFraction));
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber, width: 3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),

          // 왼쪽 핸들 (드래그 - 손가락 위치 기준으로 즉시 이동, 드래그 시작 시 제스처 선점으로 뒤로 스와이프 방지)
          Positioned(
            left: startX - handleWidth / 2,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => onTrimDragStart(),
              onHorizontalDragUpdate: (d) => onStartDragUpdate(d.globalPosition),
              onHorizontalDragEnd: (_) => onTrimDragEnd(),
              child: _Handle(height: frameHeight, width: handleWidth),
            ),
          ),

          // 오른쪽 핸들 (드래그 - 손가락 위치 기준으로 즉시 이동)
          Positioned(
            left: endX - handleWidth / 2,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => onTrimDragStart(),
              onHorizontalDragUpdate: (d) => onEndDragUpdate(d.globalPosition),
              onHorizontalDragEnd: (_) => onTrimDragEnd(),
              child: _Handle(height: frameHeight, width: handleWidth),
            ),
          ),

          // 흰색 재생 헤드 (노란 구간 안, 좌우 드래그 시 해당 프레임으로 이동)
          Positioned(
            left: playheadX,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => onTrimDragStart(),
              onHorizontalDragUpdate: (d) => onScrubDragUpdate(d.globalPosition),
              onHorizontalDragEnd: (_) => onTrimDragEnd(),
              child: Container(
                width: _kPlayheadWidth,
                height: frameHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 2,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.height, required this.width});
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.amber,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 2,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 2,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
