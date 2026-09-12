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

/// Reads, decodes, detects, converts and writes subtitle files.
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
