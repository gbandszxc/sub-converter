import 'dart:convert';

import 'package:charset/charset.dart';

import '../models/subtitle_exception.dart';
import '../utils/subtitle_defaults.dart';
import 'gb18030_codec.dart';

/// A decoded subtitle file.
class DecodedText {
  const DecodedText({
    required this.text,
    required this.encodingName,
    required this.hadBom,
  });

  /// Decoded content, BOM removed.
  final String text;

  /// Human-readable encoding name, e.g. `UTF-8`, `UTF-8 BOM`, `UTF-16 LE`,
  /// `UTF-16 BE`, `GB18030`, `GBK`, `Shift_JIS`, `EUC-JP`, `Windows-1252`.
  final String encodingName;

  /// Whether the source started with a byte order mark.
  final bool hadBom;
}

/// Decodes subtitle bytes into text and encodes text back to UTF-8.
///
/// The single entry point is [decode]; it never returns mojibake silently and
/// never lets a raw `FormatException` escape. When no candidate encoding
/// applies it throws a [SubtitleConversionException] with
/// [ConversionFailure.encodingDetectionFailed].
///
/// ## Detection pipeline
///
/// 1. Empty input decodes to an empty [DecodedText].
/// 2. A byte order mark is authoritative: UTF-8, UTF-16 LE/BE and UTF-32
///    LE/BE are recognised before anything else. If a BOM is present but the
///    bytes after it are not valid for that encoding, detection fails instead
///    of falling back to a legacy reading (a declared BOM outranks guessing).
/// 3. A BOM-less UTF-16 guess is made from NUL-byte parity. ASCII/Latin text
///    stored as UTF-16 leaves a `0x00` in every other byte; mostly-even NUL
///    positions mean big endian and mostly-odd mean little endian. The guess is
///    accepted only when the decoded text has no U+FFFD and no C0 control
///    other than tab/newline/carriage return. As an extension for the case of
///    pure CJK text stored as UTF-16 (which contains no NUL bytes at all), the
///    same guess is attempted for even-length input when exactly one byte order
///    yields text made only of plausible scripts and the opposite byte order
///    contains no hard-invalid character (U+FFFD, private-use, surrogate or C0
///    control). If both orders are plausible, neither is, or the losing order
///    contains a hard-invalid character, the guess is abandoned so that binary,
///    GBK, Shift-JIS, Western and UTF-8 data are not hijacked.
/// 4. Strict UTF-8 is attempted next; pure ASCII lands here, which is correct.
/// 5. Legacy candidates are tried in a fixed order: GB18030 (via
///    [Gb18030Decoder]), Shift_JIS, EUC-JP and Windows-1252. A candidate is
///    viable when it decodes without throwing and produces no U+FFFD. Viable
///    candidates are scored (see [_scoreText]) and the highest score wins; ties
///    favour the earlier candidate.
/// 6. If step 5 finds nothing, Windows-1252 is tried as a permissive last
///    resort. If that also fails, detection fails.
///
/// ## Heuristic limits
///
/// This is a heuristic, not a statistical detector. Chinese GBK/GB18030 and
/// Japanese Shift-JIS share most of their two-byte space, and some byte pairs
/// are valid in both. They are separated mainly by the kana bonus: genuine
/// Japanese text contains hiragana/katakana, which GBK almost never produces,
/// while GBK ideographs cannot be told apart from Shift-JIS kanji by shape.
/// To break the common GBK/Shift-JIS collision the scorer also penalises kB
/// characters decoded from GBK's rare third and fourth rows (`0x81-0x9F` and
/// `0xE0-0xEF` lead bytes), which are exactly the bytes Shift-JIS uses for its
/// kanji, and ignores half-width katakana because they are the classic artifact
/// of reading GBK Chinese bytes as Shift-JIS. Ambiguous short inputs can still
/// be misdetected; single-byte Western text is decoded as Windows-1252 unless
/// it happens to be valid UTF-8.
class EncodingService {
  const EncodingService();

  /// Names of the legacy encodings detection may report, in candidate order.
  static const List<String> legacyEncodingNames = <String>[
    'GB18030',
    'GBK',
    'Shift_JIS',
    'EUC-JP',
    'Windows-1252',
  ];

