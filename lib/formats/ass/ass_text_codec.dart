import '../../models/subtitle_cue.dart';
import '../../utils/inline_markup.dart' show normalizeInlineStyles;

/// Result of scanning one ASS/SSA event text value.
class AssTextScan {
  const AssTextScan(this.text, this.inlineStyles, this.position);

  /// Visible text with every `{...}` override block removed and line breaks
  /// normalised to `\n`.
  final String text;

  /// Canonical emphasis ranges over [text].
  final List<InlineStyleRange> inlineStyles;

  /// Placement captured from `\an` / `\pos`, or `null` when neither appeared.
  final CuePosition? position;
}

/// Converts ASS/SSA event text to and from the unified model's plain text,
/// inline emphasis ranges and cue position.
///
/// This is the one place that understands ASS override tags, so both the
/// ASS and SSA codecs (and any future ASS-family dialect) reuse it unchanged.
abstract final class AssTextCodec {
  /// Deterministic nesting order for emitted emphasis tags. Closing tags are
  /// emitted in the reverse order so brackets stay balanced.
  static const List<InlineStyle> _styleOrder = <InlineStyle>[
    InlineStyle.italic,
    InlineStyle.bold,
    InlineStyle.underline,
    InlineStyle.strikethrough,
  ];

  /// Scans [raw] into visible text, emphasis ranges and an optional position.
  ///
  /// `\N` and `\n` become `\n`, `\h` becomes a non-breaking space, and text
  /// escapes `\{` / `\}` become literal braces. Override blocks contribute
  /// style toggles and placement but never visible characters.
  static AssTextScan scan(String raw) {
    final StringBuffer output = StringBuffer();
    final Map<InlineStyle, int> openStarts = <InlineStyle, int>{};
    final List<InlineStyleRange> ranges = <InlineStyleRange>[];
    int? alignment;
    double? positionX;
    double? positionY;

    void closeRange(InlineStyle style, int start) {
      if (output.length > start) {
        ranges.add(
          InlineStyleRange(
            start: start,
            end: output.length,
            styles: <InlineStyle>{style},
          ),
        );
      }
    }

    void toggle(InlineStyle style, bool on) {
      if (on) {
        openStarts.putIfAbsent(style, () => output.length);
      } else {
        final int? start = openStarts.remove(style);
        if (start != null) {
          closeRange(style, start);
        }
      }
    }

    void reset() {
      for (final MapEntry<InlineStyle, int> entry in openStarts.entries) {
        closeRange(entry.key, entry.value);
      }
      openStarts.clear();
    }

    int index = 0;
    while (index < raw.length) {
      final int code = raw.codeUnitAt(index);

      if (code == 0x7B /* { */ ) {
        final int close = raw.indexOf('}', index + 1);
        if (close < 0) {
          // Unterminated block: treat the brace as literal text.
          output.write('{');
          index++;
          continue;
        }
        _applyBlock(
          raw.substring(index + 1, close),
          toggle: toggle,
          reset: reset,
          setAlignment: (int value) => alignment = value,
          setPosition: (double x, double y) {
            positionX = x;
            positionY = y;
          },
        );
        index = close + 1;
        continue;
      }

      if (code == 0x5C /* \ */ ) {
        if (index + 1 >= raw.length) {
          output.write('\\');
          index++;
          continue;
        }
        final int next = raw.codeUnitAt(index + 1);
        switch (next) {
          case 0x4E: // N
          case 0x6E: // n
            output.write('\n');
            index += 2;
            continue;
          case 0x68: // h
            output.write('\u00A0');
            index += 2;
            continue;
          case 0x7B: // {
            output.write('{');
            index += 2;
            continue;
          case 0x7D: // }
            output.write('}');
            index += 2;
            continue;
          default:
            // A lone backslash outside a block is literal.
            output.write('\\');
            index++;
            continue;
        }
      }

      output.writeCharCode(code);
      index++;
    }

    reset();
    final String text = output.toString();
    final bool hasPosition = positionX != null && positionY != null;
    final CuePosition? position = alignment != null || hasPosition
        ? CuePosition(alignment: alignment, x: positionX, y: positionY)
        : null;
    return AssTextScan(text, normalizeInlineStyles(text, ranges), position);
  }

