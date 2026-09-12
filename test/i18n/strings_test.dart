import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/i18n/app_language.dart';
import 'package:sub_converter/i18n/app_strings.dart';
import 'package:sub_converter/i18n/strings_en.dart';
import 'package:sub_converter/i18n/strings_zh.dart';
import 'package:sub_converter/models/loss_report.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';

/// Every member of [AppStrings], called explicitly.
///
/// The abstract base class makes a forgotten translation a compile error; this
/// test adds the runtime checks that a compile error cannot: no empty strings,
/// and no Chinese member accidentally left as its English copy.
Map<String, String> _values(AppStrings s) => <String, String>{
  'appTitle': s.appTitle,
  'addFiles': s.addFiles,
  'clear': s.clear,
  'remove': s.remove,
  'targetFormat': s.targetFormat,
  'output': s.output,
  'outputSourceFolder': s.outputSourceFolder,
  'outputCustomFolder': s.outputCustomFolder,
  'choose': s.choose,
  'noFolderChosen': s.noFolderChosen,
  'chooseFolderError': s.chooseFolderError,
  'conflict': s.conflict,
  'conflictAutoRename': s.conflictAutoRename,
  'conflictOverwrite': s.conflictOverwrite,
  'conflictSkip': s.conflictSkip,
  'conflictAutoRenameHelp': s.conflictAutoRenameHelp,
  'conflictOverwriteHelp': s.conflictOverwriteHelp,
  'conflictSkipHelp': s.conflictSkipHelp,
  'timeOffset': s.timeOffset,
  'timeOffsetHint': s.timeOffsetHint,
  'resetOffset': s.resetOffset,
  'writeBom': s.writeBom,
  'language': s.language,
  'languageSystem': s.languageSystem,
  'languageEnglish': s.languageEnglish,
  'languageChinese': s.languageChinese,
  'font': s.font,
  'fontSystemDefault': s.fontSystemDefault,
  'fontSystemDefaultHelp': s.fontSystemDefaultHelp,
  'convert': s.convert,
  'convertWithCount': s.convertWithCount(3),
  'emptyTitle': s.emptyTitle,
  'emptySubtitle': s.emptySubtitle,
  'noFiles': s.noFiles,
  'fileCount': s.fileCount(3),
  'inspecting': s.inspecting,
  'ready': s.ready,
  'converting': s.converting,
  'convertedTo': s.convertedTo('SRT'),
  'conversionFailed': s.conversionFailed,
  'skippedExisting': s.skippedExisting,
  'renamedNote': s.renamedNote('E01.srt'),
  'unknown': s.unknown,
  'lossyNotice': s.lossyNotice,
  'batchSummary': s.batchSummary(succeeded: 2, failed: 1, skipped: 3, lossy: 1),
  'lossInlineStyles': s.lossInlineStyles('LRC'),
  'lossPositions': s.lossPositions('LRC'),
  'lossNamedStyles': s.lossNamedStyles('LRC'),
  'lossLrcLineBreaks': s.lossLrcLineBreaks,
  'lossLrcEndTimes': s.lossLrcEndTimes,
  'lossInvertedCues': s.lossInvertedCues(3),
  'lossWarning': s.lossWarning(
    LossKind.invertedCueTiming,
    targetFormat: 'LRC',
    count: 3,
  ),
  'unsupportedFormat': s.unsupportedFormat,
  'encodingDetectionFailed': s.encodingDetectionFailed,
  'invalidSubtitleSyntax': s.invalidSubtitleSyntax,
  'emptyDocument': s.emptyDocument,
  'cannotWriteOutput': s.cannotWriteOutput,
  'permissionDenied': s.permissionDenied,
  'targetPathUnavailable': s.targetPathUnavailable,
  'readFailed': s.readFailed,
  'failureTitle': s.failureTitle(ConversionFailure.unsupportedFormat),
  'filterSubtitleFiles': s.filterSubtitleFiles,
  'filterAllFiles': s.filterAllFiles,
  'formatDescription.srt': s.formatDescription(SubtitleFormat.srt),
  'formatDescription.vtt': s.formatDescription(SubtitleFormat.vtt),
  'formatDescription.lrc': s.formatDescription(SubtitleFormat.lrc),
  'formatDescription.ass': s.formatDescription(SubtitleFormat.ass),
  'formatDescription.ssa': s.formatDescription(SubtitleFormat.ssa),
  'formatDescription.sbv': s.formatDescription(SubtitleFormat.sbv),
};

