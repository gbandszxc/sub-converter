import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/utils/subtitle_defaults.dart';
import 'package:sub_converter/utils/timestamp.dart';

void main() {
  group('tryParseTimestamp', () {
    test('parses SRT comma form', () {
      expect(
        tryParseTimestamp('00:01:25,300'),
        const Duration(minutes: 1, seconds: 25, milliseconds: 300),
      );
    });

    test('parses VTT/SBV dot form', () {
      expect(
        tryParseTimestamp('00:01:25.300'),
        const Duration(minutes: 1, seconds: 25, milliseconds: 300),
      );
    });

    test('parses ASS one-digit hour and centiseconds', () {
      expect(
        tryParseTimestamp('0:01:25.30'),
        const Duration(minutes: 1, seconds: 25, milliseconds: 300),
      );
    });

    test('reads two fields as MM:SS only when minimumFields is 2', () {
      expect(tryParseTimestamp('01:25.30'), isNull);
      expect(
        tryParseTimestamp('01:25.30', minimumFields: 2),
        const Duration(minutes: 1, seconds: 25, milliseconds: 300),
      );
    });

    test('reads three fields as HH:MM:SS when minimumFields is 2', () {
      expect(
        tryParseTimestamp('01:02:03.50', minimumFields: 2),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
      );
    });

    test('expands short fractions by place value', () {
      expect(
        tryParseTimestamp('00:00:01.5'),
        const Duration(seconds: 1, milliseconds: 500),
      );
      expect(
        tryParseTimestamp('00:00:01.05'),
        const Duration(seconds: 1, milliseconds: 50),
      );
      expect(
        tryParseTimestamp('00:00:01.500'),
        const Duration(seconds: 1, milliseconds: 500),
      );
    });

    test('rejects malformed values', () {
      expect(tryParseTimestamp(''), isNull);
      expect(tryParseTimestamp('not a time'), isNull);
      expect(tryParseTimestamp('00:61:00,000'), isNull);
      expect(tryParseTimestamp('00:00:61,000'), isNull);
      expect(tryParseTimestamp('1:2'), isNull);
    });

    test('accepts surrounding whitespace', () {
      expect(tryParseTimestamp('  00:00:02.000 '), const Duration(seconds: 2));
    });
  });

  group('formatTimestamp', () {
    test('formats SRT', () {
      expect(
        formatTimestamp(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4),
          separator: ',',
        ),
        '01:02:03,004',
      );
    });

    test('formats ASS with one-digit hour and centiseconds', () {
      expect(
        formatTimestamp(
          const Duration(minutes: 1, seconds: 25, milliseconds: 300),
          fractionDigits: 2,
          hourDigits: 1,
        ),
        '0:01:25.30',
      );
    });

    test('formats SBV with one-digit hour and milliseconds', () {
      expect(
        formatTimestamp(const Duration(minutes: 1, seconds: 25), hourDigits: 1),
        '0:01:25.000',
      );
    });

    test('clamps negative values to zero', () {
      expect(formatTimestamp(const Duration(seconds: -5)), '00:00:00.000');
    });
  });

  group('formatTimestampAsMinutes', () {
    test('formats LRC centiseconds', () {
      expect(
        formatTimestampAsMinutes(
          const Duration(minutes: 1, seconds: 25, milliseconds: 300),
        ),
        '01:25.30',
      );
    });

    test('lets minutes exceed 59', () {
      expect(
        formatTimestampAsMinutes(
          const Duration(hours: 1, seconds: 5),
          fractionDigits: 2,
        ),
        '60:05.00',
      );
    });
  });

  test('defaults expose the LRC fallback duration', () {
    expect(SubtitleDefaults.lrcEndTimeFallback, const Duration(seconds: 5));
  });
}
