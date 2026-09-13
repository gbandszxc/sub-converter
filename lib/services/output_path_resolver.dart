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

  /// File extensions recognized as "belongs to a media file" when
  /// [stripMediaSuffix] is on. Curated common audio and video containers;
  /// anything else (a language tag such as `.en`, or another subtitle
  /// extension) is left alone. The list is the single source of truth: the
  /// READMEs quote it verbatim.
  static const Set<String> mediaExtensions = <String>{
    // Audio containers.
    'aac', 'ape', 'flac', 'm4a', 'mp3', 'oga', 'ogg', 'opus', 'wav', 'wma',
    // Video containers.
    'avi', 'flv', 'm4v', 'mkv', 'mov', 'mp4', 'mpeg', 'mpg', 'ts', 'webm',
    'wmv',
  };

  /// Drops one trailing media extension from a file base name, matched
  /// case-insensitively: `E01.wav` becomes `E01`.
  ///
  /// Returns [base] unchanged when it does not end in a [mediaExtensions]
  /// member, or when stripping would leave an empty name (`E01` names such as
  /// `.wav` are kept whole).
  static String withoutMediaSuffix(String base) {
    final int dot = base.lastIndexOf('.');
    if (dot <= 0) {
      return base;
    }
    final String suffix = base.substring(dot + 1).toLowerCase();
    return mediaExtensions.contains(suffix) ? base.substring(0, dot) : base;
  }

  /// Builds the plain output file name for [sourcePath] converted to
  /// [targetFormat], keeping the source directory.
  ///
  /// With [stripMediaSuffix], a trailing media extension on the source base
  /// name is dropped first, so `E01.wav.vtt` converts to LRC as `E01.lrc`
  /// instead of `E01.wav.lrc`.
  static String targetFileName(
    String sourcePath,
    SubtitleFormat targetFormat, {
    bool stripMediaSuffix = false,
  }) {
    String base = p.basenameWithoutExtension(sourcePath);
    if (stripMediaSuffix) {
      base = withoutMediaSuffix(base);
    }
    return '$base.${targetFormat.extension}';
  }

  /// Resolves the output path for one conversion.
  ///
  /// [directory] is the folder outputs go to (the source folder or a custom
  /// one). [exists] must report whether a path is already taken.
  /// [stripMediaSuffix] drops a media-name suffix from the base name before
  /// the target extension is appended (see [targetFileName]).
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
    bool stripMediaSuffix = false,
  }) {
    final String fileName = targetFileName(
      sourcePath,
      targetFormat,
      stripMediaSuffix: stripMediaSuffix,
    );
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
