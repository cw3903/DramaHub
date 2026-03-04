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

  static CountryScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CountryScope>();
  }

  @override
  bool updateShouldNotify(CountryScope old) => country != old.country;
}