/// Strings that are deliberately identical in both languages.
const Set<String> _intentionallyShared = <String>{
  // Each language is listed in its own script in every locale.
  'languageEnglish',
  'languageChinese',
  // Product names inside the format descriptions. They happen to carry a
  // Chinese suffix today; they are permitted to stay identical instead.
  'formatDescription.srt',
  'formatDescription.vtt',
  'formatDescription.lrc',
  'formatDescription.ass',
  'formatDescription.ssa',
  'formatDescription.sbv',
};

void main() {
  const AppStrings en = AppStringsEn();
  const AppStrings zh = AppStringsZh();

  group('AppStrings tables', () {
    test('forLanguage picks the matching table', () {
      expect(AppStrings.forLanguage(AppLanguage.english), isA<AppStringsEn>());
      expect(AppStrings.forLanguage(AppLanguage.chinese), isA<AppStringsZh>());
    });

    test('every member is non-empty in both languages', () {
      final Map<String, String> enValues = _values(en);
      final Map<String, String> zhValues = _values(zh);
      expect(zhValues.keys.toSet(), enValues.keys.toSet());
      for (final MapEntry<String, String> entry in enValues.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: 'empty en ${entry.key}');
        expect(
          zhValues[entry.key]!.trim(),
          isNotEmpty,
          reason: 'empty zh ${entry.key}',
        );
      }
    });

    test('no Chinese translation is an accidental copy of English', () {
      final Map<String, String> enValues = _values(en);
      final Map<String, String> zhValues = _values(zh);
      for (final MapEntry<String, String> entry in enValues.entries) {
        if (_intentionallyShared.contains(entry.key)) {
          continue;
        }
        expect(
          zhValues[entry.key],
          isNot(equals(entry.value)),
          reason: '${entry.key} is still English in the Chinese table',
        );
      }
    });
  });

  group('batchSummary', () {
    test('English composes naturally and omits zero parts', () {
      expect(
        en.batchSummary(succeeded: 0, failed: 0, skipped: 0, lossy: 0),
        '',
      );
      expect(
        en.batchSummary(succeeded: 2, failed: 0, skipped: 0, lossy: 0),
        '2 succeeded.',
      );
      expect(
        en.batchSummary(succeeded: 2, failed: 1, skipped: 0, lossy: 0),
        '2 succeeded, 1 failed.',
      );
      expect(
        en.batchSummary(succeeded: 0, failed: 0, skipped: 3, lossy: 0),
        '3 skipped.',
      );
      expect(
        en.batchSummary(succeeded: 2, failed: 1, skipped: 1, lossy: 1),
        '2 succeeded, 1 failed, 1 skipped. 1 lost some styling.',
      );
    });

    test('Chinese composes naturally and omits zero parts', () {
      expect(
        zh.batchSummary(succeeded: 0, failed: 0, skipped: 0, lossy: 0),
        '',
      );
      expect(
        zh.batchSummary(succeeded: 2, failed: 0, skipped: 0, lossy: 0),
        '2 个成功。',
      );
      expect(
        zh.batchSummary(succeeded: 2, failed: 1, skipped: 0, lossy: 1),
        '2 个成功，1 个失败。1 个有样式丢失。',
      );
      expect(
        zh.batchSummary(succeeded: 0, failed: 0, skipped: 3, lossy: 0),
        '3 个已跳过。',
      );
    });
  });

  group('AppLanguage.resolve', () {
    test('any zh locale resolves to Chinese', () {
      for (final Locale locale in <Locale>[
        const Locale('zh'),
        const Locale('zh', 'CN'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        const Locale('zh', 'TW'),
        const Locale('zh-Hans'),
      ]) {
        expect(
          AppLanguage.system.resolve(locale),
          AppLanguage.chinese,
          reason: '$locale should use the single Chinese translation',
        );
      }
    });

    test('non-zh locales resolve to English', () {
      expect(
        AppLanguage.system.resolve(const Locale('en')),
        AppLanguage.english,
      );
      expect(
        AppLanguage.system.resolve(const Locale('en', 'US')),
        AppLanguage.english,
      );
    });

    test('an explicit choice ignores the platform locale', () {
      expect(
        AppLanguage.english.resolve(const Locale('zh', 'CN')),
        AppLanguage.english,
      );
      expect(
        AppLanguage.chinese.resolve(const Locale('en', 'US')),
        AppLanguage.chinese,
      );
    });

    test('locale is null for system and pinned otherwise', () {
      expect(AppLanguage.system.locale, isNull);
      expect(AppLanguage.english.locale, const Locale('en'));
      expect(AppLanguage.chinese.locale, const Locale('zh'));
      expect(AppLanguage.system.isSystem, isTrue);
      expect(AppLanguage.english.isSystem, isFalse);
    });
  });
}
