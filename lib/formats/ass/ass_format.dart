import '../../models/format_descriptor.dart';
import '../../models/format_signature.dart';
import '../../models/subtitle_format.dart';
import 'ass_parser.dart';
import 'ass_writer.dart';

/// Registry entry for ASS (Advanced SubStation Alpha).
///
/// ASS is one member of the ASS/SSA pair; both share the parser, writer and
/// text scanner in `lib/formats/ass/`. This descriptor only fixes the dialect
/// and advertises the format's capabilities and content fingerprints.
final FormatDescriptor assFormat = FormatDescriptor(
  format: SubtitleFormat.ass,
  createParser: () => AssParser(),
  createWriter: () => AssWriter(),
  signatures: <FormatSignature>[
    FormatSignatures.contains(
      '[Script Info]',
      weight: 100,
      ignoreCase: true,
      id: 'ass.script-info',
    ),
    FormatSignatures.matchesPattern(
      RegExp(r'\[V4\+\s*Styles\]', caseSensitive: false),
      weight: 100,
      id: 'ass.v4plus-styles',
    ),
    FormatSignatures.matchesPattern(
      RegExp(r'ScriptType:\s*v4\.00\+', caseSensitive: false),
      weight: 100,
      id: 'ass.script-type',
    ),
    FormatSignatures.contains(
      'Dialogue:',
      weight: 60,
      ignoreCase: true,
      id: 'ass.dialogue',
    ),
  ],
  extensionAliases: const <String>['advancedsubstation'],
  supportsStyles: true,
  supportsInlineStyles: true,
  supportsPositions: true,
);
