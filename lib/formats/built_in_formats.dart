import '../models/format_descriptor.dart';
import 'ass/ass_format.dart';
import 'format_registry.dart';
import 'lrc/lrc_format.dart';
import 'sbv/sbv_format.dart';
import 'srt/srt_format.dart';
import 'ssa/ssa_format.dart';
import 'vtt/vtt_format.dart';

/// The single registration point for the formats shipped in v0.1.
///
/// Adding a format means creating its parser/writer/descriptor and appending
/// one entry here; no switch statements or other core files change.
final List<FormatDescriptor> builtInFormatDescriptors =
    List<FormatDescriptor>.unmodifiable(<FormatDescriptor>[
  srtFormat,
  vttFormat,
  lrcFormat,
  assFormat,
  ssaFormat,
  sbvFormat,
]);

/// Registry containing every built-in format.
final FormatRegistry builtInFormatRegistry =
    FormatRegistry(builtInFormatDescriptors);
