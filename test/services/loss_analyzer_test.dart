import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/formats/built_in_formats.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_style.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/services/loss_analyzer.dart';

/// LossAnalyzer turns capability gaps and source-side oddities into short
/// user-facing notes. A lossy conversion is still a success.
void main() {
  const LossAnalyzer analyzer = LossAnalyzer();

  LossReport analyze({
    required SubtitleDocument document,
    SubtitleFormat source = SubtitleFormat.ass,
    SubtitleFormat target = SubtitleFormat.srt,
  }) {
    return analyzer.analyze(
      document: document,
      source: builtInFormatRegistry.descriptorFor(source)!,
      target: builtInFormatRegistry.descriptorFor(target)!,
    );
  }

  SubtitleDocument documentWith(List<SubtitleCue> cues) =>
      SubtitleDocument(cues: cues);

  test('plain text into a plain format loses nothing', () {
    final LossReport report = analyze(
      document: documentWith(<SubtitleCue>[
        SubtitleCue(
          start: Duration.zero,
          end: const Duration(seconds: 1),
          text: 'plain',
        ),
      ]),
      source: SubtitleFormat.srt,
      target: SubtitleFormat.sbv,
    );
    expect(report.isLossy, isFalse);
    expect(report.warnings, isEmpty);
  });

  test('inline emphasis is reported when the target cannot express it', () {
    final LossReport report = analyze(
      document: documentWith(<SubtitleCue>[
        SubtitleCue(
          start: Duration.zero,
          end: const Duration(seconds: 1),
          text: 'bold',
          inlineStyles: const <InlineStyleRange>[
            InlineStyleRange(
              start: 0,
              end: 4,
              styles: <InlineStyle>{InlineStyle.bold},
            ),
          ],
        ),
      ]),
      source: SubtitleFormat.srt,
      target: SubtitleFormat.sbv,
    );
    expect(report.isLossy, isTrue);
    expect(report.warnings.single, contains('SBV'));
  });

  test('positioning and styles are reported for a format without them', () {
    final SubtitleDocument document = SubtitleDocument(
      cues: <SubtitleCue>[
        SubtitleCue(
          start: Duration.zero,
          end: const Duration(seconds: 1),
          text: 'placed',
          position: const CuePosition(alignment: 8),
        ),
      ],
      styles: <SubtitleStyle>[SubtitleStyle(name: 'Default')],
    );
    final LossReport report = analyze(
      document: document,
      source: SubtitleFormat.ass,
      target: SubtitleFormat.srt,
    );
    expect(report.warnings.length, 2);
    expect(report.warnings.join(' '), contains('position'));
    expect(report.warnings.join(' '), contains('styles'));
  });

  test('LRC reports dropped end times and joined lines', () {
    final LossReport report = analyze(
      document: documentWith(<SubtitleCue>[
        SubtitleCue(
          start: Duration.zero,
          end: const Duration(seconds: 2),
          text: 'line one\nline two',
        ),
      ]),
      source: SubtitleFormat.srt,
      target: SubtitleFormat.lrc,
    );
    expect(report.warnings.join(' '), contains('line breaks'));
    expect(report.warnings.join(' '), contains('end times'));
  });

  test('an LRC round trip is not reported as lossy', () {
    final LossReport report = analyze(
      document: documentWith(<SubtitleCue>[
        SubtitleCue(start: Duration.zero, end: const Duration(seconds: 2), text: 'a'),
      ]),
      source: SubtitleFormat.lrc,
      target: SubtitleFormat.lrc,
    );
    expect(report.isLossy, isFalse);
  });

  test('an inverted cue is warned about but not treated as a failure', () {
    final LossReport report = analyze(
      document: documentWith(<SubtitleCue>[
        SubtitleCue(
          start: const Duration(seconds: 5),
          end: const Duration(seconds: 2),
          text: 'backwards',
        ),
      ]),
      source: SubtitleFormat.srt,
      target: SubtitleFormat.srt,
    );
    expect(report.isLossy, isTrue);
    expect(report.warnings.single, contains('ends before it starts'));
  });

  test('several inverted cues are counted', () {
    final LossReport report = analyze(
      document: documentWith(<SubtitleCue>[
        SubtitleCue(
          start: const Duration(seconds: 5),
          end: const Duration(seconds: 2),
          text: 'one',
        ),
        SubtitleCue(
          start: const Duration(seconds: 9),
          end: const Duration(seconds: 8),
          text: 'two',
        ),
      ]),
      source: SubtitleFormat.srt,
      target: SubtitleFormat.srt,
    );
    expect(report.warnings.single, contains('2 cues end before they start'));
  });
}
