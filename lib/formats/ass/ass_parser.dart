import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../models/subtitle_exception.dart';
import '../../models/subtitle_style.dart';
import '../../utils/timestamp.dart';
import 'ass_dialect.dart';
import 'ass_text_codec.dart';

/// Parser shared by ASS and SSA.
///
/// The two dialects differ only in constants, so this single class is
/// parameterised by [AssDialect]; `SsaParser` is a thin subclass that fixes
/// the dialect to [AssDialect.ssa]. Sharing one implementation means the
/// `Dialogue:` field-order handling, override-tag scanning and timestamp
/// rules can never drift between the two formats.
///
/// Dropped on purpose:
/// * `[Fonts]`, `[Graphics]` and unknown sections: embedded fonts and vector
///   graphics are not represented in the unified model.
/// * Event lines other than `Dialogue:` (`Comment`, `Picture`, `Sound`,
///   `Movie`, `Command`).
/// * Every override command except bold/italic/underline/strikethrough,
///   `\r`, `\an` and `\pos` (see [AssTextCodec]).
class AssParser implements SubtitleParser {
  AssParser([this.dialect = AssDialect.ass]);

  /// Which member of the ASS family this parser speaks.
  final AssDialect dialect;

  @override
  SubtitleDocument parse(String content) {
    final String normalized = _normalize(content);
    if (normalized.trim().isEmpty) {
      throw SubtitleSyntaxException('Empty ${dialect.format.label} content');
    }

    final SubtitleMetadata metadata = SubtitleMetadata();
    final List<SubtitleStyle> styles = <SubtitleStyle>[];
    final List<SubtitleCue> cues = <SubtitleCue>[];
    List<String> styleFields = const <String>[];
    List<String> eventFields = const <String>[];
    _Section section = _Section.none;

    for (final String rawLine in normalized.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith(';')) {
        continue;
      }

      if (line.startsWith('[') && line.endsWith(']')) {
        section = _sectionFor(line.substring(1, line.length - 1).trim());
        continue;
      }

      switch (section) {
        case _Section.scriptInfo:
          _parseScriptInfoLine(line, metadata);
          break;
        case _Section.styles:
          styleFields = _parseStylesLine(line, styleFields, styles);
          break;
        case _Section.events:
          eventFields = _parseEventsLine(line, eventFields, cues);
          break;
        case _Section.none:
        case _Section.ignored:
          break;
      }
    }

