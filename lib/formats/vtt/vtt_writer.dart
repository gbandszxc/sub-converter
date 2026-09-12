import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../utils/inline_markup.dart';
import '../../utils/subtitle_defaults.dart';
import '../../utils/timestamp.dart';
import 'vtt_parser.dart';

/// The mandatory first line of every WebVTT file.
const String _headerKeyword = 'WEBVTT';

/// Separator between the start and end timestamps of a cue.
const String _timingArrow = ' --> ';

const String _lineFeed = '\n';

/// Renders the unified model as WebVTT text.
///
/// Output uses LF newlines and a single trailing newline. [SubtitleMetadata.fields]
/// are re-emitted in insertion order with their original key casing, so a
/// parsed file round-trips its header. `STYLE`/`REGION` blocks are not written
/// because the parser does not preserve them.
///
/// Cues without an end time get one via [SubtitleDocument.resolveMissingEndTimes]
/// using [SubtitleDefaults.lrcEndTimeFallback]. Cues with empty or
/// whitespace-only text are skipped.
class VttWriter implements SubtitleWriter {
  /// Creates a stateless WebVTT writer.
  const VttWriter();

  @override
  String write(SubtitleDocument document) {
    final SubtitleDocument resolved = document.resolveMissingEndTimes(
      fallback: SubtitleDefaults.lrcEndTimeFallback,
    );

    final StringBuffer header = StringBuffer('$_headerKeyword$_lineFeed');
    for (final MapEntry<String, String> entry
        in document.metadata.fields.entries) {
      header.write('${entry.key}: ${entry.value}$_lineFeed');
    }

    final List<String> blocks = <String>[];
    for (final SubtitleCue cue in resolved.cues) {
      if (!cue.hasVisibleText) {
        continue;
      }
      blocks.add(_writeCue(cue));
    }

    if (blocks.isEmpty) {
      return header.toString();
    }
    return '${header.toString()}$_lineFeed'
        '${blocks.join('$_lineFeed$_lineFeed')}$_lineFeed';
  }

  String _writeCue(SubtitleCue cue) {
    final StringBuffer buffer = StringBuffer();

    final Object? identifier = cue.metadata[vttIdentifierMetadataKey];
    if (identifier is String && identifier.isNotEmpty) {
      buffer.write('$identifier$_lineFeed');
    }

    buffer.write(formatTimestamp(cue.start));
    buffer.write(_timingArrow);
    buffer.write(formatTimestamp(cue.end!));

    final Object? settings = cue.metadata[vttSettingsMetadataKey];
    if (settings is String && settings.isNotEmpty) {
      buffer.write(' $settings');
    }
    buffer.write(_lineFeed);

    buffer.write(HtmlMarkup.render(cue.text, cue.inlineStyles, escape: true));
    return buffer.toString();
  }
}
