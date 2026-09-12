import '../models/subtitle_cue.dart' show InlineStyle, InlineStyleRange;

/// Result of scanning marked-up subtitle text.
class ParsedInlineText {
  const ParsedInlineText(this.text, this.styles);

  /// Plain text with all markup removed, lines separated by `\n`.
  final String text;

  /// Canonical emphasis ranges over [text].
  final List<InlineStyleRange> styles;

  static const ParsedInlineText empty = ParsedInlineText('', <InlineStyleRange>[]);

  bool get isEmpty => text.isEmpty;
}

/// Shared HTML-ish inline markup handling for SRT and WebVTT.
///
/// Both formats use the same `<i>`, `<b>`, `<u>`, `<s>` tags, so parsing and
/// rendering live here instead of being duplicated per format. Unknown tags are
/// dropped rather than left in the visible text, which is what the "no leftover
/// control tags" rule requires.
abstract final class HtmlMarkup {
  static const Map<String, InlineStyle> _tagStyles = <String, InlineStyle>{
    'i': InlineStyle.italic,
    'em': InlineStyle.italic,
    'b': InlineStyle.bold,
    'strong': InlineStyle.bold,
    'u': InlineStyle.underline,
    's': InlineStyle.strikethrough,
    'strike': InlineStyle.strikethrough,
    'del': InlineStyle.strikethrough,
  };

  /// Deliberately strict: the tag name must follow `<` immediately, so that
  /// prose like `a < b > c` is never mistaken for markup.
  static final RegExp _tagPattern = RegExp(
    r'<(/?)([a-zA-Z][a-zA-Z0-9]*)(?:\s[^<>]*)?/?\s*>',
  );

  /// Removes every HTML-ish tag, keeping inner text. Emphasis is discarded.
  static String stripTags(String raw) => parse(raw).text;

  /// Parses tags into the plain [text] plus emphasis ranges.
  ///
  /// When [decodeEntities] is true (WebVTT), HTML entities are decoded as
  /// well; entity text is never re-interpreted as a tag.
  static ParsedInlineText parse(
    String raw, {
    bool decodeEntities = false,
  }) {
    final StringBuffer output = StringBuffer();
    final List<InlineStyleRange> ranges = <InlineStyleRange>[];
    final List<_OpenStyle> open = <_OpenStyle>[];
    int index = 0;

    while (index < raw.length) {
      final Match? tag = _tagPattern.matchAsPrefix(raw, index);
      if (tag != null) {
        final bool isClosing = tag.group(1) == '/';
        final InlineStyle? style = _tagStyles[tag.group(2)!.toLowerCase()];
        if (style != null) {
          if (isClosing) {
            _closeStyle(open, ranges, style, output.length);
          } else {
            open.add(_OpenStyle(style, output.length));
          }
        }
        index = tag.end;
        continue;
      }

      if (decodeEntities && raw.codeUnitAt(index) == 0x26 /* & */) {
        final _EntityMatch? entity = HtmlEntities._matchAt(raw, index);
        if (entity != null) {
          output.write(entity.value);
          index += entity.length;
          continue;
        }
      }

      final int codePoint = raw.codeUnitAt(index);
      if (codePoint == 0x0D /* \r */) {
        if (index + 1 < raw.length && raw.codeUnitAt(index + 1) == 0x0A) {
          index++;
        }
        output.write('\n');
      } else {
        output.writeCharCode(codePoint);
      }
      index++;
    }

    // Unclosed tags extend to the end of the text.
    for (final _OpenStyle style in open) {
      ranges.add(
        InlineStyleRange(
          start: style.start,
          end: output.length,
          styles: <InlineStyle>{style.style},
        ),
      );
    }

    final String text = output.toString();
    return ParsedInlineText(text, normalizeInlineStyles(text, ranges));
  }

  /// Renders [text] plus [styles] back into tag markup.
  ///
  /// [escape] should be true for WebVTT, where `&`, `<` and `>` are special.
  static String render(
    String text,
    List<InlineStyleRange> styles, {
    bool escape = false,
  }) {
    final String source = _normalizeNewlines(text);
    final List<InlineStyleRange> canonical =
        normalizeInlineStyles(source, styles);
    if (canonical.isEmpty) {
      return escape ? HtmlEntities.escape(source) : source;
    }

    final StringBuffer output = StringBuffer();
    Set<InlineStyle> active = const <InlineStyle>{};
    int cursor = 0;

    for (final _Segment segment in _segments(source, canonical)) {
      if (segment.start > cursor) {
        _writeText(output, source.substring(cursor, segment.start), escape);
      }
      for (final InlineStyle style in active.difference(segment.styles)) {
        output.write(_closingTag(style));
      }
      for (final InlineStyle style in segment.styles.difference(active)) {
        output.write(_openingTag(style));
      }
      active = segment.styles;
      _writeText(output, source.substring(segment.start, segment.end), escape);
      cursor = segment.end;
    }
    if (cursor < source.length) {
      _writeText(output, source.substring(cursor), escape);
    }
    for (final InlineStyle style in active) {
      output.write(_closingTag(style));
    }
    return output.toString();
  }

  static void _writeText(StringBuffer output, String value, bool escape) {
    output.write(escape ? HtmlEntities.escape(value) : value);
  }

  static String _openingTag(InlineStyle style) => '<${_tagName(style)}>';

  static String _closingTag(InlineStyle style) => '</${_tagName(style)}>';

