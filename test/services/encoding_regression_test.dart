import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/services/encoding_service.dart';

/// Regression tests for the decode pipeline order.
///
/// Strict UTF-8 must be attempted before the BOM-less UTF-16 heuristic: short
/// ASCII text is valid UTF-8 and must not be re-read as UTF-16.
void main() {
  const EncodingService service = EncodingService();

  group('valid UTF-8 is never mistaken for UTF-16', () {
    test('short ASCII text decodes as UTF-8', () {
      for (final String text in <String>[
        'hello\n',
        'hello world\n',
        '1\n00:00:01,000 --> 00:00:03,000\nHi\n',
        'ab',
        'WEBVTT\n',
      ]) {
        final DecodedText decoded = service.decode(utf8.encode(text));
        expect(decoded.encodingName, 'UTF-8', reason: text);
        expect(decoded.text, text, reason: text);
      }
    });

    test('short CJK UTF-8 text decodes as UTF-8', () {
      const String text = '中文字幕\n';
      final DecodedText decoded = service.decode(utf8.encode(text));
      expect(decoded.encodingName, 'UTF-8');
      expect(decoded.text, text);
    });

    test('a whole small subtitle file decodes as UTF-8', () {
      const String text = '1\n'
          '00:00:01,000 --> 00:00:02,000\n'
          '日本語のテキスト\n'
          '\n'
          '2\n'
          '00:00:03,000 --> 00:00:04,000\n'
          '中文字幕\n';
      final DecodedText decoded = service.decode(utf8.encode(text));
      expect(decoded.encodingName, 'UTF-8');
      expect(decoded.text, text);
    });
  });

  group('UTF-16 support still works after the reorder', () {
    test('BOM-less UTF-16 with NUL bytes is still UTF-16', () {
      // 'AB' as UTF-16 LE: the bytes are valid UTF-8 (A, NUL, B, NUL) but the
      // NUL check rejects that reading.
      final DecodedText decoded = service.decode(<int>[0x41, 0x00, 0x42, 0x00]);
      expect(decoded.encodingName, 'UTF-16 LE');
      expect(decoded.text, 'AB');
    });

    test('BOM-less UTF-16 CJK is still UTF-16', () {
      // 中文, which is not valid UTF-8 at all.
      final DecodedText decoded = service.decode(<int>[0x2D, 0x4E, 0x87, 0x65]);
      expect(decoded.encodingName, 'UTF-16 LE');
      expect(decoded.text, '中文');
    });

    test('a UTF-16 BOM is still authoritative', () {
      final DecodedText decoded =
          service.decode(<int>[0xFF, 0xFE, 0x2D, 0x4E, 0x87, 0x65]);
      expect(decoded.encodingName, 'UTF-16 LE');
      expect(decoded.hadBom, isTrue);
      expect(decoded.text, '中文');
    });
  });

  group('legacy encodings still resolve after the reorder', () {
    test('GBK Chinese', () {
      final DecodedText decoded =
          service.decode(<int>[0xD6, 0xD0, 0xCE, 0xC4]);
      expect(decoded.encodingName, startsWith('GBK'));
      expect(decoded.text, '中文');
    });

    test('Shift-JIS Japanese', () {
      final DecodedText decoded =
          service.decode(<int>[0x93, 0xFA, 0x96, 0x7B]);
      expect(decoded.encodingName, 'Shift_JIS');
      expect(decoded.text, '日本');
    });

    test('Windows-1252', () {
      final DecodedText decoded = service.decode(latin1.encode('café'));
      expect(decoded.encodingName, 'Windows-1252');
      expect(decoded.text, 'café');
    });
  });
}
