/// Identifies a subtitle format supported by the conversion core.
///
/// Adding a format means adding a value here, a [FormatDescriptor], and a
/// parser/writer pair. Nothing else in the core needs to change.
///
/// The enum carries only language-neutral data. The longer, user-facing
/// description is localized by the UI through `AppStrings.formatDescription`,
/// so no English display text lives here.
enum SubtitleFormat {
  srt('SRT', 'srt'),
  vtt('VTT', 'vtt'),
  lrc('LRC', 'lrc'),
  ass('ASS', 'ass'),
  ssa('SSA', 'ssa'),
  sbv('SBV', 'sbv');

  const SubtitleFormat(this.label, this.extension);

  /// Short, user-facing name, e.g. `SRT`. Language-neutral.
  final String label;

  /// Canonical file extension without a leading dot.
  final String extension;

  /// Resolves a format from a file extension or a bare file name.
  ///
  /// Accepts `srt`, `.SRT` and `movie.en.srt`. Returns `null` when the
  /// extension is unknown.
  static SubtitleFormat? fromExtension(String value) {
    final String normalized = _normalize(value);
    if (normalized.isEmpty) {
      return null;
    }
    for (final SubtitleFormat format in SubtitleFormat.values) {
      if (format.extension == normalized) {
        return format;
      }
    }
    return null;
  }

  /// Resolves a format from its short label (`SRT`, `ass`, ...).
  static SubtitleFormat? fromLabel(String value) {
    final String normalized = value.trim().toLowerCase();
    for (final SubtitleFormat format in SubtitleFormat.values) {
      if (format.label.toLowerCase() == normalized ||
          format.name == normalized) {
        return format;
      }
    }
    return null;
  }

  static String _normalize(String value) {
    String candidate = value.trim().toLowerCase();
    if (candidate.isEmpty) {
      return '';
    }
    final int separator = candidate.lastIndexOf(RegExp(r'[\\/]'));
    if (separator >= 0) {
      candidate = candidate.substring(separator + 1);
    }
    final int lastDot = candidate.lastIndexOf('.');
    if (lastDot >= 0) {
      candidate = candidate.substring(lastDot + 1);
    }
    return candidate;
  }
}
