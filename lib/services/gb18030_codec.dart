import 'dart:convert';

import 'package:charset/charset.dart';

/// Outcome of decoding a byte sequence with [Gb18030Decoder].
///
/// The decoder never throws on malformed input: invalid sequences are replaced
/// with U+FFFD so that the result stays usable for encoding detection scoring.
class Gb18030Result {
  const Gb18030Result({
    required this.text,
    required this.hadFourByteSequence,
    required this.hadInvalidSequence,
    this.ambiguousTwoByteCount = 0,
  });

  /// Decoded text. Invalid sequences are represented by U+FFFD.
  final String text;

  /// Whether at least one valid four-byte GB18030 sequence was consumed.
  ///
  /// Four-byte sequences are the one structure that GBK cannot represent, so
  /// this is the signal [EncodingService] uses to report `GB18030` instead of
  /// `GBK`.
  final bool hadFourByteSequence;

  /// Whether any malformed or undefined sequence was replaced by U+FFFD.
  final bool hadInvalidSequence;

  /// Number of two-byte codes whose lead byte lies in the byte ranges that
  /// GBK shares with Shift-JIS (`0x81-0x9F` and `0xE0-0xEF`).
  ///
  /// These pairs are the main source of GBK/Shift-JIS ambiguity: the same two
  /// bytes decode to a (rare) GBK ideograph or to a (common) Shift-JIS kanji.
  /// Callers can use this count to de-prioritise an otherwise plausible GBK
  /// reading, as [EncodingService] does.
  final int ambiguousTwoByteCount;
}

/// A self-contained GB18030 decoder.
///
/// `package:charset` aliases `gb18030` to GBK and its GBK decoder is strictly
/// two-byte, so real four-byte sequences throw. This decoder covers all four
/// GB18030 sequence lengths:
///
///  * one byte: `0x00-0x7F` maps to the same code point, `0x80` is U+20AC
///    (euro sign), `0xFF` is invalid;
///  * two bytes: lead `0x81-0xFE`, trail `0x40-0xFE` excluding `0x7F`; the
///    validated pair is delegated to the GBK mapping table of
///    `package:charset`, so no 23k-entry table has to be duplicated here;
///  * four bytes: `0x81-0xFE`, `0x30-0x39`, `0x81-0xFE`, `0x30-0x39`, mapped
///    through the embedded WHATWG `index gb18030 ranges` table.
///
/// A byte such as `0x95 0x32` is deliberately read as the start of a four-byte
/// sequence (0x32 is in `0x30-0x39`, not a valid two-byte trail), which is the
/// whole point of a dedicated GB18030 decoder.
class Gb18030Decoder {
  /// Creates a decoder. The class is stateless and cheap to construct.
  const Gb18030Decoder();

  /// Decodes [bytes], replacing malformed sequences with U+FFFD.
  Gb18030Result decode(List<int> bytes) {
    final buffer = StringBuffer();
    var hadFourByte = false;
    var hadInvalid = false;
    var ambiguous = 0;
    var i = 0;
    while (i < bytes.length) {
      final b1 = bytes[i];
      if (b1 <= 0x7F) {
        buffer.writeCharCode(b1);
        i++;
        continue;
      }
      if (b1 == 0x80) {
        buffer.writeCharCode(0x20AC);
        i++;
        continue;
      }
      if (b1 == 0xFF) {
        buffer.writeCharCode(0xFFFD);
        hadInvalid = true;
        i++;
        continue;
      }

      // b1 is now a valid lead byte in 0x81-0xFE.
      if (i + 1 >= bytes.length) {
        buffer.writeCharCode(0xFFFD);
        hadInvalid = true;
        i++;
        continue;
      }
      final b2 = bytes[i + 1];

      if (b2 >= 0x30 && b2 <= 0x39) {
        // Structurally the start of a four-byte sequence.
        if (i + 3 < bytes.length) {
          final b3 = bytes[i + 2];
          final b4 = bytes[i + 3];
          if (b3 >= 0x81 && b3 <= 0xFE && b4 >= 0x30 && b4 <= 0x39) {
            final pointer = (b1 - 0x81) * 12600 +
                (b2 - 0x30) * 1260 +
                (b3 - 0x81) * 10 +
                (b4 - 0x30);
            final codePoint = _pointerToCodePoint(pointer);
            if (codePoint != null) {
              buffer.writeCharCode(codePoint);
              hadFourByte = true;
              i += 4;
              continue;
            }
            buffer.writeCharCode(0xFFFD);
            hadInvalid = true;
            i++;
            continue;
          }
        }
        // Truncated or malformed four-byte sequence.
        buffer.writeCharCode(0xFFFD);
        hadInvalid = true;
        i++;
        continue;
      }

      if (b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
        final decoded = _decodeTwoByte(b1, b2);
        if (decoded != null) {
          buffer.writeCharCode(decoded);
          if ((b1 >= 0x81 && b1 <= 0x9F) || (b1 >= 0xE0 && b1 <= 0xEF)) {
            ambiguous++;
          }
          i += 2;
          continue;
        }
        // Well-formed pair that GBK does not define.
        buffer.writeCharCode(0xFFFD);
        hadInvalid = true;
        i += 2;
        continue;
      }

      // Invalid trail byte: skip one byte and continue.
      buffer.writeCharCode(0xFFFD);
      hadInvalid = true;
      i++;
    }

    return Gb18030Result(
      text: buffer.toString(),
      hadFourByteSequence: hadFourByte,
      hadInvalidSequence: hadInvalid,
      ambiguousTwoByteCount: ambiguous,
    );
  }

