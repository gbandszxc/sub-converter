import 'package:path/path.dart' as p;

import '../models/conversion_job.dart';
import '../models/subtitle_format.dart';

/// What to do with a resolved output path.
enum OutputPathAction {
  /// Write to [OutputPathResolution.path].
  write,

  /// Do not write; the file already exists and the policy is
  /// [OutputConflictPolicy.skip].
  skip,
}

/// The output path chosen for one source file.
class OutputPathResolution {
  const OutputPathResolution.write(
    this.path, {
    this.renamed = false,
  })  : action = OutputPathAction.write,
        reason = null;

  const OutputPathResolution.skip(this.reason)
      : action = OutputPathAction.skip,
        path = null,
        renamed = false;

  final OutputPathAction action;

  /// Absolute or relative path to write, when [action] is
  /// [OutputPathAction.write].
  final String? path;

  /// True when the requested name was taken and a numbered name was used.
  final bool renamed;

  /// Why the entry was skipped.
  final String? reason;

  bool get isSkip => action == OutputPathAction.skip;

  @override
  String toString() => 'OutputPathResolution(${action.name}, $path)';
}

/// Decides where a converted file goes and how name conflicts are resolved.
///
/// The existence check is injected so the rules are unit-testable without
/// touching disk, and so the resolver can never accidentally write.
class OutputPathResolver {
  const OutputPathResolver();

  /// Number of extra names to try before giving up on [OutputConflictPolicy.autoRename].
  ///
  /// `E01.srt` through `E01 (500).srt` is far beyond anything a real batch
  /// produces; the bound only stops an infinite loop on a pathological
  /// directory listing.
  static const int maxAutoRenameAttempts = 500;

  /// Builds the plain output file name for [sourcePath] converted to
  /// [targetFormat], keeping the source directory.
  static String targetFileName(String sourcePath, SubtitleFormat targetFormat) {
    final String base = p.basenameWithoutExtension(sourcePath);
    return '$base.${targetFormat.extension}';
  }

  /// Resolves the output path for one conversion.
  ///
  /// [directory] is the folder outputs go to (the source folder or a custom
  /// one). [exists] must report whether a path is already taken.
  ///
  /// The source file itself is never a valid output path: when [sourcePath]
  /// and the resolved path are the same file, the name is always changed, even
  /// under [OutputConflictPolicy.overwrite], because conversions must never
  /// modify their source.
  OutputPathResolution resolve({
    required String sourcePath,
    required String directory,
    required SubtitleFormat targetFormat,
    required OutputConflictPolicy policy,
    required bool Function(String path) exists,
  }) {
    final String fileName = targetFileName(sourcePath, targetFormat);
    final String requested = p.join(directory, fileName);

    final bool collidesWithSource = _isSameFile(requested, sourcePath);
    final bool taken = exists(requested);

    if (!taken && !collidesWithSource) {
      return OutputPathResolution.write(requested);
    }

    switch (policy) {
      case OutputConflictPolicy.overwrite:
        if (collidesWithSource) {
          // Refuse to overwrite the source: fall back to renaming.
          return _autoRename(
            directory: directory,
            fileName: fileName,
            sourcePath: sourcePath,
            exists: exists,
            forcedRename: true,
          );
        }
        return OutputPathResolution.write(requested);
      case OutputConflictPolicy.skip:
        if (collidesWithSource) {
          return OutputPathResolution.skip(
            'Output would overwrite the source file.',
          );
        }
        return OutputPathResolution.skip('Output file already exists.');
      case OutputConflictPolicy.autoRename:
        return _autoRename(
          directory: directory,
          fileName: fileName,
          sourcePath: sourcePath,
          exists: exists,
          forcedRename: collidesWithSource,
        );
    }
  }

  OutputPathResolution _autoRename({
    required String directory,
    required String fileName,
    required String sourcePath,
    required bool Function(String path) exists,
    required bool forcedRename,
  }) {
    final String extension = p.extension(fileName);
    final String base = p.basenameWithoutExtension(fileName);
    for (int index = 1; index <= maxAutoRenameAttempts; index++) {
      final String candidate = p.join(directory, '$base ($index)$extension');
      if (!exists(candidate) && !_isSameFile(candidate, sourcePath)) {
        return OutputPathResolution.write(candidate, renamed: true);
      }
    }
    return OutputPathResolution.skip(
      forcedRename
          ? 'No free output name was found; the source file must not be '
              'overwritten.'
          : 'No free output name was found.',
    );
  }

  static bool _isSameFile(String a, String b) {
    if (p.equals(a, b)) {
      return true;
    }
    // `equals` handles case-insensitivity on Windows; compare absolute forms
    // too so relative and absolute spellings of one path still match.
    return p.equals(p.absolute(a), p.absolute(b));
  }
}
