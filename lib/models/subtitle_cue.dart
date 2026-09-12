import 'package:collection/collection.dart';

/// Inline text emphasis that at least some subtitle formats can express.
///
/// Parsers translate format-native markup (SRT/VTT HTML tags, ASS `\b`/`\i`
/// override tags, ...) into these flags; writers translate them back into the
/// markup their format supports and silently drop what it cannot express.
enum InlineStyle {
  bold,
  italic,
  underline,
  strikethrough,
}

/// A run of [SubtitleCue.text] carrying one or more [InlineStyle]s.
///
/// Offsets are Dart string indices, i.e. UTF-16 code units, which is exactly
/// what `String.substring` expects.
class InlineStyleRange {
  const InlineStyleRange({
    required this.start,
    required this.end,
    required this.styles,
  });

  /// Inclusive start index into the cue text.
  final int start;

  /// Exclusive end index into the cue text.
  final int end;

  final Set<InlineStyle> styles;

  int get length => end - start;

  bool get isEmpty => end <= start || styles.isEmpty;

  /// Returns this range clamped to `[0, textLength]`, or `null` when the
  /// clamped range is empty.
  InlineStyleRange? clampTo(int textLength) {
    final int clampedStart = start.clamp(0, textLength);
    final int clampedEnd = end.clamp(0, textLength);
    if (clampedEnd <= clampedStart || styles.isEmpty) {
      return null;
    }
    return InlineStyleRange(
      start: clampedStart,
      end: clampedEnd,
      styles: styles,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InlineStyleRange &&
      other.start == start &&
      other.end == end &&
      const SetEquality<InlineStyle>().equals(other.styles, styles);

  @override
  int get hashCode =>
      Object.hash(start, end, const SetEquality<InlineStyle>().hash(styles));

  @override
  String toString() => 'InlineStyleRange($start..$end, $styles)';
}

/// Screen placement of a cue, when the source format expressed one.
///
/// This is intentionally small: it carries what the supported formats can
/// round-trip (`\an`/`\pos` in ASS, `line`/`position` in VTT) and keeps
/// anything else in [metadata].
class CuePosition {
  const CuePosition({
    this.alignment,
    this.x,
    this.y,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? const <String, Object?>{};

  /// Numpad alignment, `1`..`9` (ASS `\an`). `null` when unset.
  final int? alignment;

  /// Horizontal position in script resolution units, when absolute.
  final double? x;

  /// Vertical position in script resolution units, when absolute.
  final double? y;

  final Map<String, Object?> metadata;

  bool get isEmpty => alignment == null && x == null && y == null;

  @override
  bool operator ==(Object other) =>
      other is CuePosition &&
      other.alignment == alignment &&
      other.x == x &&
      other.y == y &&
      const DeepCollectionEquality().equals(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(
        alignment,
        x,
        y,
        const DeepCollectionEquality().hash(metadata),
      );

  @override
  String toString() =>
      'CuePosition(alignment: $alignment, x: $x, y: $y)';
}

/// A single subtitle event in the unified model.
///
/// Time is always a [Duration]; formatting to and from text happens only at
/// parser/writer boundaries.
class SubtitleCue {
  SubtitleCue({
    required this.start,
    this.end,
    this.text = '',
    List<InlineStyleRange>? inlineStyles,
    this.styleRef,
    this.position,
    Map<String, Object?>? metadata,
  })  : inlineStyles = inlineStyles ?? <InlineStyleRange>[],
        metadata = metadata ?? <String, Object?>{};

  /// Cue start time.
  Duration start;

  /// Cue end time, or `null` when the source format does not carry one (LRC).
  Duration? end;

  /// Plain text content, with markup removed and lines separated by `\n`.
  String text;

  /// Emphasis ranges over [text]. Empty when the cue carries no markup.
  List<InlineStyleRange> inlineStyles;

  /// Name of the [SubtitleStyle] this cue references, when the format has
  /// named styles.
  String? styleRef;

  /// Screen placement, when known.
  CuePosition? position;

  /// Format-specific extras kept for round-tripping (ASS `Layer`, `MarginL`,
  /// `Effect`, ...). Never rendered as visible text by writers that do not
  /// understand a key.
  Map<String, Object?> metadata;

  /// Whether [end] is present.
  bool get hasExplicitEnd => end != null;

  /// `null` when no end time is known.
  Duration? get duration => end == null ? null : end! - start;

  /// True when the cue would render nothing.
  bool get hasVisibleText => text.trim().isNotEmpty;

  /// True when the cue is unusable (no text, or an end before its start).
  bool get isMalformed {
    final Duration? currentEnd = end;
    return currentEnd != null && currentEnd.compareTo(start) < 0;
  }

  /// Shifts the cue by [offset], clamping each timestamp independently at zero.
  void shift(Duration offset) {
    start = _clampToZero(start + offset);
    final Duration? currentEnd = end;
    if (currentEnd != null) {
      end = _clampToZero(currentEnd + offset);
    }
  }

  /// Drops emphasis ranges that fall outside the current text.
  void clampInlineStyles() {
    if (inlineStyles.isEmpty) {
      return;
    }
    inlineStyles = inlineStyles
        .map((InlineStyleRange range) => range.clampTo(text.length))
        .whereType<InlineStyleRange>()
        .toList(growable: false);
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// [end] uses a sentinel so that `copyWith()` can distinguish "leave as is"
  /// from "set to null".
  SubtitleCue copyWith({
    Duration? start,
    Object? end = _unset,
    String? text,
    List<InlineStyleRange>? inlineStyles,
    Object? styleRef = _unset,
    Object? position = _unset,
    Map<String, Object?>? metadata,
  }) {
    return SubtitleCue(
      start: start ?? this.start,
      end: end == _unset ? this.end : end as Duration?,
      text: text ?? this.text,
      inlineStyles: inlineStyles ?? this.inlineStyles,
      styleRef: styleRef == _unset ? this.styleRef : styleRef as String?,
      position: position == _unset ? this.position : position as CuePosition?,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SubtitleCue &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      const ListEquality<InlineStyleRange>().equals(
        other.inlineStyles,
        inlineStyles,
      ) &&
      other.styleRef == styleRef &&
      other.position == position &&
      const DeepCollectionEquality().equals(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(
        start,
        end,
        text,
        const ListEquality<InlineStyleRange>().hash(inlineStyles),
        styleRef,
        position,
        const DeepCollectionEquality().hash(metadata),
      );

  @override
  String toString() => 'SubtitleCue($start..${end ?? '-'}, ${_preview(text)})';

  static String _preview(String value) {
    final String flat = value.replaceAll('\n', r'\n');
    return flat.length <= 32 ? flat : '${flat.substring(0, 29)}...';
  }
}

const Object _unset = Object();

Duration _clampToZero(Duration value) => value.isNegative ? Duration.zero : value;
