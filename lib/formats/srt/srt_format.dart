import '../../models/format_descriptor.dart';
import '../../models/format_signature.dart';
import '../../models/subtitle_format.dart';
import 'srt_parser.dart';
import 'srt_writer.dart';

/// Matches an SRT timing line (`00:00:01,000 --> 00:00:02,000`).
///
/// Deliberately requires the comma fraction separator and the arrow; a dotted
/// timestamp is left for WebVTT, so this signature cannot steal VTT files.
final RegExp _timingPattern = RegExp(
  r'^\s*\d{1,3}:\d{2}:\d{2},\d{1,3}\s*-->\s*\d{1,3}:\d{2}:\d{2},\d{1,3}',
  multiLine: true,
);

/// Descriptor for SubRip (`.srt`).
final FormatDescriptor srtFormat = FormatDescriptor(
  format: SubtitleFormat.srt,
  createParser: () => const SrtParser(),
  createWriter: () => const SrtWriter(),
  signatures: <FormatSignature>[
    FormatSignatures.matchesPattern(
      _timingPattern,
      weight: 60,
      id: 'srt.timing-arrow',
    ),
  ],
  extensionAliases: <String>['subrip'],
  supportsInlineStyles: true,
);
