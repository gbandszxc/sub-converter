import 'package:flutter/widgets.dart';

import '../models/loss_report.dart';
import '../models/subtitle_exception.dart';
import '../models/subtitle_format.dart';
import 'app_language.dart';
import 'strings_en.dart';
import 'strings_scope.dart';
import 'strings_zh.dart';

/// The complete set of user-visible strings, one getter or method per string.
///
/// Every member is abstract, so a language implementation that forgets a
/// translation is a compile error rather than a silent English fallback. The
/// class has no default text of its own.
abstract class AppStrings {
  const AppStrings();

  /// The table for [language].
  ///
  /// [AppLanguage.system] should already have been resolved by the caller; if
  /// it reaches here it falls back to English, but the app never displays an
  /// unresolved language.
  static AppStrings forLanguage(AppLanguage language) {
    switch (language) {
      case AppLanguage.english:
        return const AppStringsEn();
      case AppLanguage.chinese:
        return const AppStringsZh();
      case AppLanguage.system:
        return const AppStringsEn();
    }
  }

  /// Reads the table from the nearest [StringsScope].
  ///
  /// Throws a [FlutterError] when there is no scope: failing loud is better
  /// than silently rendering English in a Chinese UI.
  static AppStrings of(BuildContext context) => StringsScope.of(context);

  // --- Chrome / actions ----------------------------------------------------

  String get appTitle;
  String get addFiles;
  String get clear;
  String get remove;

  // --- Options -------------------------------------------------------------

  String get targetFormat;
  String get output;
  String get outputSourceFolder;
  String get outputCustomFolder;
  String get choose;
  String get noFolderChosen;
  String get chooseFolderError;
  String get conflict;
  String get conflictAutoRename;
  String get conflictOverwrite;
  String get conflictSkip;
  String get conflictAutoRenameHelp;
  String get conflictOverwriteHelp;
  String get conflictSkipHelp;
  String get timeOffset;
  String get timeOffsetHint;
  String get resetOffset;
  String get writeBom;
  String get stripMediaSuffix;
  String get stripMediaSuffixHelp;
  String get language;
  String get languageSystem;
  String get languageEnglish;
  String get languageChinese;
  String get font;
  String get fontSystemDefault;
  String get fontSystemDefaultHelp;
  String get convert;

  /// `Convert 1 file` / `Convert 3 files`.
  String convertWithCount(int count);

  // --- Empty state / rows / status -----------------------------------------

  String get emptyTitle;
  String get emptySubtitle;
  String get noFiles;

  /// `1 file` / `3 files`.
  String fileCount(int count);

  String get inspecting;
  String get ready;
  String get converting;

  /// `Converted to SRT`; [format] is a language-neutral label such as `SRT`.
  String convertedTo(String format);

  String get conversionFailed;
  String get skippedExisting;

  /// `<name>  (renamed, name was taken)`.
  String renamedNote(String name);

  String get unknown;

  /// The short notice on a successful but lossy row.
  String get lossyNotice;

  /// Native composition of the batch summary; parts with a zero count are
  /// omitted and an empty result means nothing happened.
  String batchSummary({
    required int succeeded,
    required int failed,
    required int skipped,
    required int lossy,
  });

  // --- Loss warnings -------------------------------------------------------

  String lossInlineStyles(String target);
  String lossPositions(String target);
  String lossNamedStyles(String target);
  String get lossLrcLineBreaks;
  String get lossLrcEndTimes;
  String lossInvertedCues(int count);

  /// Localized sentence for a structured [LossWarning].
  ///
  /// Dispatch is language-independent, so it lives here once; each language
  /// only supplies the leaf sentences above.
  String lossWarning(
    LossKind kind, {
    required String targetFormat,
    required int count,
  }) {
    switch (kind) {
      case LossKind.inlineStylesDropped:
        return lossInlineStyles(targetFormat);
      case LossKind.positionsDropped:
        return lossPositions(targetFormat);
      case LossKind.namedStylesDropped:
        return lossNamedStyles(targetFormat);
      case LossKind.lrcLineBreaksJoined:
        return lossLrcLineBreaks;
      case LossKind.lrcEndTimesDropped:
        return lossLrcEndTimes;
      case LossKind.invertedCueTiming:
        return lossInvertedCues(count);
    }
  }

  // --- Failure titles ------------------------------------------------------

  String get unsupportedFormat;
  String get encodingDetectionFailed;
  String get invalidSubtitleSyntax;
  String get emptyDocument;
  String get cannotWriteOutput;
  String get permissionDenied;
  String get targetPathUnavailable;
  String get readFailed;

  /// Localized title for a machine-readable failure reason.
  String failureTitle(ConversionFailure failure) {
    switch (failure) {
      case ConversionFailure.unsupportedFormat:
        return unsupportedFormat;
      case ConversionFailure.encodingDetectionFailed:
        return encodingDetectionFailed;
      case ConversionFailure.invalidSubtitleSyntax:
        return invalidSubtitleSyntax;
      case ConversionFailure.emptyDocument:
        return emptyDocument;
      case ConversionFailure.cannotWriteOutput:
        return cannotWriteOutput;
      case ConversionFailure.permissionDenied:
        return permissionDenied;
      case ConversionFailure.targetPathUnavailable:
        return targetPathUnavailable;
      case ConversionFailure.readFailed:
        return readFailed;
      case ConversionFailure.unknown:
        return conversionFailed;
    }
  }

  // --- Native file dialog filters ------------------------------------------

  String get filterSubtitleFiles;
  String get filterAllFiles;

  // --- Format descriptions -------------------------------------------------

  String get formatSubRip;
  String get formatWebVtt;
  String get formatLrc;
  String get formatAss;
  String get formatSsa;
  String get formatSbv;

  /// Longer, localized description for [format], shown after its label.
  String formatDescription(SubtitleFormat format) {
    switch (format) {
      case SubtitleFormat.srt:
        return formatSubRip;
      case SubtitleFormat.vtt:
        return formatWebVtt;
      case SubtitleFormat.lrc:
        return formatLrc;
      case SubtitleFormat.ass:
        return formatAss;
      case SubtitleFormat.ssa:
        return formatSsa;
      case SubtitleFormat.sbv:
        return formatSbv;
    }
  }
}
