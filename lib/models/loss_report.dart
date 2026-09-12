/// Non-fatal information loss that a conversion will cause.
///
/// A lossy conversion still succeeds; the UI renders these as localized notes
/// next to the result instead of treating them as a failure. This type stays
/// free of display text so the pure layers (`models`, `formats`, `services`)
/// never depend on the localization layer; the target format's label and the
/// localized wording are supplied by the UI.
library;

/// What kind of information a conversion had to drop.
///
/// The UI maps each kind to a localized sentence; the analyzer only reports
/// which loss occurred and, when meaningful, how many times.
enum LossKind {
  /// Target cannot express bold/italic/underline emphasis.
  inlineStylesDropped,

  /// Target has no representation for screen positioning.
  positionsDropped,

  /// Target has no named styles.
  namedStylesDropped,

  /// LRC has no line breaks, so multi-line cues were joined.
  lrcLineBreaksJoined,

  /// LRC has no end times, so end times were dropped.
  lrcEndTimesDropped,

  /// Source-side oddity: a cue whose end precedes its start.
  invertedCueTiming,
}

/// One reported loss: a [kind] plus how many items it affects.
///
/// Most losses are binary (the capability is missing once), so [count]
/// defaults to 1. The count only matters where a localized sentence says
/// "N cues ..." (`invertedCueTiming`).
class LossWarning {
  const LossWarning(this.kind, {this.count = 1});

  final LossKind kind;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is LossWarning && other.kind == kind && other.count == count;

  @override
  int get hashCode => Object.hash(kind, count);

  @override
  String toString() => 'LossWarning(${kind.name}, count: $count)';
}

/// The full set of losses for one conversion.
class LossReport {
  const LossReport(this.warnings);

  static const LossReport none = LossReport(<LossWarning>[]);

  final List<LossWarning> warnings;

  bool get isLossy => warnings.isNotEmpty;

  @override
  String toString() => 'LossReport($warnings)';
}
