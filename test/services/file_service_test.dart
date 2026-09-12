import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/services/file_service.dart';

/// Sample SRT with two cues in Chinese and Japanese as well as ASCII.
const String sampleSrt = '1\n'
    '00:00:01,000 --> 00:00:03,000\n'
    'Hello 你好 こんにちは\n'
    '\n'
    '2\n'
    '00:00:04,500 --> 00:00:06,000\n'
    'Second <i>line</i>\n';

void main() {
  late Directory workspace;
  late FileService service;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('sub_converter_test');
    service = FileService();
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  File writeSource(String name, {String content = sampleSrt, List<int>? bytes}) {
    final File file = File(p.join(workspace.path, name));
    file.writeAsBytesSync(bytes ?? utf8.encode(content));
    return file;
  }

  String read(File file) => utf8.decode(file.readAsBytesSync());

  ConversionOptions options({
    SubtitleFormat target = SubtitleFormat.vtt,
    OutputLocation location = OutputLocation.sourceDirectory,
    String? directory,
    OutputConflictPolicy policy = OutputConflictPolicy.autoRename,
    Duration timeOffset = Duration.zero,
    bool writeUtf8Bom = false,
  }) {
    return ConversionOptions(
      targetFormat: target,
      outputLocation: location,
      outputDirectory: directory,
      conflictPolicy: policy,
      timeOffset: timeOffset,
      writeUtf8Bom: writeUtf8Bom,
    );
  }

  group('inspect', () {
    test('detects the format and the encoding without converting', () async {
      final File source = writeSource('E01.srt');
      final FileInspection inspection = await service.inspect(source.path);
      expect(inspection.format, SubtitleFormat.srt);
      expect(inspection.encodingName, 'UTF-8');
      expect(inspection.bytes, greaterThan(0));
      expect(
        File(p.join(workspace.path, 'E01.vtt')).existsSync(),
        isFalse,
      );
    });

    test('reads a GBK encoded file without mojibake', () async {
      // 00:00:01,000 --> 00:00:02,000 with Chinese text, encoded as GBK.
      final File source = writeSource(
        'gbk.srt',
        bytes: <int>[
          ...utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n'),
          0xD6, 0xD0, 0xCE, 0xC4, // 中文
          ...utf8.encode('\n'),
        ],
      );
      final FileInspection inspection = await service.inspect(source.path);
      expect(inspection.format, SubtitleFormat.srt);
      expect(inspection.encodingName, startsWith('GBK'));

      final ConversionResult result =
          await service.convertFile(source.path, options(target: SubtitleFormat.vtt));
      expect(result.isSuccess, isTrue);
      expect(read(File(result.outputPath!)), contains('中文'));
    });

    test('reports a missing file instead of throwing', () async {
      expect(
        () => service.inspect(p.join(workspace.path, 'nope.srt')),
        throwsA(
          isA<SubtitleConversionException>().having(
            (SubtitleConversionException error) => error.failure,
            'failure',
            ConversionFailure.readFailed,
          ),
        ),
      );
    });
  });

  group('convertFile', () {
    test('writes next to the source by default and never touches it', () async {
      final File source = writeSource('E01.srt');
      final ConversionResult result = await service.convertFile(
        source.path,
        options(),
      );

      expect(result.isSuccess, isTrue);
      expect(result.sourceFormat, SubtitleFormat.srt);
      expect(result.targetFormat, SubtitleFormat.vtt);
      expect(result.cueCount, 2);
      expect(result.outputPath, p.join(workspace.path, 'E01.vtt'));

      final String converted = read(File(result.outputPath!));
      expect(converted, startsWith('WEBVTT'));
      expect(converted, contains('Hello 你好 こんにちは'));
      expect(converted, contains('<i>line</i>'));

      // The source is byte-for-byte unchanged.
      expect(read(source), sampleSrt);
    });

    test('auto-renames instead of overwriting an existing output', () async {
      final File source = writeSource('E01.srt');
      final File existing = File(p.join(workspace.path, 'E01.vtt'));
      existing.writeAsStringSync('do not touch');

      final ConversionResult result =
          await service.convertFile(source.path, options());

      expect(result.outputPath, p.join(workspace.path, 'E01 (1).vtt'));
      expect(result.warnings.join(' '), contains('already existed'));
      expect(existing.readAsStringSync(), 'do not touch');
    });

    test('reports the skip policy as skipped, not failed', () async {
      final File source = writeSource('E01.srt');
      File(p.join(workspace.path, 'E01.vtt')).writeAsStringSync('keep');

      final ConversionResult result = await service.convertFile(
        source.path,
        options(policy: OutputConflictPolicy.skip),
      );
      expect(result.isSkipped, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.detail, isNotNull);
    });

    test('overwrites only when asked to', () async {
      final File source = writeSource('E01.srt');
      final File existing = File(p.join(workspace.path, 'E01.vtt'));
      existing.writeAsStringSync('replace me');

      final ConversionResult result = await service.convertFile(
        source.path,
        options(policy: OutputConflictPolicy.overwrite),
      );
      expect(result.isSuccess, isTrue);
      expect(existing.readAsStringSync(), startsWith('WEBVTT'));
    });

    test('a same-format conversion never overwrites its source', () async {
      final File source = writeSource('E01.srt');
      final ConversionResult result = await service.convertFile(
        source.path,
        options(target: SubtitleFormat.srt),
      );
      expect(result.outputPath, p.join(workspace.path, 'E01 (1).srt'));
      expect(read(source), sampleSrt);
    });

    test('writes into a custom folder', () async {
      final File source = writeSource('E01.srt');
      final Directory out = Directory(p.join(workspace.path, 'out'))..createSync();

      final ConversionResult result = await service.convertFile(
        source.path,
        options(
          location: OutputLocation.customDirectory,
          directory: out.path,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.outputPath, p.join(out.path, 'E01.vtt'));
      expect(File(result.outputPath!).existsSync(), isTrue);
    });

    test('fails with targetPathUnavailable when the folder is gone', () async {
      final File source = writeSource('E01.srt');
      final ConversionResult result = await service.convertFile(
        source.path,
        options(
          location: OutputLocation.customDirectory,
          directory: p.join(workspace.path, 'missing'),
        ),
      );
      expect(result.isFailure, isTrue);
      expect(result.failure, ConversionFailure.targetPathUnavailable);
      expect(result.detail, isNot(contains('#0')));
    });

    test('reports an unidentifiable file as a failure, not a crash', () async {
      final File source = writeSource('notes.txt', content: 'just some notes\n');
      final ConversionResult result =
          await service.convertFile(source.path, options());
      expect(result.isFailure, isTrue);
      expect(result.failure, ConversionFailure.unsupportedFormat);
    });

    test('reports unparseable subtitle content as invalid syntax', () async {
      final File source = writeSource('broken.srt', content: 'not a subtitle\n');
      final ConversionResult result =
          await service.convertFile(source.path, options());
      expect(result.isFailure, isTrue);
      // The extension identifies it as SRT, but the content does not parse.
      expect(result.failure, ConversionFailure.invalidSubtitleSyntax);
    });

    test('writes an optional UTF-8 BOM', () async {
      final File source = writeSource('E01.srt');
      final ConversionResult result = await service.convertFile(
        source.path,
        options(writeUtf8Bom: true),
      );
      final List<int> bytes = File(result.outputPath!).readAsBytesSync();
      expect(bytes.take(3).toList(), <int>[0xEF, 0xBB, 0xBF]);
    });

    test('applies the time offset', () async {
      final File source = writeSource('E01.srt');
      final ConversionResult result = await service.convertFile(
        source.path,
        options(target: SubtitleFormat.srt, timeOffset: const Duration(seconds: 1)),
      );
      expect(read(File(result.outputPath!)), contains('00:00:02,000'));
    });
  });

  group('convertAll', () {
    test('one bad file does not stop the batch and reports progress', () async {
      final File good1 = writeSource('a.srt');
      final File bad = writeSource('b.txt', content: 'not subtitles\n');
      final File good2 = writeSource('c.srt');

      final List<int> progress = <int>[];
      final List<ConversionResult> results = await service.convertAll(
        <String>[good1.path, bad.path, good2.path],
        options(),
        onProgress: (int completed, int total, ConversionResult result) {
          progress.add(completed);
        },
      );

      expect(results.length, 3);
      expect(progress, <int>[1, 2, 3]);
      expect(results.where((ConversionResult r) => r.isSuccess).length, 2);
      expect(results.where((ConversionResult r) => r.isFailure).length, 1);
      expect(
        File(p.join(workspace.path, 'a.vtt')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(workspace.path, 'c.vtt')).existsSync(),
        isTrue,
      );
    });

    test('handles an empty batch', () async {
      final List<ConversionResult> results =
          await service.convertAll(<String>[], options());
      expect(results, isEmpty);
    });

    test('says so when the output path is a file, not a folder', () async {
      final File source = writeSource('E01.srt');
      final File notAFolder = File(p.join(workspace.path, 'not-a-folder'))
        ..writeAsStringSync('I am a file');

      final ConversionResult result = await service.convertFile(
        source.path,
        options(
          location: OutputLocation.customDirectory,
          directory: notAFolder.path,
        ),
      );
      expect(result.isFailure, isTrue);
      expect(result.failure, ConversionFailure.targetPathUnavailable);
      expect(result.detail, contains('not a folder'));
    });

    test('an inverted cue still converts, with a warning', () async {
      final File source = writeSource(
        'backwards.srt',
        content: '1\n00:00:05,000 --> 00:00:02,000\nbackwards\n',
      );
      final ConversionResult result =
          await service.convertFile(source.path, options(target: SubtitleFormat.srt));
      expect(result.isSuccess, isTrue);
      expect(result.isLossy, isTrue);
      expect(result.warnings.join(' '), contains('ends before it starts'));
    });

    test('converts a batch into a custom folder', () async {
      final Directory out = Directory(p.join(workspace.path, 'out'))..createSync();
      final List<String> sources = <String>[
        writeSource('a.srt').path,
        writeSource('b.srt').path,
        writeSource('c.srt').path,
      ];
      final List<ConversionResult> results = await service.convertAll(
        sources,
        options(
          target: SubtitleFormat.ass,
          location: OutputLocation.customDirectory,
          directory: out.path,
        ),
      );
      expect(results.every((ConversionResult r) => r.isSuccess), isTrue);
      expect(out.listSync().length, 3);
    });
  });
}
