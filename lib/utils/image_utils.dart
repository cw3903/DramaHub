import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

/// 파일 경로에서 이미지 크기 [width, height] 반환. 실패 시 null.
Future<List<int>?> getImageDimensions(String filePath) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      if (!completer.isCompleted) completer.complete(img);
    });
    final image = await completer.future;
    return [image.width, image.height];
  } catch (_) {
    return null;
  }
}
