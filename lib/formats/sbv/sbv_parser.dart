import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../models/subtitle_exception.dart';
import '../../models/subtitle_format.dart';
import '../../utils/inline_markup.dart';
import '../../utils/timestamp.dart';

/// Byte order mark that some editors prepend to UTF-8 subtitle files.
const String _bom = '\uFEFF';

/// SBV separates the two timestamps of a cue with a comma.
const String _timestampSeparator = ',';

/// Parses YouTube SBV (`.sbv`) content into the unified model.
///
/// Grammar: blocks separated by blank lines. Each block is a timing line
/// `H:MM:SS.mmm,H:MM:SS.mmm` (no arrow) followed by one or more text lines.
/// SBV has no markup, so any emphasis returned by the shared scanner is
/// discarded intentionally and only the plain text is kept.
class SbvParser implements SubtitleParser {
  const SbvParser();

  @override
  SubtitleDocument parse(String content) {
    final String normalized = _normalizeContent(content);
    if (normalized.trim().isEmpty) {
      throw SubtitleSyntaxException('SBV content is empty.');
    }

    final List<List<String>> blocks = _splitIntoBlocks(normalized.split('\n'));
    final List<SubtitleCue> cues = <SubtitleCue>[
      for (final List<String> block in blocks) _parseBlock(block),
    ];
    if (cues.isEmpty) {
      throw SubtitleSyntaxException('No SBV cue blocks found.');
    }
    return SubtitleDocument(
      cues: cues,
      sourceFormat: SubtitleFormat.sbv,
    );
  }

  SubtitleCue _parseBlock(List<String> lines) {
    final _SbvTiming? timing = _parseTiming(lines.first);
    if (timing == null) {
      throw SubtitleSyntaxException(
        'Invalid SBV timing line: "${lines.first}".',
      );
    }

    final String rawText = lines.sublist(1).join('\n');
    // Intentional: SBV cannot express emphasis, so parsed.styles is dropped.
    final ParsedInlineText parsed =
        HtmlMarkup.parse(stripAssOverrideBlocks(rawText));

    return SubtitleCue(
      start: timing.start,
      end: timing.end,
      text: parsed.text,
    );
  }

  _SbvTiming? _parseTiming(String line) {
    final int separatorIndex = line.indexOf(_timestampSeparator);
    if (separatorIndex < 0) {
      return null;
    }

    final Duration? start = tryParseTimestamp(
      line.substring(0, separatorIndex).trim(),
    );
    final Duration? end = tryParseTimestamp(
      line.substring(separatorIndex + _timestampSeparator.length).trim(),
    );
    if (start == null || end == null) {
      return null;
    }
    return _SbvTiming(start, end);
  }

  static String _normalizeContent(String content) {
    final String withoutBom =
        content.startsWith(_bom) ? content.substring(_bom.length) : content;
    return withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// Groups non-blank lines into blocks; blank runs only separate blocks.
  static List<List<String>> _splitIntoBlocks(List<String> lines) {
    final List<List<String>> blocks = <List<String>>[];
    List<String> current = <String>[];
    for (final String line in lines) {
      if (line.trim().isEmpty) {
        if (current.isNotEmpty) {
          blocks.add(current);
          current = <String>[];
        }
      } else {
        current.add(line);
      }
    }
    if (current.isNotEmpty) {
      blocks.add(current);
    }
    return blocks;
  }
}

/// A parsed SBV timing pair.
class _SbvTiming {
  const _SbvTiming(this.start, this.end);

  final Duration start;
  final Duration end;
}
