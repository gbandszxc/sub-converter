import 'dart:io';

import 'package:path/path.dart' as p;

import '../formats/built_in_formats.dart';
import '../formats/format_registry.dart';
import '../models/conversion_job.dart';
import '../models/subtitle_exception.dart';
import '../models/subtitle_format.dart';
import 'encoding_service.dart';
import 'format_detector.dart';
import 'output_path_resolver.dart';
import 'subtitle_converter.dart';

/// What a source file looks like before conversion, for the file list.
class FileInspection {
  const FileInspection({
    required this.sourcePath,
    required this.detection,
    required this.encodingName,
    required this.hadBom,
    required this.bytes,
  });

  final String sourcePath;
  final FormatDetection detection;
  final String encodingName;
  final bool hadBom;
  final int bytes;

  SubtitleFormat? get format => detection.format;

  @override
  String toString() => 'FileInspection($sourcePath, '
      '${detection.format?.label ?? 'unknown'}, $encodingName)';
}

/// Called after each file in a batch finishes, for progress reporting.
typedef ConversionProgressCallback = void Function(
  int completed,
  int total,
  ConversionResult result,
);

/// Reads, decodes, detects, converts and writes subtitle files, and resolves
/// dropped folders down to the subtitle files they hold.
///
/// This is the only service that touches the file system. Each file is handled
/// independently, so one failure can never abort a batch: the failure is
/// reported as a [ConversionResult] and the loop continues.
///
/// CPU work per file is a parse plus a render of a text file of at most a few
/// hundred kilobytes, so a plain async loop keeps the UI responsive without
/// the cost and complexity of an isolate.
class FileService {
  FileService({
    FormatRegistry? registry,
    this.encodingService = const EncodingService(),
    SubtitleConverter? converter,
    FormatDetector? detector,
    this.pathResolver = const OutputPathResolver(),
  })  : registry = registry ?? builtInFormatRegistry,
        converter = converter ??
            SubtitleConverter(registry ?? builtInFormatRegistry),
        detector = detector ?? FormatDetector(registry ?? builtInFormatRegistry);

  final FormatRegistry registry;
  final EncodingService encodingService;
  final SubtitleConverter converter;
  final FormatDetector detector;
  final OutputPathResolver pathResolver;

  /// Expands a mixed list of file and folder paths into subtitle file paths.
  ///
  /// Only subtitle files get through, so a drop never fills the list with the
  /// audio, video, image or document files that share a folder with them. A
  /// file qualifies when its name carries a registered subtitle extension (the
  /// registry's lookup, so aliases such as `.subrip` count) or declares no
  /// extension at all — an extensionless name claims nothing, so it stays a
  /// candidate and inspection identifies it from its content. Everything else
  /// (`movie.mkv`, `track.flac`, `cover.jpg`, `notes.txt`) is left out.
  ///
  /// A folder that exists is scanned one level deep and yields its direct files
  /// with a registered subtitle extension; nested folders are not descended
  /// into, and the folder's contents are never read, because probing every file
  /// of a media library just to list it would be wasteful. The result keeps the
  /// input order, with each folder's files sorted by file name so the list is
  /// stable across the order the OS happens to return. A folder that holds
  /// nothing recognizable — or that cannot be listed — contributes nothing
  /// rather than failing the whole drop.
  Future<List<String>> expandPaths(Iterable<String> paths) async {
    final List<String> expanded = <String>[];
    for (final String raw in paths) {
      final String path = raw.trim();
      if (path.isEmpty) {
        continue;
      }
      if (await _isDirectory(path)) {
        expanded.addAll(await _subtitleFilesIn(path));
      } else if (_isSubtitleName(path)) {
        expanded.add(path);
      }
    }
    return expanded;
  }

  /// True when [path]'s name alone allows it to be a subtitle: it either
  /// declares a registered subtitle extension or has no dot at all, which
  /// leaves the content to decide.
  bool _isSubtitleName(String path) {
    final String extension = _extensionOf(path);
    return extension.isEmpty ||
        registry.descriptorForExtension(extension) != null;
  }

