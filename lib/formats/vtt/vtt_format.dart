import '../../models/format_descriptor.dart';
import '../../models/format_signature.dart';
import '../../models/subtitle_format.dart';
import 'vtt_parser.dart';
import 'vtt_writer.dart';

/// Descriptor for WebVTT: parser/writer factories plus content fingerprints.
///
/// `supportsPositions` stays false because cue settings are round-tripped as
/// opaque text rather than modelled positions.
final FormatDescriptor vttFormat = FormatDescriptor(
  format: SubtitleFormat.vtt,
  createParser: VttParser.new,
  createWriter: VttWriter.new,
  signatures: <FormatSignature>[
    FormatSignatures.firstLineMatches(
      RegExp(r'^WEBVTT'),
      weight: 100,
      id: 'vtt.header',
    ),
    FormatSignatures.matchesPattern(
      RegExp(
        r'^\s*(?:\d{1,3}:)?\d{1,2}:\d{2}\.\d{1,3}\s*-->\s*'
        r'(?:\d{1,3}:)?\d{1,2}:\d{2}\.\d{1,3}',
        multiLine: true,
      ),
      weight: 40,
      id: 'vtt.timing-arrow',
    ),
  ],
  extensionAliases: <String>['webvtt'],
  supportsInlineStyles: true,
  supportsPositions: false,
);
