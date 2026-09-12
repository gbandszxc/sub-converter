import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../utils/timestamp.dart';

const String _lineFeed = '\n';

/// Metadata tags written first, in this fixed order, before any remaining
/// fields. Keys are matched case-insensitively but written with the casing
/// stored in [SubtitleMetadata.fields].
const List<String> _orderedTagKeys = <String>[
  'ti',
  'ar',
  'al',
  'by',
  'offset',
  'length',
];

/// Renders the unified model as LRC text.
///
/// Metadata fields are written as `[key:value]` lines (known tags first in
/// [_orderedTagKeys] order, then the rest in insertion order), followed by a
/// blank line and one `[mm:ss.xx]text` line per cue, sorted by start time.
///
/// Lossy by design: end times are dropped (LRC cannot express them), inline
/// styles are dropped, and multi-line cue text is joined onto a single line
/// with spaces because LRC is line-oriented. Cues with empty or
/// whitespace-only text are skipped.
class LrcWriter implements SubtitleWriter {
  /// Creates a stateless LRC writer.
  const LrcWriter();

  @override
  String write(SubtitleDocument document) {
    final List<String> output = <String>[];
    output.addAll(_metadataLines(document.metadata));

    final List<SubtitleCue> cues = List<SubtitleCue>.of(document.cues)
      ..sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));

    final List<String> cueLines = <String>[];
    for (final SubtitleCue cue in cues) {
      if (!cue.hasVisibleText) {
        continue;
      }
      final String stamp = formatTimestampAsMinutes(
        cue.start,
        fractionDigits: 2,
      );
      cueLines.add('[$stamp]${_flatten(cue.text)}');
    }

    if (output.isNotEmpty && cueLines.isNotEmpty) {
      output.add('');
    }
    output.addAll(cueLines);

    if (output.isEmpty) {
      return '';
    }
    return output.join(_lineFeed) + _lineFeed;
  }

  List<String> _metadataLines(SubtitleMetadata metadata) {
    final List<String> lines = <String>[];
    final Set<String> emitted = <String>{};

    for (final String wanted in _orderedTagKeys) {
      for (final MapEntry<String, String> entry
          in metadata.fields.entries) {
        if (emitted.contains(entry.key)) {
          continue;
        }
        if (entry.key.toLowerCase() == wanted) {
          lines.add('[${entry.key}:${entry.value}]');
          emitted.add(entry.key);
          break;
        }
      }
    }

    for (final MapEntry<String, String> entry in metadata.fields.entries) {
      if (emitted.contains(entry.key)) {
        continue;
      }
      lines.add('[${entry.key}:${entry.value}]');
      emitted.add(entry.key);
    }

    return lines;
  }

  /// LRC is line-oriented, so embedded newlines become spaces.
  String _flatten(String text) =>
      text.split(_lineFeed).map((String line) => line.trim()).join(' ');
}
