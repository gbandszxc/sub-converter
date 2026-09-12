import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/ass/ass_parser.dart';
import 'package:sub_converter/formats/ass/ass_writer.dart';
import 'package:sub_converter/formats/ssa/ssa_format.dart';
import 'package:sub_converter/formats/ssa/ssa_parser.dart';
import 'package:sub_converter/formats/ssa/ssa_writer.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/models/subtitle_style.dart';

SubtitleDocument _parseFixture(String path) =>
    SsaParser().parse(File(path).readAsStringSync());

void main() {
  group('SsaParser', () {
    test('shares the ASS implementation', () {
      expect(SsaParser(), isA<AssParser>());
      expect(SsaWriter(), isA<AssWriter>());
    });

    test('parses a normal SSA file with 18 style fields', () {
      final SubtitleDocument document = _parseFixture(
        'test/fixtures/ssa/basic.ssa',
      );

      expect(document.sourceFormat, SubtitleFormat.ssa);
      expect(document.cues.length, 2);
      expect(document.cues[0].start, const Duration(seconds: 1));
      expect(document.cues[0].end, const Duration(seconds: 2));
      expect(document.cues[0].text, 'Hello SSA');
      expect(document.cues[0].styleRef, 'Default');
      expect(document.cues[0].metadata['Marked'], 'Marked=0');

      final SubtitleStyle style = document.styles.single;
      expect(style.fields.length, 18);
      expect(style.field('Fontname'), 'Arial');
      expect(style.field('TertiaryColour'), '&H00000000');
      expect(style.field('AlphaLevel'), '0');
    });

    test('still scans override tags in SSA dialogue', () {
      const String content =
          '[Script Info]\n'
          'ScriptType: v4.00\n'
          '\n'
          '[V4 Styles]\n'
          'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
          'TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, '
          'Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding\n'
          'Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,'
          '0,0,1,2,2,2,10,10,10,0,1\n'
          '\n'
          '[Events]\n'
          'Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          'Dialogue: Marked=0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\i1}Hi{\\i0} there\n';
      final SubtitleDocument document = SsaParser().parse(content);

      final SubtitleCue cue = document.cues.single;
      expect(cue.text, 'Hi there');
      expect(cue.inlineStyles.length, 1);
      expect(cue.inlineStyles.single.start, 0);
      expect(cue.inlineStyles.single.end, 2);
      expect(cue.inlineStyles.single.styles, const <InlineStyle>{
        InlineStyle.italic,
      });
    });

    test('round-trips CJK text', () {
      final SubtitleDocument document = _parseFixture(
        'test/fixtures/ssa/cjk.ssa',
      );
      expect(document.cues[0].text, '你好，世界');

      final SubtitleDocument reparsed = SsaParser().parse(
        SsaWriter().write(document),
      );
      expect(reparsed.cues[0].text, '你好，世界');
      expect(reparsed.cues[1].text, 'こんにちは世界');
    });

    test('throws on malformed times and empty input', () {
      const String malformed =
          '[Script Info]\n'
          'ScriptType: v4.00\n'
          '\n'
          '[Events]\n'
          'Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          'Dialogue: Marked=0,xx:yy:zz,0:00:02.00,Default,,0,0,0,,Hi\n';
      expect(
        () => SsaParser().parse(malformed),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => SsaParser().parse('  '),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });
  });

  group('SsaWriter', () {
    test('emits [V4 Styles] with Marked and TertiaryColour', () {
      final SubtitleDocument document = _parseFixture(
        'test/fixtures/ssa/basic.ssa',
      );
      final String output = SsaWriter().write(document);

      expect(output.contains('[V4 Styles]'), isTrue);
      expect(output.contains('[V4+ Styles]'), isFalse);
      expect(output.contains('ScriptType: v4.00'), isTrue);
      expect(
        output.contains(
          'Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
        ),
        isTrue,
      );
      expect(output.contains('TertiaryColour'), isTrue);
      expect(output.contains('Layer'), isFalse);
      expect(
        output.contains(
          'Dialogue: Marked=0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello SSA',
        ),
        isTrue,
      );

      final SubtitleDocument reparsed = SsaParser().parse(output);
      expect(reparsed.cues.length, 2);
      expect(reparsed.cues[0].text, 'Hello SSA');
      expect(reparsed.styles.single.fields.length, 18);
      expect(reparsed.styles.single.field('TertiaryColour'), '&H00000000');
    });

    test('writes Marked=0 for a document built in code', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'Hi',
          ),
        ],
      );
      final String output = SsaWriter().write(document);

      expect(output.contains('[V4 Styles]'), isTrue);
      expect(output.contains('PlayResX: 384'), isTrue);
      expect(output.contains('PlayResY: 288'), isTrue);
      expect(output.contains('TertiaryColour'), isTrue);
      expect(
        output.contains(
          'Dialogue: Marked=0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hi',
        ),
        isTrue,
      );
      expect(output.endsWith('\n'), isTrue);
      expect(output.endsWith('\n\n'), isFalse);
    });
  });

  group('ssaFormat descriptor', () {
    test('advertises capabilities and builds the codecs', () {
      expect(ssaFormat.format, SubtitleFormat.ssa);
      expect(ssaFormat.supportsStyles, isTrue);
      expect(ssaFormat.supportsInlineStyles, isTrue);
      expect(ssaFormat.supportsPositions, isTrue);
      expect(ssaFormat.createParser(), isA<SsaParser>());
      expect(ssaFormat.createWriter(), isA<SsaWriter>());
      expect(ssaFormat.extensionAliases, contains('substation'));
    });

    test('signatures identify SSA and reject ASS content', () {
      final String ssa = File('test/fixtures/ssa/basic.ssa').readAsStringSync();
      for (final signature in ssaFormat.signatures) {
        expect(signature.matches(ssa), isTrue, reason: signature.id);
      }

      final String ass = File('test/fixtures/ass/basic.ass').readAsStringSync();
      for (final signature in ssaFormat.signatures) {
        if (signature.id == 'ssa.v4-styles' ||
            signature.id == 'ssa.script-type') {
          expect(signature.matches(ass), isFalse, reason: signature.id);
        }
      }
    });
  });
}
