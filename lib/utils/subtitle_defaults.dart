/// Central configuration for behaviour that must not be scattered as magic
/// numbers across formats and services.
abstract final class SubtitleDefaults {
  /// Duration given to the last cue of a format that has no end times (LRC).
  ///
  /// Every other LRC cue ends at the next cue's start.
  static const Duration lrcEndTimeFallback = Duration(seconds: 5);

  /// Step used by the UI's time-offset control.
  static const Duration timeOffsetStep = Duration(milliseconds: 500);

  /// Appended to a file name when a conversion would overwrite an existing
  /// file: `E01.srt` -> `E01 (1).srt`.
  static const String duplicateNameSuffixTemplate = '{name} ({index}){extension}';

  /// Prefix used for the text of a cue that has no words.
  static const String emptyCuePlaceholder = '';

  /// Output encoding of converted files. v0.1 always writes UTF-8.
  static const String outputEncodingName = 'UTF-8';

  /// Whether converted files start with a UTF-8 byte order mark by default.
  static const bool writeUtf8BomByDefault = false;
}
