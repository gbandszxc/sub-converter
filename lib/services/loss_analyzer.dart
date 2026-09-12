import '../models/format_descriptor.dart';
import '../models/loss_report.dart';
import '../models/subtitle_cue.dart';
import '../models/subtitle_document.dart';
import '../models/subtitle_format.dart';
import '../models/subtitle_style.dart';

/// Compares what a document carries against what the target format can
/// express.
///
/// The capability checks use the flags on [FormatDescriptor], so a new format
/// gets sensible reporting just by declaring them. The remaining rules cover
/// losses specific to a target format's model (LRC has neither end times nor
/// line breaks).
///
/// The analyzer reports structured [LossKind]s only. Localized wording is an
/// i18n concern and is applied by the UI, which knows the target format's
/// label and the selected language.
class LossAnalyzer {
  const LossAnalyzer();

  LossReport analyze({
    required SubtitleDocument document,
    required FormatDescriptor source,
    required FormatDescriptor target,
  }) {
    final List<LossWarning> warnings = <LossWarning>[];
    final bool sameFormat = source.format == target.format;

    if (!target.supportsInlineStyles &&
        document.cues.any((SubtitleCue cue) => cue.inlineStyles.isNotEmpty)) {
      warnings.add(const LossWarning(LossKind.inlineStylesDropped));
    }

    if (!target.supportsPositions &&
        document.cues.any((SubtitleCue cue) => cue.position != null)) {
      warnings.add(const LossWarning(LossKind.positionsDropped));
    }

    if (!target.supportsStyles &&
        document.styles.any((SubtitleStyle style) => style.name.isNotEmpty)) {
      warnings.add(const LossWarning(LossKind.namedStylesDropped));
    }

    if (!sameFormat && target.format == SubtitleFormat.lrc) {
      if (document.cues.any((SubtitleCue cue) => cue.text.contains('\n'))) {
        warnings.add(const LossWarning(LossKind.lrcLineBreaksJoined));
      }
      if (document.cues.any((SubtitleCue cue) => cue.hasExplicitEnd)) {
        warnings.add(const LossWarning(LossKind.lrcEndTimesDropped));
      }
    }

    // Source-side sanity, not a format limitation: an inverted interval is
    // usually a typo. The file still converts, because dropping the whole file
    // over one bad cue would lose far more than it protects.
    final int inverted = document.cues
        .where((SubtitleCue cue) => cue.isMalformed)
        .length;
    if (inverted > 0) {
      warnings.add(LossWarning(LossKind.invertedCueTiming, count: inverted));
    }

    return warnings.isEmpty ? LossReport.none : LossReport(warnings);
  }
}
