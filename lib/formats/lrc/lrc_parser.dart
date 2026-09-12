import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../models/subtitle_exception.dart';
import '../../models/subtitle_format.dart';
import '../../utils/inline_markup.dart';
import '../../utils/subtitle_defaults.dart';
import '../../utils/timestamp.dart';

/// UTF-8 byte order mark, which parsers tolerate at the start of a file.
const String _byteOrderMark = '\uFEFF';

/// Matches one leading `[tag]` at the current scan position. Kept unanchored:
/// [RegExp.matchAsPrefix] already anchors the match at the scan index.
final RegExp _leadingTag = RegExp(r'\[([^\[\]]*)\]');

/// A timestamp tag: `mm:ss`, `mm:ss.xx`, `hh:mm:ss.xx`, ...
///
/// The minutes/seconds fields are range-checked so this can never be confused
/// with an ASS section header such as `[Script Info]`.
final RegExp _timestampTag = RegExp(
  r'^\d{1,3}:[0-5]\d(?::[0-5]\d)?(?:[.:]\d{1,3})?$',
);

/// A metadata tag: an alphabetic key, `:`, then an opaque value.
final RegExp _metadataTag = RegExp(r'^([A-Za-z][A-Za-z0-9_-]*):(.*)$');

/// Enhanced-LRC per-word timestamps inside cue text, e.g. `<00:10.00>`.
final RegExp _wordTimestamp = RegExp(
  r'<\d{1,3}:[0-5]\d(?::[0-5]\d)?(?:[.:]\d{1,3})?>',
);

/// Metadata tag key that also populates [SubtitleMetadata.title].
const String _titleKey = 'ti';

/// Parses LRC (lyrics) content into the unified model.
///
/// Every cue starts at its `[mm:ss.xx]` tag and *has no end time*: LRC cannot
/// express one. After parsing, cues are sorted by start and end times are
/// inferred — each cue ends at the next cue's start, and the last cue gets
/// [SubtitleDefaults.lrcEndTimeFallback] added to its start.
///
/// Metadata tags (`[ti:]`, `[ar:]`, `[offset:]`, ...) become
/// [SubtitleMetadata.fields] with their original casing; `[ti:]` also sets the
/// title. The `offset` value is deliberately *not* applied to timestamps, so an
/// LRC file round-trips byte-for-byte through the model.
///
/// Lossy: enhanced-LRC word timestamps (`<00:10.00>`) are stripped from the
/// visible text, and inline emphasis tags are dropped because LRC cannot
/// express emphasis. Non-blank lines without a leading timestamp tag are
/// ignored.
class LrcParser implements SubtitleParser {
  /// Creates a stateless LRC parser.
  const LrcParser();

  @override
  SubtitleDocument parse(String content) {
    final String normalized = _normalize(content);
    final List<String> lines = normalized.split('\n');

    final SubtitleMetadata metadata = SubtitleMetadata();
    final List<SubtitleCue> cues = <SubtitleCue>[];

    for (final String line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      final _TagScan scan = _scanLeadingTags(line);
      if (scan.tags.isEmpty) {
        // No leading tag: not an LRC line, so it is ignored.
        continue;
      }

      final String text = _cleanText(scan.remainder);
      final List<Duration> starts = <Duration>[];
      for (final String tag in scan.tags) {
        if (_timestampTag.hasMatch(tag)) {
          final Duration? start = _parseTimestamp(tag);
          if (start != null) {
            starts.add(start);
          }
          continue;
        }
        final RegExpMatch? meta = _metadataTag.firstMatch(tag);
        if (meta == null) {
          continue;
        }
        final String key = meta.group(1)!;
        final String value = meta.group(2)!;
        metadata.fields[key] = value;
        if (key.toLowerCase() == _titleKey) {
          metadata.title = value;
        }
      }

      // One line may carry several timestamps for the same text.
      for (final Duration start in starts) {
        cues.add(SubtitleCue(start: start, text: text));
      }
    }

    if (cues.isEmpty && metadata.fields.isEmpty) {
      throw SubtitleSyntaxException(
        'Not an LRC file: no timestamp tags or metadata tags found.',
      );
    }

    final SubtitleDocument document = SubtitleDocument(
      cues: cues,
      metadata: metadata,
      sourceFormat: SubtitleFormat.lrc,
    );
    document.sortByStart();
    return document.resolveMissingEndTimes(
      fallback: SubtitleDefaults.lrcEndTimeFallback,
    );
  }

  /// Reads the timestamp of a timestamp-shaped tag.
  ///
  /// `tryParseTimestamp` requires a fractional part, while LRC allows
  /// `[mm:ss]`; a zero fraction is appended for that case.
  Duration? _parseTimestamp(String tag) {
    final Duration? direct = tryParseTimestamp(tag, minimumFields: 2);
    if (direct != null) {
      return direct;
    }
    return tryParseTimestamp('$tag.0', minimumFields: 2);
  }

  /// Turns raw trailing text into plain cue text.
  ///
  /// ASS override blocks and enhanced word timestamps are removed, HTML-ish
  /// tags are stripped, and emphasis ranges are dropped.
  String _cleanText(String raw) {
    final String withoutWordTimestamps = raw.replaceAll(_wordTimestamp, '');
    return HtmlMarkup.parse(
      stripAssOverrideBlocks(withoutWordTimestamps),
    ).text;
  }
}

/// Strips a leading BOM and folds CRLF/CR onto LF.
String _normalize(String raw) {
  final String withoutBom =
      raw.startsWith(_byteOrderMark) ? raw.substring(1) : raw;
  return withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Collects the `[tag]` groups at the very start of [line].
///
/// Returns the tag bodies plus the remainder of the line after them.
_TagScan _scanLeadingTags(String line) {
  final List<String> tags = <String>[];
  int index = 0;
  while (true) {
    final Match? match = _leadingTag.matchAsPrefix(line, index);
    if (match == null) {
      break;
    }
    tags.add(match.group(1)!);
    index = match.end;
  }
  return _TagScan(tags, line.substring(index));
}

class _TagScan {
  const _TagScan(this.tags, this.remainder);

  final List<String> tags;
  final String remainder;
}
