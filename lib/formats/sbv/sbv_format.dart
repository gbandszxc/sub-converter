import '../../models/format_descriptor.dart';
import '../../models/format_signature.dart';
import '../../models/subtitle_format.dart';
import 'sbv_parser.dart';
import 'sbv_writer.dart';

/// Matches an SBV timing line: two dot-fraction timestamps joined by a comma,
/// with no arrow and nothing else on the line.
final RegExp _timingPattern = RegExp(
  r'^\s*\d{1,3}:\d{2}:\d{2}\.\d{1,3}\s*,\s*\d{1,3}:\d{2}:\d{2}\.\d{1,3}\s*$',
  multiLine: true,
);

/// Descriptor for YouTube SBV (`.sbv`).
final FormatDescriptor sbvFormat = FormatDescriptor(
  format: SubtitleFormat.sbv,
  createParser: () => const SbvParser(),
  createWriter: () => const SbvWriter(),
  signatures: <FormatSignature>[
    FormatSignatures.matchesPattern(
      _timingPattern,
      weight: 60,
      id: 'sbv.timing-comma',
    ),
  ],
  supportsInlineStyles: false,
  requiresEndTime: true,
);
