import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/srt/srt_format.dart';
import 'package:sub_converter/formats/srt/srt_parser.dart';
import 'package:sub_converter/formats/srt/srt_writer.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';

/// Canonically expected rendering of [basicDocument], with one trailing `\n`.
const String _expectedBasicOutput = '1\n'
    '00:00:01,000 --> 00:00:02,500\n'
    'Hello world\n'
    '\n'
    '2\n'
    '00:00:03,000 --> 00:00:04,000\n'
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
  const SrtParser parser = SrtParser();
  const SrtWriter writer = SrtWriter();

  String fixture(String name) =>
      File('test/fixtures/srt/$name').readAsStringSync();

  group('SrtParser', () {
    test('parses a normal multi-cue fixture', () {
      final SubtitleDocument document = parser.parse(fixture('basic.srt'));

      expect(document.sourceFormat, SubtitleFormat.srt);
      expect(document.cues, hasLength(2));
      expect(document.cues.first.start, const Duration(seconds: 1));
      expect(
        document.cues.first.end,
        const Duration(seconds: 2, milliseconds: 500),
      );
      expect(document.cues.first.text, 'Hello world');
      expect(document.cues.first.metadata['srt.index'], 1);
      expect(document.cues.last.start, const Duration(seconds: 3));
      expect(document.cues.last.end, const Duration(seconds: 4));
      expect(document.cues.last.text, 'Second line');
      expect(document.cues.last.metadata['srt.index'], 2);
    });

    test('turns <i>/<b> into inline styles and strips {\\an8}', () {
      final SubtitleDocument document =
          parser.parse(fixture('with_ass_tags.srt'));

      final SubtitleCue cue = document.cues.single;
      expect(cue.text, 'Italic and bold');
      expect(cue.inlineStyles, <InlineStyleRange>[
        const InlineStyleRange(
          start: 0,
          end: 6,
          styles: <InlineStyle>{InlineStyle.italic},
        ),
        const InlineStyleRange(
          start: 11,
          end: 15,
          styles: <InlineStyle>{InlineStyle.bold},
        ),
      ]);
    });

    test('tolerates a missing index line', () {
      final SubtitleDocument document = parser.parse(
        '00:00:01,000 --> 00:00:02,000\nNo index\n',
      );

      expect(document.cues, hasLength(1));
      expect(document.cues.single.text, 'No index');
      expect(document.cues.single.metadata, isEmpty);
    });

    test('ignores trailing positioning data after the end timestamp', () {
      final SubtitleDocument document = parser.parse(
        '1\n'
        '00:00:01,000 --> 00:00:02,000 X1:0 X2:100 Y1:0 Y2:20\n'
        'Positioned\n',
      );

      expect(document.cues.single.end, const Duration(seconds: 2));
      expect(document.cues.single.text, 'Positioned');
    });

    test('preserves multi-line cue text', () {
      final SubtitleDocument document = parser.parse(
        '1\n00:00:01,000 --> 00:00:03,000\nline one\nline two\n',
      );

      expect(document.cues.single.text, 'line one\nline two');
    });

    test('parses CRLF and a leading BOM identically to LF', () {
      final String lf = '1\n00:00:01,000 --> 00:00:02,000\nBody\n';
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
        () => parser.parse('1\n00:00:01,000 -> 00:00:02,000\nBad arrow\n'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => parser.parse('1\nnot a timing line\nBody\n'),
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

  group('SrtWriter', () {
    test('writes exact SRT output', () {
      expect(writer.write(_basicDocument()), _expectedBasicOutput);
    });

    test('renders inline styles as markup', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'Italic and bold',
            inlineStyles: <InlineStyleRange>[
              const InlineStyleRange(
                start: 0,
                end: 6,
                styles: <InlineStyle>{InlineStyle.italic},
              ),
              const InlineStyleRange(
                start: 11,
                end: 15,
                styles: <InlineStyle>{InlineStyle.bold},
              ),
            ],
          ),
        ],
      );

      expect(
        writer.write(document),
        '1\n00:00:01,000 --> 00:00:02,000\n'
        '<i>Italic</i> and <b>bold</b>\n',
      );
    });

    test('renumbers sequentially and skips blank cues', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'First',
          ),
          SubtitleCue(
            start: const Duration(seconds: 3),
            end: const Duration(seconds: 4),
            text: '   ',
          ),
          SubtitleCue(
            start: const Duration(seconds: 5),
            end: const Duration(seconds: 6),
            text: 'Third',
          ),
        ],
      );

      expect(
        writer.write(document),
        '1\n00:00:01,000 --> 00:00:02,000\nFirst\n'
        '\n'
        '2\n00:00:05,000 --> 00:00:06,000\nThird\n',
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
      expect(
        reparsed.cues.single.end,
        const Duration(seconds: 7),
      );
    });

    test('returns an empty string when no cue has visible text', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: Duration.zero,
            end: const Duration(seconds: 5),
            text: '  \n ',
          ),
        ],
      );

      expect(writer.write(document), isEmpty);
    });
  });

  group('Srt round-trip', () {
    test('preserves times, text and inline styles', () {
      final SubtitleDocument original = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'Italic and bold',
            inlineStyles: <InlineStyleRange>[
              const InlineStyleRange(
                start: 0,
                end: 6,
                styles: <InlineStyle>{InlineStyle.italic},
              ),
              const InlineStyleRange(
                start: 11,
                end: 15,
                styles: <InlineStyle>{InlineStyle.bold},
              ),
            ],
          ),
        ],
      );

      final SubtitleDocument reparsed = parser.parse(writer.write(original));
      final SubtitleCue before = original.cues.single;
      final SubtitleCue after = reparsed.cues.single;

      expect(after.start, before.start);
      expect(after.end, before.end);
      expect(after.text, before.text);
      expect(after.inlineStyles, before.inlineStyles);
    });

    test('keeps Chinese and Japanese text intact', () {
      final SubtitleDocument original = parser.parse(fixture('cjk.srt'));
      final SubtitleDocument reparsed = parser.parse(writer.write(original));

      expect(reparsed.cues, hasLength(original.cues.length));
      for (int i = 0; i < original.cues.length; i++) {
        expect(reparsed.cues[i].start, original.cues[i].start);
        expect(reparsed.cues[i].end, original.cues[i].end);
        expect(reparsed.cues[i].text, original.cues[i].text);
      }
      expect(reparsed.cues.first.text, '你好，世界');
      expect(reparsed.cues.last.text, 'こんにちは世界');
    });
  });

  test('srtFormat exposes the expected descriptor', () {
    expect(srtFormat.format, SubtitleFormat.srt);
    expect(srtFormat.extension, 'srt');
    expect(srtFormat.extensionAliases, contains('subrip'));
    expect(srtFormat.supportsInlineStyles, isTrue);
    expect(srtFormat.requiresEndTime, isTrue);
    expect(srtFormat.signatures.single.id, 'srt.timing-arrow');
    expect(srtFormat.signatures.single.weight, 60);
  });
}
