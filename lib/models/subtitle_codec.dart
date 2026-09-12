import 'subtitle_document.dart';

/// Turns subtitle file content into the unified model.
///
/// Implementations must be pure: no file system, no Flutter, no network.
abstract interface class SubtitleParser {
  /// Parses [content], which was already decoded to a Dart string.
  ///
  /// Throws [SubtitleSyntaxException] when the content cannot be parsed.
  SubtitleDocument parse(String content);
}

/// Turns the unified model back into subtitle file content.
///
/// Implementations must be pure: no file system, no Flutter, no network.
abstract interface class SubtitleWriter {
  /// Renders [document] into this format's text representation.
  ///
  /// [document] is never modified.
  String write(SubtitleDocument document);
}
