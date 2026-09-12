import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../models/subtitle_exception.dart';
import '../../models/subtitle_format.dart';
import '../../utils/inline_markup.dart';
import '../../utils/timestamp.dart';

/// Metadata key holding a WebVTT cue identifier, kept verbatim so it can be
/// re-emitted unchanged by [VttWriter].
const String vttIdentifierMetadataKey = 'vtt.identifier';

/// Metadata key holding the raw trailing cue settings substring, kept verbatim
/// (for example `align:start position:50% line:3`). Settings are never
/// interpreted, only round-tripped.
const String vttSettingsMetadataKey = 'vtt.settings';

/// UTF-8 byte order mark, which parsers tolerate at the start of a file.
const String _byteOrderMark = '\uFEFF';

/// The mandatory first line marker of a WebVTT file (case-sensitive).
const String _headerKeyword = 'WEBVTT';

/// Separator between the start and end timestamp of a cue.
const String _timingArrow = '-->';

/// Block keywords that are recognised and skipped.
const String _noteKeyword = 'NOTE';
const String _styleKeyword = 'STYLE';
const String _regionKeyword = 'REGION';

/// Header key whose value populates [SubtitleMetadata.language].
const String _languageFieldKey = 'Language';

/// Matches the first non-whitespace run on a line (the cue end timestamp).
final RegExp _leadingToken = RegExp(r'\S+');

/// Parses WebVTT content into the unified model.
///
/// Cue identifiers and trailing cue settings are preserved verbatim in
/// [vttIdentifierMetadataKey] and [vttSettingsMetadataKey] respectively, but
/// are never interpreted.
///
/// `STYLE` and `REGION` blocks are skipped and are *not* preserved: the model
/// has no representation for them and v0.1 does not edit styling.
class VttParser implements SubtitleParser {
  /// Creates a stateless WebVTT parser.
  const VttParser();

  @override
  SubtitleDocument parse(String content) {
    final String normalized = _normalize(content);
    final List<String> lines = normalized.split('\n');

    final int headerIndex = _firstNonBlank(lines);
    if (headerIndex < 0 ||
        !lines[headerIndex].trim().startsWith(_headerKeyword)) {
      throw SubtitleSyntaxException(
        'Not a WebVTT file: the first line must start with WEBVTT.',
      );
    }

    final SubtitleMetadata metadata = SubtitleMetadata();
    int cursor = headerIndex + 1;
    bool isFirstHeaderLine = true;
    while (cursor < lines.length && lines[cursor].trim().isNotEmpty) {
      final String line = lines[cursor];
      final int separator = _separatorIndex(line);
      if (separator >= 0) {
        final String key = line.substring(0, separator).trim();
        final String value = line.substring(separator + 1).trim();
        if (key.isNotEmpty) {
          metadata.fields[key] = value;
        }
      } else if (isFirstHeaderLine) {
        // A header text line without a key is the file title.
        metadata.title = line.trim();
      }
      isFirstHeaderLine = false;
      cursor++;
    }

    final String? language = metadata.field(_languageFieldKey);
    if (language != null && language.isNotEmpty) {
      metadata.language = language;
    }

    final List<SubtitleCue> cues = <SubtitleCue>[];
    for (final List<String> block in _blocks(lines, cursor)) {
      final String firstLine = block.first.trim();
      if (_isNoteBlock(firstLine) ||
          firstLine == _styleKeyword ||
          firstLine == _regionKeyword) {
        continue;
      }
      cues.add(_parseCue(block));
    }

    return SubtitleDocument(
      cues: cues,
      metadata: metadata,
      sourceFormat: SubtitleFormat.vtt,
    );
  }

  SubtitleCue _parseCue(List<String> block) {
    int timingIndex = 0;
    String? identifier;
    if (!block[0].contains(_timingArrow)) {
      identifier = block[0];
      timingIndex = 1;
    }
    if (timingIndex >= block.length ||
        !block[timingIndex].contains(_timingArrow)) {
      throw SubtitleSyntaxException(
        'Malformed WebVTT cue: no timing line with "$_timingArrow".',
      );
    }

    final String timingLine = block[timingIndex];
    final int arrow = timingLine.indexOf(_timingArrow);
    final String startRaw = timingLine.substring(0, arrow).trim();
    final String afterArrow =
        timingLine.substring(arrow + _timingArrow.length);
    final RegExpMatch? endMatch = _leadingToken.firstMatch(afterArrow);
    if (endMatch == null) {
      throw SubtitleSyntaxException(
        'Malformed WebVTT cue: missing end timestamp.',
      );
    }
    final String endRaw = endMatch.group(0)!;
    // Kept verbatim: the writer appends it after the end timestamp.
    final String settings = afterArrow.substring(endMatch.end).trim();

    final Duration? start = tryParseTimestamp(startRaw, minimumFields: 2);
    final Duration? end = tryParseTimestamp(endRaw, minimumFields: 2);
    if (start == null || end == null) {
      throw SubtitleSyntaxException(
        'Malformed WebVTT cue timing line: "$timingLine".',
      );
    }

    final String rawText = block.sublist(timingIndex + 1).join('\n');
    final ParsedInlineText parsed = HtmlMarkup.parse(
      stripAssOverrideBlocks(rawText),
      decodeEntities: true,
    );

    final Map<String, Object?> cueMetadata = <String, Object?>{};
    if (identifier != null) {
      cueMetadata[vttIdentifierMetadataKey] = identifier;
    }
    if (settings.isNotEmpty) {
      cueMetadata[vttSettingsMetadataKey] = settings;
    }

    return SubtitleCue(
      start: start,
      end: end,
      text: parsed.text,
      inlineStyles: parsed.styles,
      metadata: cueMetadata,
    );
  }
}

/// Strips a leading BOM and folds CRLF/CR onto LF.
String _normalize(String raw) {
  final String withoutBom =
      raw.startsWith(_byteOrderMark) ? raw.substring(1) : raw;
  return withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Index of the first line that is not blank, or `-1`.
int _firstNonBlank(List<String> lines) {
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].trim().isNotEmpty) {
      return i;
    }
  }
  return -1;
}

/// Index of the first `:` or `=` on [line], or `-1`.
int _separatorIndex(String line) {
  final int colon = line.indexOf(':');
  final int equals = line.indexOf('=');
  if (colon < 0) {
    return equals;
  }
  if (equals < 0) {
    return colon;
  }
  return colon < equals ? colon : equals;
}

/// True for a `NOTE` block header (`NOTE`, `NOTE text`, `NOTE\ttext`).
bool _isNoteBlock(String trimmed) =>
    trimmed == _noteKeyword ||
    trimmed.startsWith('$_noteKeyword ') ||
    trimmed.startsWith('$_noteKeyword\t');

/// Splits [lines] from [start] into blank-line separated blocks.
List<List<String>> _blocks(List<String> lines, int start) {
  final List<List<String>> blocks = <List<String>>[];
  List<String>? current;
  for (int i = start; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) {
      if (current != null) {
        blocks.add(current);
        current = null;
      }
      continue;
    }
    current ??= <String>[];
    current.add(lines[i]);
  }
  if (current != null) {
    blocks.add(current);
  }
  return blocks;
}