  static String _tagName(InlineStyle style) {
    switch (style) {
      case InlineStyle.bold:
        return 'b';
      case InlineStyle.italic:
        return 'i';
      case InlineStyle.underline:
        return 'u';
      case InlineStyle.strikethrough:
        return 's';
    }
  }

  static void _closeStyle(
    List<_OpenStyle> open,
    List<InlineStyleRange> ranges,
    InlineStyle style,
    int end,
  ) {
    for (int i = open.length - 1; i >= 0; i--) {
      if (open[i].style == style) {
        final _OpenStyle opened = open.removeAt(i);
        if (end > opened.start) {
          ranges.add(
            InlineStyleRange(
              start: opened.start,
              end: end,
              styles: <InlineStyle>{style},
            ),
          );
        }
        return;
      }
    }
  }
}

/// Decodes and escapes the HTML entities that appear in subtitle files.
abstract final class HtmlEntities {
  static const Map<String, String> _named = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': '\u00A0',
    'lrm': '\u200E',
    'rlm': '\u200F',
  };

  static final RegExp _entityPattern = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,31});');

  /// Tries to read an entity starting at [index]. Returns `null` when the text
  /// at [index] is not a valid entity.
  static _EntityMatch? _matchAt(String raw, int index) {
    final Match? match = _entityPattern.matchAsPrefix(raw, index);
    if (match == null) {
      return null;
    }
    final String body = match.group(1)!;
    final String? decoded = _decodeBody(body);
    if (decoded == null) {
      return null;
    }
    return _EntityMatch(decoded, match.end - index);
  }

  /// Decodes known entities in [raw]; unknown entities are left untouched.
  static String decode(String raw) {
    return raw.replaceAllMapped(_entityPattern, (Match match) {
      final String? decoded = _decodeBody(match.group(1)!);
      return decoded ?? match.group(0)!;
    });
  }

  /// Escapes `&`, `<` and `>` for WebVTT output.
  ///
  /// Call this on already-decoded plain text; escaping text that still
  /// contains entities would double-escape them.
  static String escape(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static String? _decodeBody(String body) {
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final int? value = int.tryParse(body.substring(2), radix: 16);
      return _fromCodePoint(value);
    }
    if (body.startsWith('#')) {
      final int? value = int.tryParse(body.substring(1));
      return _fromCodePoint(value);
    }
    return _named[body.toLowerCase()];
  }

  static String? _fromCodePoint(int? value) {
    if (value == null || value <= 0 || value > 0x10FFFF) {
      return null;
    }
    return String.fromCharCode(value);
  }
}

/// Canonicalises emphasis ranges: clamps to [text], merges overlaps and
/// adjacent runs with identical style sets, and sorts by position.
///
/// Every parser funnels its ranges through this so writers only ever see
/// clean, sorted, non-overlapping-by-equal-set ranges.
List<InlineStyleRange> normalizeInlineStyles(
  String text,
  List<InlineStyleRange> ranges,
) {
  final List<InlineStyleRange> clamped = ranges
      .map((InlineStyleRange range) => range.clampTo(text.length))
      .whereType<InlineStyleRange>()
      .toList();
  if (clamped.isEmpty) {
    return <InlineStyleRange>[];
  }

  final List<_Segment> segments = _segments(text, clamped);
  final List<InlineStyleRange> merged = <InlineStyleRange>[];
  for (final _Segment segment in segments) {
    if (segment.styles.isEmpty) {
      continue;
    }
    final InlineStyleRange? last = merged.isEmpty ? null : merged.last;
    if (last != null &&
        last.end == segment.start &&
        last.styles.length == segment.styles.length &&
        last.styles.containsAll(segment.styles)) {
      merged[merged.length - 1] = InlineStyleRange(
        start: last.start,
        end: segment.end,
        styles: last.styles,
      );
    } else {
      merged.add(
        InlineStyleRange(
          start: segment.start,
          end: segment.end,
          styles: segment.styles,
        ),
      );
    }
  }
  return List<InlineStyleRange>.unmodifiable(merged);
}

/// Splits `[0, text.length)` at every range boundary and reports the active
/// style set of each piece.
List<_Segment> _segments(String text, List<InlineStyleRange> ranges) {
  final Set<int> boundaries = <int>{0, text.length};
  for (final InlineStyleRange range in ranges) {
    boundaries.add(range.start.clamp(0, text.length));
    boundaries.add(range.end.clamp(0, text.length));
  }
  final List<int> sorted = boundaries.toList()..sort();
  final List<_Segment> segments = <_Segment>[];
  for (int i = 0; i + 1 < sorted.length; i++) {
    final int start = sorted[i];
    final int end = sorted[i + 1];
    if (end <= start) {
      continue;
    }
    final Set<InlineStyle> styles = <InlineStyle>{};
    for (final InlineStyleRange range in ranges) {
      if (range.start <= start && range.end >= end) {
        styles.addAll(range.styles);
      }
    }
    segments.add(_Segment(start, end, styles));
  }
  return segments;
}

String _normalizeNewlines(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

class _Segment {
  const _Segment(this.start, this.end, this.styles);

  final int start;
  final int end;
  final Set<InlineStyle> styles;
}

class _OpenStyle {
  const _OpenStyle(this.style, this.start);

  final InlineStyle style;
  final int start;
}

class _EntityMatch {
  const _EntityMatch(this.value, this.length);

  final String value;
  final int length;
}