  /// Decodes [bytes] into text, or throws
  /// [SubtitleConversionException] with
  /// [ConversionFailure.encodingDetectionFailed].
  DecodedText decode(List<int> bytes) {
    if (bytes.isEmpty) {
      return const DecodedText(text: '', encodingName: 'UTF-8', hadBom: false);
    }

    // BOM sniffing. A declared BOM is authoritative.
    final bom = _decodeWithBom(bytes);
    if (bom != null) {
      return bom;
    }

    // BOM-less UTF-16 guess.
    final utf16 = _guessBomLessUtf16(bytes);
    if (utf16 != null) {
      return utf16;
    }

    // Strict UTF-8. Pure ASCII lands here.
    try {
      return DecodedText(
        text: utf8.decode(bytes),
        encodingName: 'UTF-8',
        hadBom: false,
      );
    } on FormatException {
      // Not valid UTF-8; keep going.
    }

    // Scored legacy candidates, in fixed candidate order.
    final best = _bestLegacyCandidate(bytes);
    if (best != null) {
      return DecodedText(
        text: best.text,
        encodingName: best.label,
        hadBom: false,
      );
    }

    // Permissive Windows-1252 last resort.
    final lastResort = _decodeWindows1252(bytes, strict: false);
    if (lastResort != null) {
      return DecodedText(
        text: lastResort,
        encodingName: 'Windows-1252',
        hadBom: false,
      );
    }

    throw SubtitleConversionException(
      ConversionFailure.encodingDetectionFailed,
      'The text encoding of this file could not be determined.',
    );
  }

  /// Encodes [text] as UTF-8, optionally prefixed with a UTF-8 BOM.
  ///
  /// This is the only output encoding v0.1 writes. When [withBom] is omitted
  /// the default comes from [SubtitleDefaults.writeUtf8BomByDefault].
  List<int> encode(
    String text, {
    bool withBom = SubtitleDefaults.writeUtf8BomByDefault,
  }) {
    final body = utf8.encode(text);
    if (!withBom) {
      return body;
    }
    return <int>[0xEF, 0xBB, 0xBF, ...body];
  }

  // --------------------------------------------------------------------------
  // BOM handling
  // --------------------------------------------------------------------------

  DecodedText? _decodeWithBom(List<int> bytes) {
    if (_startsWith(bytes, const <int>[0xEF, 0xBB, 0xBF])) {
      try {
        return DecodedText(
          text: utf8.decode(bytes.sublist(3)),
          encodingName: 'UTF-8 BOM',
          hadBom: true,
        );
      } on FormatException catch (error) {
        throw SubtitleConversionException(
          ConversionFailure.encodingDetectionFailed,
          'The file starts with a UTF-8 byte order mark but is not valid UTF-8.',
          cause: error,
        );
      }
    }

    if (_startsWith(bytes, const <int>[0xFF, 0xFE, 0x00, 0x00])) {
      return _decodeUtf32WithBom(bytes, littleEndian: true, name: 'UTF-32 LE');
    }
    if (_startsWith(bytes, const <int>[0x00, 0x00, 0xFE, 0xFF])) {
      return _decodeUtf32WithBom(bytes, littleEndian: false, name: 'UTF-32 BE');
    }

    if (_startsWith(bytes, const <int>[0xFF, 0xFE])) {
      return _decodeUtf16WithBom(bytes, littleEndian: true, name: 'UTF-16 LE');
    }
    if (_startsWith(bytes, const <int>[0xFE, 0xFF])) {
      return _decodeUtf16WithBom(bytes, littleEndian: false, name: 'UTF-16 BE');
    }

    return null;
  }

  DecodedText _decodeUtf16WithBom(
    List<int> bytes, {
    required bool littleEndian,
    required String name,
  }) {
    final text = _decodeUtf16(bytes.sublist(2), littleEndian: littleEndian);
    if (!_isAcceptableUtf16(text)) {
      throw SubtitleConversionException(
        ConversionFailure.encodingDetectionFailed,
        'The file starts with a UTF-16 byte order mark but its content is not '
        'valid UTF-16.',
      );
    }
    return DecodedText(text: text, encodingName: name, hadBom: true);
  }

