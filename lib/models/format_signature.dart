/// A content-based fingerprint used to identify a subtitle format.
///
/// Signatures live next to the format they describe and are registered through
/// `FormatDescriptor`; the detector itself stays format-agnostic.
class FormatSignature {
  const FormatSignature({
    required this.id,
    required this.weight,
    required this.matches,
  });

  /// Diagnostic identifier, e.g. `ass.script-info`.
  final String id;

  /// Confidence contributed when [matches] returns true. Higher is stronger.
  final int weight;

  /// Tests raw file content. Must be cheap and must never throw.
  final bool Function(String content) matches;

  @override
  String toString() => 'FormatSignature($id, +$weight)';
}

/// Factories for the common signature shapes.
abstract final class FormatSignatures {
  /// Fires when the content contains [needle].
  static FormatSignature contains(
    String needle, {
    required int weight,
    String? id,
    bool ignoreCase = false,
  }) {
    final String target = ignoreCase ? needle.toLowerCase() : needle;
    return FormatSignature(
      id: id ?? 'contains:"$needle"',
      weight: weight,
      matches: (String content) {
        if (target.isEmpty) {
          return false;
        }
        final String haystack = ignoreCase ? content.toLowerCase() : content;
        return haystack.contains(target);
      },
    );
  }

  /// Fires when [pattern] matches anywhere in the content.
  static FormatSignature matchesPattern(
    RegExp pattern, {
    required int weight,
    required String id,
  }) {
    return FormatSignature(
      id: id,
      weight: weight,
      matches: (String content) => pattern.hasMatch(content),
    );
  }

  /// Fires when the first non-blank line matches [pattern]. Used for formats
  /// that announce themselves in a header line (`WEBVTT`).
  static FormatSignature firstLineMatches(
    RegExp pattern, {
    required int weight,
    required String id,
  }) {
    return FormatSignature(
      id: id,
      weight: weight,
      matches: (String content) {
        for (final String line in content.split('\n')) {
          final String trimmed = line.trim();
          if (trimmed.isEmpty) {
            continue;
          }
          return pattern.hasMatch(trimmed);
        }
        return false;
      },
    );
  }

  /// Fires when [pattern] matches at least [minimum] lines of the content.
  ///
  /// Useful for line-oriented formats (LRC, SBV) where a single coincidental
  /// match is not enough evidence.
  static FormatSignature linePatternCount(
    RegExp pattern, {
    required int weight,
    required int minimum,
    required String id,
  }) {
    return FormatSignature(
      id: id,
      weight: weight,
      matches: (String content) {
        int count = 0;
        for (final String line in content.split('\n')) {
          if (pattern.hasMatch(line.trim())) {
            count++;
            if (count >= minimum) {
              return true;
            }
          }
        }
        return false;
      },
    );
  }
}
