import 'app_strings.dart';

/// English strings.
class AppStringsEn extends AppStrings {
  const AppStringsEn();

  @override
  String get appTitle => 'Subtitle Converter';

  @override
  String get addFiles => 'Add files';

  @override
  String get clear => 'Clear';

  @override
  String get remove => 'Remove';

  @override
  String get targetFormat => 'Target format';

  @override
  String get output => 'Output';

  @override
  String get outputSourceFolder => 'Source file folder';

  @override
  String get outputCustomFolder => 'Custom folder';

  @override
  String get choose => 'Choose...';

  @override
  String get noFolderChosen => 'No folder chosen';

  @override
  String get chooseFolderError => 'Choose an output folder.';

  @override
  String get conflict => 'Conflict';

  @override
  String get conflictAutoRename => 'Auto rename';

  @override
  String get conflictOverwrite => 'Overwrite';

  @override
  String get conflictSkip => 'Skip';

  @override
  String get conflictAutoRenameHelp =>
      'Write a numbered file instead of replacing an existing one.';

  @override
  String get conflictOverwriteHelp => 'Replace an existing output file.';

  @override
  String get conflictSkipHelp =>
      'Leave an existing output file and skip the entry.';

  @override
  String get timeOffset => 'Time offset';

  @override
  String get timeOffsetHint =>
      'Negative values move cues earlier; timestamps are clamped at zero.';

  @override
  String get resetOffset => 'Reset offset';

  @override
  String get writeBom => 'Write UTF-8 BOM';

  @override
  String get stripMediaSuffix => 'Strip media suffix';

  @override
  String get stripMediaSuffixHelp =>
      'Names like Movie.wav.vtt repeat the media file name. With this on, '
      'converting to LRC writes Movie.lrc instead of Movie.wav.lrc. The '
      'inner suffix is dropped only when it names a common audio or video '
      'container (wav, mp3, mp4, mkv, ...).';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get font => 'Font';

  @override
  String get fontSystemDefault => 'System default';

  @override
  String get fontSystemDefaultHelp =>
      'Uses the system UI font: Microsoft YaHei on Windows, PingFang on '
      'macOS, and the desktop font on Linux. Any installed font can be '
      'picked instead.';

  @override
  String get convert => 'Convert';

  @override
  String get exitConfirmTitle => 'Exit Subtitle Converter?';

  @override
  String get exitConfirmBody =>
      'The window will close and any conversion still running will stop.';

  @override
  String get exitConfirmExit => 'Exit';

  @override
  String get exitConfirmCancel => 'Cancel';

  @override
  String convertWithCount(int count) =>
      'Convert $count ${count == 1 ? 'file' : 'files'}';

  @override
  String get emptyTitle => 'Drag subtitle files or a folder here';

  @override
  String get emptySubtitle => 'or click Add files to choose them';

  @override
  String get noFiles => 'No files';

  @override
  String fileCount(int count) => '$count ${count == 1 ? 'file' : 'files'}';

  @override
  String get inspecting => 'Inspecting...';

  @override
  String get ready => 'Ready';

  @override
  String get converting => 'Converting...';

  @override
  String convertedTo(String format) => 'Converted to $format';

  @override
  String get conversionFailed => 'Conversion failed';

  @override
  String get skippedExisting => 'Skipped: output file already exists';

  @override
  String renamedNote(String name) => '$name  (renamed, name was taken)';

  @override
  String get unknown => 'Unknown';

  @override
  String get lossyNotice =>
      'Converted; some styling could not be represented in the target format.';

  @override
  String batchSummary({
    required int succeeded,
    required int failed,
    required int skipped,
    required int lossy,
  }) {
    final List<String> parts = <String>[
      if (succeeded > 0) '$succeeded succeeded',
      if (failed > 0) '$failed failed',
      if (skipped > 0) '$skipped skipped',
    ];
    if (parts.isEmpty) {
      return '';
    }
    final String message = '${parts.join(', ')}.';
    if (lossy == 0) {
      return message;
    }
    return '$message $lossy lost some styling.';
  }

  @override
  String lossInlineStyles(String target) =>
      'Inline emphasis (bold/italic/underline) cannot be represented in '
      '$target.';

  @override
  String lossPositions(String target) =>
      'Screen positioning cannot be represented in $target.';

  @override
  String lossNamedStyles(String target) =>
      'Named styles cannot be represented in $target.';

  @override
  String get lossLrcLineBreaks =>
      'LRC has no line breaks; multi-line cues were joined.';

  @override
  String get lossLrcEndTimes => 'LRC has no end times; end times were dropped.';

  @override
  String lossInvertedCues(int count) => count == 1
      ? '1 cue ends before it starts; its times were written unchanged.'
      : '$count cues end before they start; their times were written '
            'unchanged.';

  @override
  String get unsupportedFormat => 'Unsupported format';

  @override
  String get encodingDetectionFailed => 'Encoding detection failed';

  @override
  String get invalidSubtitleSyntax => 'Invalid subtitle syntax';

  @override
  String get emptyDocument => 'No subtitle entries';

  @override
  String get cannotWriteOutput => 'Cannot write output file';

  @override
  String get permissionDenied => 'Permission denied';

  @override
  String get targetPathUnavailable => 'Target path unavailable';

  @override
  String get readFailed => 'Cannot read input file';

  @override
  String get filterSubtitleFiles => 'Subtitle files';

  @override
  String get filterAllFiles => 'All files';

  @override
  String get formatSubRip => 'SubRip';

  @override
  String get formatWebVtt => 'WebVTT';

  @override
  String get formatLrc => 'LRC';

  @override
  String get formatAss => 'Advanced SubStation Alpha';

  @override
  String get formatSsa => 'SubStation Alpha';

  @override
  String get formatSbv => 'YouTube SBV';
}
