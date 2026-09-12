import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/sbv/sbv_format.dart';
import 'package:sub_converter/formats/sbv/sbv_parser.dart';
import 'package:sub_converter/formats/sbv/sbv_writer.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';

/// Canonically expected rendering of [basicDocument], with one trailing `\n`.
const String _expectedBasicOutput = '0:00:01.000,0:00:02.500\n'
    'Hello world\n'
    '\n'
    '0:00:03.000,0:00:04.000\n'
    'Second line\n';

const String _bom = '\uFEFF';

SubtitleDocument _basicDocument() => SubtitleDocument(
      cues: <SubtitleCue>[
        SubtitleCue(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 2, milliseconds: 500),
          text: 'Hello world',
        ),
        SubtitleCue(
          start: const Duration(seconds: 3),
          end: const Duration(seconds: 4),
          text: 'Second line',
        ),
      ],
    );

void main() {
  const SbvParser parser = SbvParser();
  const SbvWriter writer = SbvWriter();

  String fixture(String name) =>
      File('test/fixtures/sbv/$name').readAsStringSync();

  group('SbvParser', () {
    test('parses a normal multi-cue fixture', () {
      final SubtitleDocument document = parser.parse(fixture('basic.sbv'));

      expect(document.sourceFormat, SubtitleFormat.sbv);
      expect(document.cues, hasLength(2));
      expect(document.cues.first.start, const Duration(seconds: 1));
      expect(
        document.cues.first.end,
        const Duration(seconds: 2, milliseconds: 500),
      );
      expect(document.cues.first.text, 'Hello world');
      expect(document.cues.last.start, const Duration(seconds: 3));
      expect(document.cues.last.end, const Duration(seconds: 4));
      expect(document.cues.last.text, 'Second line');
    });

    test('drops inline emphasis but keeps the plain text', () {
      final SubtitleDocument document = parser.parse(
        '0:00:01.000,0:00:02.000\n<i>Hello</i> <b>world</b>\n',
      );

      final SubtitleCue cue = document.cues.single;
      expect(cue.text, 'Hello world');
      expect(cue.inlineStyles, isEmpty);
    });

    test('preserves multi-line cue text', () {
      final SubtitleDocument document = parser.parse(
        '0:00:01.000,0:00:03.000\nline one\nline two\n',
      );

      expect(document.cues.single.text, 'line one\nline two');
    });

    test('parses CRLF and a leading BOM identically to LF', () {
      const String lf =
          '0:00:01.000,0:00:02.000\nBody\n';
      final SubtitleDocument fromLf = parser.parse(lf);
      final SubtitleDocument fromCrlf =
          parser.parse(lf.replaceAll('\n', '\r\n'));
      final SubtitleDocument fromBom = parser.parse('$_bom$lf');

      for (final SubtitleDocument other in <SubtitleDocument>[
        fromCrlf,
        fromBom,
      ]) {
        expect(other.cues, hasLength(1));
        expect(other.cues.single.start, fromLf.cues.single.start);
        expect(other.cues.single.end, fromLf.cues.single.end);
        expect(other.cues.single.text, fromLf.cues.single.text);
      }
    });

    test('throws SubtitleSyntaxException on malformed input', () {
      expect(
        () => parser.parse('this is not a subtitle'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => parser.parse('0:00:01.000 -> 0:00:02.000\nBad separator\n'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => parser.parse('0:00:01.000,0:00:02.000 extra\nBody\n'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });

    test('throws on empty and whitespace-only input', () {
      expect(
        () => parser.parse(''),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => parser.parse('   \n\t\n  '),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });
  });

  group('SbvWriter', () {
    test('writes exact SBV output', () {
      expect(writer.write(_basicDocument()), _expectedBasicOutput);
    });

    test('drops inline emphasis and positions', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'Emphasis',
            inlineStyles: <InlineStyleRange>[
              const InlineStyleRange(
                start: 0,
                end: 8,
                styles: <InlineStyle>{InlineStyle.italic},
              ),
            ],
            position: const CuePosition(alignment: 8),
          ),
        ],
      );

      expect(
        writer.write(document),
        '0:00:01.000,0:00:02.000\nEmphasis\n',
      );
    });

    test('skips blank cues and returns empty when none remain', () {
      expect(
        writer.write(
          SubtitleDocument(
            cues: <SubtitleCue>[
              SubtitleCue(
                start: Duration.zero,
                end: const Duration(seconds: 5),
                text: '  \n ',
              ),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('fills a missing end time without mutating the document', () {
      final SubtitleCue cue = SubtitleCue(
        start: const Duration(seconds: 2),
        text: 'No end',
      );
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[cue],
      );

      final String output = writer.write(document);

      expect(cue.end, isNull);
      final SubtitleDocument reparsed = parser.parse(output);
      expect(reparsed.cues.single.end, const Duration(seconds: 7));
    });
  });

  group('Sbv round-trip', () {
    test('preserves times and text', () {
      final SubtitleDocument original = parser.parse(fixture('basic.sbv'));
      final SubtitleDocument reparsed = parser.parse(writer.write(original));

      expect(reparsed.cues, hasLength(original.cues.length));
      for (int i = 0; i < original.cues.length; i++) {
        expect(reparsed.cues[i].start, original.cues[i].start);
        expect(reparsed.cues[i].end, original.cues[i].end);
        expect(reparsed.cues[i].text, original.cues[i].text);
      }
    });

    test('keeps Chinese and Japanese text intact', () {
      final SubtitleDocument original = parser.parse(fixture('cjk.sbv'));
      final SubtitleDocument reparsed = parser.parse(writer.write(original));

      expect(reparsed.cues, hasLength(2));
      expect(reparsed.cues.first.text, '你好，世界');
      expect(reparsed.cues.last.text, 'こんにちは世界');
    });
  });

  test('sbvFormat exposes the expected descriptor', () {
    expect(sbvFormat.format, SubtitleFormat.sbv);
    expect(sbvFormat.extension, 'sbv');
    expect(sbvFormat.supportsInlineStyles, isFalse);
    expect(sbvFormat.requiresEndTime, isTrue);
    expect(sbvFormat.signatures.single.id, 'sbv.timing-comma');
    expect(sbvFormat.signatures.single.weight, 60);
  });
}
