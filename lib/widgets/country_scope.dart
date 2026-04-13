import 'package:flutter/material.dart';
import '../app_strings.dart';

/// 국가/언어 전달용 InheritedWidget
class CountryScope extends InheritedWidget {
  const CountryScope({
    super.key,
    required this.country,
    required super.child,
  });

  final String country;

  AppStrings get strings => AppStrings(country);

  static CountryScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CountryScope>();
    assert(scope != null, 'CountryScope not found. Wrap app with CountryScope.');
    return scope!;
  }

  /// [of]와 달리 위젯을 CountryScope 변경에 **구독시키지 않음**.
  /// `AnimatedBuilder` 등 중첩 빌더 안에서 `dependOn`을 쓰면 ancestor 검증 assertion이 날 수 있어
  /// 조회만 수행한다.
  static CountryScope? maybeOf(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<CountryScope>();
    return element?.widget as CountryScope?;
  }

  @override
  bool updateShouldNotify(CountryScope old) => country != old.country;
}
