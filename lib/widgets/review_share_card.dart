import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import 'country_scope.dart';

/// 인스타·틱톡용 리뷰 공유 카드에 필요한 데이터.
class ReviewShareCardData {
  const ReviewShareCardData({
    required this.dramaTitle,
    required this.rating,
    required this.reviewPreview,
    required this.userNickname,
    this.posterUrl,
    this.posterAsset,
  });

  final String dramaTitle;
  final double? rating;
  final String reviewPreview;
  final String userNickname;
  final String? posterUrl;
  final String? posterAsset;
}

/// Letterboxd/인스타 스타일 단일 이미지 카드 (RepaintBoundary 캡처용).
class ReviewShareCard extends StatelessWidget {
  const ReviewShareCard({super.key, required this.data});

  final ReviewShareCardData data;

  static const double designWidth = 360;
  static const double designHeight = 520;

  static const Color _bg = Color(0xFF1a1a2e);

  @override
  Widget build(BuildContext context) {
    final ratingValue = data.rating;
    final hasRating = ratingValue != null && ratingValue > 0;

    return Material(
      color: _bg,
      child: SizedBox(
        width: designWidth,
        height: designHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DRAMAFEED',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.2,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                data.dramaTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              if (hasRating)
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 22, color: Colors.amber.shade400),
                    const SizedBox(width: 6),
                    Text(
                      ratingValue.toStringAsFixed(1),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade400,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '—',
                  style: GoogleFonts.notoSansKr(fontSize: 16, color: Colors.white38),
                ),
              const SizedBox(height: 18),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 108,
                        height: 152,
                        child: _SharePoster(
                          posterUrl: data.posterUrl,
                          posterAsset: data.posterAsset,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        data.reviewPreview.trim().isEmpty ? ' ' : data.reviewPreview.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.userNickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  Text(
                    'dramafeed.app',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharePoster extends StatelessWidget {
  const _SharePoster({this.posterUrl, this.posterAsset});

  final String? posterUrl;
  final String? posterAsset;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl?.trim();
    if (url != null && url.isNotEmpty && url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    final asset = posterAsset?.trim();
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.movie_outlined, color: Colors.white24, size: 40),
      ),
    );
  }
}

/// RepaintBoundary → PNG → [Share.shareXFiles]
class ReviewShareImageHelper {
  ReviewShareImageHelper._();

  static Future<void> captureAndShare(BuildContext context, ReviewShareCardData data) async {
    if (!context.mounted) return;

    final strings = CountryScope.maybeOf(context)?.strings;
    final failMsg = strings?.get('reviewShareImageFailed') ?? 'Could not create share image.';

    var dismissedLoader = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            color: const Color(0xFF2a2a3e),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings?.get('share') ?? 'Share',
                    style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    OverlayEntry? entry;
    final repaintKey = GlobalKey();

    try {
      if (data.posterUrl != null && data.posterUrl!.trim().startsWith('http')) {
        try {
          await precacheImage(NetworkImage(data.posterUrl!.trim()), context)
              .timeout(const Duration(seconds: 6));
        } catch (_) {}
      } else if (data.posterAsset != null && data.posterAsset!.trim().isNotEmpty) {
        try {
          await precacheImage(AssetImage(data.posterAsset!.trim()), context)
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      if (!context.mounted) return;

      final overlay = Overlay.of(context);
      entry = OverlayEntry(
        builder: (ctx) => Positioned(
          left: -8000,
          top: 0,
          child: Material(
            color: Colors.transparent,
            child: RepaintBoundary(
              key: repaintKey,
              child: ReviewShareCard(data: data),
            ),
          ),
        ),
      );
      overlay.insert(entry);

      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      if (!context.mounted) {
        entry.remove();
        entry = null;
        return;
      }

      final ro = repaintKey.currentContext?.findRenderObject();
      final boundary = ro is RenderRepaintBoundary ? ro : null;
      if (boundary == null) {
        throw StateError('no boundary');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bd == null) throw StateError('no bytes');

      final bytes = bd.buffer.asUint8List();
      entry.remove();
      entry = null;

      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();
      dismissedLoader = true;

      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: 'dramafeed_review.png',
          ),
        ],
        text: 'dramafeed.app',
      );
    } catch (e) {
      entry?.remove();
      if (!dismissedLoader && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failMsg, style: GoogleFonts.notoSansKr())),
        );
      }
    }
  }
}
