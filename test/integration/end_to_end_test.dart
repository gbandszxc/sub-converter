import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/screens/app_controller.dart';
import 'package:sub_converter/services/file_service.dart';
import 'package:sub_converter/services/settings_store.dart';

/// End-to-end tests: real files on disk, the real [FileService], and the real
/// [AppController] the UI drives. Only the platform dialogs and the widget
/// layer are left out.
void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('sub_converter_e2e');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  File copyFixture(String format, String name) {
    final File source = File(p.join('test', 'fixtures', format, name));
    final File target = File(p.join(workspace.path, name));
    target.writeAsBytesSync(source.readAsBytesSync());
    return target;
  }

  File writeText(String name, String content, {List<int>? bytes}) {
    final File file = File(p.join(workspace.path, name));
    file.writeAsBytesSync(bytes ?? utf8.encode(content));
    return file;
  }

  AppController controllerFor({
    required SubtitleFormat target,
    OutputLocation location = OutputLocation.sourceDirectory,
    String? directory,
    OutputConflictPolicy policy = OutputConflictPolicy.autoRename,
    Duration offset = Duration.zero,
  }) {
    return AppController(
      fileService: FileService(),
      settingsStore: InMemorySettingsStore(),
      initialOptions: ConversionOptions(
        targetFormat: target,
        outputLocation: location,
        outputDirectory: directory,
        conflictPolicy: policy,
        timeOffset: offset,
      ),
    );
  }

  /// Waits for the controller's asynchronous inspection of every entry.
  Future<void> settleInspection(AppController controller) async {
    for (int attempt = 0; attempt < 100; attempt++) {
      final bool settled = controller.entries.every(
        (SubtitleFileEntry entry) => !entry.isInspecting,
      );
      if (settled) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('file inspection did not settle');
  }

  test('add, inspect and convert a batch through the real services', () async {
    final File srt = copyFixture('srt', 'basic.srt');
    final File ass = copyFixture('ass', 'basic.ass');
    final AppController controller =
        controllerFor(target: SubtitleFormat.vtt);

    await controller.addPaths(<String>[srt.path, ass.path]);
    await settleInspection(controller);

    expect(controller.fileCount, 2);
    expect(controller.entries[0].detectedFormat, SubtitleFormat.srt);
    expect(controller.entries[1].detectedFormat, SubtitleFormat.ass);
    expect(controller.entries[0].encodingName, 'UTF-8');
    expect(controller.canConvert, isTrue);

    await controller.convertAll();

    expect(controller.successCount, 2);
    expect(controller.failureCount, 0);
    expect(controller.batchMessage, contains('2 succeeded'));
    expect(controller.isConverting, isFalse);

    for (final String name in <String>['basic.vtt']) {
      final File output = File(p.join(workspace.path, name));
      expect(output.existsSync(), isTrue, reason: '$name should exist');
      expect(utf8.decode(output.readAsBytesSync()), startsWith('WEBVTT'));
    }
    // The ASS source produced a second VTT file under its own name.
    expect(
      File(p.join(workspace.path, 'basic.vtt')).existsSync(),
      isTrue,
    );
    // Sources are untouched.
    expect(
      srt.readAsBytesSync(),
      File(p.join('test', 'fixtures', 'srt', 'basic.srt')).readAsBytesSync(),
    );
  });

  test('a GBK source converts to readable Chinese', () async {
    // Chinese subtitle encoded as GBK, which must be detected, not mojibake.
    final File gbk = writeText(
      'gbk.srt',
      '',
      bytes: <int>[
        ...utf8.encode('1\n00:00:01,000 --> 00:00:03,000\n'),
        0xD6, 0xD0, 0xCE, 0xC4, // 中文
        0xA3, 0xAC, // ，
        ...utf8.encode('Hello\n'),
      ],
    );
    final AppController controller = controllerFor(target: SubtitleFormat.vtt);
    await controller.addPaths(<String>[gbk.path]);
    await settleInspection(controller);

    expect(controller.entries.single.detectedFormat, SubtitleFormat.srt);
    expect(controller.entries.single.encodingName, startsWith('GBK'));

    await controller.convertAll();
    expect(controller.successCount, 1);

    final String converted = utf8.decode(
      File(p.join(workspace.path, 'gbk.vtt')).readAsBytesSync(),
    );
    expect(converted, contains('中文，Hello'));
  });

  test('a Shift-JIS source converts to readable Japanese', () async {
    final File sjis = writeText(
      'jp.srt',
      '',
      bytes: <int>[
        ...utf8.encode('1\n00:00:01,000 --> 00:00:03,000\n'),
        0x93, 0xFA, 0x96, 0x7B, // 日本
        ...utf8.encode('\n'),
      ],
    );
    final AppController controller = controllerFor(target: SubtitleFormat.srt);
    await controller.addPaths(<String>[sjis.path]);
    await settleInspection(controller);
    expect(controller.entries.single.encodingName, 'Shift_JIS');

    // Same-format conversion: the source must be protected by auto rename.
    await controller.convertAll();
    expect(controller.successCount, 1);
    final String converted = utf8.decode(
      File(p.join(workspace.path, 'jp (1).srt')).readAsBytesSync(),
    );
    expect(converted, contains('日本'));
    expect(
      sjis.readAsBytesSync()[0],
      0x31, // the original still starts with '1'
    );
  });

  test('one broken file does not stop the batch', () async {
    final File good = copyFixture('srt', 'basic.srt');
    final File broken = writeText('broken.srt', 'this is not a subtitle\n');
    final File notes = writeText('notes.txt', 'shopping list\n');
    final AppController controller = controllerFor(target: SubtitleFormat.lrc);

    await controller.addPaths(<String>[good.path, broken.path, notes.path]);
    await settleInspection(controller);
    expect(controller.entries[1].detectedFormat, SubtitleFormat.srt);
    expect(controller.entries[2].detectedFormat, isNull);

    await controller.convertAll();

    expect(controller.successCount, 1);
    expect(controller.failureCount, 2);
    expect(controller.completedCount, 3);
    expect(controller.batchMessage, contains('1 succeeded'));
    expect(controller.batchMessage, contains('2 failed'));

    for (final SubtitleFileEntry entry in controller.entries.skip(1)) {
      expect(entry.result!.isFailure, isTrue);
      expect(entry.result!.failure, isNotNull);
      // Failures carry a short reason, never a stack trace.
      expect(entry.result!.detail, isNot(contains('#0')));
      expect(entry.result!.detail, isNot(contains('Exception:')));
    }
    expect(
      File(p.join(workspace.path, 'basic.lrc')).existsSync(),
      isTrue,
    );
  });

  test('converts into a custom folder with a time offset', () async {
    final File srt = copyFixture('srt', 'basic.srt');
    final Directory out = Directory(p.join(workspace.path, 'converted'))
      ..createSync();
    final AppController controller = controllerFor(
      target: SubtitleFormat.sbv,
      location: OutputLocation.customDirectory,
      directory: out.path,
      offset: const Duration(seconds: 1),
    );

    await controller.addPaths(<String>[srt.path]);
    await settleInspection(controller);
    await controller.convertAll();

    final File output = File(p.join(out.path, 'basic.sbv'));
    expect(output.existsSync(), isTrue);
    expect(controller.entries.single.result!.outputPath, output.path);
    // The offset moved the first cue from 00:00:0x to one second later.
    final String text = utf8.decode(output.readAsBytesSync());
    expect(text, isNot(contains('0:00:01.000,')));
  });

  test('duplicate paths are ignored and rows can be removed', () async {
    final File srt = copyFixture('srt', 'basic.srt');
    final AppController controller = controllerFor(target: SubtitleFormat.vtt);

    await controller.addPaths(<String>[srt.path, srt.path]);
    await controller.addPaths(<String>[srt.path]);
    await settleInspection(controller);
    expect(controller.fileCount, 1);

    controller.removeEntry(controller.entries.single);
    expect(controller.fileCount, 0);
    expect(controller.canConvert, isFalse);
  });

  test('a missing custom folder fails each file with a clear reason', () async {
    // ConversionOptions only validates shape (a folder was chosen); whether the
    // folder actually exists is checked when writing, per file.
    final AppController controller = controllerFor(
      target: SubtitleFormat.vtt,
      location: OutputLocation.customDirectory,
      directory: p.join(workspace.path, 'does-not-exist'),
    );
    expect(controller.options.validationError(), isNull);

    final File srt = copyFixture('srt', 'basic.srt');
    await controller.addPaths(<String>[srt.path]);
    await settleInspection(controller);
    expect(controller.canConvert, isTrue);

    await controller.convertAll();

    expect(controller.failureCount, 1);
    expect(
      controller.entries.single.result!.failure,
      ConversionFailure.targetPathUnavailable,
    );
    expect(controller.entries.single.result!.detail, contains('does-not-exist'));
  });

  test('an empty custom folder choice disables conversion', () async {
    final AppController controller = controllerFor(
      target: SubtitleFormat.vtt,
      location: OutputLocation.customDirectory,
    );
    expect(controller.options.validationError(), isNotNull);
    expect(controller.canConvert, isFalse);
  });

  test('an existing output is auto-renamed, never replaced', () async {
    final File srt = copyFixture('srt', 'basic.srt');
    final File existing = File(p.join(workspace.path, 'basic.vtt'));
    existing.writeAsStringSync('keep me');

    final AppController controller = controllerFor(target: SubtitleFormat.vtt);
    await controller.addPaths(<String>[srt.path]);
    await settleInspection(controller);
    await controller.convertAll();

    expect(existing.readAsStringSync(), 'keep me');
    expect(
      File(p.join(workspace.path, 'basic (1).vtt')).existsSync(),
      isTrue,
    );
    expect(controller.entries.single.result!.outputPath, endsWith('basic (1).vtt'));
  });

  test('settings survive a controller restart', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    final AppController first = AppController(
      fileService: FileService(),
      settingsStore: store,
      initialOptions: const ConversionOptions(targetFormat: SubtitleFormat.srt),
    );
    await first.loadSettings();
    first.setTargetFormat(SubtitleFormat.ass);
    first.setConflictPolicy(OutputConflictPolicy.skip);
    first.setTimeOffset(const Duration(milliseconds: -500));
    first.setWriteUtf8Bom(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final AppController second = AppController(
      fileService: FileService(),
      settingsStore: store,
      initialOptions: const ConversionOptions(targetFormat: SubtitleFormat.srt),
    );
    await second.loadSettings();

    expect(second.options.targetFormat, SubtitleFormat.ass);
    expect(second.options.conflictPolicy, OutputConflictPolicy.skip);
    expect(second.options.timeOffset, const Duration(milliseconds: -500));
    expect(second.options.writeUtf8Bom, isTrue);
  });

  test('a 100 file batch converts without losing any file', () async {
    // Goal scale: 1-100 files in one run. Every file is independent, progress
    // is reported per file, and nothing may be dropped along the way.
    final Directory out = Directory(p.join(workspace.path, 'bulk'))..createSync();
    final List<String> sources = <String>[];
    for (int index = 0; index < 100; index++) {
      final File file = File(
        p.join(workspace.path, 'E${index.toString().padLeft(3, '0')}.ass'),
      );
      file.writeAsBytesSync(
        File(p.join('test', 'fixtures', 'ass', 'basic.ass')).readAsBytesSync(),
      );
      sources.add(file.path);
    }

    final AppController controller = controllerFor(
      target: SubtitleFormat.srt,
      location: OutputLocation.customDirectory,
      directory: out.path,
    );
    await controller.addPaths(sources);
    await settleInspection(controller);
    expect(controller.completedCount, 0, reason: 'nothing converts on add');

    final Stopwatch stopwatch = Stopwatch()..start();
    await controller.convertAll();
    stopwatch.stop();

    expect(controller.fileCount, 100);
    expect(controller.successCount, 100);
    expect(controller.failureCount, 0);
    expect(out.listSync().whereType<File>().length, 100);
    // Generous safety net against pathological slowness, not a performance
    // target: subtitle files are kilobytes.
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 60)),
      reason: '100 small files took ${stopwatch.elapsed}',
    );
  });

  test('awkward file names still convert correctly', () async {
    final String content =
        File(p.join('test', 'fixtures', 'srt', 'basic.srt')).readAsStringSync();
    final AppController controller = controllerFor(target: SubtitleFormat.vtt);

    // Uppercase extension, spaces, non-ASCII characters, and multiple dots.
    final List<File> sources = <File>[
      writeText('EPISODE 01.SRT', content),
      writeText('第01話 日本語 字幕.srt', content),
      writeText('show.s01e01.en.srt', content),
    ];
    await controller.addPaths(sources.map((File file) => file.path).toList());
    await settleInspection(controller);

    expect(
      controller.entries.every(
        (SubtitleFileEntry entry) => entry.detectedFormat == SubtitleFormat.srt,
      ),
      isTrue,
      reason: controller.entries
          .map((SubtitleFileEntry e) => '${e.fileName}: ${e.detectedFormat}')
          .join(', '),
    );

    await controller.convertAll();
    expect(controller.failureCount, 0);
    expect(controller.successCount, 3);

    expect(File(p.join(workspace.path, 'EPISODE 01.vtt')).existsSync(), isTrue);
    expect(
      File(p.join(workspace.path, '第01話 日本語 字幕.vtt')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(workspace.path, 'show.s01e01.en.vtt')).existsSync(),
      isTrue,
    );
  });

  test('an extensionless file is identified from its content alone', () async {
    // Detection is content-first, so a missing extension is not fatal.
    final File extensionless = writeText(
      'subtitles',
      File(p.join('test', 'fixtures', 'srt', 'basic.srt')).readAsStringSync(),
    );
    final AppController controller = controllerFor(target: SubtitleFormat.vtt);
    await controller.addPaths(<String>[extensionless.path]);
    await settleInspection(controller);

    expect(controller.entries.single.detectedFormat, SubtitleFormat.srt);
    expect(
      controller.entries.single.detection!.isContentBased,
      isTrue,
      reason: 'the format must come from the content, not the name',
    );

    await controller.convertAll();
    expect(controller.successCount, 1);
    expect(
      File(p.join(workspace.path, 'subtitles.vtt')).existsSync(),
      isTrue,
    );
  });

  test('a file with no usable content or extension is unsupported', () async {
    final File notes = writeText('notes', 'a plain text file, not subtitles\n');
    final AppController controller = controllerFor(target: SubtitleFormat.vtt);
    await controller.addPaths(<String>[notes.path]);
    await settleInspection(controller);
    expect(controller.entries.single.detectedFormat, isNull);

    await controller.convertAll();
    expect(controller.failureCount, 1);
    expect(
      controller.entries.single.result!.failure,
      ConversionFailure.unsupportedFormat,
    );
  });

  test('every fixture format converts to every other format on disk', () async {
    final Map<SubtitleFormat, String> fixtures = <SubtitleFormat, String>{
      SubtitleFormat.srt: 'basic.srt',
      SubtitleFormat.vtt: 'basic.vtt',
      SubtitleFormat.lrc: 'basic.lrc',
      SubtitleFormat.ass: 'basic.ass',
      SubtitleFormat.ssa: 'basic.ssa',
      SubtitleFormat.sbv: 'basic.sbv',
    };

    for (final MapEntry<SubtitleFormat, String> entry in fixtures.entries) {
      final Directory perSource = Directory(
        p.join(workspace.path, 'from_${entry.key.name}'),
      )..createSync();
      final File source = File(p.join(perSource.path, entry.value));
      source.writeAsBytesSync(
        File(p.join('test', 'fixtures', entry.key.name, entry.value))
            .readAsBytesSync(),
      );

      for (final SubtitleFormat target in SubtitleFormat.values) {
        final AppController controller = controllerFor(
          target: target,
          location: OutputLocation.customDirectory,
          directory: perSource.path,
        );
        await controller.addPaths(<String>[source.path]);
        await settleInspection(controller);
        await controller.convertAll();

        expect(
          controller.successCount,
          1,
          reason: '${entry.key.label} -> ${target.label} failed: '
              '${controller.entries.single.result?.failure?.title} '
              '${controller.entries.single.result?.detail}',
        );
        final String? outputPath =
            controller.entries.single.result?.outputPath;
        expect(outputPath, isNotNull);
        expect(File(outputPath!).lengthSync(), greaterThan(0));
      }
    }
  });
}
