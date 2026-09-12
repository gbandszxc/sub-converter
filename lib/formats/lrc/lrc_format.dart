import '../../models/format_descriptor.dart';
import '../../models/format_signature.dart';
import '../../models/subtitle_format.dart';
import 'lrc_parser.dart';
import 'lrc_writer.dart';

/// Descriptor for LRC (lyrics): parser/writer factories plus content
/// fingerprints.
///
/// `requiresEndTime` is false because LRC has no end times; writers infer
/// them, but the format itself cannot express them.
final FormatDescriptor lrcFormat = FormatDescriptor(
  format: SubtitleFormat.lrc,
  createParser: LrcParser.new,
  createWriter: LrcWriter.new,
  signatures: <FormatSignature>[
    // Requires at least two timestamp lines, so a lone `[00:10.00]` in prose
    // is not misidentified. The range-checked minutes/seconds fields keep this
    // from matching ASS headers such as `[Script Info]`.
    FormatSignatures.linePatternCount(
      RegExp(r'^\[\d{1,3}:[0-5]\d(?:[.:]\d{1,3})?\]'),
      weight: 60,
      minimum: 2,
      id: 'lrc.timestamp-lines',
    ),
    FormatSignatures.contains(
      '[ti:',
      weight: 40,
      ignoreCase: true,
      id: 'lrc.id-tag',
    ),
  ],
  supportsInlineStyles: false,
  requiresEndTime: false,
);