  static final Encoding? _gbk = Charset.getByName('gbk');

  /// Decodes one structurally valid two-byte GBK code, or `null` when the code
  /// is not defined by the GBK mapping table.
  static int? _decodeTwoByte(int b1, int b2) {
    final gbk = _gbk;
    if (gbk == null) {
      return null;
    }
    try {
      final decoded = gbk.decode(<int>[b1, b2]);
      if (decoded.length != 1) {
        return null;
      }
      return decoded.codeUnitAt(0);
    } on Object {
      return null;
    }
  }

  /// Maps a four-byte GB18030 pointer to a Unicode code point, or `null` when
  /// the pointer falls in one of the gaps defined by the WHATWG algorithm.
  static int? _pointerToCodePoint(int pointer) {
    if (pointer >= 189000) {
      if (pointer > 1237575) {
        return null;
      }
      return 0x10000 + (pointer - 189000);
    }
    if (pointer > 39419) {
      return null;
    }
    // Last ranges entry whose pointer is <= [pointer].
    var low = 0;
    var high = _gb18030RangePointers.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_gb18030RangePointers[mid] <= pointer) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (found < 0) {
      return null;
    }
    final codePoint =
        _gb18030RangeCodePoints[found] + (pointer - _gb18030RangePointers[found]);
    if (codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      return null;
    }
    return codePoint;
  }
}

// ---------------------------------------------------------------------------
// WHATWG `index gb18030 ranges` table.
//
// Source: https://encoding.spec.whatwg.org/index-gb18030-ranges.txt
// Identifier: f963aaa1653f630c523e7b04729fb4e4458f35806c45eb5c179445623138f0c0
// Date: 2024-09-18
//
// The table is embedded verbatim (pointer, code point) so the decoder works
// fully offline. For a pointer P, the code point is
//   codePoint[last entry with pointer <= P] + (P - pointer[that entry]).
// Pointers >= 189000 are handled by the linear formula in
// [_pointerToCodePoint] and are represented by the final 189000 entry.
// ---------------------------------------------------------------------------