  /// Renders plain [text] plus [styles] back into ASS/SSA event text.
  ///
  /// [position] contributes a leading `{\anN}` and/or `{\pos(x,y)}` override
  /// block. Model newlines become `\N`, non-breaking spaces become `\h`, and
  /// literal braces are escaped.
  static String render(
    String text,
    List<InlineStyleRange> styles, {
    CuePosition? position,
  }) {
    final StringBuffer output = StringBuffer();

    if (position != null) {
      final int? alignment = position.alignment;
      if (alignment != null) {
        output.write('{\\an$alignment}');
      }
      final double? x = position.x;
      final double? y = position.y;
      if (x != null && y != null) {
        output.write('{\\pos(${_formatNumber(x)},${_formatNumber(y)})}');
      }
    }

    final List<InlineStyleRange> canonical = normalizeInlineStyles(
      text,
      styles,
    );
    if (canonical.isEmpty) {
      _writeText(output, text);
      return output.toString();
    }

    Set<InlineStyle> active = const <InlineStyle>{};
    int cursor = 0;
    for (final _TextSegment segment in _segments(text, canonical)) {
      if (segment.start > cursor) {
        _writeText(output, text.substring(cursor, segment.start));
      }
      for (final InlineStyle style in _styleOrder.reversed) {
        if (active.contains(style) && !segment.styles.contains(style)) {
          output.write(_closingTag(style));
        }
      }
      for (final InlineStyle style in _styleOrder) {
        if (!active.contains(style) && segment.styles.contains(style)) {
          output.write(_openingTag(style));
        }
      }
      active = segment.styles;
      _writeText(output, text.substring(segment.start, segment.end));
      cursor = segment.end;
    }
    if (cursor < text.length) {
      _writeText(output, text.substring(cursor));
    }
    for (final InlineStyle style in _styleOrder.reversed) {
      if (active.contains(style)) {
        output.write(_closingTag(style));
      }
    }
    return output.toString();
  }

  /// Applies the backslash commands of one `{...}` block.
  ///
  /// Only bold/italic/underline/strikethrough toggles, `\r` resets, `\an` and
  /// `\pos` are interpreted. Every other command (karaoke, animation,
  /// drawing, clipping, colours, fonts, ...) is dropped.
  static void _applyBlock(
    String block, {
    required void Function(InlineStyle style, bool on) toggle,
    required void Function() reset,
    required void Function(int alignment) setAlignment,
    required void Function(double x, double y) setPosition,
  }) {
    int index = 0;
    while (index < block.length) {
      if (block.codeUnitAt(index) != 0x5C /* \ */ ) {
        index++;
        continue;
      }
      index++;

      // Numeric command prefixes (e.g. `\1c`, `\3c`) belong to commands we
      // drop, but they must be consumed so the following name reads cleanly.
      while (index < block.length && _isDigit(block.codeUnitAt(index))) {
        index++;
      }

      final int nameStart = index;
      while (index < block.length && _isLetter(block.codeUnitAt(index))) {
        index++;
      }
      final String name = block.substring(nameStart, index).toLowerCase();

      String args;
      if (index < block.length && block.codeUnitAt(index) == 0x28 /* ( */ ) {
        final int close = _matchingParen(block, index);
        if (close < 0) {
          args = block.substring(index);
          index = block.length;
        } else {
          args = block.substring(index, close + 1);
          index = close + 1;
        }
      } else {
        final int argStart = index;
        while (index < block.length && block.codeUnitAt(index) != 0x5C) {
          index++;
        }
        args = block.substring(argStart, index);
      }

      switch (name) {
        case 'b':
          toggle(InlineStyle.bold, _isToggleOn(args));
          break;
        case 'i':
          toggle(InlineStyle.italic, _isToggleOn(args));
          break;
        case 'u':
          toggle(InlineStyle.underline, _isToggleOn(args));
          break;
        case 's':
          toggle(InlineStyle.strikethrough, _isToggleOn(args));
          break;
        case 'r':
          reset();
          break;
        case 'an':
          final int? value = int.tryParse(args.trim());
          if (value != null && value >= 1 && value <= 9) {
            setAlignment(value);
          }
          break;
        case 'pos':
          final _Coordinates? coordinates = _parseCoordinates(args);
          if (coordinates != null) {
            setPosition(coordinates.x, coordinates.y);
          }
          break;
        default:
          // Unsupported command, including legacy `\a`, colours (`\1c`, ...),
          // karaoke, animation, drawing and clipping: dropped.
          break;
      }
    }
  }

