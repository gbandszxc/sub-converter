import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/loss_report.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/screens/app_controller.dart';
import 'package:sub_converter/services/settings_store.dart';

import 'fakes.dart';

void main() {
  group('AppController file list', () {
    test('starts empty and cannot convert', () {
      final AppController controller = testController();
      addTearDown(controller.dispose);

      expect(controller.entries, isEmpty);
      expect(controller.canConvert, isFalse);
      expect(controller.fileCount, 0);
    });

    test('adding paths populates entries and inspects them', () async {
      final AppController controller = testController();
      addTearDown(controller.dispose);

      await controller.addPaths(<String>['/movies/a.srt', '/movies/b.ass']);
      await Future<void>.delayed(Duration.zero);

      expect(controller.fileCount, 2);
      expect(controller.canConvert, isTrue);
      expect(controller.entries.first.detectedFormat, SubtitleFormat.srt);
      expect(controller.entries.last.detectedFormat, SubtitleFormat.ass);
    });

    test('a folder path expands into the subtitle files it holds', () async {
      final AppController controller = testController(
        fileService: FakeFileService(
          expandHandler: (List<String> paths) async => <String>[
            for (final String path in paths)
              if (path == '/movies/Season 1')
                '/movies/Season 1/E01.vtt'
              else
                path,
          ],
        ),
      );
      addTearDown(controller.dispose);

      await controller.addPaths(<String>['/movies/Season 1', '/movies/b.ass']);
      await Future<void>.delayed(Duration.zero);

      expect(controller.fileCount, 2);
      expect(controller.entries.first.path, '/movies/Season 1/E01.vtt');
      expect(controller.entries.last.path, '/movies/b.ass');
    });

    test('duplicate paths are ignored', () async {
      final AppController controller = testController();
      addTearDown(controller.dispose);

      final String path = p.join('movies', 'A.srt');
      await controller.addPaths(<String>[path, path, path]);

      expect(controller.fileCount, 1);
    });

    test('case-only differences collapse on Windows but not elsewhere', () async {
      // Duplicate detection is case-insensitive where the file system is
      // (Windows) and case-sensitive where it is not (macOS, Linux). Asserting
      // the platform-appropriate contract is what makes this suite pass on all
      // three targets; hardcoding Windows behaviour failed on the other two.
      final AppController controller = testController();
      addTearDown(controller.dispose);

      await controller.addPaths(<String>[
        p.join('movies', 'A.srt'),
        p.join('movies', 'a.srt'),
      ]);

      expect(controller.fileCount, Platform.isWindows ? 1 : 2);
    });

    test('inspection failure keeps the row with an explanation', () async {
      final FakeFileService service = FakeFileService(
        inspectHandler: (String path) async {
          throw SubtitleConversionException(
            ConversionFailure.readFailed,
            'The file does not exist.',
          );
        },
      );
      final AppController controller = testController(fileService: service);
      addTearDown(controller.dispose);

      await controller.addPaths(<String>['/movies/missing.srt']);
      await Future<void>.delayed(Duration.zero);

      final SubtitleFileEntry entry = controller.entries.single;
      expect(entry.inspectionError, ConversionFailure.readFailed);
      expect(entry.detectedFormat, isNull);
      expect(controller.canConvert, isTrue);
    });

    test('clear removes every row; remove removes one', () async {
      final AppController controller = testController();
      addTearDown(controller.dispose);

      await controller.addPaths(<String>['/a.srt', '/b.srt', '/c.srt']);
      controller.removeEntry(controller.entries.first);
      expect(controller.fileCount, 2);

      controller.clearEntries();
      expect(controller.entries, isEmpty);
    });
  });

  group('AppController options', () {
    test('custom output folder requires a directory', () async {
      final AppController controller = testController();
      addTearDown(controller.dispose);
      await controller.addPaths(<String>['/a.srt']);

      controller.setOutputLocation(OutputLocation.customDirectory);
      expect(controller.options.validationError(), isNotNull);
      expect(controller.canConvert, isFalse);

      controller.setOutputDirectory('/out');
      expect(controller.options.validationError(), isNull);
      expect(controller.canConvert, isTrue);
    });

    test('settings round-trip through the store', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final AppController first = testController(settingsStore: store);
      addTearDown(first.dispose);

      first.setTargetFormat(SubtitleFormat.vtt);
      first.setOutputLocation(OutputLocation.customDirectory);
      first.setOutputDirectory('/out');
      first.setConflictPolicy(OutputConflictPolicy.overwrite);
      first.setTimeOffset(const Duration(milliseconds: -1200));
      first.setWriteUtf8Bom(true);
      first.setStripMediaSuffix(true);
      await Future<void>.delayed(Duration.zero);

      final AppController second = testController(settingsStore: store);
      addTearDown(second.dispose);
      await second.loadSettings();

      expect(second.options.targetFormat, SubtitleFormat.vtt);
      expect(second.options.outputLocation, OutputLocation.customDirectory);
      expect(second.options.outputDirectory, '/out');
      expect(second.options.conflictPolicy, OutputConflictPolicy.overwrite);
      expect(second.options.timeOffset, const Duration(milliseconds: -1200));
      expect(second.options.writeUtf8Bom, isTrue);
      expect(second.options.stripMediaSuffix, isTrue);
    });

    test('corrupt persisted values fall back to defaults', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(
        <String, Object?>{
          'targetFormat': 42,
          'outputLocation': 'not-a-location',
          'conflictPolicy': false,
          'timeOffsetMs': 'oops',
          'writeUtf8Bom': 'yes',
          'stripMediaSuffix': 'nope',
        },
      );
      final AppController controller = testController(settingsStore: store);
      addTearDown(controller.dispose);

      await controller.loadSettings();

      expect(controller.options.targetFormat, SubtitleFormat.srt);
      expect(controller.options.outputLocation, OutputLocation.sourceDirectory);
      expect(
        controller.options.conflictPolicy,
        OutputConflictPolicy.autoRename,
      );
      expect(controller.options.timeOffset, Duration.zero);
      expect(controller.options.writeUtf8Bom, isFalse);
      expect(controller.options.stripMediaSuffix, isFalse);
    });
  });

  group('AppController conversion', () {
    test('successful batch reports counts and message', () async {
      final AppController controller = testController();
      addTearDown(controller.dispose);
      await controller.addPaths(<String>['/a.srt', '/b.srt']);

      await controller.convertAll();

      expect(controller.isConverting, isFalse);
      expect(controller.successCount, 2);
      expect(controller.failureCount, 0);
      expect(controller.lossyCount, 0);
      expect(controller.hasBatchSummary, isTrue);
      expect(controller.batchFailure, isNull);
      expect(
        controller.entries.every((SubtitleFileEntry e) => e.result!.isSuccess),
        isTrue,
      );
    });

    test('one failure does not stop the batch', () async {
      final FakeFileService service = FakeFileService(
        convertBuilder: (String path, ConversionOptions options) =>
            path.endsWith('bad.srt')
            ? failureResult(path)
            : successResult(path, options),
      );
      final AppController controller = testController(fileService: service);
      addTearDown(controller.dispose);
      await controller.addPaths(<String>['/a.srt', '/bad.srt', '/c.srt']);

      await controller.convertAll();

      expect(controller.successCount, 2);
      expect(controller.failureCount, 1);
      expect(controller.hasBatchSummary, isTrue);
      expect(controller.batchFailure, isNull);
    });

    test('lossy success counts as success and lossy', () async {
      final FakeFileService service = FakeFileService(
        convertBuilder: (String path, ConversionOptions options) =>
            successResult(
              path,
              options,
              warnings: const <LossWarning>[
                LossWarning(LossKind.inlineStylesDropped),
              ],
            ),
      );
      final AppController controller = testController(fileService: service);
      addTearDown(controller.dispose);
      await controller.addPaths(<String>['/a.srt']);

      await controller.convertAll();

      expect(controller.successCount, 1);
      expect(controller.lossyCount, 1);
      expect(controller.entries.single.result!.isLossy, isTrue);
    });

    test('convert passes the current options to the service', () async {
      final FakeFileService service = FakeFileService();
      final AppController controller = testController(fileService: service);
      addTearDown(controller.dispose);
      await controller.addPaths(<String>['/a.srt']);
      controller.setTargetFormat(SubtitleFormat.lrc);

      await controller.convertAll();

      expect(service.lastConvertedPaths, <String>['/a.srt']);
      expect(service.lastOptions!.targetFormat, SubtitleFormat.lrc);
    });

    test('remove and clear are ignored while converting', () async {
      final FakeFileService service = FakeFileService();
      final AppController controller = testController(fileService: service);
      addTearDown(controller.dispose);
      await controller.addPaths(<String>['/a.srt', '/b.srt']);

      final Future<void> running = controller.convertAll();
      expect(controller.isConverting, isTrue);
      controller.removeEntry(controller.entries.first);
      controller.clearEntries();
      expect(controller.fileCount, 2);

      await running;
      expect(controller.isConverting, isFalse);
    });
  });
}