const List<int> _gb18030RangePointers = <int>[
  0,  36,  38,  45,  50,  81,  89,  95,  96,  100,  103,  104,
  105,  109,  126,  133,  148,  172,  175,  179,  208,  306,  307,  308,
  309,  310,  311,  312,  313,  341,  428,  443,  544,  545,  558,  741,
  742,  749,  750,  805,  819,  820,  7922,  7924,  7925,  7927,  7934,  7943,
  7944,  7945,  7950,  8062,  8148,  8149,  8152,  8164,  8174,  8236,  8240,  8262,
  8264,  8374,  8380,  8381,  8384,  8388,  8390,  8392,  8393,  8394,  8396,  8401,
  8406,  8416,  8419,  8424,  8437,  8439,  8445,  8482,  8485,  8496,  8521,  8603,
  8936,  8946,  9046,  9050,  9063,  9066,  9076,  9092,  9100,  9108,  9111,  9113,
  9131,  9162,  9164,  9218,  9219,  11329,  11331,  11334,  11336,  11346,  11361,  11363,
  11366,  11370,  11372,  11375,  11389,  11682,  11686,  11687,  11692,  11694,  11714,  11716,
  11723,  11725,  11730,  11736,  11982,  11989,  12102,  12336,  12348,  12350,  12384,  12393,
  12395,  12397,  12510,  12553,  12851,  12962,  12973,  13738,  13823,  13919,  13933,  14080,
  14298,  14585,  14698,  15583,  15847,  16318,  16434,  16438,  16481,  16729,  17102,  17122,
  17315,  17320,  17402,  17418,  17859,  17909,  17911,  17915,  17916,  17936,  17939,  17961,
  18664,  18703,  18814,  18962,  19043,  33469,  33470,  33471,  33484,  33485,  33490,  33497,
  33501,  33505,  33513,  33520,  33536,  33550,  37845,  37921,  37948,  38029,  38038,  38064,
  38065,  38066,  38069,  38075,  38076,  38078,  39108,  39109,  39113,  39114,  39115,  39116,
  39265,  39394,  189000,
];
const List<int> _gb18030RangeCodePoints = <int>[
  0x0080,  0x00A5,  0x00A9,  0x00B2,  0x00B8,  0x00D8,  0x00E2,  0x00EB,  0x00EE,  0x00F4,  0x00F8,  0x00FB,
  0x00FD,  0x0102,  0x0114,  0x011C,  0x012C,  0x0145,  0x0149,  0x014E,  0x016C,  0x01CF,  0x01D1,  0x01D3,
  0x01D5,  0x01D7,  0x01D9,  0x01DB,  0x01DD,  0x01FA,  0x0252,  0x0262,  0x02C8,  0x02CC,  0x02DA,  0x03A2,
  0x03AA,  0x03C2,  0x03CA,  0x0402,  0x0450,  0x0452,  0x2011,  0x2017,  0x201A,  0x201E,  0x2027,  0x2031,
  0x2034,  0x2036,  0x203C,  0x20AD,  0x2104,  0x2106,  0x210A,  0x2117,  0x2122,  0x216C,  0x217A,  0x2194,
  0x219A,  0x2209,  0x2210,  0x2212,  0x2216,  0x221B,  0x2221,  0x2224,  0x2226,  0x222C,  0x222F,  0x2238,
  0x223E,  0x2249,  0x224D,  0x2253,  0x2262,  0x2268,  0x2270,  0x2296,  0x229A,  0x22A6,  0x22C0,  0x2313,
  0x246A,  0x249C,  0x254C,  0x2574,  0x2590,  0x2596,  0x25A2,  0x25B4,  0x25BE,  0x25C8,  0x25CC,  0x25D0,
  0x25E6,  0x2607,  0x260A,  0x2641,  0x2643,  0x2E82,  0x2E85,  0x2E89,  0x2E8D,  0x2E98,  0x2EA8,  0x2EAB,
  0x2EAF,  0x2EB4,  0x2EB8,  0x2EBC,  0x2ECB,  0x2FFC,  0x3004,  0x3018,  0x301F,  0x302A,  0x303F,  0x3094,
  0x309F,  0x30F7,  0x30FF,  0x312A,  0x322A,  0x3232,  0x32A4,  0x3390,  0x339F,  0x33A2,  0x33C5,  0x33CF,
  0x33D3,  0x33D6,  0x3448,  0x3474,  0x359F,  0x360F,  0x361B,  0x3919,  0x396F,  0x39D1,  0x39E0,  0x3A74,
  0x3B4F,  0x3C6F,  0x3CE1,  0x4057,  0x4160,  0x4338,  0x43AD,  0x43B2,  0x43DE,  0x44D7,  0x464D,  0x4662,
  0x4724,  0x472A,  0x477D,  0x478E,  0x4948,  0x497B,  0x497E,  0x4984,  0x4987,  0x499C,  0x49A0,  0x49B8,
  0x4C78,  0x4CA4,  0x4D1A,  0x4DAF,  0x9FA6,  0xE76C,  0xE7C8,  0xE7E7,  0xE815,  0xE819,  0xE81F,  0xE827,
  0xE82D,  0xE833,  0xE83C,  0xE844,  0xE856,  0xE865,  0xF92D,  0xF97A,  0xF996,  0xF9E8,  0xF9F2,  0xFA10,
  0xFA12,  0xFA15,  0xFA19,  0xFA22,  0xFA25,  0xFA2A,  0xFE32,  0xFE45,  0xFE53,  0xFE58,  0xFE67,  0xFE6C,
  0xFF5F,  0xFFE6,  0x10000,
];