  /// True when a `\b`/`\i`/`\u`/`\s` argument means "on".
  ///
  /// An empty argument or a non-numeric one means on; a numeric argument is on
  /// when it is non-zero.
  static bool _isToggleOn(String args) {
    final String trimmed = args.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    final Match? match = RegExp(r'^[+-]?\d+').firstMatch(trimmed);
    if (match == null) {
      return true;
    }
    return int.parse(match.group(0)!) != 0;
  }

  /// Parses `(x,y)` coordinates, returning `null` when they are not numeric.
  static _Coordinates? _parseCoordinates(String args) {
    final String inner = args.replaceAll(RegExp(r'[()]'), '');
    final List<String> parts = inner.split(',');
    if (parts.length < 2) {
      return null;
    }
    final double? x = double.tryParse(parts[0].trim());
    final double? y = double.tryParse(parts[1].trim());
    if (x == null || y == null) {
      return null;
    }
    return _Coordinates(x, y);
  }

  static int _matchingParen(String source, int open) {
    int depth = 0;
    for (int index = open; index < source.length; index++) {
      final int code = source.codeUnitAt(index);
      if (code == 0x28) {
        depth++;
      } else if (code == 0x29) {
        depth--;
        if (depth == 0) {
          return index;
        }
      }
    }
    return -1;
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isLetter(int code) =>
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

  static void _writeText(StringBuffer output, String value) {
    for (int index = 0; index < value.length; index++) {
      final int code = value.codeUnitAt(index);
      switch (code) {
        case 0x0A: // \n
          output.write(r'\N');
          break;
        case 0x7B: // {
          output.write(r'\{');
          break;
        case 0x7D: // }
          output.write(r'\}');
          break;
        case 0x00A0: // non-breaking space
          output.write(r'\h');
          break;
        default:
          output.writeCharCode(code);
          break;
      }
    }
  }

  static String _openingTag(InlineStyle style) {
    switch (style) {
      case InlineStyle.italic:
        return r'{\i1}';
      case InlineStyle.bold:
        return r'{\b1}';
      case InlineStyle.underline:
        return r'{\u1}';
      case InlineStyle.strikethrough:
        return r'{\s1}';
    }
  }

  static String _closingTag(InlineStyle style) {
    switch (style) {
      case InlineStyle.italic:
        return r'{\i0}';
      case InlineStyle.bold:
        return r'{\b0}';
      case InlineStyle.underline:
        return r'{\u0}';
      case InlineStyle.strikethrough:
        return r'{\s0}';
    }
  }

  /// Formats a coordinate without a trailing `.0` for whole numbers.
  static String _formatNumber(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

/// Splits [text] at every emphasis boundary, tagging each piece.
List<_TextSegment> _segments(String text, List<InlineStyleRange> ranges) {
  final Set<int> boundaries = <int>{0, text.length};
  for (final InlineStyleRange range in ranges) {
    boundaries.add(range.start.clamp(0, text.length));
    boundaries.add(range.end.clamp(0, text.length));
  }
  final List<int> sorted = boundaries.toList()..sort();
  final List<_TextSegment> segments = <_TextSegment>[];
  for (int index = 0; index + 1 < sorted.length; index++) {
    final int start = sorted[index];
    final int end = sorted[index + 1];
    if (end <= start) {
      continue;
    }
    final Set<InlineStyle> styles = <InlineStyle>{};
    for (final InlineStyleRange range in ranges) {
      if (range.start <= start && range.end >= end) {
        styles.addAll(range.styles);
      }
    }
    segments.add(_TextSegment(start, end, styles));
  }
  return segments;
}

class _TextSegment {
  const _TextSegment(this.start, this.end, this.styles);

  final int start;
  final int end;
  final Set<InlineStyle> styles;
}

class _Coordinates {
  const _Coordinates(this.x, this.y);

  final double x;
  final double y;
}
