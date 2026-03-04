import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/country_scope.dart';

/// 갤러리에서 선택 후 크롭한 이미지를 원형으로 미리 보여주고, 수정(재크롭) 또는 저장할 수 있는 화면.
class ProfilePhotoPreviewPage extends StatefulWidget {
  const ProfilePhotoPreviewPage({
    super.key,
    required this.croppedImagePath,
    this.originalImagePath,
    required this.onSave,
    required this.onEdit,
  });

  final String croppedImagePath;
  final String? originalImagePath;
  final Future<void> Function(Uint8List bytes) onSave;
  final VoidCallback onEdit;

  @override
  State<ProfilePhotoPreviewPage> createState() => _ProfilePhotoPreviewPageState();
}

class _ProfilePhotoPreviewPageState extends State<ProfilePhotoPreviewPage> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.x, color: cs.onSurface),
          onPressed: _uploading ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          s.get('profilePhotoPreview'),
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              ClipOval(
                child: Image.file(
                  File(widget.croppedImagePath),
                  width: 280,
                  height: 280,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              if (widget.originalImagePath != null)
                OutlinedButton.icon(
                  onPressed: _uploading ? null : widget.onEdit,
                  icon: Icon(LucideIcons.scan_line, size: 20, color: cs.primary),
                  label: Text(
                    s.get('edit'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: cs.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    side: BorderSide(color: cs.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              if (widget.originalImagePath != null) const SizedBox(height: 16),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _uploading
                      ? null
                      : () async {
                          setState(() => _uploading = true);
                          final bytes = await File(widget.croppedImagePath).readAsBytes();
                          await widget.onSave(bytes);
                          if (mounted) Navigator.of(context).pop();
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _uploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          s.get('save'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
