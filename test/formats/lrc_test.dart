import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/lrc/lrc_format.dart';
import 'package:sub_converter/formats/lrc/lrc_parser.dart';
import 'package:sub_converter/formats/lrc/lrc_writer.dart';
import 'package:sub_converter/models/format_signature.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';

void main() {
  const LrcParser parser = LrcParser();
  const LrcWriter writer = LrcWriter();

  String fixture(String name) =>
      File('test/fixtures/lrc/$name').readAsStringSync();

  group('LrcParser', () {
    test('parses a normal multi-cue file and infers end times', () {
      final SubtitleDocument document = parser.parse(fixture('basic.lrc'));

      expect(document.cues, hasLength(3));
      expect(document.cues[0].start, const Duration(seconds: 10));
      expect(document.cues[0].end, const Duration(milliseconds: 20500));
      expect(document.cues[1].start, const Duration(milliseconds: 20500));
      expect(document.cues[1].end, const Duration(seconds: 30));
      expect(document.cues[2].start, const Duration(seconds: 30));
      expect(document.cues[2].end, const Duration(seconds: 35));
      expect(document.cues.map((SubtitleCue cue) => cue.text), <String>[
        'First line',
        'Second line',
        'Third line',
      ]);
      expect(document.sourceFormat, SubtitleFormat.lrc);
    });

    test('stores metadata tags, sets the title and ignores offset', () {
      final SubtitleDocument document =
          parser.parse(fixture('metadata.lrc'));

      expect(document.metadata.title, 'My Song');
      expect(document.metadata.field('ti'), 'My Song');
      expect(document.metadata.field('ar'), 'Some Artist');
      expect(document.metadata.field('al'), 'An Album');
      expect(document.metadata.field('by'), 'uploader');
      expect(document.metadata.field('offset'), '+500');
      expect(document.metadata.field('length'), '03:20');
      expect(document.cues, hasLength(2));
      // The offset is data only; it must not shift timestamps.
      expect(document.cues[0].start, const Duration(seconds: 5));
      expect(document.cues[1].start, const Duration(milliseconds: 12300));
    });

    test('parses CJK lyrics', () {
      final SubtitleDocument document = parser.parse(fixture('cjk.lrc'));
      expect(document.cues.map((SubtitleCue cue) => cue.text), <String>[
        '你好世界',
        'こんにちは',
      ]);
    });

    test('creates one cue per timestamp tag on a shared line', () {
      final SubtitleDocument document =
          parser.parse('[00:10.00][00:20.00]same text');

      expect(document.cues, hasLength(2));
      expect(document.cues[0].text, 'same text');
      expect(document.cues[1].text, 'same text');
      expect(document.cues[0].start, const Duration(seconds: 10));
      expect(document.cues[1].start, const Duration(seconds: 20));
      expect(document.cues[0].end, const Duration(seconds: 20));
    });

    test('accepts timestamps without fractions and with hours', () {
      final SubtitleDocument noFraction = parser.parse('[00:10]no fraction');
      expect(noFraction.cues.single.start, const Duration(seconds: 10));

      final SubtitleDocument withHours =
          parser.parse('[01:02:03.50]long');
      expect(
        withHours.cues.single.start,
        const Duration(
          hours: 1,
          minutes: 2,
          seconds: 3,
          milliseconds: 500,
        ),
      );
    });

    test('strips enhanced word timestamps and ASS override blocks', () {
      final SubtitleDocument document = parser.parse(
        '[00:10.00]{\\an8}<00:10.00>Hello <00:11.00>world',
      );
      expect(document.cues.single.text, 'Hello world');
    });

    test('sorts out-of-order cues and gives the last cue start + 5s', () {
      final SubtitleDocument document =
          parser.parse('[00:30.00]late\n[00:10.00]early');

      expect(document.cues, hasLength(2));
      expect(document.cues[0].text, 'early');
      expect(document.cues[0].end, const Duration(seconds: 30));
      expect(document.cues[1].text, 'late');
      expect(document.cues[1].end, const Duration(seconds: 35));
    });

    test('tolerates a BOM and CRLF like LF', () {
      const String lf = '[00:10.00]line one\n[00:20.00]line two\n';
      const String crlf =
          '\uFEFF[00:10.00]line one\r\n[00:20.00]line two\r\n';

      final SubtitleDocument a = parser.parse(lf);
      final SubtitleDocument b = parser.parse(crlf);

      expect(
        b.cues.map((SubtitleCue cue) => cue.start),
        a.cues.map((SubtitleCue cue) => cue.start),
      );
      expect(
        b.cues.map((SubtitleCue cue) => cue.text),
        a.cues.map((SubtitleCue cue) => cue.text),
      );
    });

    test('throws when nothing recognisable is present', () {
      expect(
        () => parser.parse('just some prose\nwith no timestamps'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });

    test('throws on empty or whitespace-only input', () {
      expect(
        () => parser.parse(''),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => parser.parse('  \n\t\n'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });

    test('ignores lines without a leading timestamp tag', () {
      final SubtitleDocument document =
          parser.parse('random line\n[00:10.00]kept\nanother random line');
      expect(document.cues, hasLength(1));
      expect(document.cues.single.text, 'kept');
    });
  });

  group('LrcWriter', () {
    test('writes the exact expected output', () {
      final SubtitleDocument document = SubtitleDocument(
        metadata: SubtitleMetadata(
          title: 'Song',
          fields: <String, String>{'ti': 'Song', 'ar': 'Artist'},
        ),
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 10), text: 'First'),
          SubtitleCue(start: const Duration(seconds: 20), text: 'Second'),
        ],
      );

      expect(
        writer.write(document),
        '[ti:Song]\n'
        '[ar:Artist]\n'
        '\n'
        '[00:10.00]First\n'
        '[00:20.00]Second\n',
      );
    });

    test('orders known metadata tags before the rest', () {
      final SubtitleDocument document = SubtitleDocument(
        metadata: SubtitleMetadata(
          fields: <String, String>{
            'offset': '+500',
            'ti': 'Song',
            'ar': 'Artist',
            'note': 'extra',
          },
        ),
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 10), text: 'First'),
        ],
      );

      expect(
        writer.write(document),
        '[ti:Song]\n'
        '[ar:Artist]\n'
        '[offset:+500]\n'
        '[note:extra]\n'
        '\n'
        '[00:10.00]First\n',
      );
    });

    test('sorts cues by start time', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 20), text: 'Second'),
          SubtitleCue(start: const Duration(seconds: 10), text: 'First'),
        ],
      );

      expect(
        writer.write(document),
        '[00:10.00]First\n[00:20.00]Second\n',
      );
    });

    test('joins multi-line cue text onto one line', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: Duration.zero, text: 'first line\nsecond line'),
        ],
      );

      expect(writer.write(document), '[00:00.00]first line second line\n');
    });

    test('skips cues with blank text', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: Duration.zero, text: '   '),
          SubtitleCue(start: const Duration(seconds: 1), text: 'Kept'),
        ],
      );

      expect(writer.write(document), '[00:01.00]Kept\n');
    });

    test('does not mutate the input document', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 10), text: 'Hi'),
        ],
      );
      writer.write(document);
      expect(document.cues.single.end, isNull);
    });

    test('writes no blank line when there is no metadata', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: Duration.zero, text: 'only'),
        ],
      );
      expect(writer.write(document), '[00:00.00]only\n');
    });
  });

  group('LrcRoundTrip', () {
    test('preserves times and text', () {
      final SubtitleDocument original = parser.parse(fixture('basic.lrc'));
      final SubtitleDocument roundTripped =
          parser.parse(writer.write(original));

      expect(
        roundTripped.cues.map((SubtitleCue cue) => cue.start),
        original.cues.map((SubtitleCue cue) => cue.start),
      );
      expect(
        roundTripped.cues.map((SubtitleCue cue) => cue.text),
        original.cues.map((SubtitleCue cue) => cue.text),
      );
    });

    test('preserves metadata and stops it from becoming cues', () {
      final SubtitleDocument original =
          parser.parse(fixture('metadata.lrc'));
      final SubtitleDocument roundTripped =
          parser.parse(writer.write(original));

      expect(roundTripped.cues.length, original.cues.length);
      expect(roundTripped.metadata.fields, original.metadata.fields);
      expect(roundTripped.metadata.title, original.metadata.title);
    });

    test('a cue with only a start time round-trips through the model', () {
      final SubtitleDocument original = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 10), text: 'Hi'),
        ],
      );

      final SubtitleDocument roundTripped =
          parser.parse(writer.write(original));

      expect(original.cues.single.end, isNull);
      expect(roundTripped.cues.single.start, const Duration(seconds: 10));
      expect(roundTripped.cues.single.text, 'Hi');
      expect(roundTripped.cues.single.end, const Duration(seconds: 15));
    });

    test('round-trips CJK text', () {
      final SubtitleDocument original = parser.parse(fixture('cjk.lrc'));
      final SubtitleDocument roundTripped =
          parser.parse(writer.write(original));
      expect(roundTripped.cues.map((SubtitleCue cue) => cue.text).toList(),
          <String>['你好世界', 'こんにちは']);
    });
  });

  group('lrcFormat descriptor', () {
    test('exposes format and capabilities', () {
      expect(lrcFormat.format, SubtitleFormat.lrc);
      expect(lrcFormat.supportsInlineStyles, isFalse);
      expect(lrcFormat.requiresEndTime, isFalse);
      expect(lrcFormat.createParser(), isA<LrcParser>());
      expect(lrcFormat.createWriter(), isA<LrcWriter>());
    });

    test('signatures identify LRC content but not ASS headers', () {
      final String basic = fixture('basic.lrc');
      final String metadata = fixture('metadata.lrc');

      final FormatSignature timestampLines =
          lrcFormat.signatures[0];
      final FormatSignature idTag = lrcFormat.signatures[1];

      expect(timestampLines.matches(basic), isTrue);
      expect(timestampLines.matches(metadata), isTrue);
      expect(idTag.matches(metadata), isTrue);

      expect(
        lrcFormat.signatures.map((signature) => signature.weight).toList(),
        <int>[60, 40],
      );

      const String assHeader = '[Script Info]\nTitle: x\n[V4+ Styles]\n';
      for (final signature in lrcFormat.signatures) {
        expect(signature.matches(assHeader), isFalse, reason: signature.id);
      }
    });
  });
}
