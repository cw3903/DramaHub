import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 동영상 전체화면 재생 페이지.
class FullScreenVideoPage extends StatefulWidget {
  const FullScreenVideoPage({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.isGif = false,
    this.existingController,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final bool isGif;

  /// 인라인 플레이어에서 이미 초기화된 컨트롤러를 전달하면 중복 네트워크 요청 없이
  /// 전체화면을 즉시 시작한다. dispose는 caller 책임이므로 이 페이지에서 하지 않음.
  final VideoPlayerController? existingController;

  static Future<void> show(
    BuildContext context, {
    required String videoUrl,
    String? thumbnailUrl,
    bool isGif = false,
    VideoPlayerController? existingController,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => FullScreenVideoPage(
          videoUrl: videoUrl,
          thumbnailUrl: thumbnailUrl,
          isGif: isGif,
          existingController: existingController,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  VideoPlayerController? _controller;
  bool _muted = false;
  // 기존 컨트롤러를 받았으면 이 페이지에서 dispose하지 않음
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingController != null &&
        widget.existingController!.value.isInitialized) {
      // 이미 초기화된 컨트롤러 재사용 — 즉시 전체화면에서 재생
      _controller = widget.existingController;
      _ownsController = false;
      _muted = _controller!.value.volume == 0;
      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
      // 이미 재생 중이면 그대로, 아니면 시작
      if (!_controller!.value.isPlaying) _controller!.play();
    } else {
      // 기존 컨트롤러 없음 또는 미초기화 → 새로 생성
      _ownsController = true;
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          _controller!.setLooping(widget.isGif);
          if (widget.isGif) {
            _controller!.setVolume(0);
            _muted = true;
          }
          setState(() {});
          _controller!.play();
        })
        ..addListener(() {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {});
  }

  void _toggleMute() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _muted = !_muted;
    _controller!.setVolume(_muted ? 0 : 1);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _togglePlayPause,
            child: Center(
              child: _controller != null && _controller!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty
                      ? Image.network(
                          widget.thumbnailUrl!,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(color: Colors.white70),
                            );
                          },
                        )
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: const EdgeInsets.all(8),
                    ),
                    const Spacer(),
                    if (!widget.isGif)
                      IconButton(
                        icon: Icon(
                          _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: _toggleMute,
                        padding: const EdgeInsets.all(8),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_controller != null && _controller!.value.isInitialized && !_controller!.value.isPlaying)
            const Center(
              child: Icon(Icons.play_arrow_rounded, size: 72, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
