import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/services/output_path_resolver.dart';

void main() {
  const OutputPathResolver resolver = OutputPathResolver();

  // Paths are built with `p.join` so these tests behave the same on Windows,
  // macOS and Linux; `norm` makes the simulated directory listing comparable.
  String norm(String path) => path.replaceAll('\\', '/');

  bool Function(String) existing(Set<String> taken) {
    final Set<String> normalized = taken.map(norm).toSet();
    return (String path) => normalized.contains(norm(path));
  }

  OutputPathResolution resolve({
    String source = 'anime/E01.ass',
    String directory = 'anime',
    SubtitleFormat target = SubtitleFormat.srt,
    OutputConflictPolicy policy = OutputConflictPolicy.autoRename,
    Set<String> taken = const <String>{},
  }) {
    return resolver.resolve(
      sourcePath: p.joinAll(source.split('/')),
      directory: p.joinAll(directory.split('/')),
      targetFormat: target,
      policy: policy,
      exists: existing(taken),
    );
  }

  String takenName(String name) => norm(p.join('anime', name));

  group('target file names', () {
    test('replaces the extension and keeps the directory', () {
      expect(
        OutputPathResolver.targetFileName(
          p.join('anime', 'E01.ass'),
          SubtitleFormat.srt,
        ),
        'E01.srt',
      );
      expect(resolve().path, p.join('anime', 'E01.srt'));
    });

    test('keeps multi-dot base names', () {
      expect(
        resolve(source: 'anime/E01.en.ass').path,
        p.join('anime', 'E01.en.srt'),
      );
    });

    test('accepts a bare extension for every format', () {
      for (final SubtitleFormat format in SubtitleFormat.values) {
        expect(
          OutputPathResolver.targetFileName('E01.ass', format),
          'E01.${format.extension}',
        );
      }
    });
  });

  group('autoRename (default policy)', () {
    test('uses the plain name when nothing is taken', () {
      expect(resolve().path, p.join('anime', 'E01.srt'));
      expect(resolve().renamed, isFalse);
    });

    test('appends a counter when the name exists', () {
      final OutputPathResolution resolution =
          resolve(taken: <String>{takenName('E01.srt')});
      expect(resolution.path, p.join('anime', 'E01 (1).srt'));
      expect(resolution.renamed, isTrue);
    });

    test('finds the next free counter', () {
      final OutputPathResolution resolution = resolve(
        taken: <String>{
          takenName('E01.srt'),
          takenName('E01 (1).srt'),
          takenName('E01 (2).srt'),
        },
      );
      expect(resolution.path, p.join('anime', 'E01 (3).srt'));
    });

    test('never resolves to the source file in a same-format conversion', () {
      final OutputPathResolution resolution = resolve(source: 'anime/E01.srt');
      expect(resolution.path, p.join('anime', 'E01 (1).srt'));
      expect(resolution.renamed, isTrue);
    });

    test('skips instead of looping forever when every name is taken', () {
      final Set<String> all = <String>{takenName('E01.srt')};
      for (int i = 1; i <= OutputPathResolver.maxAutoRenameAttempts; i++) {
        all.add(takenName('E01 ($i).srt'));
      }
      final OutputPathResolution resolution = resolve(taken: all);
      expect(resolution.isSkip, isTrue);
    });
  });

  group('overwrite policy', () {
    test('reuses an existing unrelated file', () {
      final OutputPathResolution resolution = resolve(
        policy: OutputConflictPolicy.overwrite,
        taken: <String>{takenName('E01.srt')},
      );
      expect(resolution.path, p.join('anime', 'E01.srt'));
      expect(resolution.renamed, isFalse);
    });

    test('still refuses to overwrite the source file', () {
      final OutputPathResolution resolution = resolve(
        source: 'anime/E01.srt',
        policy: OutputConflictPolicy.overwrite,
      );
      expect(resolution.path, p.join('anime', 'E01 (1).srt'));
      expect(resolution.renamed, isTrue);
    });
  });

  group('skip policy', () {
    test('skips when the output exists', () {
      final OutputPathResolution resolution = resolve(
        policy: OutputConflictPolicy.skip,
        taken: <String>{takenName('E01.srt')},
      );
      expect(resolution.isSkip, isTrue);
      expect(resolution.path, isNull);
      expect(resolution.reason, isNotNull);
    });

    test('writes when the output is free', () {
      final OutputPathResolution resolution =
          resolve(policy: OutputConflictPolicy.skip);
      expect(resolution.isSkip, isFalse);
      expect(resolution.path, p.join('anime', 'E01.srt'));
    });

    test('skips rather than overwriting the source', () {
      final OutputPathResolution resolution = resolve(
        source: 'anime/E01.srt',
        policy: OutputConflictPolicy.skip,
      );
      expect(resolution.isSkip, isTrue);
    });
  });

  group('ConversionOptions', () {
    test('defaults to source folder, no offset and auto rename', () {
      const ConversionOptions options =
          ConversionOptions(targetFormat: SubtitleFormat.srt);
      expect(options.outputLocation, OutputLocation.sourceDirectory);
      expect(options.timeOffset, Duration.zero);
      expect(options.conflictPolicy, OutputConflictPolicy.autoRename);
      expect(options.writeUtf8Bom, isFalse);
      expect(options.validationError(), isNull);
    });

    test('requires a folder for the custom location', () {
      const ConversionOptions options = ConversionOptions(
        targetFormat: SubtitleFormat.srt,
        outputLocation: OutputLocation.customDirectory,
      );
      expect(options.validationError(), isNotNull);
      expect(
        options.copyWith(outputDirectory: p.join('out')).validationError(),
        isNull,
      );
    });
  });
}
