import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../utils/subtitle_defaults.dart';
import '../../utils/timestamp.dart';

/// SBV always uses millisecond precision.
const int _fractionDigits = 3;

/// SBV conventionally writes a single-digit hour.
const int _hourDigits = 1;

/// SBV separates the two timestamps of a cue with a comma and no arrow.
const String _timestampSeparator = ',';

/// Renders the unified model as YouTube SBV (`.sbv`) text.
///
/// Deliberately lossy: inline emphasis and cue positions are dropped, because
/// SBV cannot express them; only plain [SubtitleCue.text] is written. Cues
/// without an explicit end time are given one through
/// [SubtitleDocument.resolveMissingEndTimes]. Cues whose text is empty or
/// whitespace-only are skipped.
class SbvWriter implements SubtitleWriter {
  const SbvWriter();

  @override
  String write(SubtitleDocument document) {
    final SubtitleDocument resolved = document.resolveMissingEndTimes(
      fallback: SubtitleDefaults.lrcEndTimeFallback,
    );

    final List<String> blocks = <String>[];
    for (final SubtitleCue cue in resolved.cues) {
      if (!cue.hasVisibleText) {
        continue;
      }
      final String timing = '${_format(cue.start)}$_timestampSeparator'
          '${_format(cue.end!)}';
      blocks.add('$timing\n${cue.text}');
    }

    if (blocks.isEmpty) {
      return '';
    }
    return '${blocks.join('\n\n')}\n';
  }

  static String _format(Duration value) => formatTimestamp(
        value,
        fractionDigits: _fractionDigits,
        hourDigits: _hourDigits,
      );
}
