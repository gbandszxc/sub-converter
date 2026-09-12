import 'package:flutter/widgets.dart';

import 'app_strings.dart';

/// Provides the active [AppStrings] to the widget tree.
///
/// [of] fails loud when the scope is missing: silently falling back to English
/// would hide a wiring mistake and show the wrong language to a Chinese user.
class StringsScope extends InheritedWidget {
  const StringsScope({super.key, required this.strings, required super.child});

  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final StringsScope? scope = context
        .dependOnInheritedWidgetOfExactType<StringsScope>();
    if (scope == null) {
      throw FlutterError(
        'StringsScope.of() was called with a context that does not contain a '
        'StringsScope. Wrap the widget tree in '
        'StringsScope(strings: AppStrings.forLanguage(...), child: ...).',
      );
    }
    return scope.strings;
  }

  @override
  bool updateShouldNotify(StringsScope oldWidget) =>
      strings != oldWidget.strings;
}
