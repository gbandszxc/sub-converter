import 'subtitle_exception.dart';
import 'subtitle_format.dart';

/// What to do when the resolved output file already exists.
///
/// [autoRename] is the default and the only policy that can never destroy
/// data.
enum OutputConflictPolicy {
  /// Write `E01 (1).srt` instead of overwriting `E01.srt`.
  autoRename('Auto rename'),

  /// Replace the existing file. Never applied to the source file itself.
  overwrite('Overwrite'),

  /// Leave the existing file alone and report the entry as skipped.
  skip('Skip');

  const OutputConflictPolicy(this.label);

  final String label;
}

/// Where converted files are written.
enum OutputLocation {
  /// Next to each source file (the default).
  sourceDirectory('Source file folder'),

  /// All files into one user-chosen directory.
  customDirectory('Custom folder');

  const OutputLocation(this.label);

  final String label;
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

  /// User-facing problem with this configuration, or `null` when it is usable.
  String? validationError() {
    if (outputLocation == OutputLocation.customDirectory) {
      final String? directory = outputDirectory?.trim();
      if (directory == null || directory.isEmpty) {
        return 'Choose an output folder.';
      }
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
    );
  }

  @override
  String toString() => 'ConversionOptions(target: ${targetFormat.label}, '
      'location: ${outputLocation.name}, offset: $timeOffset, '
      'conflict: ${conflictPolicy.name})';
}

/// Outcome of processing one file.
enum ConversionStatus {
  pending('Pending'),
  converting('Converting'),
  succeeded('Succeeded'),
  failed('Failed'),
  skipped('Skipped');

  const ConversionStatus(this.label);

  final String label;

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
    this.warnings = const <String>[],
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
        warnings = const <String>[],
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
  /// a rename are reported separately.
  final List<String> warnings;

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

  /// One-line summary for the UI.
  String get summary {
    switch (status) {
      case ConversionStatus.pending:
        return 'Ready';
      case ConversionStatus.converting:
        return 'Converting...';
      case ConversionStatus.succeeded:
        return 'Converted to ${targetFormat?.label ?? '?'}';
      case ConversionStatus.skipped:
        return 'Skipped: output file already exists';
      case ConversionStatus.failed:
        return failure?.title ?? 'Conversion failed';
    }
  }

  ConversionResult copyWith({
    ConversionStatus? status,
    SubtitleFormat? sourceFormat,
    SubtitleFormat? targetFormat,
    String? outputPath,
    ConversionFailure? failure,
    String? detail,
    String? detectedEncoding,
    List<String>? warnings,
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
