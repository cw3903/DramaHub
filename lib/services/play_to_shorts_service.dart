import 'package:flutter/foundation.dart';
import '../models/drama.dart';

/// 상세 페이지 재생 버튼 탭 시 숏폼 탭으로 이동 요청
class PlayToShortsService {
  PlayToShortsService._();
  static final instance = PlayToShortsService._();

  final ValueNotifier<DramaDetail?> request = ValueNotifier(null);

  void requestPlayToShorts(DramaDetail detail) {
    request.value = detail;
  }

  DramaDetail? takeRequest() {
    final d = request.value;
    request.value = null;
    return d;
  }
}
