/// Why a file could not be converted.
///
/// The enum is the machine-readable reason. Its [title] and [message] are the
/// developer-facing diagnostic (used by tests and for logging); the UI must
/// show the localized title from `AppStrings.failureTitle` instead, and only
/// surface a technical detail when it carries a path the user needs.
///
/// Detailed causes stay in [SubtitleConversionException.cause] for debug logs
/// only.
enum ConversionFailure {
  unsupportedFormat(
    'Unsupported format',
    'The file format could not be identified or is not supported.',
  ),
  encodingDetectionFailed(
    'Encoding detection failed',
    'The text encoding of this file could not be determined.',
  ),
  invalidSubtitleSyntax(
    'Invalid subtitle syntax',
    'The file does not contain valid subtitle data.',
  ),
  emptyDocument(
    'No subtitle entries',
    'The file was parsed but contains no subtitle entries.',
  ),
  cannotWriteOutput(
    'Cannot write output file',
    'The converted file could not be written.',
  ),
  permissionDenied(
    'Permission denied',
    'The output file could not be written because access was denied.',
  ),
  targetPathUnavailable(
    'Target path unavailable',
    'The output directory does not exist or is not reachable.',
  ),
  readFailed('Cannot read input file', 'The source file could not be read.'),
  unknown('Conversion failed', 'The file could not be converted.');

  const ConversionFailure(this.title, this.message);

  /// Short, user-facing title, e.g. `Permission denied`.
  final String title;

  /// One-sentence, user-facing explanation.
  final String message;
}

/// Base class for every recoverable conversion error.
///
/// Carries a [ConversionFailure] so the UI can show a clear reason without
/// ever printing a Dart stack trace at the user.
class SubtitleConversionException implements Exception {
  SubtitleConversionException(this.failure, this.message, {this.cause});

  final ConversionFailure failure;

  /// Technical, single-line detail. Safe to show next to [ConversionFailure.title].
  final String message;

  /// Underlying error, for debug logging only.
  final Object? cause;

  /// Reason shown to the user.
  String get userMessage => message.isEmpty ? failure.message : message;

  @override
  String toString() => '${failure.name}: $message';
}

/// Raised by parsers when content does not match the format's grammar.
class SubtitleSyntaxException extends SubtitleConversionException {
  SubtitleSyntaxException(String message, {super.cause})
    : super(ConversionFailure.invalidSubtitleSyntax, message);
}

/// Raised when no format matches the file's content or extension.
class UnsupportedFormatException extends SubtitleConversionException {
  UnsupportedFormatException([String? message])
    : super(
        ConversionFailure.unsupportedFormat,
        message ??
            'The file format could not be identified or is not supported.',
      );
}
