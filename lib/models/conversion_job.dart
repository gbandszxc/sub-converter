import 'loss_report.dart';
import 'subtitle_exception.dart';
import 'subtitle_format.dart';

/// What to do when the resolved output file already exists.
///
/// [autoRename] is the default and the only policy that can never destroy
/// data.
///
/// The enum is display-free: the UI maps each value to a localized label from
/// `AppStrings`.
enum OutputConflictPolicy {
  /// Write `E01 (1).srt` instead of overwriting `E01.srt`.
  autoRename,

  /// Replace the existing file. Never applied to the source file itself.
  overwrite,

  /// Leave the existing file alone and report the entry as skipped.
  skip,
}

/// Where converted files are written.
///
/// Display-free; the UI localizes the labels.
enum OutputLocation {
  /// Next to each source file (the default).
  sourceDirectory,

  /// All files into one user-chosen directory.
  customDirectory,
}

/// Everything that controls a batch conversion run.
///
/// Immutable; the UI rebuilds it with [copyWith] as the user changes options.
class ConversionOptions {
  const ConversionOptions({
    required this.targetFormat,
    this.outputLocation = OutputLocation.sourceDirectory,
    this.outputDirectory,
    this.timeOffset = Duration.zero,
    this.conflictPolicy = OutputConflictPolicy.autoRename,
    this.writeUtf8Bom = false,
    this.stripMediaSuffix = false,
  });

  final SubtitleFormat targetFormat;
  final OutputLocation outputLocation;

  /// Required when [outputLocation] is [OutputLocation.customDirectory].
  final String? outputDirectory;

  /// Applied to every cue before writing; negative values move cues earlier
  /// and are clamped at zero.
  final Duration timeOffset;

  final OutputConflictPolicy conflictPolicy;

  /// Whether output starts with a UTF-8 BOM. Output is always UTF-8.
  final bool writeUtf8Bom;

  /// Whether to drop a media-name suffix from the output base name, e.g.
  /// `E01.wav.vtt` converting to LRC writes `E01.lrc` instead of
  /// `E01.wav.lrc`. What counts as a media suffix is decided by
  /// `OutputPathResolver.mediaExtensions`; the model stays display- and
  /// format-free.
  final bool stripMediaSuffix;

  /// True when [outputLocation] is [OutputLocation.customDirectory] but no
  /// usable folder was chosen. The UI maps this to a localized message
  /// (`AppStrings.chooseFolderError`); no display text lives in the model.
  bool get isOutputDirectoryMissing {
    if (outputLocation != OutputLocation.customDirectory) {
      return false;
    }
    final String? directory = outputDirectory?.trim();
    return directory == null || directory.isEmpty;
  }

  /// Developer-facing description of a configuration problem, or `null` when
  /// the options are usable. The UI must render [isOutputDirectoryMissing]
  /// through `AppStrings.chooseFolderError` rather than show this text.
  String? validationError() {
    if (isOutputDirectoryMissing) {
      return 'Choose an output folder.';
    }
    return null;
  }

  ConversionOptions copyWith({
    SubtitleFormat? targetFormat,
    OutputLocation? outputLocation,
    Object? outputDirectory = _unset,
    Duration? timeOffset,
    OutputConflictPolicy? conflictPolicy,
    bool? writeUtf8Bom,
    bool? stripMediaSuffix,
  }) {
    return ConversionOptions(
      targetFormat: targetFormat ?? this.targetFormat,
      outputLocation: outputLocation ?? this.outputLocation,
      outputDirectory: outputDirectory == _unset
          ? this.outputDirectory
          : outputDirectory as String?,
      timeOffset: timeOffset ?? this.timeOffset,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      writeUtf8Bom: writeUtf8Bom ?? this.writeUtf8Bom,
      stripMediaSuffix: stripMediaSuffix ?? this.stripMediaSuffix,
    );
  }

  @override
  String toString() =>
      'ConversionOptions(target: ${targetFormat.label}, '
      'location: ${outputLocation.name}, offset: $timeOffset, '
      'conflict: ${conflictPolicy.name}, '
      'stripMediaSuffix: $stripMediaSuffix)';
}

/// Outcome of processing one file.
///
/// Display-free; the UI localizes the status text.
enum ConversionStatus {
  pending,
  converting,
  succeeded,
  failed,
  skipped;

  /// True while the entry has not reached a final state.
  bool get isInProgress =>
      this == ConversionStatus.pending || this == ConversionStatus.converting;
}

/// Result of converting one file, ready to render in the file list.
class ConversionResult {
  const ConversionResult({
    required this.sourcePath,
    required this.status,
    this.sourceFormat,
    this.targetFormat,
    this.outputPath,
    this.failure,
    this.detail,
    this.detectedEncoding,
    this.warnings = const <LossWarning>[],
    this.outputRenamed = false,
    this.cueCount = 0,
    this.elapsed = Duration.zero,
  });

  /// An entry that has been added to the list but not converted yet.
  const ConversionResult.pending(this.sourcePath)
    : status = ConversionStatus.pending,
      sourceFormat = null,
      targetFormat = null,
      outputPath = null,
      failure = null,
      detail = null,
      detectedEncoding = null,
      warnings = const <LossWarning>[],
      outputRenamed = false,
      cueCount = 0,
      elapsed = Duration.zero;

  final String sourcePath;
  final ConversionStatus status;
  final SubtitleFormat? sourceFormat;
  final SubtitleFormat? targetFormat;
  final String? outputPath;

  /// Machine-readable failure reason, when [status] is
  /// [ConversionStatus.failed].
  final ConversionFailure? failure;

  /// Short technical detail. Never a stack trace.
  final String? detail;

  /// Encoding the source file was decoded with, e.g. `GBK`.
  final String? detectedEncoding;

  /// Non-fatal information loss, e.g. dropped styling. Only ever populated
  /// with loss notes, so [isLossy] means what it says; file-level facts such as
  /// a rename are reported separately. The UI localizes each warning.
  final List<LossWarning> warnings;

  /// True when the output had to be given a numbered name because the plain
  /// name was taken (or was the source file itself).
  final bool outputRenamed;

  final int cueCount;
  final Duration elapsed;

  bool get isSuccess => status == ConversionStatus.succeeded;
  bool get isFailure => status == ConversionStatus.failed;
  bool get isSkipped => status == ConversionStatus.skipped;

  /// True when the conversion succeeded but lost some source information.
  bool get isLossy => isSuccess && warnings.isNotEmpty;

  ConversionResult copyWith({
    ConversionStatus? status,
    SubtitleFormat? sourceFormat,
    SubtitleFormat? targetFormat,
    String? outputPath,
    ConversionFailure? failure,
    String? detail,
    String? detectedEncoding,
    List<LossWarning>? warnings,
    bool? outputRenamed,
    int? cueCount,
    Duration? elapsed,
  }) {
    return ConversionResult(
      sourcePath: sourcePath,
      status: status ?? this.status,
      sourceFormat: sourceFormat ?? this.sourceFormat,
      targetFormat: targetFormat ?? this.targetFormat,
      outputPath: outputPath ?? this.outputPath,
      failure: failure ?? this.failure,
      detail: detail ?? this.detail,
      detectedEncoding: detectedEncoding ?? this.detectedEncoding,
      warnings: warnings ?? this.warnings,
      outputRenamed: outputRenamed ?? this.outputRenamed,
      cueCount: cueCount ?? this.cueCount,
      elapsed: elapsed ?? this.elapsed,
    );
  }

  @override
  String toString() => 'ConversionResult(${status.name}, $sourcePath)';
}

const Object _unset = Object();
