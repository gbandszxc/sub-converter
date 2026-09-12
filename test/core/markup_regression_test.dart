import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/utils/inline_markup.dart';

/// Regression tests for defects found by an independent audit of the markup
/// layer.
void main() {
  group('render nests tags correctly', () {
    /// Builds a range covering the whole of [text].
    InlineStyleRange whole(String text, Set<InlineStyle> styles) =>
        InlineStyleRange(start: 0, end: text.length, styles: styles);

    test('two simultaneous styles close in reverse order', () {
      const String text = 'both';
      expect(
        HtmlMarkup.render(
          text,
          <InlineStyleRange>[
            whole(text, <InlineStyle>{InlineStyle.bold, InlineStyle.italic}),
          ],
        ),
        '<b><i>both</i></b>',
      );
    });

    test('three simultaneous styles nest instead of interleaving', () {
      const String text = 'abc';
      expect(
        HtmlMarkup.render(
          text,
          <InlineStyleRange>[
            whole(
              text,
              <InlineStyle>{
                InlineStyle.italic,
                InlineStyle.bold,
                InlineStyle.underline,
              },
            ),
          ],
        ),
        '<b><i><u>abc</u></i></b>',
      );
    });

    test('the same document always renders the same bytes', () {
      const String text = 'abc';
      final List<InlineStyleRange> ranges = <InlineStyleRange>[
        whole(text, <InlineStyle>{InlineStyle.bold, InlineStyle.italic}),
      ];
      final String first = HtmlMarkup.render(text, ranges);
      for (int i = 0; i < 5; i++) {
        expect(HtmlMarkup.render(text, ranges), first);
      }
    });

    test('re-parsing a rendered overlap yields the original emphasis', () {
      const String text = 'abc';
      final List<InlineStyleRange> ranges = <InlineStyleRange>[
        whole(text, <InlineStyle>{InlineStyle.bold, InlineStyle.italic}),
      ];
      final ParsedInlineText reparsed =
          HtmlMarkup.parse(HtmlMarkup.render(text, ranges));
      expect(reparsed.text, text);
      expect(reparsed.styles.single.styles,
          <InlineStyle>{InlineStyle.bold, InlineStyle.italic});
    });
  });

  group('stripAssOverrideBlocks only removes real override commands', () {
    test('removes the documented ASS examples', () {
      expect(stripAssOverrideBlocks(r'{\an8}{\bord2}Hello'), 'Hello');
      expect(stripAssOverrideBlocks(r'{\i1}a{\i0}b'), 'ab');
      expect(stripAssOverrideBlocks(r'{\pos(10,20)}x'), 'x');
      expect(stripAssOverrideBlocks(r'{\c&HFFFFFF&}white'), 'white');
      expect(stripAssOverrideBlocks(r'{\1c&H00FF00&}green'), 'green');
      expect(stripAssOverrideBlocks(r'{\t(0,500,\fs30)}grow'), 'grow');
    });

    test('removes an unterminated tag instead of leaking it', () {
      expect(stripAssOverrideBlocks(r'{\b1'), '');
      expect(stripAssOverrideBlocks('before {\\i1'), 'before ');
    });

    test('keeps braces that are ordinary punctuation', () {
      expect(stripAssOverrideBlocks('{laughs}'), '{laughs}');
      expect(stripAssOverrideBlocks(r'{C:\path\to\file}'), r'{C:\path\to\file}');
      expect(stripAssOverrideBlocks(r'{see \play note}'), r'{see \play note}');
      expect(
        stripAssOverrideBlocks('a {note} and {another}'),
        'a {note} and {another}',
      );
    });

    test('a cue that is only a brace path keeps its text', () {
      const String srt = '1\n'
          '00:00:01,000 --> 00:00:02,000\n'
          r'{C:\path}'
          '\n';
      // The path text must survive the parser rather than emptying the cue.
      final ParsedInlineText parsed = HtmlMarkup.parse(
        stripAssOverrideBlocks(r'{C:\path}'),
      );
      expect(parsed.text, r'{C:\path}');
      expect(srt, contains(r'{C:\path}'));
    });
  });
}
