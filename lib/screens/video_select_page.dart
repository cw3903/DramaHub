import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/country_scope.dart';
import 'video_clip_adjust_page.dart';

/// 선택지: 갤러리 / 카메라 / 파일에서 선택(Browse files)
enum _VideoSource { gallery, camera, files }

/// 레딧 스타일 1단계: 갤러리·카메라·파일에서 영상 1개 선택 후 클립 조정으로 이동
class VideoSelectPage extends StatefulWidget {
  const VideoSelectPage({super.key});

  @override
  State<VideoSelectPage> createState() => _VideoSelectPageState();
}

class _VideoSelectPageState extends State<VideoSelectPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showSourceAndPick());
  }

  Future<void> _showSourceAndPick() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = CountryScope.of(context).strings;
    final source = await showModalBottomSheet<_VideoSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
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
                  onTap: () => Navigator.pop(ctx, _VideoSource.gallery),
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
                  onTap: () => Navigator.pop(ctx, _VideoSource.camera),
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
                  onTap: () => Navigator.pop(ctx, _VideoSource.files),
                ),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (source == null) {
      Navigator.pop(context);
      return;
    }
    try {
      String? path;
      if (source == _VideoSource.files) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: false,
        );
        if (!mounted) return;
        if (result == null || result.files.isEmpty) {
          Navigator.pop(context);
          return;
        }
        final platformFile = result.files.single;
        if (platformFile.path != null && platformFile.path!.isNotEmpty) {
          path = platformFile.path;
        } else if (platformFile.bytes != null) {
          final ext = platformFile.name.contains('.')
              ? platformFile.name.split('.').last
              : 'mp4';
          final temp = File(
            '${Directory.systemTemp.path}/drama_hub_pick_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
          await temp.writeAsBytes(platformFile.bytes!);
          path = temp.path;
        }
      } else {
        final picker = ImagePicker();
        final file = await picker.pickVideo(
          source: source == _VideoSource.gallery ? ImageSource.gallery : ImageSource.camera,
        );
        if (!mounted) return;
        if (file == null) {
          Navigator.pop(context);
          return;
        }
        path = file.path;
      }
      if (path == null || path.isEmpty) {
        Navigator.pop(context);
        return;
      }
      final result = await Navigator.push<dynamic>(
        context,
        MaterialPageRoute(
          builder: (_) => VideoClipAdjustPage(initialVideoPath: path!),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('영상 선택 실패: $e', style: GoogleFonts.notoSansKr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('영상 선택', style: GoogleFonts.notoSansKr()),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
