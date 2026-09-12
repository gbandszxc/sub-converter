import '../../models/format_descriptor.dart';
import '../../models/format_signature.dart';
import '../../models/subtitle_format.dart';
import 'ssa_parser.dart';
import 'ssa_writer.dart';

/// Registry entry for SSA (SubStation Alpha).
///
/// SSA is the older member of the ASS/SSA pair; both share the parser, writer
/// and text scanner in `lib/formats/ass/`. This descriptor only fixes the
/// dialect and advertises the format's capabilities and content fingerprints.
///
/// The extension aliases deliberately avoid `ssa`/`ass` cross-listing so
/// extension detection can never confuse the two formats.
final FormatDescriptor ssaFormat = FormatDescriptor(
  format: SubtitleFormat.ssa,
  createParser: () => SsaParser(),
  createWriter: () => SsaWriter(),
  signatures: <FormatSignature>[
    FormatSignatures.matchesPattern(
      RegExp(r'\[V4\s+Styles\]', caseSensitive: false),
      weight: 100,
      id: 'ssa.v4-styles',
    ),
    FormatSignatures.matchesPattern(
      RegExp(
        r'ScriptType:\s*v4\.00\s*$',
        multiLine: true,
        caseSensitive: false,
      ),
      weight: 100,
      id: 'ssa.script-type',
    ),
    FormatSignatures.contains(
      'Dialogue:',
      weight: 60,
      ignoreCase: true,
      id: 'ssa.dialogue',
    ),
  ],
  extensionAliases: const <String>['substation'],
  supportsStyles: true,
  supportsInlineStyles: true,
  supportsPositions: true,
);
