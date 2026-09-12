import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/utils/inline_markup.dart';

void main() {
  group('HtmlMarkup.parse', () {
    test('strips tags and records emphasis', () {
      final ParsedInlineText parsed = HtmlMarkup.parse('<i>hello</i> world');
      expect(parsed.text, 'hello world');
      expect(parsed.styles, <InlineStyleRange>[
        const InlineStyleRange(
          start: 0,
          end: 5,
          styles: <InlineStyle>{InlineStyle.italic},
        ),
      ]);
    });

    test('handles nested emphasis as disjoint style segments', () {
      final ParsedInlineText parsed = HtmlMarkup.parse('<b>a<i>b</i>c</b>');
      expect(parsed.text, 'abc');
      expect(parsed.styles, <InlineStyleRange>[
        const InlineStyleRange(
          start: 0,
          end: 1,
          styles: <InlineStyle>{InlineStyle.bold},
        ),
        const InlineStyleRange(
          start: 1,
          end: 2,
          styles: <InlineStyle>{InlineStyle.bold, InlineStyle.italic},
        ),
        const InlineStyleRange(
          start: 2,
          end: 3,
          styles: <InlineStyle>{InlineStyle.bold},
        ),
      ]);
    });

    test('drops unknown and font tags', () {
      final ParsedInlineText parsed =
          HtmlMarkup.parse('<font color="#fff">hi</font><ruby>there</ruby>');
      expect(parsed.text, 'hithere');
      expect(parsed.styles, isEmpty);
    });

    test('keeps a bare less-than as text', () {
      final ParsedInlineText parsed = HtmlMarkup.parse('a < b > c');
      expect(parsed.text, 'a < b > c');
    });

    test('normalises CRLF and lone CR', () {
      expect(HtmlMarkup.parse('a\r\nb\rc').text, 'a\nb\nc');
    });

    test('decodes entities only when asked and never re-reads them as tags', () {
      expect(HtmlMarkup.parse('Tom &amp; Jerry').text, 'Tom &amp; Jerry');
      expect(
        HtmlMarkup.parse('Tom &amp; Jerry', decodeEntities: true).text,
        'Tom & Jerry',
      );
      final ParsedInlineText parsed =
          HtmlMarkup.parse('&lt;i&gt;literal&lt;/i&gt;', decodeEntities: true);
      expect(parsed.text, '<i>literal</i>');
      expect(parsed.styles, isEmpty);
    });

    test('closes unclosed emphasis at end of text', () {
      final ParsedInlineText parsed = HtmlMarkup.parse('<i>open');
      expect(parsed.text, 'open');
      expect(parsed.styles.single.end, 4);
    });
  });

  group('HtmlMarkup.render', () {
    test('round-trips emphasis', () {
      final ParsedInlineText parsed = HtmlMarkup.parse('<b>a<i>b</i>c</b>');
      expect(HtmlMarkup.render(parsed.text, parsed.styles), '<b>a<i>b</i>c</b>');
    });

    test('escapes special characters for WebVTT', () {
      expect(
        HtmlMarkup.render('a & b < c', const <InlineStyleRange>[], escape: true),
        'a &amp; b &lt; c',
      );
    });

    test('escapes text but not the tags it adds', () {
      expect(
        HtmlMarkup.render(
          'a & b',
          <InlineStyleRange>[
            const InlineStyleRange(
              start: 0,
              end: 5,
              styles: <InlineStyle>{InlineStyle.bold},
            ),
          ],
          escape: true,
        ),
        '<b>a &amp; b</b>',
      );
    });

    test('renders nothing extra for an empty document text', () {
      expect(HtmlMarkup.render('', const <InlineStyleRange>[]), '');
    });
  });

  group('normalizeInlineStyles', () {
    test('clamps out-of-range spans', () {
      final List<InlineStyleRange> result = normalizeInlineStyles(
        'abc',
        <InlineStyleRange>[
          const InlineStyleRange(
            start: 1,
            end: 99,
            styles: <InlineStyle>{InlineStyle.italic},
          ),
        ],
      );
      expect(result.single.start, 1);
      expect(result.single.end, 3);
    });

    test('merges adjacent identical style sets', () {
      final List<InlineStyleRange> result = normalizeInlineStyles(
        'abcd',
        <InlineStyleRange>[
          const InlineStyleRange(
            start: 0,
            end: 2,
            styles: <InlineStyle>{InlineStyle.bold},
          ),
          const InlineStyleRange(
            start: 2,
            end: 4,
            styles: <InlineStyle>{InlineStyle.bold},
          ),
        ],
      );
      expect(result.single.start, 0);
      expect(result.single.end, 4);
    });
  });
}
