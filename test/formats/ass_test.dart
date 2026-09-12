import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/ass/ass_format.dart';
import 'package:sub_converter/formats/ass/ass_parser.dart';
import 'package:sub_converter/formats/ass/ass_writer.dart';
import 'package:sub_converter/formats/ssa/ssa_format.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/models/subtitle_style.dart';

SubtitleDocument _parseFixture(String path) =>
    AssParser().parse(File(path).readAsStringSync());

void main() {
  group('AssParser', () {
    test('parses a normal multi-cue file', () {
      final SubtitleDocument document = _parseFixture(
        'test/fixtures/ass/basic.ass',
      );

      expect(document.cues.length, 2);
      expect(document.sourceFormat, SubtitleFormat.ass);

      final SubtitleCue first = document.cues[0];
      expect(first.start, const Duration(seconds: 1));
      expect(first.end, const Duration(seconds: 3));
      expect(first.text, 'Hello world');
      expect(first.styleRef, 'Default');
      expect(first.inlineStyles, isEmpty);

      final SubtitleCue second = document.cues[1];
      expect(second.start, const Duration(seconds: 3, milliseconds: 500));
      expect(second.end, const Duration(seconds: 5, milliseconds: 250));
      expect(second.text, 'Second line');
      expect(second.styleRef, 'Header');
      expect(second.metadata['Name'], 'Alice');
      expect(second.metadata['MarginL'], '10');
      expect(second.metadata['MarginR'], '20');
      expect(second.metadata['MarginV'], '30');
      expect(second.metadata['Effect'], 'fx');
      expect(second.metadata['Layer'], '1');
    });

    test('round-trips all 23 style fields', () {
      final SubtitleDocument document = _parseFixture(
        'test/fixtures/ass/basic.ass',
      );
      final SubtitleStyle? style = document.styleByName('Header');

      expect(style, isNotNull);
      expect(style!.fields.length, 23);
      expect(style.field('Fontname'), 'Arial');
      expect(style.numericField('Fontsize'), 36);
      expect(style.field('PrimaryColour'), '&H00FF0000');
      expect(style.field('Bold'), '-1');

      final SubtitleDocument reparsed = AssParser().parse(
        AssWriter().write(document),
      );
      final SubtitleStyle? reparsedStyle = reparsed.styleByName('Header');
      expect(reparsedStyle, isNotNull);
      expect(reparsedStyle!.fields.length, 23);
      expect(reparsedStyle.field('Fontname'), 'Arial');
      expect(reparsedStyle.numericField('Fontsize'), 36);
      expect(reparsedStyle.field('PrimaryColour'), '&H00FF0000');
    });

    test('drops override tags and captures \\an alignment', () {
      final SubtitleDocument document = _parseFixture(
        'test/fixtures/ass/tags.ass',
      );
      final SubtitleCue cue = document.cues[0];

      expect(cue.text, 'Hello');
      expect(cue.text.contains('{'), isFalse);
      expect(cue.text.contains('}'), isFalse);
      expect(cue.position?.alignment, 8);
      expect(cue.inlineStyles, isEmpty);
    });

    test('captures italic range over the right offsets', () {
      final SubtitleCue cue = _parseFixture('test/fixtures/ass/tags.ass')
          .cues[1];

      expect(cue.text, 'italic plain');
      expect(cue.inlineStyles.length, 1);
      final InlineStyleRange range = cue.inlineStyles.single;
      expect(range.start, 0);
      expect(range.end, 6);
      expect(range.styles, const <InlineStyle>{InlineStyle.italic});
    });

    test('\\r clears bold and italic', () {
      final SubtitleCue cue = _parseFixture('test/fixtures/ass/tags.ass')
          .cues[2];

      expect(cue.text, 'bothrest');
      expect(cue.inlineStyles.length, 1);
      final InlineStyleRange range = cue.inlineStyles.single;
      expect(range.start, 0);
      expect(range.end, 4);
      expect(range.styles, const <InlineStyle>{
        InlineStyle.bold,
        InlineStyle.italic,
      });
    });

    test('\\N becomes a model newline and \\{ \\} become literal braces', () {
      final List<SubtitleCue> cues = _parseFixture('test/fixtures/ass/tags.ass')
          .cues;

      expect(cues[3].text, 'line one\nline two');
      expect(cues[4].text, 'braces { literal }');
    });

    test('handles reordered and omitted Format fields', () {
      const String content =
          '[Script Info]\n'
          'ScriptType: v4.00+\n'
          '\n'
          '[Events]\n'
          'Format: Start, Text, End, MarginL, MarginR, MarginV, Style, Name\n'
          'Dialogue: 0:00:01.00,Hello there,0:00:02.00,1,2,3,Default,Bob\n';
      final SubtitleDocument document = AssParser().parse(content);

      final SubtitleCue cue = document.cues.single;
      expect(cue.start, const Duration(seconds: 1));
      expect(cue.end, const Duration(seconds: 2));
      expect(cue.text, 'Hello there');
      expect(cue.styleRef, 'Default');
      expect(cue.metadata['MarginL'], '1');
      expect(cue.metadata['MarginR'], '2');
      expect(cue.metadata['MarginV'], '3');
      expect(cue.metadata['Name'], 'Bob');
      expect(cue.metadata.containsKey('Effect'), isFalse);
    });

    test('drops [Fonts], unknown sections and non-Dialogue events', () {
      const String content =
          '[Script Info]\n'
          'ScriptType: v4.00+\n'
          '\n'
          '[V4+ Styles]\n'
          'Format: Name, Fontname\n'
          'Style: Default,Arial\n'
          '\n'
          '[Fonts]\n'
          'fontname: embedded.ttf\n'
          '\n'
          '[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          'Comment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,ignored\n'
          'Picture: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,pic.png\n'
          'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,kept\n';
      final SubtitleDocument document = AssParser().parse(content);

      expect(document.cues.length, 1);
      expect(document.cues.single.text, 'kept');
      expect(document.styles.length, 1);
      expect(document.styles.single.fields.length, 2);
    });

    test('returns an empty document when structure is valid but has no Dialogue', () {
      const String content =
          '[Script Info]\n'
          'ScriptType: v4.00+\n'
          '\n'
          '[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n';
      final SubtitleDocument document = AssParser().parse(content);

      expect(document.cues, isEmpty);
      expect(document.sourceFormat, SubtitleFormat.ass);
    });

    test('throws on malformed times', () {
      const String content =
          '[Script Info]\n'
          'ScriptType: v4.00+\n'
          '\n'
          '[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          'Dialogue: 0,not-a-time,0:00:02.00,Default,,0,0,0,,Hi\n';

      expect(
        () => AssParser().parse(content),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });

    test('throws on empty or whitespace-only input', () {
      expect(
        () => AssParser().parse(''),
        throwsA(isA<SubtitleSyntaxException>()),
      );
      expect(
        () => AssParser().parse('   \n\t  '),
        throwsA(isA<SubtitleSyntaxException>()),
      );
    });

    test('tolerates a leading BOM and CRLF newlines', () {
      final String content = File('test/fixtures/ass/basic.ass')
          .readAsStringSync();
      final String mangled = '\uFEFF${content.replaceAll('\n', '\r\n')}';
      final SubtitleDocument document = AssParser().parse(mangled);

      expect(document.cues.length, 2);
      expect(document.cues[0].text, 'Hello world');
    });

    test('round-trips CJK text', () {
      final SubtitleDocument document = _parseFixture(
        'test/fixtures/ass/cjk.ass',
      );
      expect(document.cues[0].text, '你好，世界');
      expect(document.cues[1].text, 'こんにちは世界');

      final SubtitleDocument reparsed = AssParser().parse(
        AssWriter().write(document),
      );
      expect(reparsed.cues[0].text, '你好，世界');
      expect(reparsed.cues[1].text, 'こんにちは世界');
    });
  });

  group('AssWriter', () {
    test('writes sections, canonical Format lines and formatted times', () {
      final SubtitleDocument document = SubtitleDocument(
        metadata: SubtitleMetadata(title: 'Demo'),
        styles: <SubtitleStyle>[
          SubtitleStyle(
            name: 'Default',
            fields: <String, String>{'Fontname': 'Arial'},
          ),
        ],
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'Hello',
            styleRef: 'Default',
          ),
        ],
      );

      final String output = AssWriter().write(document);

      expect(output.contains('[Script Info]'), isTrue);
      expect(output.contains('[V4+ Styles]'), isTrue);
      expect(output.contains('[Events]'), isTrue);
      expect(output.contains('ScriptType: v4.00+'), isTrue);
      expect(output.contains('Title: Demo'), isTrue);
      expect(output.contains('WrapStyle: 0'), isTrue);
      expect(output.contains('ScaledBorderAndShadow: yes'), isTrue);
      expect(output.contains('PlayResX: 1920'), isTrue);
      expect(output.contains('PlayResY: 1080'), isTrue);
      expect(
        output.contains(
          'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
          'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
          'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
          'Alignment, MarginL, MarginR, MarginV, Encoding',
        ),
        isTrue,
      );
      expect(
        output.contains(
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
        ),
        isTrue,
      );
      expect(
        output.contains(
          'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello',
        ),
        isTrue,
      );
      expect(output.contains('\r'), isFalse);
      expect(output.endsWith('\n'), isTrue);
      expect(output.endsWith('\n\n'), isFalse);
    });

    test('writes a Default style when the document has none', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'Hi',
          ),
        ],
      );
      final String output = AssWriter().write(document);

      expect(output.contains('Style: Default,Arial,20,&H00FFFFFF'), isTrue);
    });

    test('renders \\n as \\N, escapes braces and emits position tags', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: 'line one\nline two {x}',
            position: const CuePosition(alignment: 8, x: 100, y: 200),
            inlineStyles: const <InlineStyleRange>[
              InlineStyleRange(
                start: 0,
                end: 8,
                styles: <InlineStyle>{InlineStyle.bold},
              ),
            ],
          ),
        ],
      );
      final String output = AssWriter().write(document);

      expect(output.contains(r'{\an8}'), isTrue);
      expect(output.contains(r'{\pos(100,200)}'), isTrue);
      expect(output.contains(r'{\b1}line one{\b0}'), isTrue);
      expect(output.contains(r'\Nline two \{x\}'), isTrue);
    });

    test('fills a missing end time instead of writing nothing', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 1), text: 'No end'),
        ],
      );
      final String output = AssWriter().write(document);

      expect(
        output.contains(
          'Dialogue: 0,0:00:01.00,0:00:06.00,Default,,0,0,0,,No end',
        ),
        isTrue,
      );
    });

    test('skips cues with empty or whitespace-only text', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
            text: '   ',
          ),
          SubtitleCue(
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 3),
            text: 'kept',
          ),
        ],
      );
      final String output = AssWriter().write(document);

      expect(RegExp('Dialogue:').allMatches(output).length, 1);
      expect(output.contains('kept'), isTrue);
    });

    test('does not mutate the input document', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 1), text: 'Hi'),
        ],
      );
      AssWriter().write(document);
      expect(document.cues.single.end, isNull);
    });

    test('round-trips times, text, styles and inline emphasis', () {
      final SubtitleDocument document = SubtitleDocument(
        metadata: SubtitleMetadata(title: 'Round trip'),
        styles: <SubtitleStyle>[
          SubtitleStyle(
            name: 'Default',
            fields: <String, String>{
              'Fontname': 'Arial',
              'Fontsize': '24',
              'PrimaryColour': '&H00FFFFFF',
              'Alignment': '2',
            },
          ),
        ],
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2, milliseconds: 500),
            text: 'italic plain',
            styleRef: 'Default',
            inlineStyles: const <InlineStyleRange>[
              InlineStyleRange(
                start: 0,
                end: 6,
                styles: <InlineStyle>{InlineStyle.italic},
              ),
            ],
          ),
          SubtitleCue(
            start: const Duration(seconds: 3),
            end: const Duration(seconds: 4),
            text: 'bothrest',
            styleRef: 'Default',
            position: const CuePosition(alignment: 8, x: 100, y: 200),
            inlineStyles: const <InlineStyleRange>[
              InlineStyleRange(
                start: 0,
                end: 4,
                styles: <InlineStyle>{InlineStyle.bold, InlineStyle.italic},
              ),
            ],
          ),
        ],
      );

      final SubtitleDocument reparsed = AssParser().parse(
        AssWriter().write(document),
      );

      expect(reparsed.cues.length, 2);
      expect(reparsed.cues[0].start, document.cues[0].start);
      expect(reparsed.cues[0].end, document.cues[0].end);
      expect(reparsed.cues[0].text, 'italic plain');
      expect(reparsed.cues[0].styleRef, 'Default');
      expect(reparsed.cues[0].inlineStyles.length, 1);
      expect(reparsed.cues[0].inlineStyles.single.start, 0);
      expect(reparsed.cues[0].inlineStyles.single.end, 6);
      expect(reparsed.cues[0].inlineStyles.single.styles, const <InlineStyle>{
        InlineStyle.italic,
      });

      expect(reparsed.cues[1].start, document.cues[1].start);
      expect(reparsed.cues[1].end, document.cues[1].end);
      expect(reparsed.cues[1].text, 'bothrest');
      expect(reparsed.cues[1].position?.alignment, 8);
      expect(reparsed.cues[1].position?.x, 100);
      expect(reparsed.cues[1].position?.y, 200);
      expect(reparsed.cues[1].inlineStyles.single.styles, const <InlineStyle>{
        InlineStyle.bold,
        InlineStyle.italic,
      });

      final SubtitleStyle? style = reparsed.styleByName('Default');
      expect(style, isNotNull);
      expect(style!.field('Fontname'), 'Arial');
      expect(style.numericField('Fontsize'), 24);
    });
  });

  group('assFormat descriptor', () {
    test('advertises capabilities and builds the codecs', () {
      expect(assFormat.format, SubtitleFormat.ass);
      expect(assFormat.supportsStyles, isTrue);
      expect(assFormat.supportsInlineStyles, isTrue);
      expect(assFormat.supportsPositions, isTrue);
      expect(assFormat.createParser(), isA<AssParser>());
      expect(assFormat.createWriter(), isA<AssWriter>());
    });

    test('signatures identify ASS content', () {
      final String content = File('test/fixtures/ass/basic.ass')
          .readAsStringSync();
      for (final signature in assFormat.signatures) {
        expect(signature.matches(content), isTrue, reason: signature.id);
      }
      for (final signature in ssaFormat.signatures) {
        if (signature.id == 'ssa.v4-styles' ||
            signature.id == 'ssa.script-type') {
          expect(signature.matches(content), isFalse, reason: signature.id);
        }
      }
    });
  });
}
