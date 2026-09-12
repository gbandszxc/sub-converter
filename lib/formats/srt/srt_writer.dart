import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../utils/inline_markup.dart';
import '../../utils/subtitle_defaults.dart';
import '../../utils/timestamp.dart';

/// Millisecond precision required by SRT.
const int _fractionDigits = 3;

/// SRT pads the hour field to two digits.
const int _hourDigits = 2;

/// SRT separates seconds from milliseconds with a comma.
const String _fractionSeparator = ',';

/// The SRT timing separator, padded with spaces on both sides.
const String _arrowSeparator = ' --> ';

/// Renders the unified model as SubRip (`.srt`) text.
///
/// Cues are renumbered sequentially from 1; the original `srt.index` metadata
/// is ignored. Cues without an explicit end time are given one through
/// [SubtitleDocument.resolveMissingEndTimes]; trailing positioning data
/// (`X1:0 X2:100 ...`) is never emitted, because the parser drops it.
/// Cues whose text is empty or whitespace-only are skipped.
class SrtWriter implements SubtitleWriter {
  const SrtWriter();

  @override
  String write(SubtitleDocument document) {
    final SubtitleDocument resolved = document.resolveMissingEndTimes(
      fallback: SubtitleDefaults.lrcEndTimeFallback,
    );

    final List<String> blocks = <String>[];
    int index = 1;
    for (final SubtitleCue cue in resolved.cues) {
      if (!cue.hasVisibleText) {
        continue;
      }
      final String timing = '${_format(cue.start)}$_arrowSeparator'
          '${_format(cue.end!)}';
      final String text =
          HtmlMarkup.render(cue.text, cue.inlineStyles, escape: false);
      blocks.add('$index\n$timing\n$text');
      index++;
    }

    if (blocks.isEmpty) {
      return '';
    }
    return '${blocks.join('\n\n')}\n';
  }

  static String _format(Duration value) => formatTimestamp(
        value,
        separator: _fractionSeparator,
        fractionDigits: _fractionDigits,
        hourDigits: _hourDigits,
      );
}
