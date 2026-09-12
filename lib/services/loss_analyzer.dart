import '../models/format_descriptor.dart';
import '../models/subtitle_cue.dart';
import '../models/subtitle_document.dart';
import '../models/subtitle_style.dart';
import '../models/subtitle_format.dart';

/// Non-fatal information loss that a conversion will cause.
///
/// A lossy conversion still succeeds; the UI shows these notes next to the
/// result instead of treating it as a failure.
class LossReport {
  const LossReport(this.warnings);

  static const LossReport none = LossReport(<String>[]);

  /// Short, user-facing notes such as
  /// `Inline emphasis cannot be represented in LRC.`
  final List<String> warnings;

  bool get isLossy => warnings.isNotEmpty;

  @override
  String toString() => 'LossReport($warnings)';
}

/// Compares what a document carries against what the target format can
/// express.
///
/// The capability checks use the flags on [FormatDescriptor], so a new format
/// gets sensible reporting just by declaring them. The remaining rules cover
/// losses specific to a target format's model (LRC has neither end times nor
/// line breaks).
class LossAnalyzer {
  const LossAnalyzer();

  LossReport analyze({
    required SubtitleDocument document,
    required FormatDescriptor source,
    required FormatDescriptor target,
  }) {
    final List<String> warnings = <String>[];
    final String targetLabel = target.format.label;
    final bool sameFormat = source.format == target.format;

    if (!target.supportsInlineStyles &&
        document.cues.any((SubtitleCue cue) => cue.inlineStyles.isNotEmpty)) {
      warnings.add(
        'Inline emphasis (bold/italic/underline) cannot be represented in '
        '$targetLabel.',
      );
    }

    if (!target.supportsPositions &&
        document.cues.any((SubtitleCue cue) => cue.position != null)) {
      warnings.add('Screen positioning cannot be represented in $targetLabel.');
    }

    if (!target.supportsStyles &&
        document.styles.any((SubtitleStyle style) => style.name.isNotEmpty)) {
      warnings.add('Named styles cannot be represented in $targetLabel.');
    }

    if (!sameFormat && target.format == SubtitleFormat.lrc) {
      if (document.cues.any((SubtitleCue cue) => cue.text.contains('\n'))) {
        warnings.add('LRC has no line breaks; multi-line cues were joined.');
      }
      if (document.cues.any((SubtitleCue cue) => cue.hasExplicitEnd)) {
        warnings.add('LRC has no end times; end times were dropped.');
      }
    }

    // Source-side sanity, not a format limitation: an inverted interval is
    // usually a typo. The file still converts, because dropping the whole file
    // over one bad cue would lose far more than it protects.
    final int inverted =
        document.cues.where((SubtitleCue cue) => cue.isMalformed).length;
    if (inverted > 0) {
      warnings.add(
        inverted == 1
            ? '1 cue ends before it starts; its times were written unchanged.'
            : '$inverted cues end before they start; their times were written '
                'unchanged.',
      );
    }

    return warnings.isEmpty ? LossReport.none : LossReport(warnings);
  }
}
