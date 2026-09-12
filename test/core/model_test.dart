import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/models/subtitle_cue.dart';
import 'package:sub_converter/models/subtitle_document.dart';
import 'package:sub_converter/models/subtitle_format.dart';

void main() {
  group('SubtitleCue.shift', () {
    test('moves both timestamps', () {
      final SubtitleCue cue = SubtitleCue(
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 12),
      );
      cue.shift(const Duration(milliseconds: 500));
      expect(cue.start, const Duration(milliseconds: 10500));
      expect(cue.end, const Duration(milliseconds: 12500));
    });

    test('clamps each timestamp at zero independently', () {
      final SubtitleCue cue = SubtitleCue(
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 3),
      );
      cue.shift(const Duration(seconds: -2));
      expect(cue.start, Duration.zero);
      expect(cue.end, const Duration(seconds: 1));
    });

    test('leaves a missing end time missing', () {
      final SubtitleCue cue = SubtitleCue(start: const Duration(seconds: 1));
      cue.shift(const Duration(seconds: 1));
      expect(cue.end, isNull);
    });
  });

  group('SubtitleDocument.resolveMissingEndTimes', () {
    test('uses the next cue start for open-ended cues', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 10), text: 'a'),
          SubtitleCue(start: const Duration(seconds: 15), text: 'b'),
        ],
      );
      final SubtitleDocument resolved = document.resolveMissingEndTimes(
        fallback: const Duration(seconds: 5),
      );
      expect(resolved.cues[0].end, const Duration(seconds: 15));
    });

    test('adds the fallback to the last cue and keeps explicit ends', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 4),
            text: 'explicit',
          ),
          SubtitleCue(start: const Duration(seconds: 10), text: 'last'),
        ],
      );
      final SubtitleDocument resolved = document.resolveMissingEndTimes(
        fallback: const Duration(seconds: 5),
      );
      expect(resolved.cues[0].end, const Duration(seconds: 4));
      expect(resolved.cues[1].end, const Duration(seconds: 15));
    });

    test('does not modify the input document', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[SubtitleCue(start: Duration.zero, text: 'a')],
      );
      document.resolveMissingEndTimes(fallback: const Duration(seconds: 5));
      expect(document.cues.single.end, isNull);
    });

    test('falls back when the next cue does not start later', () {
      final SubtitleDocument document = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue(start: const Duration(seconds: 10), text: 'a'),
          SubtitleCue(start: const Duration(seconds: 10), text: 'b'),
        ],
      );
      final SubtitleDocument resolved = document.resolveMissingEndTimes(
        fallback: const Duration(seconds: 5),
      );
      expect(resolved.cues[0].end, const Duration(seconds: 15));
    });
  });

  test('document copy is deep for cues', () {
    final SubtitleDocument document = SubtitleDocument(
      cues: <SubtitleCue>[
        SubtitleCue(
          start: Duration.zero,
          text: 'hello',
          metadata: <String, Object?>{'Layer': '0'},
        ),
      ],
    );
    final SubtitleDocument copy = document.copy();
    copy.cues.single.text = 'changed';
    copy.cues.single.shift(const Duration(seconds: 1));
    expect(document.cues.single.text, 'hello');
    expect(document.cues.single.start, Duration.zero);
  });

  test('sortByStart orders cues chronologically', () {
    final SubtitleDocument document = SubtitleDocument(
      cues: <SubtitleCue>[
        SubtitleCue(start: const Duration(seconds: 5), text: 'b'),
        SubtitleCue(start: const Duration(seconds: 1), text: 'a'),
      ],
    );
    document.sortByStart();
    expect(document.cues.map((SubtitleCue cue) => cue.text), <String>['a', 'b']);
  });

  group('SubtitleFormat', () {
    test('resolves from extension, with dot, and from a file name', () {
      expect(SubtitleFormat.fromExtension('srt'), SubtitleFormat.srt);
      expect(SubtitleFormat.fromExtension('.ASS'), SubtitleFormat.ass);
      expect(
        SubtitleFormat.fromExtension(r'D:\Anime\E01.en.vtt'),
        SubtitleFormat.vtt,
      );
      expect(SubtitleFormat.fromExtension('unknown'), isNull);
    });

    test('resolves from label', () {
      expect(SubtitleFormat.fromLabel('ssa'), SubtitleFormat.ssa);
      expect(SubtitleFormat.fromLabel('SBV'), SubtitleFormat.sbv);
      expect(SubtitleFormat.fromLabel('nope'), isNull);
    });
  });
}
