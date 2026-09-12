import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/services/encoding_service.dart';
import 'package:sub_converter/services/gb18030_codec.dart';

/// The service under test. Stateless, so a single const instance is enough.
const EncodingService service = EncodingService();

List<int> ascii(String text) => latin1.encode(text);

void main() {
  group('public API', () {
    test('legacyEncodingNames lists the candidates in detection order', () {
      expect(
        EncodingService.legacyEncodingNames,
        <String>['GB18030', 'GBK', 'Shift_JIS', 'EUC-JP', 'Windows-1252'],
      );
    });

    test('empty input decodes to empty text without throwing', () {
      final DecodedText decoded = service.decode(<int>[]);
      expect(decoded.text, '');
      expect(decoded.encodingName, 'UTF-8');
      expect(decoded.hadBom, isFalse);
    });
  });

  group('UTF-8', () {
    test('ASCII without BOM', () {
      final DecodedText decoded = service.decode(utf8.encode('Hello, world!\n'));
      expect(decoded.text, 'Hello, world!\n');
      expect(decoded.encodingName, 'UTF-8');
      expect(decoded.hadBom, isFalse);
    });

    test('Chinese without BOM', () {
      const String text = '中文字幕';
      final DecodedText decoded = service.decode(utf8.encode(text));
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-8');
    });

    test('Japanese without BOM', () {
      const String text = '日本語の字幕です。';
      final DecodedText decoded = service.decode(utf8.encode(text));
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-8');
    });

    test('with BOM strips the BOM and reports UTF-8 BOM', () {
      const String text = '中文字幕';
      final List<int> bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)];
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-8 BOM');
      expect(decoded.hadBom, isTrue);
    });
  });

  group('UTF-16/UTF-32 with BOM', () {
    test('UTF-16 LE', () {
      const String text = '中文字幕';
      final List<int> bytes = const Utf16Encoder().encodeUtf16Le(text, true);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-16 LE');
      expect(decoded.hadBom, isTrue);
    });

    test('UTF-16 BE', () {
      const String text = '日本語';
      final List<int> bytes = const Utf16Encoder().encodeUtf16Be(text, true);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-16 BE');
      expect(decoded.hadBom, isTrue);
    });

    test('UTF-32 LE', () {
      const String text = 'Hi 中文';
      final List<int> bytes = const Utf32Encoder().encodeUtf32Le(text, true);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-32 LE');
      expect(decoded.hadBom, isTrue);
    });

    test('UTF-32 BE', () {
      const String text = 'Hi 中文';
      final List<int> bytes = const Utf32Encoder().encodeUtf32Be(text, true);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-32 BE');
      expect(decoded.hadBom, isTrue);
    });
  });

  group('BOM-less UTF-16', () {
    test('pure CJK little endian', () {
      final DecodedText decoded =
          service.decode(<int>[0x2D, 0x4E, 0x87, 0x65]);
      expect(decoded.text, '中文');
      expect(decoded.encodingName, 'UTF-16 LE');
      expect(decoded.hadBom, isFalse);
    });

    test('pure CJK big endian', () {
      final DecodedText decoded =
          service.decode(<int>[0x4E, 0x2D, 0x65, 0x87]);
      expect(decoded.text, '中文');
      expect(decoded.encodingName, 'UTF-16 BE');
      expect(decoded.hadBom, isFalse);
    });

    test('longer pure CJK is disambiguated by the private-use check', () {
      const String text = '中文字幕';
      final List<int> le = const Utf16Encoder().encodeUtf16Le(text, false);
      final DecodedText decodedLe = service.decode(le);
      expect(decodedLe.text, text);
      expect(decodedLe.encodingName, 'UTF-16 LE');
      final List<int> be = const Utf16Encoder().encodeUtf16Be(text, false);
      final DecodedText decodedBe = service.decode(be);
      expect(decodedBe.text, text);
      expect(decodedBe.encodingName, 'UTF-16 BE');
    });

    test('NUL parity detects little endian ASCII text', () {
      const String text = 'Hello, world!';
      final List<int> bytes = const Utf16Encoder().encodeUtf16Le(text, false);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-16 LE');
    });

    test('NUL parity detects big endian ASCII text', () {
      const String text = 'Hello, world!';
      final List<int> bytes = const Utf16Encoder().encodeUtf16Be(text, false);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-16 BE');
    });
  });

  group('legacy encodings', () {
    test('GBK Chinese', () {
      final DecodedText decoded =
          service.decode(<int>[0xD6, 0xD0, 0xCE, 0xC4]);
      expect(decoded.text, '中文');
      expect(decoded.encodingName, startsWith('GBK'));
      expect(decoded.hadBom, isFalse);
    });

    test('GB18030 four-byte sequence', () {
      final DecodedText decoded =
          service.decode(<int>[0x95, 0x32, 0x82, 0x36]);
      expect(decoded.text, '\u{20000}');
      expect(decoded.encodingName, 'GB18030');
    });

    test('GB18030 mixed two- and four-byte text', () {
      final DecodedText decoded = service
          .decode(<int>[0xD6, 0xD0, 0x95, 0x32, 0x82, 0x36, 0xCE, 0xC4]);
      expect(decoded.text, '中\u{20000}文');
      expect(decoded.encodingName, 'GB18030');
    });

    test('Shift-JIS Japanese', () {
      final DecodedText decoded =
          service.decode(<int>[0x93, 0xFA, 0x96, 0x7B]);
      expect(decoded.text, '日本');
      expect(decoded.encodingName, 'Shift_JIS');
    });

    test('Windows-1252 / Latin-1 fallback', () {
      final List<int> bytes = latin1.encode('café');
      expect(bytes, <int>[0x63, 0x61, 0x66, 0xE9]);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, 'café');
      expect(decoded.encodingName, 'Windows-1252');
    });
  });

  group('realistic subtitle samples', () {
    test('GBK-encoded SRT', () {
      const String expected = '1\n'
          '00:00:01,000 --> 00:00:03,000\n'
          '你好，世界！\n'
          '\n'
          '2\n'
          '00:00:04,000 --> 00:00:06,000\n'
          '中文字幕测试\n';
      final List<int> bytes = <int>[
        ...ascii('1\n00:00:01,000 --> 00:00:03,000\n'),
        // 你 好 ， 世 界 ！
        0xC4, 0xE3, 0xBA, 0xC3, 0xA3, 0xAC, 0xCA, 0xC0, 0xBD, 0xE7, 0xA3, 0xA1,
        ...ascii('\n\n2\n00:00:04,000 --> 00:00:06,000\n'),
        // 中 文 字 幕 测 试
        0xD6, 0xD0, 0xCE, 0xC4, 0xD7, 0xD6, 0xC4, 0xBB, 0xB2, 0xE2, 0xCA, 0xD4,
        ...ascii('\n'),
      ];
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, expected);
      expect(decoded.encodingName, startsWith('GBK'));
    });

    test('Shift-JIS-encoded subtitle', () {
      const String expected = '1\n'
          '00:00:01,000 --> 00:00:03,000\n'
          'こんにちは、世界！\n'
          '\n'
          '2\n'
          '00:00:04,000 --> 00:00:06,000\n'
          '日本語です\n';
      final List<int> bytes = <int>[
        ...ascii('1\n00:00:01,000 --> 00:00:03,000\n'),
        // こ ん に ち は 、 世 界 ！
        0x82, 0xB1, 0x82, 0xF1, 0x82, 0xC9, 0x82, 0xBF, 0x82, 0xCD, 0x81, 0x41,
        0x90, 0xA2, 0x8A, 0x45, 0x81, 0x49,
        ...ascii('\n\n2\n00:00:04,000 --> 00:00:06,000\n'),
        // 日 本 語 で す
        0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x82, 0xC5, 0x82, 0xB7,
        ...ascii('\n'),
      ];
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, expected);
      expect(decoded.encodingName, 'Shift_JIS');
    });
  });

  group('undecodable input', () {
    test('garbage after a UTF-16 BOM throws a conversion exception', () {
      final List<int> bytes = <int>[0xFF, 0xFE, 0xFF, 0xFF, 0xFF];
      expect(
        () => service.decode(bytes),
        throwsA(
          isA<SubtitleConversionException>().having(
            (SubtitleConversionException error) => error.failure,
            'failure',
            ConversionFailure.encodingDetectionFailed,
          ),
        ),
      );
    });

    test('bytes undefined in Windows-1252 throw a conversion exception', () {
      final List<int> bytes = <int>[0x81, 0x8D, 0x90];
      expect(
        () => service.decode(bytes),
        throwsA(
          isA<SubtitleConversionException>().having(
            (SubtitleConversionException error) => error.failure,
            'failure',
            ConversionFailure.encodingDetectionFailed,
          ),
        ),
      );
    });
  });

  group('encode', () {
    test('defaults to no BOM and round-trips Chinese', () {
      const String text = '中文字幕';
      final List<int> bytes = service.encode(text);
      expect(bytes.first, isNot(0xEF));
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-8');
    });

    test('round-trips Japanese', () {
      const String text = '日本語の字幕';
      final DecodedText decoded = service.decode(service.encode(text));
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-8');
    });

    test('withBom prepends the UTF-8 BOM and decodes back', () {
      const String text = '中文字幕';
      final List<int> bytes = service.encode(text, withBom: true);
      expect(bytes.take(3).toList(), <int>[0xEF, 0xBB, 0xBF]);
      final DecodedText decoded = service.decode(bytes);
      expect(decoded.text, text);
      expect(decoded.encodingName, 'UTF-8 BOM');
      expect(decoded.hadBom, isTrue);
    });
  });

  group('Gb18030Decoder', () {
    test('reports four-byte consumption for GB18030-only characters', () {
      final Gb18030Result result =
          const Gb18030Decoder().decode(<int>[0x95, 0x32, 0x82, 0x36]);
      expect(result.text, '\u{20000}');
      expect(result.hadFourByteSequence, isTrue);
      expect(result.hadInvalidSequence, isFalse);
    });

    test('reads 0x95 0x32 as a four-byte lead, not as an error', () {
      // 0x32 is not a valid two-byte trail (trail must be >= 0x40), so the
      // sequence can only be a valid four-byte GB18030 sequence.
      final Gb18030Result result =
          const Gb18030Decoder().decode(<int>[0x95, 0x32, 0x82, 0x36]);
      expect(result.hadInvalidSequence, isFalse);
      expect(result.hadFourByteSequence, isTrue);
    });

    test('maps a four-byte pointer through the WHATWG BMP ranges table', () {
      // Pointer 36 corresponds to U+00A5 (yen sign) per index-gb18030-ranges.
      final Gb18030Result result =
          const Gb18030Decoder().decode(<int>[0x81, 0x30, 0x84, 0x36]);
      expect(result.text, '\u00A5');
      expect(result.hadFourByteSequence, isTrue);
      expect(result.hadInvalidSequence, isFalse);
    });

    test('does not report four-byte consumption for plain GBK', () {
      final Gb18030Result result =
          const Gb18030Decoder().decode(<int>[0xD6, 0xD0, 0xCE, 0xC4]);
      expect(result.text, '中文');
      expect(result.hadFourByteSequence, isFalse);
      expect(result.hadInvalidSequence, isFalse);
    });

    test('replaces invalid bytes with U+FFFD instead of throwing', () {
      final Gb18030Result result =
          const Gb18030Decoder().decode(<int>[0xFF, 0x41]);
      expect(result.text, contains('\uFFFD'));
      expect(result.hadInvalidSequence, isTrue);
    });
  });
}
