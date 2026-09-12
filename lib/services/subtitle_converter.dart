import '../formats/format_registry.dart';
import '../models/format_descriptor.dart';
import '../models/subtitle_document.dart';
import '../models/subtitle_exception.dart';
import '../models/subtitle_format.dart';
import 'loss_analyzer.dart';

/// A converted subtitle, ready to be written to disk.
class ConversionOutput {
  const ConversionOutput({
    required this.content,
    required this.sourceFormat,
    required this.targetFormat,
    required this.loss,
    required this.cueCount,
    required this.timeOffset,
  });

  /// Rendered target-format text.
  final String content;

  final SubtitleFormat sourceFormat;
  final SubtitleFormat targetFormat;

  /// What could not be carried over.
  final LossReport loss;

  final int cueCount;

  /// Offset that was applied, for display.
  final Duration timeOffset;

  bool get isLossy => loss.isLossy;

  @override
  String toString() => 'ConversionOutput(${sourceFormat.label} -> '
      '${targetFormat.label}, $cueCount cues)';
}

/// The conversion core: source text in, target text out.
///
/// Pure and synchronous — no file system, no Flutter. Every conversion goes
/// `parse -> SubtitleDocument -> write`, so there is one code path rather than
/// one per format pair.
class SubtitleConverter {
  SubtitleConverter(this.registry, {this.lossAnalyzer = const LossAnalyzer()});

  final FormatRegistry registry;
  final LossAnalyzer lossAnalyzer;

  /// Converts [content] from [sourceFormat] to [targetFormat].
  ///
  /// [timeOffset] is applied to every cue, clamping at zero.
  ///
  /// Throws [UnsupportedFormatException] when a format is not registered,
  /// [SubtitleSyntaxException] when the content does not parse, and a
  /// [SubtitleConversionException] with
  /// [ConversionFailure.emptyDocument] when there is nothing to write.
  ConversionOutput convert(
    String content, {
    required SubtitleFormat sourceFormat,
    required SubtitleFormat targetFormat,
    Duration timeOffset = Duration.zero,
  }) {
    final FormatDescriptor? sourceDescriptor =
        registry.descriptorFor(sourceFormat);
    final FormatDescriptor? targetDescriptor =
        registry.descriptorFor(targetFormat);
    if (sourceDescriptor == null || targetDescriptor == null) {
      throw UnsupportedFormatException(
        'Conversion from ${sourceFormat.label} to ${targetFormat.label} '
        'is not supported.',
      );
    }

    final SubtitleDocument document = registry.parserFor(sourceFormat).parse(content);
    document.sourceFormat = sourceFormat;

    if (document.isEmpty) {
      throw SubtitleConversionException(
        ConversionFailure.emptyDocument,
        'The file contains no subtitle entries.',
      );
    }

    // Work on a copy so the parsed document stays untouched for the caller.
    final SubtitleDocument working = document.copy()..shift(timeOffset);
    final LossReport loss = lossAnalyzer.analyze(
      document: working,
      source: sourceDescriptor,
      target: targetDescriptor,
    );
    final String rendered = registry.writerFor(targetFormat).write(working);

    if (rendered.trim().isEmpty) {
      throw SubtitleConversionException(
        ConversionFailure.emptyDocument,
        'The file contains no subtitle entries to write.',
      );
    }

    return ConversionOutput(
      content: rendered,
      sourceFormat: sourceFormat,
      targetFormat: targetFormat,
      loss: loss,
      cueCount: working.cues.length,
      timeOffset: timeOffset,
    );
  }
}