  DecodedText _decodeUtf32WithBom(
    List<int> bytes, {
    required bool littleEndian,
    required String name,
  }) {
    final decoder = const Utf32Decoder();
    final body = bytes.sublist(4);
    final text = littleEndian
        ? decoder.decodeUtf32Le(body)
        : decoder.decodeUtf32Be(body);
    if (text.contains('\uFFFD')) {
      throw SubtitleConversionException(
        ConversionFailure.encodingDetectionFailed,
        'The file starts with a UTF-32 byte order mark but its content is not '
        'valid UTF-32.',
      );
    }
    return DecodedText(text: text, encodingName: name, hadBom: true);
  }

  // --------------------------------------------------------------------------
  // BOM-less UTF-16
  // --------------------------------------------------------------------------

  DecodedText? _guessBomLessUtf16(List<int> bytes) {
    if (bytes.length < 2) {
      return null;
    }

    final sampleLength = bytes.length < 64 ? bytes.length : 64;
    var zeros = 0;
    var evenZeros = 0;
    var oddZeros = 0;
    for (var i = 0; i < sampleLength; i++) {
      if (bytes[i] == 0) {
        zeros++;
        if (i.isEven) {
          evenZeros++;
        } else {
          oddZeros++;
        }
      }
    }

    if (zeros >= 4) {
      final littleEndian = oddZeros > evenZeros;
      final text = _decodeUtf16(bytes, littleEndian: littleEndian);
      if (!_isAcceptableUtf16(text)) {
        // A strong NUL signal that does not decode cleanly: refuse to guess.
        return null;
      }
      return DecodedText(
        text: text,
        encodingName: littleEndian ? 'UTF-16 LE' : 'UTF-16 BE',
        hadBom: false,
      );
    }

    // No NUL bytes: pure CJK stored as UTF-16 has this shape. Only accept when
    // exactly one byte order yields text made solely of plausible scripts.
    if (bytes.length.isEven && bytes.length >= 4) {
      final littleEndianText = _decodeUtf16(bytes, littleEndian: true);
      final bigEndianText = _decodeUtf16(bytes, littleEndian: false);
      final littleEndianOk = _isStronglyPlausibleUtf16(littleEndianText);
      final bigEndianOk = _isStronglyPlausibleUtf16(bigEndianText);
      if (littleEndianOk &&
          !bigEndianOk &&
          !_hasHardInvalidUtf16(bigEndianText)) {
        return DecodedText(
          text: littleEndianText,
          encodingName: 'UTF-16 LE',
          hadBom: false,
        );
      }
      if (bigEndianOk &&
          !littleEndianOk &&
          !_hasHardInvalidUtf16(littleEndianText)) {
        return DecodedText(
          text: bigEndianText,
          encodingName: 'UTF-16 BE',
          hadBom: false,
        );
      }
    }
    return null;
  }

