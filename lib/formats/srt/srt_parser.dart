import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../models/subtitle_exception.dart';
import '../../models/subtitle_format.dart';
import '../../utils/inline_markup.dart';
import '../../utils/timestamp.dart';

/// Byte order mark that some editors prepend to UTF-8 subtitle files.
const String _bom = '\uFEFF';

/// The SRT timing separator.
const String _arrow = '-->';

/// Matches an SRT index line: digits only, no padding or sign.
final RegExp _indexLinePattern = RegExp(r'^\d+$');

/// Matches the leading timestamp of an SRT timing side, ignoring any trailing
/// positioning data (`X1:0 X2:100 Y1:0 Y2:20`).
final RegExp _timestampTokenPattern = RegExp(
  r'\d{1,3}\s*:\s*[0-5]?\d\s*:\s*[0-5]?\d\s*[.,]\s*\d{1,6}',
);

/// Parses SubRip (`.srt`) content into the unified model.
///
/// Grammar: blocks separated by one or more blank lines. Each block is an
/// optional index line, a `HH:MM:SS,mmm --> HH:MM:SS,mmm` timing line and one
/// or more text lines. A missing index line is tolerated, and trailing
/// positioning data after the end timestamp is ignored.
class SrtParser implements SubtitleParser {
  const SrtParser();

  @override
  SubtitleDocument parse(String content) {
    final String normalized = _normalizeContent(content);
    if (normalized.trim().isEmpty) {
      throw SubtitleSyntaxException('SRT content is empty.');
    }

    final List<List<String>> blocks = _splitIntoBlocks(normalized.split('\n'));
    final List<SubtitleCue> cues = <SubtitleCue>[
      for (final List<String> block in blocks) _parseBlock(block),
    ];
    if (cues.isEmpty) {
      throw SubtitleSyntaxException('No SRT cue blocks found.');
    }
    return SubtitleDocument(
      cues: cues,
      sourceFormat: SubtitleFormat.srt,
    );
  }

  SubtitleCue _parseBlock(List<String> lines) {
    int cursor = 0;
    int? index;
    if (_indexLinePattern.hasMatch(lines.first.trim())) {
      index = int.tryParse(lines.first.trim());
      cursor = 1;
    }
    if (cursor >= lines.length) {
      throw SubtitleSyntaxException(
        'SRT block has an index but no timing line.',
      );
    }

    final _SrtTiming? timing = _parseTiming(lines[cursor]);
    if (timing == null) {
      throw SubtitleSyntaxException(
        'Invalid SRT timing line: "${lines[cursor]}".',
      );
    }
    cursor++;

    final String rawText = lines.sublist(cursor).join('\n');
    final ParsedInlineText parsed =
        HtmlMarkup.parse(stripAssOverrideBlocks(rawText));

    return SubtitleCue(
      start: timing.start,
      end: timing.end,
      text: parsed.text,
      inlineStyles: parsed.styles,
      metadata: index == null
          ? <String, Object?>{}
          : <String, Object?>{'srt.index': index},
    );
  }

  _SrtTiming? _parseTiming(String line) {
    final int arrowIndex = line.indexOf(_arrow);
    if (arrowIndex < 0) {
      return null;
    }

    final Duration? start = tryParseTimestamp(
      line.substring(0, arrowIndex).trim(),
    );
    if (start == null) {
      return null;
    }

    // The end side may carry trailing positioning data; take its first token.
    final Match? token =
        _timestampTokenPattern.firstMatch(line.substring(arrowIndex + _arrow.length));
    if (token == null) {
      return null;
    }
    final Duration? end = tryParseTimestamp(token.group(0)!);
    if (end == null) {
      return null;
    }
    return _SrtTiming(start, end);
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

/// A parsed SRT timing pair.
class _SrtTiming {
  const _SrtTiming(this.start, this.end);

  final Duration start;
  final Duration end;
}
