import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/built_in_formats.dart';
import 'package:sub_converter/formats/format_registry.dart';
import 'package:sub_converter/formats/srt/srt_format.dart';
import 'package:sub_converter/models/format_descriptor.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/services/format_detector.dart';
import 'package:sub_converter/services/subtitle_converter.dart';

/// Source fixture used for each format in the matrix test.
const Map<SubtitleFormat, String> fixturePaths = <SubtitleFormat, String>{
  SubtitleFormat.srt: 'test/fixtures/srt/basic.srt',
  SubtitleFormat.vtt: 'test/fixtures/vtt/basic.vtt',
  SubtitleFormat.lrc: 'test/fixtures/lrc/basic.lrc',
  SubtitleFormat.ass: 'test/fixtures/ass/basic.ass',
  SubtitleFormat.ssa: 'test/fixtures/ssa/basic.ssa',
  SubtitleFormat.sbv: 'test/fixtures/sbv/basic.sbv',
};

/// Targets that store centiseconds cannot keep millisecond precision.
const Set<SubtitleFormat> centisecondTargets = <SubtitleFormat>{
  SubtitleFormat.lrc,
  SubtitleFormat.ass,
  SubtitleFormat.ssa,
};

void main() {
  final SubtitleConverter converter = SubtitleConverter(builtInFormatRegistry);
  final FormatDetector detector = FormatDetector(builtInFormatRegistry);

  group('registry', () {
    test('registers all six v0.1 formats', () {
      expect(
        builtInFormatRegistry.formats,
        <SubtitleFormat>[
          SubtitleFormat.srt,
          SubtitleFormat.vtt,
          SubtitleFormat.lrc,
          SubtitleFormat.ass,
          SubtitleFormat.ssa,
          SubtitleFormat.sbv,
        ],
      );
    });

    test('every format has a parser, a writer and signatures', () {
      for (final SubtitleFormat format in SubtitleFormat.values) {
        expect(builtInFormatRegistry.canRead(format), isTrue, reason: format.name);
        expect(builtInFormatRegistry.canWrite(format), isTrue, reason: format.name);
        expect(
          builtInFormatRegistry.descriptorFor(format)!.signatures,
          isNotEmpty,
          reason: format.name,
        );
      }
    });
  });

  group('format detection from content', () {
    test('identifies every fixture, even when renamed', () {
      for (final MapEntry<SubtitleFormat, String> entry
          in fixturePaths.entries) {
        final String content = File(entry.value).readAsStringSync();
        final FormatDetection detection = detector.detect(
          content,
          fileName: 'renamed.dat',
        );
        expect(
          detection.format,
          entry.key,
          reason: '${entry.value} was detected as '
              '${detection.format?.label} (score ${detection.score}, '
              'evidence ${detection.evidence})',
        );
        expect(detection.isContentBased, isTrue, reason: entry.value);
      }
    });

    test('uses the extension when the content is inconclusive', () {
      final FormatDetection detection =
          detector.detect('hello world', fileName: 'notes.srt');
      expect(detection.format, SubtitleFormat.srt);
      expect(detection.extensionMatched, isTrue);
      expect(detection.isContentBased, isFalse);
    });

    test('content beats a misleading extension', () {
      final String srt = File(fixturePaths[SubtitleFormat.srt]!).readAsStringSync();
      final FormatDetection detection =
          detector.detect(srt, fileName: 'movie.ass');
      expect(detection.format, SubtitleFormat.srt);
      expect(detection.extensionMatched, isFalse);
    });

    test('returns nothing for unrelated content', () {
      final FormatDetection detection = detector.detect(
        'const x = 1;\nvoid main() {}\n',
        fileName: 'main.dart',
      );
      expect(detection.format, isNull);
      expect(detection.isDetected, isFalse);
    });

    test('distinguishes ASS from SSA', () {
      final String ass = File(fixturePaths[SubtitleFormat.ass]!).readAsStringSync();
      final String ssa = File(fixturePaths[SubtitleFormat.ssa]!).readAsStringSync();
      expect(
        detector.detect(ass, fileName: 'a.ass').format,
        SubtitleFormat.ass,
      );
      expect(
        detector.detect(ssa, fileName: 'a.ssa').format,
        SubtitleFormat.ssa,
      );
    });

    test('reports the runner-up when content and extension disagree', () {
      // Content says SRT; the name says VTT. Content wins, and VTT is
      // reported as the runner-up so the UI could flag the mismatch.
      final FormatDetection detection = detector.detect(
        '1\n00:00:01,000 --> 00:00:02,000\nhi\n',
        fileName: 'x.vtt',
      );
      expect(detection.format, SubtitleFormat.srt);
      expect(detection.extensionMatched, isFalse);
      expect(detection.runnerUp, SubtitleFormat.vtt);
    });

    test('a clean WebVTT file has no runner-up', () {
      final FormatDetection detection = detector.detect(
        'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nhi\n',
        fileName: 'x.vtt',
      );
      expect(detection.format, SubtitleFormat.vtt);
      expect(detection.runnerUp, isNull);
      expect(detection.isAmbiguous, isFalse);
    });
  });

  group('6x6 conversion matrix through the unified model', () {
    for (final MapEntry<SubtitleFormat, String> source in fixturePaths.entries) {
      for (final SubtitleFormat target in SubtitleFormat.values) {
        test('${source.key.label} -> ${target.label}', () {
          final String sourceText = File(source.value).readAsStringSync();
          final ConversionOutput output = converter.convert(
            sourceText,
            sourceFormat: source.key,
            targetFormat: target,
          );

          expect(output.content.trim(), isNotEmpty);
          expect(output.cueCount, greaterThan(0));

          // Re-parse the produced file with the target format's own parser:
          // every writer must emit something its parser understands.
          final SubtitleDocument reparsed = builtInFormatRegistry
              .parserFor(target)
              .parse(output.content);

          expect(
            reparsed.cues.length,
            output.cueCount,
            reason: 're-parsing the ${target.label} output changed the cue '
                'count',
          );

          final List<SubtitleCue> originalCues = builtInFormatRegistry
              .parserFor(source.key)
              .parse(sourceText)
              .cues;
          final int tolerance = centisecondTargets.contains(target) ? 10 : 1;

          for (int i = 0; i < originalCues.length; i++) {
            final Duration originalStart = originalCues[i].start;
            final Duration reparsedStart = reparsed.cues[i].start;
            expect(
              (reparsedStart - originalStart).inMilliseconds.abs(),
              lessThanOrEqualTo(tolerance),
              reason: 'cue $i start drifted',
            );
          }
        });
      }
    }
  });

  group('SubtitleConverter', () {
    test('keeps text and start times through a detour', () {
      const String srt = '1\n'
          '00:00:01,000 --> 00:00:03,000\n'
          'Hello world\n'
          '\n'
          '2\n'
          '00:00:04,500 --> 00:00:06,000\n'
          'Second line\n';
      for (final SubtitleFormat target in SubtitleFormat.values) {
        final ConversionOutput there = converter.convert(
          srt,
          sourceFormat: SubtitleFormat.srt,
          targetFormat: target,
        );
        final ConversionOutput back = converter.convert(
          there.content,
          sourceFormat: target,
          targetFormat: SubtitleFormat.srt,
        );
        final SubtitleDocument reparsed = builtInFormatRegistry
            .parserFor(SubtitleFormat.srt)
            .parse(back.content);
        expect(reparsed.cues.length, 2, reason: 'via ${target.label}');
        expect(reparsed.cues[0].text, 'Hello world', reason: target.label);
        expect(reparsed.cues[1].text, 'Second line', reason: target.label);
        expect(reparsed.cues[0].start, const Duration(seconds: 1));
      }
    });

    test('applies a positive time offset to every cue', () {
      const String srt = '1\n00:00:10,000 --> 00:00:12,000\nhi\n';
      final ConversionOutput output = converter.convert(
        srt,
        sourceFormat: SubtitleFormat.srt,
        targetFormat: SubtitleFormat.srt,
        timeOffset: const Duration(milliseconds: 500),
      );
      expect(output.content, contains('00:00:10,500 --> 00:00:12,500'));
    });

    test('clamps a negative offset at zero', () {
      const String srt = '1\n00:00:00,200 --> 00:00:02,000\nhi\n';
      final ConversionOutput output = converter.convert(
        srt,
        sourceFormat: SubtitleFormat.srt,
        targetFormat: SubtitleFormat.srt,
        timeOffset: const Duration(seconds: -1),
      );
      expect(output.content, contains('00:00:00,000 --> 00:00:01,000'));
    });

    test('does not mutate the input text', () {
      const String srt = '1\n00:00:10,000 --> 00:00:12,000\nhi\n';
      converter.convert(
        srt,
        sourceFormat: SubtitleFormat.srt,
        targetFormat: SubtitleFormat.srt,
        timeOffset: const Duration(seconds: 5),
      );
      expect(srt, contains('00:00:10,000'));
    });

    test('reports stale ASS tags as a lossy conversion, not a failure', () {
      const String ass = '[Script Info]\n'
          'ScriptType: v4.00+\n'
          '\n'
          '[V4+ Styles]\n'
          'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
          'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
          'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
          'Alignment, MarginL, MarginR, MarginV, Encoding\n'
          'Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,'
          '&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1\n'
          '\n'
          '[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
          'Effect, Text\n'
          'Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,'
          '{\\an8}{\\bord2}Hello\n';
      final ConversionOutput output = converter.convert(
        ass,
        sourceFormat: SubtitleFormat.ass,
        targetFormat: SubtitleFormat.srt,
      );
      expect(output.content, contains('Hello'));
      expect(output.content, isNot(contains('an8')));
      expect(output.content, isNot(contains('bord2')));
      expect(output.isLossy, isTrue);
    });

    test('throws for empty content and for unparseable content', () {
      expect(
        () => converter.convert(
          '   \n\n',
          sourceFormat: SubtitleFormat.srt,
          targetFormat: SubtitleFormat.vtt,
        ),
        throwsA(isA<SubtitleSyntaxException>()),
      );

      expect(
        () => converter.convert(
          '[ti:only metadata]\n[ar:nobody]\n',
          sourceFormat: SubtitleFormat.lrc,
          targetFormat: SubtitleFormat.srt,
        ),
        throwsA(
          isA<SubtitleConversionException>().having(
            (SubtitleConversionException error) => error.failure,
            'failure',
            ConversionFailure.emptyDocument,
          ),
        ),
      );
    });

    test('throws when a format is not registered', () {
      final SubtitleConverter limited = SubtitleConverter(
        FormatRegistry(<FormatDescriptor>[srtFormat]),
      );
      expect(
        () => limited.convert(
          'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nhi\n',
          sourceFormat: SubtitleFormat.vtt,
          targetFormat: SubtitleFormat.srt,
        ),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });
  });
}