  String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    const decoder = Utf16Decoder();
    return littleEndian
        ? decoder.decodeUtf16Le(bytes)
        : decoder.decodeUtf16Be(bytes);
  }

  /// Accepts UTF-16 output that has no replacement character and no C0 control
  /// other than tab, newline and carriage return.
  bool _isAcceptableUtf16(String text) {
    for (final rune in text.runes) {
      if (rune == 0xFFFD) {
        return false;
      }
      if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
        return false;
      }
    }
    return true;
  }

  /// Like [_isAcceptableUtf16], but additionally requires every character to
  /// belong to a script that plausibly appears in a subtitle. Hangul and
  /// private-use code points are excluded so that binary and GBK data are not
  /// mistaken for UTF-16.
  bool _isStronglyPlausibleUtf16(String text) {
    if (text.isEmpty || !_isAcceptableUtf16(text)) {
      return false;
    }
    for (final rune in text.runes) {
      if (!_isPlausibleUtf16Rune(rune)) {
        return false;
      }
    }
    return true;
  }

  /// Whether [text] contains a character that no real text would contain:
  /// U+FFFD, a private-use code point, a surrogate or a disallowed C0 control.
  bool _hasHardInvalidUtf16(String text) {
    for (final rune in text.runes) {
      if (rune == 0xFFFD) return true;
      if (rune >= 0xD800 && rune <= 0xDFFF) return true;
      if (rune >= 0xE000 && rune <= 0xF8FF) return true;
      if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
        return true;
      }
    }
    return false;
  }

  bool _isPlausibleUtf16Rune(int rune) {
    if (rune == 0x09 || rune == 0x0A || rune == 0x0D) {
      return true;
    }
    if (rune >= 0x20 && rune <= 0x7E) return true;
    if (rune >= 0x00A0 && rune <= 0x024F) return true; // Latin supplement/ext.
    if (rune >= 0x2000 && rune <= 0x206F) return true; // General punctuation.
    if (rune >= 0x20A0 && rune <= 0x20CF) return true; // Currency.
    if (rune >= 0x2100 && rune <= 0x214F) return true; // Letterlike.
    if (rune >= 0x2190 && rune <= 0x21FF) return true; // Arrows.
    if (rune >= 0x2200 && rune <= 0x22FF) return true; // Math.
    if (rune >= 0x2460 && rune <= 0x24FF) return true; // Enclosed alnum.
    if (rune >= 0x2500 && rune <= 0x257F) return true; // Box drawing.
    if (rune >= 0x25A0 && rune <= 0x26FF) return true; // Geometric/symbols.
    if (rune >= 0x3000 && rune <= 0x303F) return true; // CJK punctuation.
    if (rune >= 0x3040 && rune <= 0x30FF) return true; // Kana.
    if (rune >= 0x3200 && rune <= 0x32FF) return true; // Enclosed CJK.
    if (rune >= 0x3400 && rune <= 0x4DBF) return true; // CJK ext. A.
    if (rune >= 0x4E00 && rune <= 0x9FFF) return true; // CJK unified.
    if (rune >= 0xF900 && rune <= 0xFAFF) return true; // CJK compatibility.
    if (rune >= 0xFE30 && rune <= 0xFE4F) return true; // CJK compat. forms.
    if (rune >= 0xFF00 && rune <= 0xFFEF) return true; // Full/halfwidth.
    if (rune >= 0x20000 && rune <= 0x2FA1F) return true; // CJK ext. B-F.
    return false;
  }

  // --------------------------------------------------------------------------
  // Scored legacy candidates
  // --------------------------------------------------------------------------

  _LegacyCandidate? _bestLegacyCandidate(List<int> bytes) {
    final candidates = <_LegacyCandidate? Function(List<int>)>[
      _tryGb18030,
      (input) => _tryCharset('shift_jis', 'Shift_JIS', input),
      (input) => _tryCharset('euc-jp', 'EUC-JP', input),
      _tryWindows1252Candidate,
    ];

    _LegacyCandidate? best;
    for (final candidate in candidates) {
      final decoded = candidate(bytes);
      if (decoded == null) {
        continue;
      }
      // Strictly greater so that ties favour the earlier candidate.
      if (best == null || decoded.score > best.score) {
        best = decoded;
      }
    }
    return best;
  }

  _LegacyCandidate? _tryGb18030(List<int> bytes) {
    final result = const Gb18030Decoder().decode(bytes);
    if (result.hadInvalidSequence || result.text.contains('\uFFFD')) {
      return null;
    }
    final score = _scoreText(
      result.text,
      fourByteBonus: result.hadFourByteSequence ? 50 : 0,
      ambiguityPenalty: result.ambiguousTwoByteCount * 4,
    );
    return _LegacyCandidate(
      text: result.text,
      label: result.hadFourByteSequence ? 'GB18030' : 'GBK',
      score: score,
    );
  }

  _LegacyCandidate? _tryCharset(String name, String label, List<int> bytes) {
    final encoding = Charset.getByName(name);
    if (encoding == null) {
      return null;
    }
    try {
      final text = encoding.decode(bytes);
      if (text.contains('\uFFFD')) {
        return null;
      }
      return _LegacyCandidate(
        text: text,
        label: label,
        score: _scoreText(text),
      );
    } on Object {
      // A throw means "this candidate does not apply".
      return null;
    }
  }

  _LegacyCandidate? _tryWindows1252Candidate(List<int> bytes) {
    final text = _decodeWindows1252(bytes, strict: true);
    if (text == null) {
      return null;
    }
    return _LegacyCandidate(
      text: text,
      label: 'Windows-1252',
      score: _scoreText(text),
    );
  }

  /// Decodes [bytes] as Windows-1252.
  ///
  /// Returns `null` when the bytes are undefined in the code page, when they
  /// produce U+FFFD, or when the result is dominated by control characters.
  /// When [strict] is true the control threshold is tighter; the last-resort
  /// pass allows a higher proportion before giving up.
  String? _decodeWindows1252(List<int> bytes, {required bool strict}) {
    final encoding = Charset.getByName('windows-1252');
    if (encoding == null) {
      return null;
    }
    final String text;
    try {
      text = encoding.decode(bytes);
    } on Object {
      return null;
    }
    if (text.contains('\uFFFD')) {
      return null;
    }
    final runes = text.runes.toList(growable: false);
    if (runes.isEmpty) {
      return null;
    }
    var controls = 0;
    for (final rune in runes) {
      final isC0 = rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D;
      final isC1 = rune >= 0x80 && rune <= 0x9F;
      if (isC0 || isC1) {
        controls++;
      }
    }
    final ratio = controls / runes.length;
    if (strict && ratio > 0.33) {
      return null;
    }
    if (!strict && ratio > 0.5) {
      return null;
    }
    return text;
  }

  /// Scores decoded text as evidence for a legacy encoding.
  ///
  /// The score is deliberately crude: CJK ideographs and kana are strong
  /// evidence, CJK punctuation and ASCII are weak evidence, and control
  /// characters, private-use characters and lone surrogates indicate a wrong
  /// reading. Half-width katakana (U+FF61-U+FF9F) earn nothing because they
  /// are the classic product of decoding GBK Chinese bytes as Shift-JIS.
  int _scoreText(
    String text, {
    int fourByteBonus = 0,
    int ambiguityPenalty = 0,
  }) {
    var ideographs = 0;
    var kana = 0;
    var punctuation = 0;
    var ascii = 0;
    var controlPenalty = 0;
    for (final rune in text.runes) {
      if (_isIdeograph(rune)) {
        ideographs++;
      } else if (rune >= 0x3040 && rune <= 0x30FF) {
        kana++;
      } else if ((rune >= 0x3000 && rune <= 0x303F) ||
          (rune >= 0xFF00 && rune <= 0xFFEF)) {
        if (rune < 0xFF61 || rune > 0xFF9F) {
          punctuation++;
        }
      }
      if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          rune == 0x20) {
        ascii++;
      }
      final isControl =
          rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D;
      final isPrivateUse = rune >= 0xE000 && rune <= 0xF8FF;
      final isSurrogate = rune >= 0xD800 && rune <= 0xDFFF;
      if (isControl || isPrivateUse || isSurrogate) {
        controlPenalty++;
      }
    }
    final score = _cap(ideographs * 3, 60) +
        _cap(kana * 6, 60) +
        _cap(punctuation * 2, 20) +
        _cap(ascii, 10) -
        controlPenalty * 40 +
        fourByteBonus -
        ambiguityPenalty;
    return score;
  }

  bool _isIdeograph(int rune) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) return true;
    if (rune >= 0x3400 && rune <= 0x4DBF) return true; // Extension A.
    if (rune >= 0xF900 && rune <= 0xFAFF) return true; // Compatibility.
    if (rune >= 0x20000 && rune <= 0x2FA1F) return true; // Extensions B-F.
    return false;
  }

  int _cap(int value, int maximum) => value > maximum ? maximum : value;

  bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }
}

/// A viable legacy decoding with its score and reported name.
class _LegacyCandidate {
  const _LegacyCandidate({
    required this.text,
    required this.label,
    required this.score,
  });

  final String text;
  final String label;
  final int score;
}
