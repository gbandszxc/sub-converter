import 'package:flutter/widgets.dart';

/// UI language choices.
///
/// Contains no display text; the names shown in the picker come from
/// `AppStrings` (`languageSystem`, `languageEnglish`, `languageChinese`).
enum AppLanguage { system, english, chinese }

extension AppLanguageResolution on AppLanguage {
  /// The locale to hand to `MaterialApp`, or `null` to let Flutter/OS decide.
  ///
  /// Only [AppLanguage.system] returns `null`; the other choices pin a locale.
  Locale? get locale {
    switch (this) {
      case AppLanguage.system:
        return null;
      case AppLanguage.english:
        return const Locale('en');
      case AppLanguage.chinese:
        return const Locale('zh');
    }
  }

  bool get isSystem => this == AppLanguage.system;

  /// Resolves [AppLanguage.system] against the platform locale:
  /// Chinese (`zh*`) -> [AppLanguage.chinese], anything else -> english.
  ///
  /// Any `zh` locale (zh, zh-CN, zh-Hans, zh-TW, ...) maps to chinese: the app
  /// ships a single Simplified Chinese translation, so Traditional users get
  /// Simplified rather than falling back to English.
  AppLanguage resolve(Locale platformLocale) {
    switch (this) {
      case AppLanguage.english:
        return AppLanguage.english;
      case AppLanguage.chinese:
        return AppLanguage.chinese;
      case AppLanguage.system:
        // `startsWith` catches zh, zh-CN, zh-Hans, zh-TW and the like, including
        // callers that pass a full tag as the language code.
        return platformLocale.languageCode.startsWith('zh')
            ? AppLanguage.chinese
            : AppLanguage.english;
    }
  }
}
