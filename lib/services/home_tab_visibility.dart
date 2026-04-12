import 'package:flutter/foundation.dart';

/// 하단 네비에서 홈(커뮤니티) 탭이 선택됐는지. IndexedStack 때문에 홈이 가려져도 위젯이 살아 있으므로
/// 피드 동영상 일시정지 등에 사용합니다.
class HomeTabVisibility {
  HomeTabVisibility._();

  static final ValueNotifier<bool> isHomeMainTabSelected = ValueNotifier<bool>(true);
}
