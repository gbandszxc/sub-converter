import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/vtt/vtt_format.dart';
import 'package:sub_converter/formats/vtt/vtt_parser.dart';
import 'package:sub_converter/formats/vtt/vtt_writer.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';

void main() {
  const VttParser parser = VttParser();
  const VttWriter writer = VttWriter();

  String fixture(String name) =>
      File('test/fixtures/vtt/$name').readAsStringSync();

  group('VttParser', () {
    test('parses a normal multi-cue file', () {
      final SubtitleDocument document = parser.parse(fixture('basic.vtt'));

      expect(document.cues, hasLength(2));
      expect(document.cues[0].start, const Duration(seconds: 1));
      expect(document.cues[0].end, const Duration(milliseconds: 3500));
      expect(document.cues[0].text, 'Hello world\nSecond line');
      expect(document.cues[1].start, const Duration(seconds: 4));
      expect(document.cues[1].end, const Duration(seconds: 6));
      expect(document.cues[1].text, 'Goodbye');
      expect(document.sourceFormat, SubtitleFormat.vtt);
    });

    test('skips NOTE, STYLE and REGION blocks and reads header fields', () {
      final SubtitleDocument document =
          parser.parse(fixture('notes_and_settings.vtt'));

      expect(document.cues, hasLength(2));
      expect(document.metadata.field('Kind'), 'captions');
      expect(document.metadata.field('Language'), 'en');
      expect(document.metadata.language, 'en');

      final SubtitleCue first = document.cues.first;
      expect(first.metadata[vttIdentifierMetadataKey], 'intro');
      expect(
        first.metadata[vttSettingsMetadataKey],
        'align:start position:50% line:3',
      );
      expect(first.text, 'Hello & welcome');
      expect(document.cues[1].text, 'Second');
    });

    test('parses CJK text', () {
      final SubtitleDocument document = parser.parse(fixture('cjk.vtt'));
      expect(document.cues.map((SubtitleCue cue) => cue.text), <String>[
        '你好，世界',
        'こんにちは世界',
      ]);
    });

    test('decodes entities and turns tags into inline styles', () {
      final SubtitleDocument document = parser.parse(
        'WEBVTT\n\n'
        '00:00:01.000 --> 00:00:02.000\n'
        '<i>Hi</i> &amp; bye\n',
      );

      final SubtitleCue cue = document.cues.single;
      expect(cue.text, 'Hi & bye');
      expect(cue.inlineStyles, hasLength(1));
      expect(cue.inlineStyles.single.start, 0);
      expect(cue.inlineStyles.single.end, 2);
      expect(cue.inlineStyles.single.styles, <InlineStyle>{InlineStyle.italic});
    });

    test('tolerates a BOM and CRLF like LF', () {
      const String lf =
          'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n';
      const String crlf =
          '\uFEFFWEBVTT\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nHi\r\n';

      final SubtitleDocument a = parser.parse(lf);
      final SubtitleDocument b = parser.parse(crlf);

      expect(b.cues, hasLength(1));
      expect(b.cues.single.start, a.cues.single.start);
      expect(b.cues.single.end, a.cues.single.end);
      expect(b.cues.single.text, a.cues.single.text);
    });

    test('throws when the WEBVTT header is missing', () {
      expect(
        () => parser.parse('00:00:01.000 --> 00:00:02.000\nHi'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => parser.parse('not a vtt file\nat all'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });

    test('throws on empty or whitespace-only input', () {
      expect(
        () => parser.parse(''),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => parser.parse('   \n\t\n'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });

    test('throws on a cue block without a timing line', () {
      expect(
        () => parser.parse('WEBVTT\n\njust some text\n'),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });
  });

  group('VttWriter', () {
    test('writes the exact expected output', () {
      final SubtitleDocument document = SubtitleDocument(
        metadata: SubtitleMetadata(
          fields: <String, String>{
            'Kind': 'captions',
            'Language': 'en',
          },
        ),
        cues: <SubtitleCue>[
          SubtitleCue(
            start: Duration.zero,
            end: const Duration(seconds: 2),
            text: 'Hello',
          ),
          SubtitleCue(
            start: const Duration(seconds: 3),
            end: const Duration(seconds: 5),
            text: 'World',
          ),
        ],
      );

      expect(
        writer.write(document),
        'WEBVTT\n'
        'Kind: captions\n'
        'Language: en\n'
        '\n'
        '00:00:00.000 --> 00:00:02.000\n'
        'Hello\n'
        '\n'
        '00:00:03.000 --> 00:00:05.000\n'
        'World\n',
      );
    });

    test('re-encodes entities and inline tags', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: Duration.zero,
            end: const Duration(seconds: 2),
            text: 'Hi & bye',
            inlineStyles: <InlineStyleRange>[
              const InlineStyleRange(
                start: 0,
                end: 2,
                styles: <InlineStyle>{InlineStyle.italic},
              ),
            ],
          ),
        ],
      );

      final String output = writer.write(document);
      expect(output, contains('<i>Hi</i> &amp; bye'));
      expect(output, isNot(contains('&amp;amp;')));
    });

    test('writes a real end time for a cue with end: null', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[SubtitleCue(start: Duration.zero, text: 'Open')],
      );

      expect(
        writer.write(document),
        'WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nOpen\n',
      );
    });

    test('does not mutate the input document', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[SubtitleCue(start: Duration.zero, text: 'Open')],
      );
      writer.write(document);
      expect(document.cues.single.end, isNull);
    });

    test('skips cues with blank text', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: Duration.zero,
            end: const Duration(seconds: 1),
            text: '   ',
          ),
          SubtitleCue(
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 3),
            text: 'Kept',
          ),
        ],
      );

      expect(
        writer.write(document),
        'WEBVTT\n\n00:00:02.000 --> 00:00:03.000\nKept\n',
      );
    });
  });

  group('VttRoundTrip', () {
    test('preserves times and text', () {
      final SubtitleDocument original = parser.parse(fixture('basic.vtt'));
      final SubtitleDocument roundTripped =
          parser.parse(writer.write(original));

      expect(
        roundTripped.cues.map((SubtitleCue cue) => cue.start),
        original.cues.map((SubtitleCue cue) => cue.start),
      );
      expect(
        roundTripped.cues.map((SubtitleCue cue) => cue.end),
        original.cues.map((SubtitleCue cue) => cue.end),
      );
      expect(
        roundTripped.cues.map((SubtitleCue cue) => cue.text),
        original.cues.map((SubtitleCue cue) => cue.text),
      );
    });

    test('preserves cue identifier and settings', () {
      final SubtitleDocument original =
          parser.parse(fixture('notes_and_settings.vtt'));
      final String output = writer.write(original);
      final SubtitleDocument roundTripped = parser.parse(output);

      final SubtitleCue cue = roundTripped.cues.first;
      expect(cue.metadata[vttIdentifierMetadataKey], 'intro');
      expect(
        cue.metadata[vttSettingsMetadataKey],
        'align:start position:50% line:3',
      );
      expect(cue.text, 'Hello & welcome');
    });

    test('round-trips CJK text', () {
      final SubtitleDocument original = parser.parse(fixture('cjk.vtt'));
      final SubtitleDocument roundTripped =
          parser.parse(writer.write(original));
      expect(roundTripped.cues.map((SubtitleCue cue) => cue.text).toList(),
          <String>['你好，世界', 'こんにちは世界']);
    });
  });

  group('vttFormat descriptor', () {
    test('exposes format, aliases and capabilities', () {
      expect(vttFormat.format, SubtitleFormat.vtt);
      expect(vttFormat.extensionAliases, contains('webvtt'));
      expect(vttFormat.supportsInlineStyles, isTrue);
      expect(vttFormat.supportsPositions, isFalse);
      expect(vttFormat.requiresEndTime, isTrue);
      expect(vttFormat.createParser(), isA<VttParser>());
      expect(vttFormat.createWriter(), isA<VttWriter>());
    });

    test('signatures identify VTT content', () {
      final String content = fixture('basic.vtt');
      for (final signature in vttFormat.signatures) {
        expect(signature.matches(content), isTrue, reason: signature.id);
      }
      expect(
        vttFormat.signatures.map((signature) => signature.weight).toList(),
        <int>[100, 40],
      );
    });
  });

  group('missing blank line after the header', () {
    test('a cue immediately after WEBVTT is parsed, not swallowed', () {
      const String content = 'WEBVTT\n'
          '00:00:01.000 --> 00:00:02.000\n'
          'Hello\n';
      final document = const VttParser().parse(content);
      expect(document.cues.length, 1);
      expect(document.cues.single.text, 'Hello');
      expect(document.cues.single.start, const Duration(seconds: 1));
      expect(document.cues.single.end, const Duration(seconds: 2));
      expect(document.metadata.fields, isEmpty);
    });

    test('header fields still parse before a cue with no blank line', () {
      const String content = 'WEBVTT\n'
          'Kind: captions\n'
          'Language: ja\n'
          '00:00:01.000 --> 00:00:02.000\n'
          '日本語\n'
          '\n'
          '00:00:03.000 --> 00:00:04.000\n'
          'two\n';
      final document = const VttParser().parse(content);
      expect(document.metadata.fields['Kind'], 'captions');
      expect(document.metadata.language, 'ja');
      expect(document.cues.length, 2);
      expect(document.cues.first.text, '日本語');
      expect(document.cues.last.text, 'two');
    });

    test('a normal blank-line separated file is unaffected', () {
      final document = const VttParser().parse(fixture('basic.vtt'));
      expect(document.cues, isNotEmpty);
    });
  });
}
