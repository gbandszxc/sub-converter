import 'format_signature.dart';
import 'subtitle_codec.dart';
import 'subtitle_format.dart';

/// Everything the rest of the app needs to know about one subtitle format:
/// how to build its parser and writer, what content it looks like, and what
/// the canonical extension and aliases are.
///
/// Each format ships exactly one of these from its own directory; the format
/// registry just collects them. Adding a format therefore touches one new
/// directory plus one registration line.
class FormatDescriptor {
  FormatDescriptor({
    required this.format,
    required this.createParser,
    required this.createWriter,
    List<FormatSignature>? signatures,
    List<String>? extensionAliases,
    this.supportsStyles = false,
    this.supportsInlineStyles = false,
    this.supportsPositions = false,
    this.requiresEndTime = true,
  })  : signatures = signatures ?? const <FormatSignature>[],
        extensionAliases = extensionAliases ?? const <String>[];

  /// The format this descriptor describes.
  final SubtitleFormat format;

  /// Builds a fresh parser. Parsers are cheap and stateless, but a factory
  /// keeps them from being shared mutable state.
  final SubtitleParser Function() createParser;

  /// Builds a fresh writer.
  final SubtitleWriter Function() createWriter;

  /// Content fingerprints used by the format detector.
  final List<FormatSignature> signatures;

  /// Extra extensions that map to this format, e.g. `subrip` for SRT.
  /// Values are lowercase, without a leading dot.
  final List<String> extensionAliases;

  /// Whether the format can express named styles.
  final bool supportsStyles;

  /// Whether the format can express inline bold/italic/underline.
  final bool supportsInlineStyles;

  /// Whether the format can express screen placement.
  final bool supportsPositions;

  /// Whether the format must write an end time for every cue.
  final bool requiresEndTime;

  /// Canonical extension without a leading dot.
  String get extension => format.extension;

  /// True when [extension] (with or without dot) belongs to this format.
  bool matchesExtension(String candidate) {
    final String normalized = candidate
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.'), '');
    return normalized == extension || extensionAliases.contains(normalized);
  }

  @override
  String toString() => 'FormatDescriptor(${format.label})';
}