  /// The lowercase extension of [path] without its dot, or an empty string when
  /// the name has no dot at all (`subtitles`, `README`). A leading dot is the
  /// name's own suffix, so `.gitignore` reports `gitignore`.
  static String _extensionOf(String path) {
    final String name = p.basename(path).toLowerCase();
    final int dot = name.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }
    return name.substring(dot + 1);
  }

  /// True when [path] names an existing folder. A path that is missing, names a
  /// file, or cannot be inspected at all is not a folder.
  static Future<bool> _isDirectory(String path) async {
    try {
      return await Directory(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Direct subtitle files inside [directory], sorted by file name.
  ///
  /// Names only: no file's content is read, so the extension has to decide here
  /// and an extensionless subtitle inside a folder is not picked up (drop that
  /// file on its own and its content identifies it). An unreadable folder
  /// yields whatever it listed before the error instead of throwing.
  Future<List<String>> _subtitleFilesIn(String directory) async {
    final List<String> matches = <String>[];
    try {
      await for (final FileSystemEntity entity in Directory(directory).list()) {
        if (entity is! File) {
          continue;
        }
        if (registry.descriptorForExtension(entity.path) == null) {
          continue;
        }
        matches.add(entity.path);
      }
    } catch (_) {
      // An unreadable folder contributes the entries it managed to list.
    }
    matches.sort(_byFileName);
    return matches;
  }

  /// Case-insensitive file-name order with the full path as tiebreaker, so the
  /// order does not depend on how the OS enumerates a folder.
  static int _byFileName(String a, String b) {
    final int byName =
        p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
    return byName != 0 ? byName : a.compareTo(b);
  }

  /// Reads and identifies [sourcePath] without converting it.
  ///
  /// Throws [SubtitleConversionException] when the file cannot be read or
  /// decoded. A file whose format cannot be identified still returns an
  /// inspection whose `detection.format` is `null`, so the UI can show
  /// `Unknown` and let conversion produce the real error.
  Future<FileInspection> inspect(String sourcePath) async {
    final List<int> bytes = await _readBytes(sourcePath);
    final DecodedText decoded = encodingService.decode(bytes);
    final FormatDetection detection = detector.detect(
      decoded.text,
      fileName: p.basename(sourcePath),
    );
    return FileInspection(
      sourcePath: sourcePath,
      detection: detection,
      encodingName: decoded.encodingName,
      hadBom: decoded.hadBom,
      bytes: bytes.length,
    );
  }

  /// Converts one file and writes the result.
  ///
  /// Never throws for an expected problem: every failure becomes a
  /// [ConversionResult] with [ConversionStatus.failed].
  Future<ConversionResult> convertFile(
    String sourcePath,
    ConversionOptions options,
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final List<int> bytes = await _readBytes(sourcePath);
      final DecodedText decoded = encodingService.decode(bytes);
      final FormatDetection detection = detector.detect(
        decoded.text,
        fileName: p.basename(sourcePath),
      );
      final SubtitleFormat? sourceFormat = detection.format;
      if (sourceFormat == null) {
        throw UnsupportedFormatException(
          'The format of ${p.basename(sourcePath)} could not be identified.',
        );
      }

      final ConversionOutput output = converter.convert(
        decoded.text,
        sourceFormat: sourceFormat,
        targetFormat: options.targetFormat,
        timeOffset: options.timeOffset,
      );

      final String directory = await _resolveOutputDirectory(sourcePath, options);
      final OutputPathResolution resolution = pathResolver.resolve(
        sourcePath: sourcePath,
        directory: directory,
        targetFormat: options.targetFormat,
        policy: options.conflictPolicy,
        exists: (String path) => File(path).existsSync(),
        stripMediaSuffix: options.stripMediaSuffix,
      );
      if (resolution.isSkip) {
        return ConversionResult(
          sourcePath: sourcePath,
          status: ConversionStatus.skipped,
          sourceFormat: sourceFormat,
          targetFormat: options.targetFormat,
          failure: null,
          detail: resolution.reason,
          detectedEncoding: decoded.encodingName,
          warnings: output.loss.warnings,
          cueCount: output.cueCount,
          elapsed: stopwatch.elapsed,
        );
      }

      final String outputPath = resolution.path!;

      await _writeBytes(
        outputPath,
        encodingService.encode(
          output.content,
          withBom: options.writeUtf8Bom,
        ),
      );

      return ConversionResult(
        sourcePath: sourcePath,
        status: ConversionStatus.succeeded,
        sourceFormat: sourceFormat,
        targetFormat: options.targetFormat,
        outputPath: outputPath,
        detectedEncoding: decoded.encodingName,
        warnings: output.loss.warnings,
        outputRenamed: resolution.renamed,
        cueCount: output.cueCount,
        elapsed: stopwatch.elapsed,
      );
    } on SubtitleConversionException catch (error) {
      return _failure(sourcePath, error, stopwatch);
    } on FileSystemException catch (error) {
      return _failure(
        sourcePath,
        SubtitleConversionException(
          _failureFor(error),
          _describeFileSystemError(error),
          cause: error,
        ),
        stopwatch,
      );
    } catch (error) {
      return _failure(
        sourcePath,
        SubtitleConversionException(
          ConversionFailure.unknown,
          'The file could not be converted.',
          cause: error,
        ),
        stopwatch,
      );
    }
  }

  /// Converts every path in [sourcePaths], one after another.
  ///
  /// [onProgress] fires after each file so the UI can update the list and the
  /// progress bar. The returned list has one result per input path, in order.
  Future<List<ConversionResult>> convertAll(
    List<String> sourcePaths,
    ConversionOptions options, {
    ConversionProgressCallback? onProgress,
  }) async {
    final List<ConversionResult> results = <ConversionResult>[];
    for (int index = 0; index < sourcePaths.length; index++) {
      final ConversionResult result =
          await convertFile(sourcePaths[index], options);
      results.add(result);
      onProgress?.call(index + 1, sourcePaths.length, result);
    }
    return results;
  }

  Future<String> _resolveOutputDirectory(
    String sourcePath,
    ConversionOptions options,
  ) async {
    if (options.outputLocation == OutputLocation.sourceDirectory) {
      return p.dirname(sourcePath);
    }
    final String directory = options.outputDirectory!.trim();
    final String? problem = await _describeDirectoryProblem(directory);
    if (problem != null) {
      throw SubtitleConversionException(
        ConversionFailure.targetPathUnavailable,
        problem,
      );
    }
    return directory;
  }

  /// Returns a user-facing description of why [path] is not a usable output
  /// folder, or `null` when it is fine.
  static Future<String?> _describeDirectoryProblem(String path) async {
    if (await File(path).exists()) {
      return 'The output path is a file, not a folder: $path';
    }
    if (!await Directory(path).exists()) {
      return 'The output folder does not exist: $path';
    }
    return null;
  }

  Future<List<int>> _readBytes(String sourcePath) async {
    final File file = File(sourcePath);
    if (!await file.exists()) {
      throw SubtitleConversionException(
        ConversionFailure.readFailed,
        'The file does not exist: ${p.basename(sourcePath)}',
      );
    }
    return file.readAsBytes();
  }

  Future<void> _writeBytes(String outputPath, List<int> bytes) async {
    final String? problem =
        await _describeDirectoryProblem(File(outputPath).parent.path);
    if (problem != null) {
      throw SubtitleConversionException(
        ConversionFailure.targetPathUnavailable,
        problem,
      );
    }
    await File(outputPath).writeAsBytes(bytes, flush: true);
  }

  ConversionResult _failure(
    String sourcePath,
    SubtitleConversionException error,
    Stopwatch stopwatch,
  ) {
    return ConversionResult(
      sourcePath: sourcePath,
      status: ConversionStatus.failed,
      failure: error.failure,
      detail: error.userMessage,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Maps a file system error onto the closest user-facing failure reason.
  static ConversionFailure _failureFor(FileSystemException error) {
    final int? code = error.osError?.errorCode;
    // 5 / 13 are the Windows and POSIX access-denied codes.
    if (code == 5 || code == 13) {
      return ConversionFailure.permissionDenied;
    }
    if (code == 2 || code == 3) {
      return ConversionFailure.readFailed;
    }
    final String message = error.osError?.message.toLowerCase() ?? '';
    if (message.contains('permission') || message.contains('access is denied')) {
      return ConversionFailure.permissionDenied;
    }
    if (message.contains('no such file') ||
        message.contains('cannot find') ||
        message.contains('system cannot find')) {
      return ConversionFailure.readFailed;
    }
    return ConversionFailure.cannotWriteOutput;
  }

  static String _describeFileSystemError(FileSystemException error) {
    final String? message = error.osError?.message;
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return error.message;
  }
}
