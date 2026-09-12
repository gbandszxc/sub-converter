import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_converter/i18n/app_language.dart';
import 'package:sub_converter/i18n/app_strings.dart';
import 'package:sub_converter/i18n/strings_scope.dart';
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/loss_report.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/platform/system_fonts.dart';
import 'package:sub_converter/screens/app_controller.dart';
import 'package:sub_converter/screens/home_screen.dart';
import 'package:sub_converter/services/file_service.dart';
import 'package:sub_converter/services/format_detector.dart';
import 'package:sub_converter/services/settings_store.dart';

/// Builds a detection for [format] without touching the real detector.
FormatDetection detectionFor(SubtitleFormat? format, {bool ambiguous = false}) {
  if (format == null) {
    return const FormatDetection.none();
  }
  return FormatDetection(
    format: format,
    score: 100,
    evidence: const <String>['fake'],
    extensionMatched: true,
    runnerUp: ambiguous ? SubtitleFormat.srt : null,
    runnerUpScore: ambiguous ? 100 : 0,
  );
}

/// Builds a [FileInspection] with a canned format and encoding.
FileInspection inspectionFor(
  String path, {
  SubtitleFormat? format,
  String encoding = 'UTF-8',
}) {
  return FileInspection(
    sourcePath: path,
    detection: detectionFor(format),
    encodingName: encoding,
    hadBom: false,
    bytes: 128,
  );
}

/// A successful conversion result, optionally lossy.
ConversionResult successResult(
  String path,
  ConversionOptions options, {
  List<LossWarning> warnings = const <LossWarning>[],
}) {
  return ConversionResult(
    sourcePath: path,
    status: ConversionStatus.succeeded,
    sourceFormat: SubtitleFormat.srt,
    targetFormat: options.targetFormat,
    outputPath: '${p.withoutExtension(path)}.${options.targetFormat.extension}',
    detectedEncoding: 'UTF-8',
    warnings: warnings,
    cueCount: 2,
    elapsed: const Duration(milliseconds: 5),
  );
}

/// A failed conversion result carrying a user-facing reason.
ConversionResult failureResult(
  String path, {
  ConversionFailure failure = ConversionFailure.permissionDenied,
  String detail = 'Access to the output folder was denied.',
}) {
  return ConversionResult(
    sourcePath: path,
    status: ConversionStatus.failed,
    failure: failure,
    detail: detail,
    elapsed: const Duration(milliseconds: 5),
  );
}

/// Test double for [FileService] that never touches the file system.
class FakeFileService extends FileService {
  FakeFileService({
    this.inspectHandler,
    this.convertBuilder,
    this.expandHandler,
  });

  final Future<FileInspection> Function(String path)? inspectHandler;
  final ConversionResult Function(String path, ConversionOptions options)?
  convertBuilder;

  /// Fakes folder expansion. Without it, paths pass through the way files do,
  /// so the double never stats the disk.
  final Future<List<String>> Function(List<String> paths)? expandHandler;

  /// Paths passed to the most recent [convertAll] call.
  List<String> lastConvertedPaths = const <String>[];

  ConversionOptions? lastOptions;

  @override
  Future<List<String>> expandPaths(Iterable<String> paths) {
    final List<String> input = paths
        .map((String path) => path.trim())
        .where((String path) => path.isNotEmpty)
        .toList();
    final Future<List<String>> Function(List<String>)? handler = expandHandler;
    if (handler != null) {
      return handler(input);
    }
    return Future<List<String>>.value(input);
  }

  @override
  Future<FileInspection> inspect(String sourcePath) {
    final Future<FileInspection> Function(String)? handler = inspectHandler;
    if (handler != null) {
      return handler(sourcePath);
    }
    final SubtitleFormat? format = SubtitleFormat.fromExtension(
      p.basename(sourcePath),
    );
    return Future<FileInspection>.value(
      inspectionFor(sourcePath, format: format),
    );
  }

  @override
  Future<List<ConversionResult>> convertAll(
    List<String> sourcePaths,
    ConversionOptions options, {
    ConversionProgressCallback? onProgress,
  }) async {
    lastConvertedPaths = List<String>.from(sourcePaths);
    lastOptions = options;
    final List<ConversionResult> results = <ConversionResult>[];
    for (int index = 0; index < sourcePaths.length; index++) {
      final ConversionResult result = convertBuilder == null
          ? successResult(sourcePaths[index], options)
          : convertBuilder!(sourcePaths[index], options);
      results.add(result);
      onProgress?.call(index + 1, sourcePaths.length, result);
    }
    return results;
  }
}

/// Pumps [HomeScreen] wired to [controller] inside a minimal MaterialApp.
///
/// [language] selects the string table; it defaults to English so existing
/// call sites keep working. Note this only fixes the table - a test that drives
/// the in-app Language dropdown must build `SubtitleConverterApp` instead, so
/// the scope rebuilds when the controller changes.
Future<void> pumpHomeScreen(
  WidgetTester tester,
  AppController controller, {
  AppLanguage language = AppLanguage.english,
}) async {
  await tester.pumpWidget(
    StringsScope(
      strings: AppStrings.forLanguage(language),
      child: MaterialApp(home: HomeScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Test double for [SystemFonts] with canned answers; never touches a
/// platform channel.
class FakeSystemFonts implements SystemFonts {
  FakeSystemFonts({
    this.families = const <String>[],
    this.desktopDefault,
    this.failure,
  });

  /// Families the OS would report.
  final List<String> families;

  /// The OS-reported default UI family, if any.
  final String? desktopDefault;

  /// When set, queries throw this instead of answering, simulating a
  /// missing or broken platform implementation.
  final Object? failure;

  @override
  Future<List<String>> installedFontFamilies() async {
    if (failure != null) {
      throw failure!;
    }
    return families;
  }

  @override
  Future<String?> defaultFontFamily() async {
    if (failure != null) {
      throw failure!;
    }
    return desktopDefault;
  }
}

/// Builds a controller with fakes, suitable for widget tests.
AppController testController({
  FakeFileService? fileService,
  InMemorySettingsStore? settingsStore,
  FakeSystemFonts? systemFonts,
  String? platformName,
}) {
  return AppController(
    fileService: fileService ?? FakeFileService(),
    settingsStore: settingsStore ?? InMemorySettingsStore(),
    systemFonts: systemFonts,
    platformName: platformName,
  );
}
