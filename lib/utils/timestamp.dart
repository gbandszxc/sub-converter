/// The single place where subtitle timestamps are parsed and formatted.
///
/// Formats differ only in separator, fraction digits and hour padding, e.g.
///
/// ```text
/// SRT  00:01:25,300
/// VTT  00:01:25.300
/// ASS  0:01:25.30
/// SSA  0:01:25.30
/// SBV  0:01:25.300
/// LRC  [01:25.30]
/// ```
///
/// Every parser and writer must go through these helpers so timestamp handling
/// never gets duplicated per format.
library;

/// Matches `H:MM:SS.mmm`, `MM:SS.mmm` and `H:MM:SS,mmm` field layouts.
///
/// Fraction digits are `1..3`; more than three digits are truncated to
/// milliseconds.
final RegExp _clockPattern = RegExp(
  r'^\s*(\d{1,3})\s*:\s*([0-5]?\d)'
  r'(?:\s*:\s*([0-5]?\d))?'
  r'\s*[.,:]\s*(\d{1,6})\s*$',
);

/// The largest value accepted as an hour/minute field before we treat the
/// input as malformed rather than silently overflowing.
const int _maxClockField = 999;

/// Parses a clock timestamp into a [Duration], or returns `null` when [raw] is
/// not a timestamp.
///
/// [minimumFields] controls how a two-field value is read:
/// * `3` (default, SRT/VTT/ASS/SSA/SBV) requires `HH:MM:SS` and rejects
///   `MM:SS`.
/// * `2` (LRC) accepts `MM:SS` as well, and reads three-field values as
///   `HH:MM:SS`.
Duration? tryParseTimestamp(String raw, {int minimumFields = 3}) {
  final RegExpMatch? match = _clockPattern.firstMatch(raw);
  if (match == null) {
    return null;
  }
  final int first = int.parse(match.group(1)!);
  final int second = int.parse(match.group(2)!);
  final String? thirdGroup = match.group(3);
  final String fractionGroup = match.group(4)!;

  if (first > _maxClockField || second > _maxClockField) {
    return null;
  }

  final int hours;
  final int minutes;
  final int seconds;
  if (thirdGroup != null) {
    hours = first;
    minutes = second;
    seconds = int.parse(thirdGroup);
  } else {
    if (minimumFields >= 3) {
      return null;
    }
    hours = 0;
    minutes = first;
    seconds = second;
  }
  if (minutes > 59 || seconds > 59) {
    return null;
  }

  final int milliseconds = _fractionToMilliseconds(fractionGroup);
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: milliseconds,
  );
}

/// Parses a clock timestamp, throwing [FormatException] when [raw] is invalid.
Duration parseTimestamp(String raw, {int minimumFields = 3}) {
  final Duration? parsed = tryParseTimestamp(raw, minimumFields: minimumFields);
  if (parsed == null) {
    throw FormatException('Invalid timestamp: "$raw"');
  }
  return parsed;
}

/// Formats [value] as `HH:MM:SS<separator>fraction`.
///
/// [fractionDigits] is clamped to `1..3`. Negative values are clamped to zero.
String formatTimestamp(
  Duration value, {
  String separator = '.',
  int fractionDigits = 3,
  int hourDigits = 2,
}) {
  final Duration clamped = value.isNegative ? Duration.zero : value;
  final int digits = fractionDigits.clamp(1, 3);
  final int hours = clamped.inHours;
  final int minutes = clamped.inMinutes.remainder(60);
  final int seconds = clamped.inSeconds.remainder(60);
  final String fraction =
      _fractionString(clamped.inMilliseconds.remainder(1000), digits);
  final String hourText = hours.toString().padLeft(hourDigits, '0');
  return '$hourText:${_two(minutes)}:${_two(seconds)}$separator$fraction';
}

/// Formats [value] as `MM:SS<separator>fraction`, where minutes are the total
/// minutes and may exceed 59. Used by LRC, which has no hour field.
String formatTimestampAsMinutes(
  Duration value, {
  String separator = '.',
  int fractionDigits = 2,
  int minuteDigits = 2,
}) {
  final Duration clamped = value.isNegative ? Duration.zero : value;
  final int digits = fractionDigits.clamp(1, 3);
  final int minutes = clamped.inMinutes;
  final int seconds = clamped.inSeconds.remainder(60);
  final String fraction =
      _fractionString(clamped.inMilliseconds.remainder(1000), digits);
  return '${minutes.toString().padLeft(minuteDigits, '0')}:${_two(seconds)}'
      '$separator$fraction';
}

/// Interprets a fractional-second group: `5` -> 500 ms, `53` -> 530 ms,
/// `530` -> 530 ms. Extra digits beyond milliseconds are truncated.
int _fractionToMilliseconds(String fraction) {
  final String digits = fraction.length > 3 ? fraction.substring(0, 3) : fraction;
  return int.parse(digits.padRight(3, '0'));
}

String _fractionString(int milliseconds, int digits) {
  final String padded = milliseconds.toString().padLeft(3, '0');
  return digits >= 3 ? padded : padded.substring(0, digits);
}

String _two(int value) => value.toString().padLeft(2, '0');