    return SubtitleDocument(
      cues: cues,
      styles: styles,
      metadata: metadata,
      sourceFormat: dialect.format,
    );
  }

  /// Strips a UTF-8 BOM and normalises CRLF/CR to LF.
  ///
  /// Components are pure and receive already-decoded strings, so the BOM can
  /// only appear as a leading `\uFEFF`.
  static String _normalize(String content) {
    String value = content;
    if (value.startsWith('\uFEFF')) {
      value = value.substring(1);
    }
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static _Section _sectionFor(String name) {
    switch (name.toLowerCase()) {
      case 'script info':
        return _Section.scriptInfo;
      case 'v4+ styles':
      case 'v4 styles':
        return _Section.styles;
      case 'events':
        return _Section.events;
      default:
        // [Fonts], [Graphics] and anything unknown: dropped.
        return _Section.ignored;
    }
  }

  void _parseScriptInfoLine(String line, SubtitleMetadata metadata) {
    final int separator = line.indexOf(':');
    if (separator <= 0) {
      return;
    }
    final String key = line.substring(0, separator).trim();
    final String value = line.substring(separator + 1).trim();
    if (key.isEmpty) {
      return;
    }
    metadata.fields[key] = value;
    if (key.toLowerCase() == AssScriptInfo.title.toLowerCase()) {
      metadata.title = value;
    }
  }

  List<String> _parseStylesLine(
    String line,
    List<String> currentFields,
    List<SubtitleStyle> styles,
  ) {
    final int separator = line.indexOf(':');
    if (separator <= 0) {
      return currentFields;
    }
    final String key = line.substring(0, separator).trim().toLowerCase();
    final String value = line.substring(separator + 1);

    if (key == AssLinePrefixes.format.toLowerCase()) {
      return _parseFieldList(value);
    }
    if (key == AssLinePrefixes.style.toLowerCase()) {
      if (currentFields.isEmpty) {
        return currentFields;
      }
      final List<String> values = _splitLimited(value, currentFields.length);
      final Map<String, String> fields = <String, String>{};
      String name = '';
      for (int index = 0; index < currentFields.length; index++) {
        final String fieldName = currentFields[index];
        final String fieldValue = values[index].trim();
        fields[fieldName] = fieldValue;
        if (fieldName.toLowerCase() == 'name') {
          name = fieldValue;
        }
      }
      styles.add(SubtitleStyle(name: name, fields: fields));
      return currentFields;
    }
    return currentFields;
  }

  List<String> _parseEventsLine(
    String line,
    List<String> currentFields,
    List<SubtitleCue> cues,
  ) {
    final int separator = line.indexOf(':');
    if (separator <= 0) {
      return currentFields;
    }
    final String key = line.substring(0, separator).trim().toLowerCase();
    final String value = line.substring(separator + 1);

    if (key == AssLinePrefixes.format.toLowerCase()) {
      return _parseFieldList(value);
    }
    if (key != AssLinePrefixes.dialogue.toLowerCase()) {
      // Comment:, Picture:, Sound:, Movie:, Command: are dropped.
      return currentFields;
    }
    if (currentFields.isEmpty) {
      return currentFields;
    }

    final SubtitleCue? cue = _parseDialogue(value, currentFields);
    if (cue != null) {
      cues.add(cue);
    }
    return currentFields;
  }

  SubtitleCue? _parseDialogue(String value, List<String> fields) {
    int startIndex = -1;
    int endIndex = -1;
    int textIndex = -1;
    int styleIndex = -1;
    for (int index = 0; index < fields.length; index++) {
      switch (fields[index].toLowerCase()) {
        case 'start':
          startIndex = index;
          break;
        case 'end':
          endIndex = index;
          break;
        case 'text':
          textIndex = index;
          break;
        case 'style':
          styleIndex = index;
          break;
      }
    }
    if (startIndex < 0 || endIndex < 0 || textIndex < 0) {
      return null;
    }

    final List<String> values = _splitLimited(value, fields.length);

    final String startRaw = values[startIndex].trim();
    final Duration? start = tryParseTimestamp(startRaw, minimumFields: 3);
    if (start == null) {
      throw SubtitleSyntaxException(
        'Invalid ${dialect.format.label} start time: "$startRaw"',
      );
    }
    final String endRaw = values[endIndex].trim();
    final Duration? end = tryParseTimestamp(endRaw, minimumFields: 3);
    if (end == null) {
      throw SubtitleSyntaxException(
        'Invalid ${dialect.format.label} end time: "$endRaw"',
      );
    }

    // Text is last, so earlier field values never swallow commas inside it.
    final String rawText = values[textIndex].trim();
    final AssTextScan scan = AssTextCodec.scan(rawText);

    final String? styleRef =
        styleIndex >= 0 && values[styleIndex].trim().isNotEmpty
        ? values[styleIndex].trim()
        : null;

    final Map<String, Object?> cueMetadata = <String, Object?>{};
    for (int index = 0; index < fields.length; index++) {
      if (index == startIndex ||
          index == endIndex ||
          index == textIndex ||
          index == styleIndex) {
        continue;
      }
      cueMetadata[fields[index]] = values[index].trim();
    }

    return SubtitleCue(
      start: start,
      end: end,
      text: scan.text,
      inlineStyles: scan.inlineStyles,
      styleRef: styleRef,
      position: scan.position,
      metadata: cueMetadata,
    );
  }

  /// Splits a `Format:` payload into trimmed, original-cased field names.
  static List<String> _parseFieldList(String value) {
    final List<String> fields = <String>[];
    for (final String part in value.split(',')) {
      final String trimmed = part.trim();
      if (trimmed.isNotEmpty) {
        fields.add(trimmed);
      }
    }
    return fields;
  }

  /// Splits [value] on `,` into at most [count] parts.
  ///
  /// The last part keeps any remaining commas, which is what keeps commas
  /// inside the `Text` field intact. Missing trailing fields become empty
  /// strings.
  static List<String> _splitLimited(String value, int count) {
    if (count <= 0) {
      return <String>[];
    }
    final List<String> parts = <String>[];
    int start = 0;
    for (
      int index = 0;
      index < value.length && parts.length < count - 1;
      index++
    ) {
      if (value.codeUnitAt(index) == 0x2C /* , */ ) {
        parts.add(value.substring(start, index));
        start = index + 1;
      }
    }
    parts.add(value.substring(start));
    while (parts.length < count) {
      parts.add('');
    }
    return parts;
  }
}

enum _Section { none, scriptInfo, styles, events, ignored }
