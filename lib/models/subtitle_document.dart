import 'package:collection/collection.dart';

import 'subtitle_cue.dart';
import 'subtitle_format.dart';
import 'subtitle_style.dart';

/// Document-wide metadata that does not belong to any single cue.
///
/// [fields] is an open string map so formats can keep their own header data
/// (ASS `[Script Info]`, VTT header lines, ...) without the model growing a
/// field per format.
class SubtitleMetadata {
  SubtitleMetadata({
    this.title,
    this.language,
    Map<String, String>? fields,
  }) : fields = fields ?? <String, String>{};

  String? title;
  String? language;

  /// Format-native header key to value, kept in original casing.
  Map<String, String> fields;

  /// Case-insensitive lookup of a raw header field.
  String? field(String key) {
    final String? direct = fields[key];
    if (direct != null) {
      return direct;
    }
    final String lower = key.toLowerCase();
    for (final MapEntry<String, String> entry in fields.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  bool get isEmpty => title == null && language == null && fields.isEmpty;

  SubtitleMetadata copy() => SubtitleMetadata(
        title: title,
        language: language,
        fields: Map<String, String>.of(fields),
      );

  @override
  bool operator ==(Object other) =>
      other is SubtitleMetadata &&
      other.title == title &&
      other.language == language &&
      const MapEquality<String, String>().equals(other.fields, fields);

  @override
  int get hashCode =>
      Object.hash(title, language, const MapEquality<String, String>().hash(fields));

  @override
  String toString() =>
      'SubtitleMetadata(title: $title, language: $language, ${fields.length} fields)';
}

/// The unified subtitle model every parser produces and every writer consumes.
///
/// Conversion is always `source -> parse -> SubtitleDocument -> write ->
/// target`; there is deliberately no format-to-format shortcut.
class SubtitleDocument {
  SubtitleDocument({
    List<SubtitleCue>? cues,
    List<SubtitleStyle>? styles,
    SubtitleMetadata? metadata,
    this.sourceFormat,
  })  : cues = cues ?? <SubtitleCue>[],
        styles = styles ?? <SubtitleStyle>[],
        metadata = metadata ?? SubtitleMetadata();

  SubtitleDocument.empty() : this();

  final List<SubtitleCue> cues;
  final List<SubtitleStyle> styles;
  final SubtitleMetadata metadata;

  /// Format this document was parsed from, when known.
  SubtitleFormat? sourceFormat;

  bool get isEmpty => cues.isEmpty;

  int get length => cues.length;

  /// Cues that carry visible text.
  Iterable<SubtitleCue> get visibleCues =>
      cues.where((SubtitleCue cue) => cue.hasVisibleText);

  /// Returns the style with [name], or `null`.
  SubtitleStyle? styleByName(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }
    for (final SubtitleStyle style in styles) {
      if (style.name == name) {
        return style;
      }
    }
    return null;
  }

  /// Sorts cues by start time (LRC files are not always chronological).
  void sortByStart() {
    cues.sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));
  }

  /// Shifts every cue by [offset], clamping timestamps at zero.
  void shift(Duration offset) {
    if (offset == Duration.zero) {
      return;
    }
    for (final SubtitleCue cue in cues) {
      cue.shift(offset);
    }
  }

  /// Returns a copy with every cue shifted by [offset].
  SubtitleDocument shifted(Duration offset) {
    final SubtitleDocument result = copy();
    result.shift(offset);
    return result;
  }

  /// Fills in `null` end times, which formats without an end time (LRC) leave
  /// behind. Each cue ends at the next cue's start, and the last cue gets
  /// [fallback] added to its start.
  ///
  /// Cues that already have an end time are left untouched. Input is not
  /// modified; the returned document is a copy.
  SubtitleDocument resolveMissingEndTimes({required Duration fallback}) {
    final SubtitleDocument result = copy();
    final List<SubtitleCue> ordered = List<SubtitleCue>.of(result.cues)
      ..sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));
    for (int i = 0; i < ordered.length; i++) {
      final SubtitleCue cue = ordered[i];
      if (cue.hasExplicitEnd) {
        continue;
      }
      final Duration? nextStart =
          i + 1 < ordered.length ? ordered[i + 1].start : null;
      cue.end = nextStart != null && nextStart.compareTo(cue.start) > 0
          ? nextStart
          : cue.start + fallback;
    }
    return result;
  }

  /// Deep copy. Cue objects are new; their metadata maps are shallow-copied.
  SubtitleDocument copy() {
    return SubtitleDocument(
      cues: cues
          .map((SubtitleCue cue) => cue.copyWith(
                metadata: Map<String, Object?>.of(cue.metadata),
                inlineStyles: List<InlineStyleRange>.of(cue.inlineStyles),
              ))
          .toList(),
      styles: styles.map((SubtitleStyle style) => style.copy()).toList(),
      metadata: metadata.copy(),
      sourceFormat: sourceFormat,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SubtitleDocument &&
      other.sourceFormat == sourceFormat &&
      const ListEquality<SubtitleCue>().equals(other.cues, cues) &&
      const ListEquality<SubtitleStyle>().equals(other.styles, styles) &&
      other.metadata == metadata;

  @override
  int get hashCode => Object.hash(
        sourceFormat,
        const ListEquality<SubtitleCue>().hash(cues),
        const ListEquality<SubtitleStyle>().hash(styles),
        metadata,
      );

  @override
  String toString() =>
      'SubtitleDocument(${cues.length} cues, ${styles.length} styles, '
      'source: ${sourceFormat?.label ?? 'unknown'})';
}
