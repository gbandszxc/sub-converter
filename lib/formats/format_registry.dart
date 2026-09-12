import '../models/format_descriptor.dart';
import '../models/subtitle_codec.dart';
import '../models/subtitle_format.dart';

/// Looks up parsers, writers and extension mappings for the known formats.
///
/// The registry holds plain data; it never branches on individual formats.
/// Populate it with [FormatRegistry.withBuiltIns] or a custom descriptor list
/// in tests.
class FormatRegistry {
  FormatRegistry(Iterable<FormatDescriptor> descriptors)
      : _descriptors = <SubtitleFormat, FormatDescriptor>{
          for (final FormatDescriptor descriptor in descriptors)
            descriptor.format: descriptor,
        } {
    for (final FormatDescriptor descriptor in _descriptors.values) {
      for (final String alias in <String>[
        descriptor.extension,
        ...descriptor.extensionAliases,
      ]) {
        _byExtension[alias] = descriptor;
      }
    }
  }

  final Map<SubtitleFormat, FormatDescriptor> _descriptors;
  final Map<String, FormatDescriptor> _byExtension =
      <String, FormatDescriptor>{};

  /// All registered formats, in declaration order.
  List<SubtitleFormat> get formats => SubtitleFormat.values
      .where(_descriptors.containsKey)
      .toList(growable: false);

  /// Descriptors in declaration order.
  List<FormatDescriptor> get descriptors => formats
      .map((SubtitleFormat format) => _descriptors[format]!)
      .toList(growable: false);

  bool supports(SubtitleFormat format) => _descriptors.containsKey(format);

  FormatDescriptor? descriptorFor(SubtitleFormat format) => _descriptors[format];

  /// Resolves a descriptor from a file extension or bare file name.
  FormatDescriptor? descriptorForExtension(String value) {
    final String normalized = _extensionOf(value);
    if (normalized.isEmpty) {
      return null;
    }
    return _byExtension[normalized];
  }

  /// Builds a parser for [format].
  ///
  /// Throws [ArgumentError] when the format is not registered.
  SubtitleParser parserFor(SubtitleFormat format) {
    final FormatDescriptor? descriptor = _descriptors[format];
    if (descriptor == null) {
      throw ArgumentError.value(
        format,
        'format',
        'No parser registered for this format',
      );
    }
    return descriptor.createParser();
  }

  /// Builds a writer for [format].
  ///
  /// Throws [ArgumentError] when the format is not registered.
  SubtitleWriter writerFor(SubtitleFormat format) {
    final FormatDescriptor? descriptor = _descriptors[format];
    if (descriptor == null) {
      throw ArgumentError.value(
        format,
        'format',
        'No writer registered for this format',
      );
    }
    return descriptor.createWriter();
  }

  /// True when [format] can be produced as output.
  bool canWrite(SubtitleFormat format) => supports(format);

  /// True when [format] can be read as input.
  bool canRead(SubtitleFormat format) => supports(format);

  static String _extensionOf(String value) {
    String candidate = value.trim().toLowerCase();
    if (candidate.isEmpty) {
      return '';
    }
    final int separator = candidate.lastIndexOf(RegExp(r'[\\/]'));
    if (separator >= 0) {
      candidate = candidate.substring(separator + 1);
    }
    final int dot = candidate.lastIndexOf('.');
    if (dot >= 0) {
      candidate = candidate.substring(dot + 1);
    }
    return candidate;
  }
}
